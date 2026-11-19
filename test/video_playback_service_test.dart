import 'package:flutter_test/flutter_test.dart';
import 'package:http_parser/http_parser.dart';
import 'package:plexus/services/video_playback_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('summarizes streaming fields without returning secret values', () {
    final summary = YouTubeVideoPlaybackService.summarizePlayerResponse({
      'playabilityStatus': {'status': 'OK', 'reason': 'private reason'},
      'streamingData': {
        'formats': const [],
        'adaptiveFormats': const [],
        'serverAbrStreamingUrl': 'https://example.test/secret-url',
      },
      'playerConfig': {
        'mediaCommonConfig': {
          'mediaUstreamerRequestConfig': {
            'videoPlaybackUstreamerConfig': 'private config',
          },
        },
      },
    });

    expect(summary, contains('playabilityStatus=OK'));
    expect(summary, contains('reasonCategory=private'));
    expect(summary, contains('formats=0'));
    expect(summary, contains('adaptiveFormats=0'));
    expect(summary, contains('serverAbrStreamingUrl=true'));
    expect(summary, contains('videoPlaybackUstreamerConfig=true'));
    expect(summary, isNot(contains('secret-url')));
    expect(summary, isNot(contains('private config')));
    expect(summary, isNot(contains('private reason')));
  });

  test('summarizes playability reason text for diagnostics', () {
    final reason = YouTubeVideoPlaybackService.summarizePlayabilityReason({
      'playabilityStatus': {
        'status': 'LOGIN_REQUIRED',
        'reason': 'Sign in to confirm you are not a bot',
      },
    });

    expect(reason, 'Sign in to confirm you are not a bot');
    expect(
      YouTubeVideoPlaybackService.summarizePlayabilityReason({
        'playabilityStatus': {'status': 'OK'},
      }),
      'absent',
    );
  });

  test('summarizes innertube error responses without echoing headers', () {
    final summary = YouTubeVideoPlaybackService.summarizeErrorResponse({
      'error': {
        'code': 400,
        'status': 'INVALID_ARGUMENT',
        'message': 'Request contains an invalid argument.',
        'details': [
          {'reason': 'INVALID_ARGUMENT'},
        ],
      },
    });

    expect(summary, contains('code=400'));
    expect(summary, contains('status=INVALID_ARGUMENT'));
    expect(summary, contains('message=Request contains an invalid argument.'));
    expect(summary, contains('reasons=INVALID_ARGUMENT'));
  });

  test('does not classify image wording as an age restriction', () {
    final summary = YouTubeVideoPlaybackService.summarizePlayerResponse({
      'playabilityStatus': {
        'status': 'UNPLAYABLE',
        'reason': 'Image is unavailable for this request',
      },
    });

    expect(summary, isNot(contains('reasonCategory=age')));
  });

  test('classifies explicit age-restriction wording', () {
    final summary = YouTubeVideoPlaybackService.summarizePlayerResponse({
      'playabilityStatus': {
        'status': 'UNPLAYABLE',
        'reason': 'Please confirm your age to continue',
      },
    });

    expect(summary, contains('reasonCategory=age'));
  });

  test('classifies nested playability messages without logging their text', () {
    const privateMessage = 'This client is not supported on this device';
    final summary = YouTubeVideoPlaybackService.summarizePlayerResponse({
      'playabilityStatus': {
        'status': 'UNPLAYABLE',
        'messages': [
          {'text': privateMessage},
        ],
      },
    });

    expect(summary, contains('reasonCategory=client_compatibility'));
    expect(summary, isNot(contains(privateMessage)));
  });

  test('does not treat the playability status as a reason', () {
    final summary = YouTubeVideoPlaybackService.summarizePlayerResponse({
      'playabilityStatus': {'status': 'UNPLAYABLE'},
    });

    expect(summary, contains('reasonCategory=unknown'));
  });

  test('explains the bot gate as a network-level refusal', () {
    final message = YouTubeVideoPlaybackService.playabilityFailureMessage(
      status: 'LOGIN_REQUIRED',
      reason: 'Sign in to confirm you’re not a bot',
    );

    expect(message, isNotNull);
    expect(message, contains('机器人'));
    expect(message, contains('网络'));
  });

  test('recognizes the localized bot gate wording', () {
    final message = YouTubeVideoPlaybackService.playabilityFailureMessage(
      status: 'LOGIN_REQUIRED',
      reason: '请登录，以便我们确认你不是聊天机器人',
    );

    expect(message, contains('机器人'));
  });

  test('does not explain an age gate as a bot gate', () {
    final message = YouTubeVideoPlaybackService.playabilityFailureMessage(
      status: 'LOGIN_REQUIRED',
      reason: 'Sign in to confirm your age',
    );

    expect(message, contains('年龄'));
    expect(message, isNot(contains('机器人')));
  });

  test('does not read "page" as an age gate', () {
    expect(
      YouTubeVideoPlaybackService.playabilityFailureMessage(
        status: 'UNPLAYABLE',
        reason: 'The page needs to be reloaded.',
      ),
      isNull,
    );
  });

  test('stays quiet when the player response was playable', () {
    expect(
      YouTubeVideoPlaybackService.playabilityFailureMessage(
        status: 'OK',
        reason: 'ignored',
      ),
      isNull,
    );
    expect(YouTubeVideoPlaybackService.playabilityFailureMessage(), isNull);
  });

  test('rejects an empty video ID without requesting a manifest', () async {
    var requested = false;
    final service = YouTubeVideoPlaybackService(
      manifestLoader: (_, _) async {
        requested = true;
        return StreamManifest(const []);
      },
    );
    addTearDown(service.dispose);

    await expectLater(
      service.resolveSources(' '),
      throwsA(isA<VideoPlaybackSourceException>()),
    );
    expect(requested, isFalse);
  });

  test('reports manifests without muxed audio-video sources', () async {
    final service = YouTubeVideoPlaybackService(
      manifestLoader: (_, _) async => StreamManifest(const []),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.resolveSources('video-id'),
      throwsA(isA<VideoPlaybackSourceException>()),
    );
  });

  test('requests the manifest with the Android SDK-less client', () async {
    final requestedClients = <YoutubeApiClient>[];
    final service = YouTubeVideoPlaybackService(
      manifestLoader: (_, client) async {
        requestedClients.add(client);
        return StreamManifest(const []);
      },
    );
    addTearDown(service.dispose);

    await expectLater(
      service.resolveSources('video-id'),
      throwsA(isA<VideoPlaybackSourceException>()),
    );
    expect(
      requestedClients.map(
        (client) => client.payload['context']['client']['clientName'],
      ),
      everyElement('ANDROID'),
    );
    expect(
      requestedClients.map(
        (client) => client.payload['context']['client']['clientVersion'],
      ),
      ['20.10.38'],
    );
    expect(
      requestedClients.first.payload['context']['client']['userAgent'],
      contains('com.google.android.youtube/20.10.38'),
    );
    expect(
      requestedClients.first.payload['context']['client'],
      isNot(contains('androidSdkVersion')),
    );
  });

  test('sanitizes manifest request failures', () async {
    final service = YouTubeVideoPlaybackService(
      manifestLoader: (_, _) async =>
          throw Exception('https://example.test/stream?token=secret'),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.resolveSources('video-id'),
      throwsA(
        isA<VideoPlaybackSourceException>()
            .having((error) => error.message, 'message', contains('Exception'))
            .having(
              (error) => error.message,
              'message',
              isNot(contains('secret')),
            ),
      ),
    );
  });

  test('pairs adaptive video with one audio track up to 1080p', () async {
    final audioAac = _audio(tag: 140, codec: 'mp4a.40.2', bitrate: 128000);
    final audioOpus = _audio(tag: 251, codec: 'opus', bitrate: 160000);
    final hd1080Avc = _video(
      tag: 137,
      codec: 'avc1.640028',
      label: '1080p',
      height: 1080,
      bitrate: 4000000,
    );
    final hd1080Vp9 = _video(
      tag: 248,
      codec: 'vp9',
      label: '1080p',
      height: 1080,
      bitrate: 3000000,
    );
    final hd720 = _video(
      tag: 136,
      codec: 'avc1.4d401f',
      label: '720p',
      height: 720,
      bitrate: 2000000,
    );
    final uhd2160 = _video(
      tag: 313,
      codec: 'vp9',
      label: '2160p',
      height: 2160,
      bitrate: 20000000,
    );
    final muxed = _muxed(tag: 18, label: '360p', height: 360);

    final service = YouTubeVideoPlaybackService(
      manifestLoader: (_, _) async => StreamManifest([
        uhd2160,
        hd1080Vp9,
        hd1080Avc,
        hd720,
        audioOpus,
        audioAac,
        muxed,
      ]),
    );
    addTearDown(service.dispose);

    final sources = await service.resolveSources('video-id');

    expect(sources.map((source) => source.height), [1080, 720]);
    expect(sources.first.uri, hd1080Avc.url);
    expect(sources.every((source) => source.audioUri == audioAac.url), isTrue);
  });

  test(
    'falls back to muxed streams when adaptive tracks are missing',
    () async {
      final muxed = _muxed(tag: 18, label: '360p', height: 360);
      final service = YouTubeVideoPlaybackService(
        manifestLoader: (_, _) async => StreamManifest([muxed]),
      );
      addTearDown(service.dispose);

      final sources = await service.resolveSources('video-id');

      expect(sources, hasLength(1));
      expect(sources.single.uri, muxed.url);
      expect(sources.single.audioUri, isNull);
      expect(sources.single.qualityLabel, '360p');
    },
  );

  test(
    'retries anonymously when the authenticated player request fails',
    () async {
      final clients = <YoutubeApiClient>[];
      final muxed = _muxed(tag: 18, label: '360p', height: 360);
      final service = YouTubeVideoPlaybackService(
        manifestLoader: (_, client) async {
          clients.add(client);
          if (client.headers.containsKey('Authorization')) {
            throw FatalFailureException('HTTP 400', 400);
          }
          return StreamManifest([muxed]);
        },
      );
      addTearDown(service.dispose);

      final sources = await service.resolveSources(
        'video-id',
        authHeaders: const {'Authorization': 'Bearer test-token'},
      );

      expect(sources.single.uri, muxed.url);
      expect(clients, hasLength(2));
      expect(clients.first.headers['Authorization'], 'Bearer test-token');
      expect(clients.last.headers, isNot(contains('Authorization')));
    },
  );
}

