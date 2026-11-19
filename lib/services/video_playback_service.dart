import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const _currentPlaybackClient = YoutubeApiClient.androidSdkless;

/// Android SDK-less client is the active playback client and still returns
/// muxed and adaptive streams. Higher resolutions are offered through
/// adaptive video + external audio tracks instead of muxed streams, which
/// YouTube caps at 360p.
const _maxAdaptiveHeight = 1080;

YoutubeApiClient _withAuthHeaders(
  YoutubeApiClient client,
  Map<String, String> authHeaders,
) {
  final headers = Map<String, dynamic>.from(client.headers)
    ..addAll(authHeaders);
  return YoutubeApiClient(
    Map<String, dynamic>.from(client.payload),
    client.apiUrl,
    headers: headers,
  );
}

class VideoPlaybackSource {
  final Uri uri;
  final Uri? audioUri;
  final String qualityLabel;
  final int height;
  final num frameRate;

  const VideoPlaybackSource({
    required this.uri,
    this.audioUri,
    required this.qualityLabel,
    required this.height,
    required this.frameRate,
  });
}

typedef VideoManifestLoader = Future<StreamManifest> Function(
  String videoId,
  YoutubeApiClient client,
);
typedef PlaybackClientLoader = Future<YoutubeApiClient> Function(
  Map<String, String> authHeaders,
);

class VideoPlaybackSourceException extends FormatException {
  const VideoPlaybackSourceException(super.message);
}

class YouTubeVideoPlaybackService {
  late final YoutubeExplode _client;
  late final _PlaybackResponseProbeClient _responseProbe;
  final VideoManifestLoader? manifestLoader;
  final PlaybackClientLoader? playbackClientLoader;
  final bool _ownsClient;
  final http.Client _egressProbeClient = http.Client();
  StreamSubscription<LogRecord>? _streamLogSubscription;

  YouTubeVideoPlaybackService({
    YoutubeExplode? client,
    this.manifestLoader,
    this.playbackClientLoader,
  }) : _ownsClient = client == null {
    _responseProbe = _PlaybackResponseProbeClient();
    _client =
        client ?? YoutubeExplode(httpClient: YoutubeHttpClient(_responseProbe));
    if (kDebugMode && manifestLoader == null) {
      _streamLogSubscription = Logger.root.onRecord.listen((record) {
        if (record.loggerName != 'YoutubeExplode.StreamsClient' ||
            record.error == null) {
          return;
        }
        debugPrint(
          'FormatException: YouTube 播放源诊断；阶段：youtube_explode；'
          '日志级别：${record.level.name}；异常类型：${record.error.runtimeType}',
        );
      });
    }
  }

