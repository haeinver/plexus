import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/video.dart';
import '../models/video_section.dart';
import 'locale_service.dart';
import 'youtube_auth_service.dart';

typedef _HomeRequestConfig = ({
  Uri uri,
  Map<String, String> headers,
  Map<String, dynamic> context,
});

/// Real YouTube InnerTube API Data Service
/// Strictly matches SmartTube V2 MediaServiceCore (QueryBuilder.kt / BrowseService2.kt / TVHTML5 Client).
class YouTubeDataService {
  static final YouTubeDataService _instance = YouTubeDataService._internal();
  factory YouTubeDataService() => _instance;
  YouTubeDataService._internal();

  static const String _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  /// Fetch Real Home Feed Videos strictly using SmartTube TVHTML5 Client & QueryBuilder JSON
  Future<List<VideoSection>> fetchHomeFeed() async {
    return fetchHomeFeedProgressively().last;
  }

  Future<_HomeRequestConfig> _createHomeRequestConfig() async {
    final authService = YouTubeAuthService();
    await authService.init();
    if (!authService.isLoggedIn) {
      throw StateError('未登录 YouTube 账号，无法请求首页内容');
    }

    final localeService = LocaleService();
    await localeService.init();

    final authHeaders = await authService.getAuthHeaders();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
      'Referer': 'https://www.youtube.com/tv',
      ...authHeaders,
    };
    final context = <String, dynamic>{
      'client': {
        'clientName': 'TVHTML5',
        'clientVersion': '7.20260901.15.00',
        'clientScreen': 'WATCH',
        'userAgent': 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
        'acceptLanguage': localeService.language,
        'acceptRegion': localeService.region,
        'utcOffsetMinutes': localeService.utcOffsetMinutes.toString(),
      },
      'user': {'enableSafetyMode': false, 'lockedSafetyMode': false},
    };