final _videoId = VideoId('dQw4w9WgXcQ');
const _fileSize = FileSize(1000);

VideoOnlyStreamInfo _video({
  required int tag,
  required String codec,
  required String label,
  required int height,
  required int bitrate,
}) => VideoOnlyStreamInfo(
  _videoId,
  tag,
  Uri.parse('https://example.test/video-$tag'),
  StreamContainer.mp4,
  _fileSize,
  Bitrate(bitrate),
  codec,
  label,
  VideoQuality.high1080,
  VideoResolution(height * 16 ~/ 9, height),
  const Framerate(30),
  const [],
  MediaType.parse('video/mp4'),
);

AudioOnlyStreamInfo _audio({
  required int tag,
  required String codec,
  required int bitrate,
}) => AudioOnlyStreamInfo(
  _videoId,
  tag,
  Uri.parse('https://example.test/audio-$tag'),
  StreamContainer.mp4,
  _fileSize,
  Bitrate(bitrate),
  codec,
  'medium',
  const [],
  MediaType.parse('audio/mp4'),
  null,
);

MuxedStreamInfo _muxed({
  required int tag,
  required String label,
  required int height,
}) => MuxedStreamInfo(
  _videoId,
  tag,
  Uri.parse('https://example.test/muxed-$tag'),
  StreamContainer.mp4,
  _fileSize,
  const Bitrate(1000000),
  'mp4a.40.2',
  'avc1.42001E',
  label,
  VideoQuality.medium360,
  VideoResolution(height * 16 ~/ 9, height),
  const Framerate(30),
  MediaType.parse('video/mp4'),
);