  Future<List<VideoPlaybackSource>> resolveSources(
    String videoId, {
    Map<String, String> authHeaders = const {},
  }) async {
    if (videoId.trim().isEmpty) {
      throw const VideoPlaybackSourceException('视频缺少有效的 YouTube ID');
    }

    try {
      return await _resolveSources(
        videoId,
        authHeaders: authHeaders,
        attempt: authHeaders.isEmpty ? 'anonymous' : 'authenticated',
      );
    } catch (error) {
      if (authHeaders.isEmpty) rethrow;
      try {
        // The saved TV OAuth token is rejected by the Android player client
        // with HTTP 400. Public videos still play anonymously, so retry
        // without account headers before surfacing the failure.
        return await _resolveSources(
          videoId,
          authHeaders: const {},
          attempt: 'anonymous_retry',
        );
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<List<VideoPlaybackSource>> _resolveSources(
    String videoId, {
    required Map<String, String> authHeaders,
    required String attempt,
  }) async {
    YoutubeApiClient? client;
    try {
      client = await _resolvePlaybackClient(authHeaders);
      _responseProbe.reset();
      _writePlaybackProbe(client, 'request', attempt: attempt);
      await _writeEgressProbe(attempt);
      final manifestLoader = this.manifestLoader;
      final manifest = manifestLoader == null
          ? await _client.videos.streams.getManifest(
              videoId,
              ytClients: [client],
              requireWatchPage: false,
            )
          : await manifestLoader(videoId, client);
      final sources = _sourcesFromManifest(manifest);
      if (sources.isEmpty) {
        _writePlaybackProbe(client, 'no_playable_sources', attempt: attempt);
        throw const VideoPlaybackSourceException(
          'YouTube 播放源解析失败；阶段：manifest；'
          '字段：streamingData.formats/streamingData.adaptiveFormats；'
          '客户端：ANDROID；结果：无音视频流',
        );
      }
      _writePlaybackProbe(
        client,
        'sources=${sources.length}',
        attempt: attempt,
      );
      return sources;
    } catch (error) {
      if (client != null) {
        _writePlaybackProbe(client, 'error', attempt: attempt, error: error);
      }
      if (error is VideoPlaybackSourceException) rethrow;
      final refusal = playabilityFailureMessage(
        status: _responseProbe.playabilityStatus,
        reason: _responseProbe.playabilityReason,
      );
      if (refusal != null) throw VideoPlaybackSourceException(refusal);
      throw VideoPlaybackSourceException(
        'YouTube 播放源解析失败；阶段：manifest；'
        '字段：streamingData.formats/streamingData.adaptiveFormats；'
        '客户端：ANDROID；异常类型：${error.runtimeType}',
      );
    }
  }

  /// Explains why YouTube refused to hand out playback URLs.
  ///
  /// The provocation is on the server side: a `LOGIN_REQUIRED` reply is used
  /// both for genuine sign-in walls and for the "confirm you're not a bot"
  /// gate that YouTube applies to network exits it distrusts (data-centre and
  /// VPN ranges in particular). Only the second kind is worth telling the user
  /// about, because it is the one they can act on.
  @visibleForTesting
  static String? playabilityFailureMessage({String? status, String? reason}) {
    if (status == null || status == 'OK') return null;
    final text = (reason ?? '').toLowerCase();
    if (_isBotGate(text)) {
      return 'YouTube 要求先验证「你不是机器人」，因此没有下发播放地址。'
          '这项检查按网络出口判定：请关闭代理/VPN，或改用其它网络（例如手机流量）后重试。';
    }
    if (_isAgeGate(text)) {
      return '该视频有年龄限制，需要登录已通过年龄验证的 YouTube 账号才能播放。';
    }
    if (status == 'LOGIN_REQUIRED') {
      return '该视频需要登录后才能播放。';
    }
    return null;
  }

  /// The "confirm you're not a bot" gate. Matched narrowly on purpose: the
  /// generic `LOGIN_REQUIRED` wording is shared with ordinary sign-in walls.
  static bool _isBotGate(String reason) =>
      reason.contains('not a bot') ||
      reason.contains('robot') ||
      reason.contains('botguard') ||
      reason.contains('机器人');

  /// Age gating. Matched with full phrases because a bare `age` also appears
  /// inside words like "page".
  static bool _isAgeGate(String reason) =>
      reason.contains('age-restricted') ||
      reason.contains('age restricted') ||
      reason.contains('confirm your age') ||
      reason.contains('age verification') ||
      reason.contains('18+') ||
      reason.contains('年龄');

  Future<YoutubeApiClient> _resolvePlaybackClient(
    Map<String, String> authHeaders,
  ) {
    final playbackClientLoader = this.playbackClientLoader;
    if (playbackClientLoader != null) {
      return playbackClientLoader(authHeaders);
    }
    return Future.value(_withAuthHeaders(_currentPlaybackClient, authHeaders));
  }

  @visibleForTesting
  static String summarizePlayerResponse(Map<String, dynamic> response) {
    final playability = response['playabilityStatus'];
    final status = playability is Map<String, dynamic>
        ? playability['status']
        : null;
    final streamingData = response['streamingData'];
    final streaming = streamingData is Map<String, dynamic>
        ? streamingData
        : const <String, dynamic>{};
    final playerConfig = response['playerConfig'];
    final mediaCommonConfig = playerConfig is Map<String, dynamic>
        ? playerConfig['mediaCommonConfig']
        : null;
    final mediaUstreamerRequestConfig =
        mediaCommonConfig is Map<String, dynamic>
        ? mediaCommonConfig['mediaUstreamerRequestConfig']
        : null;
    final ustreamerConfig = mediaUstreamerRequestConfig is Map<String, dynamic>
        ? mediaUstreamerRequestConfig['videoPlaybackUstreamerConfig']
        : null;

    return 'playabilityStatus=${status is String ? status : 'unknown'}; '
        'reasonCategory=${_playabilityReasonCategory(playability)}; '
        'streamingDataKeys=${streaming.keys.toList()..sort()}; '
        'formats=${_listLength(streaming['formats'])}; '
        'adaptiveFormats=${_listLength(streaming['adaptiveFormats'])}; '
        'serverAbrStreamingUrl=${_isPresent(streaming['serverAbrStreamingUrl'])}; '
        'videoPlaybackUstreamerConfig=${_isPresent(ustreamerConfig)}';
  }

  /// Returns the server-provided playability reason for debug logging.
  /// Kept separate from [summarizePlayerResponse] because that summary must
  /// never echo free-form server text.
  @visibleForTesting
  static String summarizePlayabilityReason(Map<String, dynamic> response) {
    final playability = response['playabilityStatus'];
    if (playability is! Map) return 'absent';
    final reason = playability['reason'];
    if (reason is! String || reason.isEmpty) return 'absent';
    return reason.length > 120 ? '${reason.substring(0, 120)}…' : reason;
  }

  static int _listLength(Object? value) => value is List ? value.length : 0;
  static bool _isPresent(Object? value) => value is String && value.isNotEmpty;

  /// Summarizes an Innertube error response without echoing credentials.
  @visibleForTesting
  static String summarizeErrorResponse(Map<String, dynamic> response) {
    final error = response['error'];
    if (error is! Map) return 'error=absent';
    final code = error['code'];
    final status = error['status'];
    final message = error['message'];
    final details = error['details'];
    final reasons = <String>[];
    if (details is List) {
      for (final detail in details) {
        if (detail is Map) {
          final reason = detail['reason'];
          if (reason is String && reason.isNotEmpty) reasons.add(reason);
        }
      }
    }
    final text = message is String ? message : '';
    return 'code=${code ?? 'unknown'}; status=${status ?? 'unknown'}; '
        'message=${text.length > 160 ? '${text.substring(0, 160)}…' : text}; '
        'reasons=${reasons.join(',')}';
  }

  static String _playabilityReasonCategory(Object? value) {
    if (value is! Map) return 'unknown';
    final reason = _stringsIn([
      value['reason'],
      value['messages'],
      value['errorScreen'],
    ]).join(' ').toLowerCase();
    if (reason.isEmpty) return 'unknown';
    if (reason.contains('sign in') || reason.contains('login')) {
      return 'authentication';
    }
    if (_isAgeGate(reason)) return 'age';
    if (reason.contains('country') || reason.contains('region')) {
      return 'region';
    }
    if (reason.contains('embed') || reason.contains('website')) return 'embed';
    if (reason.contains('private')) return 'private';
    if (reason.contains('not a bot') ||
        reason.contains('robot') ||
        reason.contains('botguard')) {
      return 'bot_verification';
    }
    if (reason.contains('not supported') ||
        reason.contains('unsupported') ||
        reason.contains('device')) {
      return 'client_compatibility';
    }
    if (reason.contains('unavailable') || reason.contains('not available')) {
      return 'unavailable';
    }
    if (reason.contains('network') || reason.contains('connection')) {
      return 'network';
    }
    if (reason.contains('temporarily')) return 'temporary';
    return 'other';
  }

  static Iterable<String> _stringsIn(Object? value) sync* {
    if (value is String) {
      yield value;
    } else if (value is Map) {
      for (final nested in value.values) {
        yield* _stringsIn(nested);
      }
    } else if (value is Iterable) {
      for (final nested in value) {
        yield* _stringsIn(nested);
      }
    }
  }

  List<VideoPlaybackSource> _sourcesFromManifest(StreamManifest manifest) {
    final adaptive = _adaptiveSources(manifest);
    if (adaptive.isNotEmpty) return adaptive;

    final hlsMuxed = manifest.hls.whereType<HlsMuxedStreamInfo>().toList();
    final Iterable<StreamInfo> candidates = hlsMuxed.isNotEmpty
        ? hlsMuxed
        : manifest.muxed;
    final sources = <String, VideoPlaybackSource>{};

    for (final stream in candidates) {
      if (stream is! VideoStreamInfo) continue;
      final uri = stream.url;
      final height = stream.videoResolution.height;
      if (uri.scheme != 'https' || height <= 0) continue;

      final label = stream.qualityLabel.trim().isNotEmpty
          ? stream.qualityLabel
          : '${height}p';
      final frameRate = stream.framerate.framesPerSecond;
      final key = '$label:$height:$frameRate';
      sources.putIfAbsent(
        key,
        () => VideoPlaybackSource(
          uri: uri,
          qualityLabel: label,
          height: height,
          frameRate: frameRate,
        ),
      );
    }

    return sources.values.toList()..sort(_compareSources);
  }

  List<VideoPlaybackSource> _adaptiveSources(StreamManifest manifest) {
    final audio = _pickAudio(manifest.audioOnly);
    if (audio == null) return const [];

    final videosByHeight = <int, VideoOnlyStreamInfo>{};
    for (final video in manifest.videoOnly) {
      final uri = video.url;
      final height = video.videoResolution.height;
      if (uri.scheme != 'https' || height <= 0) continue;
      if (height > _maxAdaptiveHeight) continue;

      final current = videosByHeight[height];
      if (current == null || _isPreferredVideo(video, current)) {
        videosByHeight[height] = video;
      }
    }

    final sources = <VideoPlaybackSource>[];
    for (final entry in videosByHeight.entries) {
      final video = entry.value;
      final label = video.qualityLabel.trim().isNotEmpty
          ? video.qualityLabel
          : '${entry.key}p';
      sources.add(
        VideoPlaybackSource(
          uri: video.url,
          audioUri: audio.url,
          qualityLabel: label,
          height: entry.key,
          frameRate: video.framerate.framesPerSecond,
        ),
      );
    }

    return sources..sort(_compareSources);
  }

  AudioOnlyStreamInfo? _pickAudio(Iterable<AudioOnlyStreamInfo> streams) {
    final candidates = streams
        .where((stream) => stream.url.scheme == 'https')
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final codecOrder = _audioCodecRank(a).compareTo(_audioCodecRank(b));
      if (codecOrder != 0) return codecOrder;
      return b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond);
    });
    return candidates.first;
  }