    return (
      uri: Uri.parse('https://www.youtube.com/youtubei/v1/browse?key=$_apiKey'),
      headers: headers,
      context: context,
    );
  }

  Future<VideoSection> fetchMoreHomeSectionVideos(VideoSection section) async {
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return section;

    final request = await _createHomeRequestConfig();
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode({
            'context': request.context,
            'continuation': token,
          }),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception(
        'YouTube 首页分区续页接口响应异常 '
        '[HTTP ${response.statusCode}]: ${_shortMsg(response.body)}',
      );
    }

    return parseHomeSectionContinuationResponse(
      section,
      json.decode(response.body),
    );
  }

  Future<VideoSection> fetchBrowseDestination(VideoSection destination) async {
    final browseId = destination.browseId;
    if (browseId == null || browseId.isEmpty) {
      throw ArgumentError('YouTube 浏览入口缺少 browseId');
    }

    final request = await _createHomeRequestConfig();
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode({
            'context': request.context,
            'browseId': browseId,
            if (destination.browseParams != null)
              'params': destination.browseParams,
          }),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception(
        'YouTube 浏览入口接口响应异常 '
        '[HTTP ${response.statusCode}]: ${_shortMsg(response.body)}',
      );
    }

    return parseBrowseDestinationResponse(
      destination,
      json.decode(response.body),
    );
  }

  Future<VideoSection> fetchMoreBrowseDestinationVideos(
    VideoSection section,
  ) async {
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return section;

    final request = await _createHomeRequestConfig();
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode({
            'context': request.context,
            'continuation': token,
          }),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception(
        'YouTube 浏览列表续页接口响应异常 '
        '[HTTP ${response.statusCode}]: ${_shortMsg(response.body)}',
      );
    }

    return parseBrowseDestinationContinuationResponse(
      section,
      json.decode(response.body),
    );
  }

  Stream<List<VideoSection>> fetchHomeFeedProgressively() async* {
    final request = await _createHomeRequestConfig();
    final body = json.encode({
      'context': request.context,
      'racyCheckOk': true,
      'contentCheckOk': true,
      'browseId': 'default',
    });

    final response = await http
        .post(request.uri, headers: request.headers, body: body)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception(
        'YouTube TVHTML5 首页接口响应异常 [HTTP ${response.statusCode}]: ${_shortMsg(response.body)}',
      );
    }

    final dynamic data = json.decode(response.body);
    final sections = parseHomeFeedResponse(data);
    yield List.unmodifiable(sections);
    var continuation = extractHomeSectionContinuationToken(data);
    final seenTokens = <String>{};

    while (continuation != null && continuation.isNotEmpty) {
      if (!seenTokens.add(continuation)) {
        throw const FormatException('YouTube 首页 continuation token 重复');
      }

      final continuationResponse = await http
          .post(
            request.uri,
            headers: request.headers,
            body: json.encode({
              'context': request.context,
              'continuation': continuation,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (continuationResponse.statusCode != 200) {
        throw Exception(
          'YouTube TVHTML5 首页 continuation 响应异常 '
          '[HTTP ${continuationResponse.statusCode}]: '
          '${_shortMsg(continuationResponse.body)}',
        );
      }

      final dynamic continuationData = json.decode(continuationResponse.body);
      final nextSections = parseHomeContinuationResponse(continuationData);
      if (nextSections.isEmpty) break;

      sections.addAll(nextSections);
      yield List.unmodifiable(sections);
      continuation = extractHomeSectionContinuationToken(continuationData);
    }
  }

  @visibleForTesting
  List<VideoSection> parseHomeFeedResponse(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube 首页响应不是 JSON 对象');
    }

    final dynamic tvContent =
        data['contents']?['tvBrowseRenderer']?['content']?['tvSurfaceContentRenderer']?['content'];
    if (tvContent is! Map<String, dynamic>) {
      throw const FormatException('YouTube TV 首页响应缺少 surface content');
    }

    final dynamic rawShelves = tvContent['sectionListRenderer']?['contents'];
    if (rawShelves is! List) {
      throw const FormatException(
        'YouTube TV 首页响应缺少 sectionListRenderer.contents',
      );
    }

    final sections = _parseHomeShelves(rawShelves);
    if (sections.isEmpty) {
      throw const FormatException('YouTube 首页响应中没有可解析的视频分区');
    }
    return sections;
  }

  @visibleForTesting
  List<VideoSection> parseHomeContinuationResponse(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube 首页 continuation 响应不是 JSON 对象');
    }

    final sectionList = _continuationSectionList(data);
    final dynamic rawShelves = sectionList?['contents'];
    if (rawShelves is! List) {
      final continuationContents = data['continuationContents'];
      if (continuationContents is Map<String, dynamic> &&
          continuationContents['horizontalListContinuation']
              is Map<String, dynamic>) {
        return const [];
      }
      throw const FormatException(
        'YouTube 首页 continuation 缺少 sectionListContinuation.contents',
      );
    }
    return _parseHomeShelves(rawShelves);
  }

  @visibleForTesting
  VideoSection parseHomeSectionContinuationResponse(
    VideoSection section,
    dynamic data,
  ) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube 分区 continuation 响应不是 JSON 对象');
    }

    final continuationContents = data['continuationContents'];
    if (continuationContents is! Map<String, dynamic>) {
      throw const FormatException(
        'YouTube 分区 continuation 缺少 continuationContents',
      );
    }

    final dynamic rawGridRenderer =
        continuationContents['horizontalListContinuation'] ??
        continuationContents['gridContinuation'] ??
        continuationContents['playlistVideoListContinuation'] ??
        continuationContents['tvSurfaceContentContinuation']?['content']?['gridRenderer'];
    final sectionListContinuation = _continuationSectionList(data);
    if (rawGridRenderer != null && rawGridRenderer is! Map<String, dynamic>) {
      throw const FormatException(
        'YouTube 分区 continuation 的 grid renderer 格式无效',
      );
    }
    final Map<String, dynamic>? gridRenderer =
        rawGridRenderer as Map<String, dynamic>?;
    if (gridRenderer == null && sectionListContinuation == null) {
      throw FormatException(
        'YouTube 分区 continuation 缺少列表 renderer；'
        'continuationContents 字段：${continuationContents.keys.toList()}；'
        '结构：${_describeJsonShape(continuationContents)}',
      );
    }

    final dynamic rawItems = gridRenderer != null
        ? gridRenderer['items'] ?? gridRenderer['contents']
        : sectionListContinuation!['contents'];
    if (rawItems is! List) {
      throw const FormatException('YouTube 分区 continuation 缺少 items/contents');
    }

    final newVideos = <Video>[];
    _extractSectionVideos(rawItems, section.title ?? '', newVideos);
    final videos = [...section.videos];
    for (final video in newVideos) {
      final alreadyPresent = videos.any((existing) {
        if (video.id != null) return existing.id == video.id;
        return video.browseId != null && existing.browseId == video.browseId;
      });
      if (!alreadyPresent) videos.add(video);
    }

    return VideoSection(
      title: section.title,
      videos: videos,
      continuationToken:
          _extractNextContinuationToken(gridRenderer) ??
          _extractNextContinuationToken(sectionListContinuation) ??
          _findContinuationToken(rawItems),
    );
  }

  @visibleForTesting
  VideoSection parseBrowseDestinationResponse(
    VideoSection destination,
    dynamic data,
  ) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube 浏览入口响应不是 JSON 对象');
    }
    final pageTitle = destination.title ?? destination.browseTitle;
    if (pageTitle == null || pageTitle.trim().isEmpty) {
      throw const FormatException('YouTube 浏览入口缺少页面标题');
    }

    final dynamic tvContent =
        data['contents']?['tvBrowseRenderer']?['content']?['tvSurfaceContentRenderer']?['content'];
    if (tvContent is! Map<String, dynamic>) {
      throw const FormatException('YouTube 浏览入口响应缺少 TV surface content');
    }

    final rawSectionList = tvContent['sectionListRenderer'];
    final Map<String, dynamic>? sectionList =
        rawSectionList is Map<String, dynamic> ? rawSectionList : null;
    final dynamic rawItems;
    Map<String, dynamic>? listRenderer;
    if (sectionList != null) {
      rawItems = sectionList['contents'];
      if (rawItems is! List) {
        throw const FormatException(
          'YouTube 浏览入口缺少 sectionListRenderer.contents',
        );
      }
    } else {
      final dynamic renderer =
          tvContent['gridRenderer'] ?? tvContent['horizontalListRenderer'];
      if (renderer is! Map<String, dynamic>) {
        throw const FormatException('YouTube 浏览入口缺少列表 renderer');
      }
      listRenderer = renderer;
      rawItems = renderer['items'] ?? renderer['contents'];
      if (rawItems is! List) {
        throw const FormatException('YouTube 浏览入口缺少 items/contents');
      }
    }

    final videos = <Video>[];
    _extractSectionVideos(rawItems, pageTitle, videos);
    final continuationToken =
        _extractNextContinuationToken(sectionList) ??
        _extractNextContinuationToken(listRenderer) ??
        _findContinuationToken(rawItems);
    if (videos.isEmpty && continuationToken == null) {
      throw const FormatException('YouTube 浏览入口没有可解析的视频或后续内容');
    }

    return VideoSection(
      title: pageTitle,
      videos: videos,
      continuationToken: continuationToken,
    );
  }

  @visibleForTesting
  VideoSection parseBrowseDestinationContinuationResponse(
    VideoSection section,
    dynamic data,
  ) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube 浏览列表 continuation 响应不是 JSON 对象');
    }

    final sectionList = _continuationSectionList(data);
    final dynamic rawItems;
    Map<String, dynamic>? listRenderer;
    if (sectionList != null) {
      rawItems = sectionList['contents'];
      if (rawItems is! List) {
        throw const FormatException(
          'YouTube 浏览列表 continuation 缺少 sectionListContinuation.contents',
        );
      }
    } else {
      final continuationContents = data['continuationContents'];
      if (continuationContents is! Map<String, dynamic>) {
        throw const FormatException(
          'YouTube 浏览列表 continuation 缺少 continuationContents',
        );
      }
      final dynamic renderer =
          continuationContents['gridContinuation'] ??
          continuationContents['horizontalListContinuation'] ??
          continuationContents['tvSurfaceContentContinuation']?['content']?['gridRenderer'];
      if (renderer is! Map<String, dynamic>) {
        throw const FormatException('YouTube 浏览列表 continuation 缺少列表 renderer');
      }
      listRenderer = renderer;
      rawItems = renderer['items'] ?? renderer['contents'];
      if (rawItems is! List) {
        throw const FormatException(
          'YouTube 浏览列表 continuation 缺少 items/contents',
        );
      }
    }

    final newVideos = <Video>[];
    _extractSectionVideos(rawItems, section.title ?? '', newVideos);
    final videos = [...section.videos];
    for (final video in newVideos) {
      final alreadyPresent = videos.any((existing) {
        if (video.id != null) return existing.id == video.id;
        return video.browseId != null && existing.browseId == video.browseId;
      });
      if (!alreadyPresent) videos.add(video);
    }

    final continuationToken =
        _extractNextContinuationToken(sectionList) ??
        _extractNextContinuationToken(listRenderer) ??
        _findContinuationToken(rawItems);
    if (videos.length == section.videos.length &&
        continuationToken == section.continuationToken) {
      throw const FormatException(
        'YouTube 浏览列表续页没有新增条目且 continuation token 未变化',
      );
    }

    return VideoSection(
      title: section.title,
      videos: videos,
      continuationToken: continuationToken,
    );
  }

  @visibleForTesting
  String? extractHomeSectionContinuationToken(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube 首页响应不是 JSON 对象');
    }
    final sectionList =
        _continuationSectionList(data) ?? _initialSectionList(data);
    return _homeSectionListContinuationToken(sectionList);
  }

  String? _homeSectionListContinuationToken(Map<String, dynamic>? sectionList) {
    final token = _extractNextContinuationToken(sectionList);
    if (token != null) return token;

    final contents = sectionList?['contents'];
    if (contents is! List || contents.isEmpty) return null;

    final firstShelf = contents.first;
    if (firstShelf is! Map<String, dynamic>) return null;
    final shelfRenderer = firstShelf['shelfRenderer'];
    if (shelfRenderer is! Map<String, dynamic>) return null;

    return _extractShelfContinuationToken(shelfRenderer);
  }

  Map<String, dynamic>? _initialSectionList(Map<String, dynamic> data) {
    final dynamic sectionList =
        data['contents']?['tvBrowseRenderer']?['content']?['tvSurfaceContentRenderer']?['content']?['sectionListRenderer'];
    return sectionList is Map<String, dynamic> ? sectionList : null;
  }

  Map<String, dynamic>? _continuationSectionList(Map<String, dynamic> data) {
    final dynamic sectionList =
        data['continuationContents']?['sectionListContinuation'] ??
        data['continuationContents']?['tvSurfaceContentContinuation']?['content']?['sectionListRenderer'];
    return sectionList is Map<String, dynamic> ? sectionList : null;
  }

  String? _extractNextContinuationToken(Map<String, dynamic>? sectionList) {
    if (sectionList == null) return null;

    return _extractContinuationToken(sectionList['continuations']);
  }

  String? _extractShelfContinuationToken(Map<String, dynamic> shelf) {
    final continuations =
        shelf['content']?['horizontalListRenderer']?['continuations'];
    return _extractContinuationToken(continuations);
  }

  String? _findContinuationToken(dynamic node) {
    if (node is Map<String, dynamic>) {
      if (node.containsKey('gridButtonRenderer')) {
        return _extractGridButtonContinuation(node['gridButtonRenderer']);
      }
      final token = _extractContinuationToken(node['continuations']);
      if (token != null) return token;
      for (final value in node.values) {
        final nestedToken = _findContinuationToken(value);
        if (nestedToken != null) return nestedToken;
      }
    } else if (node is List) {
      for (final item in node) {
        final token = _findContinuationToken(item);
        if (token != null) return token;
      }
    }
    return null;
  }

  String? _extractContinuationToken(dynamic continuations) {
    if (continuations is List) {
      for (final item in continuations) {
        final token =
            item?['nextContinuationData']?['continuation'] ??
            item?['nextRadioContinuationData']?['continuation'] ??
            item?['reloadContinuationData']?['continuation'];
        if (token is String && token.isNotEmpty) return token;
      }
    }

    return null;
  }

  List<VideoSection> _parseHomeShelves(List<dynamic> rawShelves) {
    final sections = <VideoSection>[];
    for (final sectionNode in rawShelves) {
      if (sectionNode is! Map<String, dynamic>) {
        throw FormatException('YouTube 首页包含无效分区节点：${sectionNode.runtimeType}');
      }
      if (sectionNode.containsKey('appealSurveyShelfRenderer')) {
        if (sectionNode['appealSurveyShelfRenderer'] is! Map<String, dynamic>) {
          throw const FormatException('YouTube appealSurveyShelfRenderer 格式无效');
        }
        continue;
      }

      final dynamic rawShelf = sectionNode['shelfRenderer'];
      if (rawShelf == null) {
        if (sectionNode.containsKey('adSlotRenderer') ||
            sectionNode.containsKey('continuationItemRenderer')) {
          continue;
        }
        throw FormatException(
          'YouTube 首页包含不支持的分区 renderer：${sectionNode.keys.toList()}',
        );
      }
      if (rawShelf is! Map<String, dynamic>) {
        throw const FormatException('YouTube 首页 shelfRenderer 格式无效');
      }

      final title = _extractShelfTitle(rawShelf);
      final browseDestination = _extractShelfBrowseDestination(rawShelf);
      final items = _extractShelfItems(sectionNode, rawShelf);
      if (items == null && browseDestination == null) {
        throw FormatException(
          'YouTube 首页分区「${title ?? '(无标题)'}」没有受支持的条目列表或浏览入口',
        );
      }

      final videos = <Video>[];
      if (items != null) _extractSectionVideos(items, title ?? '', videos);
      final continuationToken =
          _extractShelfContinuationToken(rawShelf) ??
          (items == null ? null : _findContinuationToken(items));
      if (videos.isEmpty &&
          browseDestination == null &&
          items != null &&
          items.isNotEmpty &&
          items.every(_isGridButtonOnlyEntry)) {
        continue;
      }
      if (videos.isEmpty &&
          browseDestination == null &&
          continuationToken == null) {
        final itemShapes = items
            ?.take(6)
            .map((item) => _describeJsonShape(item))
            .toList();
        throw FormatException(
          'YouTube 首页分区「${title ?? '(无标题)'}」没有可解析的内容；'
          'shelf字段：${rawShelf.keys.toList()}；'
          'content结构：${_describeJsonShape(rawShelf['content'])}；'
          '条目结构：$itemShapes；'
          'continuation：${_extractShelfContinuationToken(rawShelf) != null}',
        );
      }
      sections.add(
        VideoSection(
          title: title,
          videos: videos,
          continuationToken: continuationToken,
          browseId: browseDestination?.browseId,
          browseParams: browseDestination?.browseParams,
          browseTitle: browseDestination?.title,
        ),
      );
    }
    return sections;
  }

  String _shortMsg(String msg) {
    if (msg.length > 200) {
      return '${msg.substring(0, 200)}...';
    }
    return msg;
  }

  String? _extractShelfTitle(Map<String, dynamic> shelf) {
    final shelfHeader = shelf['headerRenderer']?['shelfHeaderRenderer'];
    return _extractText(shelf['title']) ??
        _extractText(shelfHeader?['title']) ??
        _extractText(
          shelfHeader?['avatarLockup']?['avatarLockupRenderer']?['title'],
        );
  }

  ({String browseId, String? browseParams, String title})?
  _extractShelfBrowseDestination(Map<String, dynamic> shelf) {
    final shelfHeader = shelf['headerRenderer']?['shelfHeaderRenderer'];
    final dynamic rawMoreButton = shelfHeader?['moreContentButton'];
    if (rawMoreButton == null) return null;
    if (rawMoreButton is! Map<String, dynamic>) {
      throw const FormatException('YouTube shelf moreContentButton 格式无效');
    }

    final button = rawMoreButton['buttonRenderer'];
    if (button is! Map<String, dynamic>) {
      throw const FormatException(
        'YouTube shelf moreContentButton 缺少 buttonRenderer',
      );
    }
    final title = _extractText(button['text']);
    if (title == null || title.trim().isEmpty) {
      throw const FormatException('YouTube shelf moreContentButton 缺少标题');
    }

    final browseEndpoint = button['navigationEndpoint']?['browseEndpoint'];
    if (browseEndpoint is! Map<String, dynamic>) {
      throw const FormatException(
        'YouTube shelf moreContentButton 缺少 browseEndpoint',
      );
    }
    final browseId = browseEndpoint['browseId']?.toString();
    if (browseId == null || browseId.isEmpty) {
      throw const FormatException(
        'YouTube shelf moreContentButton 缺少 browseId',
      );
    }

    final browseParams = browseEndpoint['params']?.toString();
    return (
      browseId: browseId,
      browseParams: browseParams == null || browseParams.isEmpty
          ? null
          : browseParams,
      title: title,
    );
  }

  List<dynamic>? _extractShelfItems(
    Map<String, dynamic> shelfWrapper,
    Map<String, dynamic> shelfRenderer,
  ) {
    final content = shelfRenderer['content'];
    if (content is Map<String, dynamic>) {
      final horizontalItems = content['horizontalListRenderer']?['items'];
      if (horizontalItems is List) return horizontalItems;

      final expandedItems = content['expandedShelfContentsRenderer']?['items'];
      if (expandedItems is List) return expandedItems;

      final shelfGridItems = content['gridRenderer']?['items'];
      if (shelfGridItems is List) return shelfGridItems;
    }

    final featuredItems =
        shelfWrapper['channelFeaturedContentRenderer']?['items'];
    if (featuredItems is List) return featuredItems;

    final gridItems = shelfWrapper['gridRenderer']?['items'];
    if (gridItems is List) return gridItems;

    final playlistVideoItems =
        shelfWrapper['playlistVideoListRenderer']?['contents'];
    if (playlistVideoItems is List) return playlistVideoItems;

    final videoRenderer = shelfWrapper['videoRenderer'];
    if (videoRenderer is Map<String, dynamic>) {
      return [
        <String, dynamic>{'videoRenderer': videoRenderer},
      ];
    }

    return null;
  }

  void _extractSectionVideos(
    dynamic node,
    String sectionTitle,
    List<Video> result,
  ) {
    if (node is Map<String, dynamic>) {
      if (node.containsKey('adSlotRenderer') ||
          node.containsKey('continuationItemRenderer')) {
        return;
      }

      final rendererKeys = const [
        'videoRenderer',
        'gridVideoRenderer',
        'compactVideoRenderer',
        'playlistVideoRenderer',
      ].where(node.containsKey).toList();
      if (rendererKeys.length > 1 ||
          (rendererKeys.isNotEmpty && node.containsKey('tileRenderer'))) {
        throw FormatException(
          'YouTube 分区「$sectionTitle」条目包含多个内容 renderer：${node.keys.toList()}',
        );
      }
      if (rendererKeys.isNotEmpty) {
        final video = _parseVideoRenderer(
          node[rendererKeys.single],
          sectionTitle,
        );
        if (!result.any((item) => item.id == video.id)) result.add(video);
        return;
      }
      if (node['tileRenderer'] != null) {
        final video = _parseTileRenderer(node['tileRenderer'], sectionTitle);
        if (!result.any(
          (item) => item.id == video.id && item.browseId == video.browseId,
        )) {
          result.add(video);
        }
        return;
      }
      if (node['richItemRenderer'] is Map<String, dynamic>) {
        _extractSectionVideos(
          node['richItemRenderer']['content'],
          sectionTitle,
          result,
        );
        return;
      }
      if (node['itemSectionRenderer'] is Map<String, dynamic>) {
        _extractSectionVideos(
          node['itemSectionRenderer']['contents'],
          sectionTitle,
          result,
        );
        return;
      }
      if (node['shelfRenderer'] is Map<String, dynamic>) {
        final shelf = node['shelfRenderer'] as Map<String, dynamic>;
        final items = _extractShelfItems(node, shelf);
        if (items == null) {
          throw FormatException('YouTube 分区「$sectionTitle」的 shelf 缺少受支持的条目列表');
        }
        _extractSectionVideos(items, sectionTitle, result);
        return;
      }
      if (node.containsKey('gridButtonRenderer')) {
        _extractGridButtonContinuation(node['gridButtonRenderer']);
        return;
      }
      throw FormatException(
        'YouTube 分区「$sectionTitle」包含不支持的条目 renderer：${node.keys.toList()}',
      );
    } else if (node is List) {
      for (final item in node) {
        _extractSectionVideos(item, sectionTitle, result);
      }
    } else {
      throw FormatException(
        'YouTube 分区「$sectionTitle」包含无效条目：${node.runtimeType}',
      );
    }
  }

  bool _isGridButtonOnlyEntry(dynamic node) =>
      node is Map<String, dynamic> &&
      node.length == 1 &&
      node['gridButtonRenderer'] is Map<String, dynamic>;

  String _extractGridButtonContinuation(dynamic rawButton) {
    if (rawButton is! Map<String, dynamic>) {
      throw const FormatException('YouTube gridButtonRenderer 格式无效');
    }
    final title = _extractText(rawButton['title']);
    if (title == null || title.trim().isEmpty) {
      throw const FormatException('YouTube gridButtonRenderer 缺少标题');
    }
    final navigation = rawButton['navigationEndpoint'];
    if (navigation is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube gridButtonRenderer「$title」缺少 navigationEndpoint',
      );
    }
    final reloadCommand = navigation['loadReloadContinuationCommand'];
    if (reloadCommand is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube gridButtonRenderer「$title」缺少 loadReloadContinuationCommand；'
        'navigationEndpoint 字段：${navigation.keys.toList()}',
      );
    }
    final token = reloadCommand['continuation']?.toString();
    if (token == null || token.isEmpty) {
      throw FormatException(
        'YouTube gridButtonRenderer「$title」的 reload command 缺少 continuation',
      );
    }
    return token;
  }

  Video _parseVideoRenderer(dynamic renderer, String sectionTitle) {
    if (renderer is! Map<String, dynamic>) {
      throw const FormatException('YouTube 视频条目格式无效');
    }

    final videoId = renderer['videoId']?.toString();
    if (videoId == null || videoId.isEmpty) {
      throw const FormatException('YouTube 视频条目缺少 videoId');
    }

    final title = _extractText(renderer['title']);
    if (title == null || title.trim().isEmpty) {
      throw FormatException('YouTube 视频 $videoId 缺少标题');
    }
    final channelName =
        _extractText(renderer['shortBylineText']) ??
        _extractText(renderer['ownerText']) ??
        _extractText(renderer['longBylineText']) ??
        '';

    final views =
        _extractText(renderer['viewCountText']) ??
        _extractText(renderer['shortViewCountText']) ??
        '';

    final uploadTime = _extractText(renderer['publishedTimeText']) ?? '';
    final duration = _extractText(renderer['lengthText']) ?? '';

    final thumbnailUrl = _extractThumbnail(renderer['thumbnail']);
    if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
      final thumbnailFields = renderer.keys
          .where((key) => key.toLowerCase().contains('thumbnail'))
          .toList();
      throw FormatException(
        'YouTube 视频 $videoId 缺少缩略图地址；响应图片字段：$thumbnailFields',
      );
    }

    final channelAvatar =
        _extractThumbnail(renderer['channelThumbnail']) ??
        _extractThumbnail(renderer['authorPhoto']) ??
        '';

    return Video(
      id: videoId,
      itemType: VideoItemType.video,
      isLive:
          _hasVideoState(renderer['badges'], 'LIVE') ||
          _hasVideoState(renderer['thumbnailOverlays'], 'LIVE') ||
          _hasVideoState(renderer['upcomingEventData'], 'LIVE'),
      isUpcoming:
          _hasVideoState(renderer['badges'], 'UPCOMING') ||
          _hasVideoState(renderer['thumbnailOverlays'], 'UPCOMING') ||
          _hasVideoState(renderer['upcomingEventData'], 'UPCOMING'),
      title: title,
      channelName: channelName,
      channelAvatar: channelAvatar,
      views: views,
      uploadTime: uploadTime,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      videoUrl: 'https://www.youtube.com/watch?v=$videoId',
      categoryId: 'home',
      categoryName: sectionTitle,
      description: title,
      likesCount: 0,
    );
  }

  /// Parse Cobalt / TVHTML5 tileRenderer
  Video _parseTileRenderer(dynamic renderer, String sectionTitle) {
    if (renderer is! Map<String, dynamic>) {
      throw const FormatException('YouTube 磁贴视频条目格式无效');
    }

    final contentType = renderer['contentType'];
    final command = renderer['onSelectCommand'];
    if (command is! Map<String, dynamic>) {
      throw const FormatException('YouTube tile 缺少 onSelectCommand');
    }
    final itemType = switch (contentType) {
      'TILE_CONTENT_TYPE_VIDEO' => _videoTileTypeFromEndpoint(command),
      'TILE_CONTENT_TYPE_SHORTS' => VideoItemType.shorts,
      'TILE_CONTENT_TYPE_TRACK' => VideoItemType.track,
      'TILE_CONTENT_TYPE_PLAYLIST' => VideoItemType.playlist,
      'TILE_CONTENT_TYPE_CHANNEL' => VideoItemType.channel,
      null => _inferTileTypeFromEndpoint(command),
      _ => throw FormatException('YouTube 首页 tile 类型不受支持：$contentType'),
    };

    String? videoId;
    String? browseId;
    String? browseParams;
    String? playlistId;
    if (itemType == VideoItemType.video || itemType == VideoItemType.shorts) {
      final hasWatchEndpoint = command['watchEndpoint'] != null;
      final hasReelEndpoint = command['reelWatchEndpoint'] != null;
      final hasBrowseEndpoint = command['browseEndpoint'] != null;
      if (hasWatchEndpoint == hasReelEndpoint ||
          hasBrowseEndpoint ||
          (itemType == VideoItemType.shorts && !hasReelEndpoint)) {
        throw FormatException(
          'YouTube $contentType tile 必须且只能包含与类型匹配的 watchEndpoint 或 '
          'reelWatchEndpoint；实际结构：${_describeJsonShape(command)}；'
          'browseId：${command['browseEndpoint']?['browseId']}',
        );
      }
      final endpointName = hasReelEndpoint
          ? 'reelWatchEndpoint'
          : 'watchEndpoint';
      final endpoint = command[endpointName];
      if (endpoint is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube $contentType tile 缺少 $endpointName；'
          'onSelectCommand 结构：${_describeJsonShape(command)}',
        );
      }
      videoId = endpoint['videoId']?.toString();
      if (videoId == null || videoId.isEmpty) {
        throw FormatException('YouTube $contentType tile 缺少 videoId');
      }
    } else if (itemType == VideoItemType.playlist) {
      final hasBrowseEndpoint = command['browseEndpoint'] != null;
      final hasWatchEndpoint = command['watchEndpoint'] != null;
      if (hasBrowseEndpoint == hasWatchEndpoint) {
        throw FormatException(
          'YouTube playlist tile 必须且只能包含 browseEndpoint 或 '
          'watchEndpoint；实际 onSelectCommand 字段：${command.keys.toList()}',
        );
      }
      if (hasWatchEndpoint) {
        final endpoint = command['watchEndpoint'];
        if (endpoint is! Map<String, dynamic>) {
          throw const FormatException(
            'YouTube playlist tile 的 watchEndpoint 格式无效',
          );
        }
        videoId = endpoint['videoId']?.toString();
        playlistId = endpoint['playlistId']?.toString();
        if (videoId == null || videoId.isEmpty) {
          throw const FormatException(
            'YouTube playlist watchEndpoint 缺少 videoId',
          );
        }
        if (playlistId == null || playlistId.isEmpty) {
          throw const FormatException(
            'YouTube playlist watchEndpoint 缺少 playlistId',
          );
        }
      } else {
        final endpoint = command['browseEndpoint'];
        if (endpoint is! Map<String, dynamic>) {
          throw const FormatException(
            'YouTube playlist tile 的 browseEndpoint 格式无效',
          );
        }
        browseId = endpoint['browseId']?.toString();
        browseParams = endpoint['params']?.toString();
        if (browseId == null || browseId.isEmpty) {
          throw const FormatException(
            'YouTube playlist browseEndpoint 缺少 browseId',
          );
        }
      }
    } else {
      final endpoint = command['browseEndpoint'];
      if (endpoint is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube $contentType tile 缺少 browseEndpoint；'
          'onSelectCommand 字段：${command.keys.toList()}',
        );
      }
      browseId = endpoint['browseId']?.toString();
      browseParams = endpoint['params']?.toString();
      if (browseId == null || browseId.isEmpty) {
        throw FormatException('YouTube $contentType tile 缺少 browseId');
      }
    }

    final metadata = renderer['metadata']?['tileMetadataRenderer'];
    final tileHeader = renderer['header']?['tileHeaderRenderer'];
    final trackTileHeader = renderer['header']?['trackTileHeaderRenderer'];
    final overlays = tileHeader?['thumbnailOverlays'] as List?;
    final overlayTitle = overlays
        ?.map(
          (overlay) => _extractText(overlay?['tileMetadataRenderer']?['title']),
        )
        .whereType<String>()
        .firstOrNull;
    final title =
        _extractText(metadata?['title']) ??
        overlayTitle ??
        _extractText(trackTileHeader?['title']) ??
        _extractText(
          renderer['onLongPressCommand']?['showMenuCommand']?['title'],
        );
    if (title == null || title.trim().isEmpty) {
      throw FormatException('YouTube 视频 $videoId 缺少标题');
    }

    final metadataLines = _extractTileMetadataLines(metadata?['lines']);
    final thumbnailUrl =
        _extractThumbnail(tileHeader?['thumbnail']) ??
        _extractThumbnail(trackTileHeader?['thumbnail']);
    if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
      if (videoId != null && videoId.isNotEmpty ||
          browseId == null ||
          browseId.isEmpty) {
        throw FormatException('YouTube 视频 $videoId 缺少缩略图地址');
      }
    }

    final duration =
        _extractTileDuration(tileHeader) ??
        _extractText(trackTileHeader?['duration']) ??
        '';
    if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
      if (itemType == VideoItemType.video ||
          itemType == VideoItemType.shorts ||
          itemType == VideoItemType.track) {
        throw FormatException('YouTube $contentType tile 缺少缩略图地址');
      }
    }

    return Video(
      id: videoId,
      itemType: itemType,
      isLive: _hasVideoState(tileHeader?['thumbnailOverlays'], 'LIVE'),
      isUpcoming: _hasVideoState(tileHeader?['thumbnailOverlays'], 'UPCOMING'),
      browseId: browseId,
      browseParams: browseParams,
      playlistId: playlistId,
      title: title,
      channelName: '',
      channelAvatar: '',
      views: metadataLines.join(' • '),
      uploadTime: '',
      duration: duration,
      thumbnailUrl: thumbnailUrl ?? '',
      videoUrl: videoId == null || videoId.isEmpty
          ? ''
          : itemType == VideoItemType.shorts
          ? 'https://www.youtube.com/shorts/$videoId'
          : playlistId == null
          ? 'https://www.youtube.com/watch?v=$videoId'
          : Uri.https('www.youtube.com', '/watch', {
              'v': videoId,
              'list': playlistId,
            }).toString(),
      categoryId: 'home',
      categoryName: sectionTitle,
      description: title,
      likesCount: 0,
    );
  }

  VideoItemType _inferTileTypeFromEndpoint(Map<String, dynamic> command) {
    final endpoints = const [
      'watchEndpoint',
      'reelWatchEndpoint',
      'browseEndpoint',
    ].where(command.containsKey).toList();
    if (endpoints.length != 1) {
      throw FormatException(
        'YouTube tile 缺少 contentType，且无法从唯一 endpoint 分类；'
        'onSelectCommand 字段：${command.keys.toList()}',
      );
    }

    return switch (endpoints.single) {
      'watchEndpoint' =>
        command['watchEndpoint'] is Map<String, dynamic> &&
                (command['watchEndpoint']['playlistId']
                        ?.toString()
                        .isNotEmpty ??
                    false)
            ? VideoItemType.playlist
            : VideoItemType.video,
      'reelWatchEndpoint' => VideoItemType.shorts,
      'browseEndpoint' => _browseEndpointTileType(command['browseEndpoint']),
      _ => throw StateError('Unreachable tile endpoint: ${endpoints.single}'),
    };
  }

  VideoItemType _videoTileTypeFromEndpoint(Map<String, dynamic> command) {
    final endpoints = const [
      'watchEndpoint',
      'reelWatchEndpoint',
      'browseEndpoint',
    ].where(command.containsKey).toList();
    if (endpoints.length != 1) {
      throw FormatException(
        'YouTube VIDEO tile 必须且只能包含一个播放或浏览 endpoint；'
        '实际字段：${command.keys.toList()}',
      );
    }

    return switch (endpoints.single) {
      'watchEndpoint' => VideoItemType.video,
      'reelWatchEndpoint' => VideoItemType.shorts,
      'browseEndpoint' => _browseEndpointTileType(command['browseEndpoint']),
      _ => throw StateError(
        'Unreachable video tile endpoint: ${endpoints.single}',
      ),
    };
  }

  VideoItemType _browseEndpointTileType(dynamic rawEndpoint) {
    if (rawEndpoint is! Map<String, dynamic>) {
      throw const FormatException('YouTube tile 的 browseEndpoint 格式无效');
    }
    final browseId = rawEndpoint['browseId']?.toString();
    if (browseId == null || browseId.isEmpty) {
      throw const FormatException('YouTube tile 的 browseEndpoint 缺少 browseId');
    }
    return browseId.startsWith('VL')
        ? VideoItemType.playlist
        : VideoItemType.browseDestination;
  }

  Object? _describeJsonShape(dynamic value, [int depth = 0]) {
    if (depth >= 5) {
      return value is Map
          ? '<object>'
          : value is List
          ? '<list>'
          : value?.runtimeType.toString();
    }
    if (value is Map) {
      return {
        for (final entry in value.entries.take(12))
          entry.key.toString(): entry.value is Map || entry.value is List
              ? _describeJsonShape(entry.value, depth + 1)
              : entry.value?.runtimeType.toString(),
      };
    }
    if (value is List) {
      return value
          .take(4)
          .map((item) => _describeJsonShape(item, depth + 1))
          .toList();
    }
    return value?.runtimeType.toString();
  }

  bool _hasVideoState(dynamic node, String state) {
    if (node is Map<String, dynamic>) {
      final style = node['style']?.toString().toUpperCase();
      final text = _extractText(node['text'])?.toUpperCase();
      final badgeStyle = state == 'LIVE'
          ? 'BADGE_STYLE_TYPE_LIVE_NOW'
          : 'BADGE_STYLE_TYPE_UPCOMING';
      if (style == state || style == badgeStyle || text == state) return true;
      return node.values.any((value) => _hasVideoState(value, state));
    }
    if (node is List) {
      return node.any((value) => _hasVideoState(value, state));
    }
    return false;
  }

  List<String> _extractTileMetadataLines(dynamic linesNode) {
    if (linesNode is! List) return const [];

    return linesNode
        .map((line) {
          final items = line?['lineRenderer']?['items'];
          if (items is! List) return '';
          return items
              .map((item) => _extractText(item?['lineItemRenderer']?['text']))
              .whereType<String>()
              .where((text) => text.isNotEmpty)
              .join(' ');
        })
        .where((line) => line.isNotEmpty)
        .toList();
  }

  String? _extractTileDuration(dynamic tileHeader) {
    final overlays = tileHeader?['thumbnailOverlays'] as List?;
    if (overlays == null) return null;

    for (final overlay in overlays) {
      final duration = _extractText(
        overlay?['thumbnailOverlayTimeStatusRenderer']?['text'],
      );
      if (duration != null && duration.isNotEmpty) return duration;
    }
    return null;
  }

  /// Helper to extract string from Innertube TextItem JSON node
  String? _extractText(dynamic textNode) {
    if (textNode == null) return null;
    if (textNode is String) return textNode;
    if (textNode is Map<String, dynamic>) {
      if (textNode['simpleText'] != null) {
        return textNode['simpleText'].toString();
      }
      if (textNode['snippet'] != null && textNode['snippet']['text'] != null) {
        return textNode['snippet']['text'].toString();
      }
      final runs = textNode['runs'] as List?;
      if (runs != null && runs.isNotEmpty) {
        return runs.map((r) => r['text'] ?? '').join('');
      }
      if (textNode['content'] != null) {
        return textNode['content'].toString();
      }
    }
    return null;
  }

  /// Helper to extract highest resolution avatar thumbnail URL
  String? _extractThumbnail(dynamic photoNode) {
    if (photoNode == null || photoNode is! Map<String, dynamic>) return null;
    final thumbnails =
        (photoNode['thumbnails'] ?? photoNode['sources']) as List?;
    if (thumbnails == null || thumbnails.isEmpty) return null;

    String? bestUrl;
    int maxRes = -1;

    for (final thumb in thumbnails) {
      final url = thumb['url']?.toString();
      final width = (thumb['width'] as num?)?.toInt() ?? 0;
      if (url != null && width >= maxRes) {
        maxRes = width;
        bestUrl = url;
      }
    }

    if (bestUrl != null && bestUrl.startsWith('//')) {
      bestUrl = 'https:$bestUrl';
    }
    return bestUrl;
  }
}