  static int _audioCodecRank(AudioStreamInfo stream) {
    final codec = stream.audioCodec.toLowerCase();
    if (codec.contains('mp4a')) return 0;
    if (codec.contains('opus')) return 1;
    return 2;
  }

  static bool _isPreferredVideo(
    VideoOnlyStreamInfo candidate,
    VideoOnlyStreamInfo current,
  ) {
    final codecOrder = _videoCodecRank(candidate)
        .compareTo(_videoCodecRank(current));
    if (codecOrder != 0) return codecOrder < 0;
    final frameRate = candidate.framerate.framesPerSecond;
    final currentFrameRate = current.framerate.framesPerSecond;
    if (frameRate != currentFrameRate) return frameRate > currentFrameRate;
    return candidate.bitrate.bitsPerSecond > current.bitrate.bitsPerSecond;
  }

  static int _videoCodecRank(VideoStreamInfo stream) {
    final codec = stream.videoCodec.toLowerCase();
    if (codec.contains('avc')) return 0;
    if (codec.contains('vp9') || codec.contains('vp09')) return 1;
    if (codec.contains('av01')) return 2;
    return 3;
  }

  static int _compareSources(VideoPlaybackSource a, VideoPlaybackSource b) {
    final heightOrder = b.height.compareTo(a.height);
    return heightOrder != 0 ? heightOrder : b.frameRate.compareTo(a.frameRate);
  }

  void _writePlaybackProbe(
    YoutubeApiClient client,
    String result, {
    required String attempt,
    Object? error,
  }) {
    if (!kDebugMode || manifestLoader != null) return;
    final clientData = client.payload['context']['client'];
    debugPrint(
      'FormatException: YouTube 播放源诊断；阶段：manifest；尝试：$attempt；'
      '客户端：${clientData['clientName']}；版本：${clientData['clientVersion']}；'
      'visitorData：${clientData.containsKey('visitorData') ? 'present' : 'absent'}；'
      'Authorization：${client.headers.containsKey('Authorization') ? 'present' : 'absent'}；'
      'X-Goog-Pageid：${client.headers.containsKey('X-Goog-Pageid') ? 'present' : 'absent'}；'
      '结果：$result${error == null ? '' : '；异常类型：${error.runtimeType}'}',
    );
  }

  /// Debug-only egress probe used to tell which public IP the app's HTTP
  /// client actually leaves from. It resolves the same `dart:io` stack that
  /// issues the player request, so it exposes VPN/proxy routing surprises.
  Future<void> _writeEgressProbe(String attempt) async {
    if (!kDebugMode || manifestLoader != null) return;
    try {
      final response = await _egressProbeClient
          .get(Uri.parse('https://api64.ipify.org'))
          .timeout(const Duration(seconds: 6));
      debugPrint(
        'FormatException: YouTube 播放源诊断；阶段：egress；尝试：$attempt；'
        'HTTP=${response.statusCode}；出口IP=${response.body.trim()}',
      );
    } catch (error) {
      debugPrint(
        'FormatException: YouTube 播放源诊断；阶段：egress；尝试：$attempt；'
        '异常类型：${error.runtimeType}',
      );
    }
  }

  void dispose() {
    unawaited(_streamLogSubscription?.cancel());
    _egressProbeClient.close();
    if (_ownsClient) {
      _client.close();
    }
  }
}

class _PlaybackResponseProbeClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  /// Last playability verdict seen on a `/youtubei/v1/player` response.
  ///
  /// Recorded in every build, not just debug builds, because the playback
  /// service uses it to explain a failure to the user. The reason text is kept
  /// only for classification and is never shown verbatim.
  String? playabilityStatus;
  String? playabilityReason;

  void reset() {
    playabilityStatus = null;
    playabilityReason = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final isYoutubeRequest = request.url.host == 'www.youtube.com';
    final isPlayerRequest =
        isYoutubeRequest && request.url.path.endsWith('/youtubei/v1/player');

    if (isPlayerRequest) {
      final body = await response.stream.toBytes();
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(body));
      } catch (_) {
        decoded = null;
      }
      final playability = decoded is Map<String, dynamic>
          ? decoded['playabilityStatus']
          : null;
      final status = playability is Map ? playability['status'] : null;
      final reason = playability is Map ? playability['reason'] : null;
      playabilityStatus = status is String ? status : null;
      playabilityReason = reason is String ? reason : null;

      if (kDebugMode) {
        if (decoded is Map<String, dynamic>) {
          debugPrint(
            'FormatException: YouTube player response probe; '
            'HTTP=${response.statusCode}; '
            '${YouTubeVideoPlaybackService.summarizePlayerResponse(decoded)}',
          );
          final reasonText =
              YouTubeVideoPlaybackService.summarizePlayabilityReason(decoded);
          if (reasonText != 'absent') {
            debugPrint('FormatException: YouTube player reason; $reasonText');
          }
          if (response.statusCode >= 400) {
            debugPrint(
              'FormatException: YouTube player error body; '
              '${YouTubeVideoPlaybackService.summarizeErrorResponse(decoded)}',
            );
          }
        } else {
          debugPrint(
            'FormatException: YouTube player response probe; '
            'HTTP=${response.statusCode}; JSON=invalid; bytes=${body.length}',
          );
        }
      }

      return _buffer(response, body);
    }

    final isWatchRequest = isYoutubeRequest && request.url.path == '/watch';
    if (!kDebugMode || !isWatchRequest) return response;

    final body = await response.stream.toBytes();
    final html = utf8.decode(body, allowMalformed: true);
    final status = RegExp(
      r'"playabilityStatus"\s*:\s*\{\s*"status"\s*:\s*"([^"]+)"',
    ).firstMatch(html)?.group(1);
    debugPrint(
      'FormatException: YouTube watch page probe; '
      'HTTP=${response.statusCode}; '
      'hasInitialPlayerResponse=${html.contains('ytInitialPlayerResponse')}; '
      'playabilityStatus=${status ?? 'unknown'}',
    );

    return _buffer(response, body);
  }

  http.StreamedResponse _buffer(
    http.StreamedResponse response,
    List<int> body,
  ) => http.StreamedResponse(
    Stream<List<int>>.value(body),
    response.statusCode,
    contentLength: body.length,
    request: response.request,
    headers: response.headers,
    isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection,
    reasonPhrase: response.reasonPhrase,
  );

  @override
  void close() {
    _inner.close();
  }
}
