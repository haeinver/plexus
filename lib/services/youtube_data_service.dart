import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/channel.dart';
import '../models/video.dart';
import '../models/video_section.dart';
import 'locale_service.dart';
import 'youtube_auth_service.dart';

typedef _HomeRequestConfig = ({
  Uri uri,
  Map<String, String> headers,
  Map<String, dynamic> context,
});

typedef CategoryBrowsePage = ({
  List<VideoSection> sections,
  String? continuationToken,
});
typedef MusicBrowsePage = CategoryBrowsePage;
typedef SearchBrowsePage = ({
  List<VideoSection> sections,
  String? estimatedResults,
});
typedef SubscriptionBrowsePage = ({
  List<Channel> channels,
  List<VideoSection> sections,
  String? continuationToken,
});
typedef SubscriptionChannelPage = ({
  List<VideoSection> sections,
  String? continuationToken,
});

abstract interface class SearchDataSource {
  Future<List<String>> fetchSearchSuggestions(String query);
  Future<SearchBrowsePage> fetchSearchResults(String query);
  Future<VideoSection> fetchMoreSearchSectionVideos(VideoSection section);
}

abstract interface class SubscriptionDataSource {
  Future<SubscriptionBrowsePage> fetchSubscriptions();
  Future<SubscriptionBrowsePage> fetchMoreSubscriptionSections(
    String continuation,
  );
  Future<SubscriptionChannelPage> fetchSubscriptionChannelPage(Channel channel);
  Future<VideoSection> fetchMoreSubscriptionSectionVideos(VideoSection section);
}

/// Real YouTube InnerTube API Data Service
/// Strictly matches SmartTube V2 MediaServiceCore (QueryBuilder.kt / BrowseService2.kt / TVHTML5 Client).
class YouTubeDataService implements SearchDataSource, SubscriptionDataSource {
  static final YouTubeDataService _instance = YouTubeDataService._internal();
  factory YouTubeDataService() => _instance;
  YouTubeDataService._internal();

  static const String _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const String _musicBrowseId = 'FEtopics_music';
  static const String _gamingBrowseId = 'FEtopics_gaming';
  static const String _liveBrowseId = 'FEtopics_live';
  static const String _subscriptionsBrowseId = 'FEsubscriptions';
  static const String _tvUserAgent =
      'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)';
  String? _visitorData;

  String _topicBrowseId(String categoryId) => switch (categoryId) {
    'music' => _musicBrowseId,
    'gaming' => _gamingBrowseId,
    'live' => _liveBrowseId,
    _ => throw ArgumentError.value(categoryId, 'categoryId'),
  };

  String _topicName(String categoryId) => switch (categoryId) {
    'music' => '音乐',
    'gaming' => '游戏',
    'live' => '直播',
    _ => throw ArgumentError.value(categoryId, 'categoryId'),
  };

  /// Fetch Real Home Feed Videos strictly using SmartTube TVHTML5 Client & QueryBuilder JSON
  Future<List<VideoSection>> fetchHomeFeed() async {
    return fetchHomeFeedProgressively().last;
  }

  Future<_HomeRequestConfig> _createHomeRequestConfig({
    bool requireAuth = true,
    String apiEndpoint = 'browse',
  }) async {
    final authService = YouTubeAuthService();
    await authService.init();
    final isLoggedIn = authService.isLoggedIn;
    if (requireAuth && !isLoggedIn) {
      throw StateError('未登录 YouTube 账号，无法请求首页内容');
    }

    final localeService = LocaleService();
    await localeService.init();
    final authHeaders = isLoggedIn
        ? await authService.getAuthHeaders()
        : <String, String>{};
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': _tvUserAgent,
      'Referer': 'https://www.youtube.com/tv',
      ...authHeaders,
    };
    final context = createTVBrowseContext(
      language: localeService.language,
      region: localeService.region,
      utcOffsetMinutes: localeService.utcOffsetMinutes.toString(),
      visitorData: _visitorData,
    );

    return (
      uri: Uri.parse(
        'https://www.youtube.com/youtubei/v1/$apiEndpoint?key=$_apiKey',
      ),
      headers: headers,
      context: context,
    );
  }

  @visibleForTesting
  Map<String, dynamic> createTVBrowseContext({
    required String language,
    required String region,
    required String utcOffsetMinutes,
    String? visitorData,
  }) => {
    'client': {
      'clientName': 'TVHTML5',
      'clientVersion': '7.20260901.15.00',
      'clientScreen': 'WATCH',
      'userAgent': _tvUserAgent,
      'acceptLanguage': language,
      'acceptRegion': region,
      'utcOffsetMinutes': utcOffsetMinutes,
      if (visitorData != null && visitorData.isNotEmpty)
        'visitorData': visitorData,
      'tvAppInfo': {
        'appQuality': 'TV_APP_QUALITY_FULL_ANIMATION',
        'zylonLeftNav': true,
      },
      'webpSupport': false,
      'animatedWebpSupport': true,
    },
    'user': {'enableSafetyMode': false, 'lockedSafetyMode': false},
  };

  dynamic _decodeResponseBody(
    String body, {
    required Map<String, dynamic> requestContext,
  }) {
    final dynamic data = json.decode(body);
    captureVisitorData(data, requestContext);
    return data;
  }

  @visibleForTesting
  void captureVisitorData(dynamic data, Map<String, dynamic> requestContext) {
    final responseContext = data is Map<String, dynamic>
        ? data['responseContext']
        : null;
    final visitorData = responseContext is Map<String, dynamic>
        ? responseContext['visitorData']
        : null;
    if (visitorData is String && visitorData.isNotEmpty) {
      _visitorData = visitorData;
      final clientContext = requestContext['client'];
      if (clientContext is Map<String, dynamic>) {
        clientContext['visitorData'] = visitorData;
      }
    }
  }

  Future<VideoSection> fetchMoreHomeSectionVideos(VideoSection section) async {
    return _fetchMoreSectionVideos(section, requireAuth: true);
  }

  @override
  Future<SubscriptionBrowsePage> fetchSubscriptions() async {
    final request = await _createHomeRequestConfig();
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode(createSubscriptionsRequestBody(request.context)),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception(
        'YouTube 订阅接口响应异常 [HTTP ${response.statusCode}]: '
        '${_shortMsg(response.body)}',
      );
    }
    return parseSubscriptionsResponse(
      _decodeResponseBody(response.body, requestContext: request.context),
    );
  }

  @override
  Future<SubscriptionBrowsePage> fetchMoreSubscriptionSections(
    String continuation,
  ) async {
    if (continuation.isEmpty) {
      throw const FormatException('YouTube 订阅 section-list continuation 不能为空');
    }
    final request = await _createHomeRequestConfig();
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode(
            createContinuationRequestBody(request.context, continuation),
          ),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception(
        'YouTube 订阅 section-list continuation 响应异常 '
        '[HTTP ${response.statusCode}]: ${_shortMsg(response.body)}',
      );
    }
    return parseSubscriptionContinuationResponse(
      _decodeResponseBody(response.body, requestContext: request.context),
    );
  }

  @override
  Future<SubscriptionChannelPage> fetchSubscriptionChannelPage(
    Channel channel,
  ) async {
    final browseId = channel.browseId;
    if (browseId == null || browseId.isEmpty) {
      throw const FormatException('YouTube TV 订阅频道缺少 endpoint.browseId');
    }
    final browseParams = channel.browseParams;
    if (browseParams == null || browseParams.isEmpty) {
      throw const FormatException('YouTube TV 订阅频道缺少 endpoint.params');
    }
    final destination = VideoSection(
      title: channel.name,
      videos: const [],
      browseId: browseId,
      browseParams: browseParams,
    );
    final request = await _createHomeRequestConfig();
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode(
            createBrowseDestinationRequestBody(request.context, destination),
          ),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception(
        'YouTube 订阅频道「${channel.name}」接口响应异常 '
        '[HTTP ${response.statusCode}]: ${_shortMsg(response.body)}',
      );
    }
    final data = _decodeResponseBody(
      response.body,
      requestContext: request.context,
    );
    return parseSubscriptionChannelResponse(channel, data);
  }

  @override
  Future<VideoSection> fetchMoreSubscriptionSectionVideos(
    VideoSection section,
  ) => _fetchMoreSectionVideos(section, requireAuth: true);

  Future<VideoSection> fetchMoreMusicSectionVideos(VideoSection section) async {
    return fetchMoreCategorySectionVideos('music', section);
  }

  Future<VideoSection> fetchMoreCategorySectionVideos(
    String categoryId,
    VideoSection section,
  ) {
    _topicName(categoryId);
    return _fetchMoreSectionVideos(
      section,
      requireAuth: false,
      categoryId: categoryId,
    );
  }

  @visibleForTesting
  Map<String, dynamic> createContinuationRequestBody(
    Map<String, dynamic> context,
    String continuation,
  ) => {
    'context': context,
    'continuation': continuation,
    'racyCheckOk': true,
    'contentCheckOk': true,
  };

  @visibleForTesting
  Map<String, dynamic> createSubscriptionsRequestBody(
    Map<String, dynamic> context,
  ) => {
    'context': context,
    'browseId': _subscriptionsBrowseId,
    'racyCheckOk': true,
    'contentCheckOk': true,
  };

  @visibleForTesting
  Map<String, dynamic> createSearchRequestBody(
    Map<String, dynamic> context,
    String query,
  ) => {
    'context': context,
    'query': query,
    'racyCheckOk': true,
    'contentCheckOk': true,
  };

  @visibleForTesting
  Uri createSearchSuggestionsUri(String query, {required String region}) =>
      Uri.https('clients1.google.com', '/complete/search', {
        'client': 'youtube-lr',
        'ds': 'yt',
        'xhr': 't',
        'oe': 'utf-8',
        'xssi': 't',
        'gl': region,
        'q': query,
      });

  Future<VideoSection> _fetchMoreSectionVideos(
    VideoSection section, {
    required bool requireAuth,
    String categoryId = 'home',
  }) async {
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return section;
    final request = await _createHomeRequestConfig(requireAuth: requireAuth);
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode(
            createContinuationRequestBody(request.context, token),
          ),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      final feedName = categoryId == 'home'
          ? '首页'
          : '${_topicName(categoryId)}分区';
      throw Exception(
        'YouTube $feedName 续页接口响应异常 '
        '[HTTP ${response.statusCode}]: ${_shortMsg(response.body)}',
      );
    }
    return parseHomeSectionContinuationResponse(
      section,
      _decodeResponseBody(response.body, requestContext: request.context),
      categoryId: categoryId,
    );
  }

  Future<CategoryBrowsePage> fetchCategoryFeed(String categoryId) async {
    final topicName = _topicName(categoryId);
    final request = await _createHomeRequestConfig(requireAuth: false);
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode({
            'context': request.context,
            'browseId': _topicBrowseId(categoryId),
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception(
        'YouTube TVHTML5 $topicName 分区接口响应异常 '
        '[HTTP ${response.statusCode}]: ${_shortMsg(response.body)}',
      );
    }
    return parseCategoryBrowseResponse(
      _decodeResponseBody(response.body, requestContext: request.context),
      topicName: topicName,
      categoryId: categoryId,
    );
  }

  Future<MusicBrowsePage> fetchMusicFeed() => fetchCategoryFeed('music');

  Future<CategoryBrowsePage> fetchGamingFeed() => fetchCategoryFeed('gaming');

  Future<CategoryBrowsePage> fetchLiveFeed() => fetchCategoryFeed('live');

  Future<CategoryBrowsePage> fetchMoreCategorySections(
    String categoryId,
    String continuation,
  ) async {
    final topicName = _topicName(categoryId);
    if (continuation.isEmpty) {
      throw ArgumentError('YouTube $topicName section-list continuation 不能为空');
    }

    final request = await _createHomeRequestConfig(requireAuth: false);
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode(
            createContinuationRequestBody(request.context, continuation),
          ),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception(
        'YouTube TVHTML5 $topicName 分区 continuation 响应异常 '
        '[HTTP ${response.statusCode}]: ${_shortMsg(response.body)}',
      );
    }

    return parseCategoryBrowseContinuationResponse(
      _decodeResponseBody(response.body, requestContext: request.context),
      topicName: topicName,
      categoryId: categoryId,
    );
  }

  Future<MusicBrowsePage> fetchMoreMusicSections(String continuation) =>
      fetchMoreCategorySections('music', continuation);

  Future<CategoryBrowsePage> fetchMoreGamingSections(String continuation) =>
      fetchMoreCategorySections('gaming', continuation);

  Stream<CategoryBrowsePage> fetchCategoryFeedProgressively(
    String categoryId,
  ) async* {
    final firstPage = await fetchCategoryFeed(categoryId);
    yield* streamCategoryBrowsePages(
      firstPage,
      (continuation) => fetchMoreCategorySections(categoryId, continuation),
      topicName: _topicName(categoryId),
    );
  }

  Stream<MusicBrowsePage> fetchMusicFeedProgressively() =>
      fetchCategoryFeedProgressively('music');

  Stream<CategoryBrowsePage> fetchGamingFeedProgressively() =>
      fetchCategoryFeedProgressively('gaming');

  Stream<CategoryBrowsePage> fetchLiveFeedProgressively() =>
      fetchCategoryFeedProgressively('live');

  @override
  Future<SearchBrowsePage> fetchSearchResults(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      throw ArgumentError.value(query, 'query', '不能为空');
    }
    final request = await _createHomeRequestConfig(
      requireAuth: false,
      apiEndpoint: 'search',
    );
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode(
            createSearchRequestBody(request.context, normalizedQuery),
          ),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('YouTube TVHTML5 搜索接口响应异常 [HTTP ${response.statusCode}]');
    }

    return parseSearchResponse(
      _decodeResponseBody(response.body, requestContext: request.context),
    );
  }

  @override
  Future<List<String>> fetchSearchSuggestions(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const [];

    final localeService = LocaleService();
    await localeService.init();
    final response = await http
        .get(
          createSearchSuggestionsUri(
            normalizedQuery,
            region: localeService.region,
          ),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('YouTube 搜索提示接口响应异常 [HTTP ${response.statusCode}]');
    }
    return parseSearchSuggestionsResponse(response.body);
  }

  @visibleForTesting
  List<String> parseSearchSuggestionsResponse(String body) {
    final payload = body.trim().replaceFirst(RegExp(r"^\)\]\}',?\s*"), '');
    final dynamic decoded = json.decode(payload);
    if (decoded is! List || decoded.length < 2) {
      throw const FormatException('YouTube 搜索提示响应缺少顶层查询和建议数组');
    }

    final rawSuggestions = decoded[1];
    if (rawSuggestions is! List) {
      throw const FormatException('YouTube 搜索提示响应缺少 [1] 建议列表');
    }

    final suggestions = <String>[];
    final seenSuggestions = <String>{};
    for (var index = 0; index < rawSuggestions.length; index++) {
      final rawSuggestion = rawSuggestions[index];
      if (rawSuggestion is! List ||
          rawSuggestion.isEmpty ||
          rawSuggestion.first is! String) {
        throw FormatException(
          'YouTube 搜索提示 [1][$index][0] 不是字符串；'
          '结构：${_describeJsonShape(rawSuggestion)}',
        );
      }
      final suggestion = (rawSuggestion.first as String).trim();
      if (suggestion.isNotEmpty && seenSuggestions.add(suggestion)) {
        suggestions.add(suggestion);
      }
    }
    return suggestions;
  }

  @override
  Future<VideoSection> fetchMoreSearchSectionVideos(
    VideoSection section,
  ) async {
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return section;

    final request = await _createHomeRequestConfig(
      requireAuth: false,
      apiEndpoint: 'search',
    );
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode(
            createContinuationRequestBody(request.context, token),
          ),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception(
        'YouTube TVHTML5 搜索续页接口响应异常 [HTTP ${response.statusCode}]',
      );
    }

    return parseSearchContinuationResponse(
      section,
      _decodeResponseBody(response.body, requestContext: request.context),
    );
  }

  @visibleForTesting
  Stream<MusicBrowsePage> streamMusicBrowsePages(
    MusicBrowsePage firstPage,
    Future<MusicBrowsePage> Function(String continuation) fetchMore,
  ) => streamCategoryBrowsePages(firstPage, fetchMore, topicName: '音乐');

  @visibleForTesting
  Stream<CategoryBrowsePage> streamCategoryBrowsePages(
    CategoryBrowsePage firstPage,
    Future<CategoryBrowsePage> Function(String continuation) fetchMore, {
    required String topicName,
  }) async* {
    final sections = List<VideoSection>.of(firstPage.sections);
    var continuation = firstPage.continuationToken;
    final seenTokens = <String>{};

    yield (
      sections: List.unmodifiable(sections),
      continuationToken: continuation,
    );

    while (continuation != null && continuation.isNotEmpty) {
      if (!seenTokens.add(continuation)) {
        throw FormatException(
          'YouTube $topicName section-list continuation token 重复',
        );
      }

      final nextPage = await fetchMore(continuation);
      if (nextPage.sections.isEmpty) break;

      sections.addAll(nextPage.sections);
      continuation = nextPage.continuationToken;
      yield (
        sections: List.unmodifiable(sections),
        continuationToken: continuation,
      );
    }
  }

  Future<VideoSection> fetchMoreBrowseDestinationVideos(
    VideoSection section,
  ) async {
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return section;

    final request = await _createHomeRequestConfig(requireAuth: false);
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode(
            createContinuationRequestBody(request.context, token),
          ),
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
      _decodeResponseBody(response.body, requestContext: request.context),
    );
  }

  @visibleForTesting
  Map<String, dynamic> createBrowseDestinationRequestBody(
    Map<String, dynamic> context,
    VideoSection destination,
  ) {
    final browseId = destination.browseId;
    if (browseId == null || browseId.isEmpty) {
      throw const FormatException('YouTube 浏览入口缺少 browseId');
    }
    return {
      'context': context,
      'browseId': browseId,
      if (destination.browseParams != null &&
          destination.browseParams!.isNotEmpty)
        'params': destination.browseParams,
    };
  }

  Future<VideoSection> fetchBrowseDestination(VideoSection destination) async {
    final request = await _createHomeRequestConfig(requireAuth: false);
    final response = await http
        .post(
          request.uri,
          headers: request.headers,
          body: json.encode(
            createBrowseDestinationRequestBody(request.context, destination),
          ),
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
      _decodeResponseBody(response.body, requestContext: request.context),
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

    final dynamic data = _decodeResponseBody(
      response.body,
      requestContext: request.context,
    );
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
            body: json.encode(
              createContinuationRequestBody(request.context, continuation),
            ),
          )
          .timeout(const Duration(seconds: 8));

      if (continuationResponse.statusCode != 200) {
        throw Exception(
          'YouTube TVHTML5 首页 continuation 响应异常 '
          '[HTTP ${continuationResponse.statusCode}]: '
          '${_shortMsg(continuationResponse.body)}',
        );
      }

      final dynamic continuationData = _decodeResponseBody(
        continuationResponse.body,
        requestContext: request.context,
      );
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
  List<VideoSection> parseHomeContinuationResponse(
    dynamic data, {
    String categoryId = 'home',
  }) {
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
    return _parseHomeShelves(rawShelves, categoryId: categoryId);
  }

  @visibleForTesting
  VideoSection parseHomeSectionContinuationResponse(
    VideoSection section,
    dynamic data, {
    String categoryId = 'home',
  }) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube 分区 continuation 响应不是 JSON 对象');
    }

    final continuationContents = data['continuationContents'];
    if (continuationContents is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube 分区 continuation 缺少 continuationContents；'
        '顶层字段：${data.keys.toList()}；'
        '脱敏结构：${_describeJsonShape(data)}',
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
    _extractSectionVideos(
      rawItems,
      section.title ?? '',
      newVideos,
      categoryId: categoryId,
    );
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
  SearchBrowsePage parseSearchResponse(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube TVHTML5 搜索响应不是 JSON 对象');
    }

    final sectionList = data['contents']?['sectionListRenderer'];
    if (sectionList is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube TVHTML5 搜索响应缺少 contents.sectionListRenderer；'
        '响应结构：${_describeJsonShape(data)}',
      );
    }
    final rawSections = sectionList['contents'];
    if (rawSections is! List) {
      throw FormatException(
        'YouTube TVHTML5 搜索响应缺少 sectionListRenderer.contents；'
        'sectionListRenderer 字段：${sectionList.keys.toList()}',
      );
    }

    final sections = <VideoSection>[];
    for (final sectionNode in rawSections) {
      if (sectionNode is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube 搜索响应包含无效 section renderer：${sectionNode.runtimeType}',
        );
      }
      if (sectionNode.containsKey('adSlotRenderer') ||
          sectionNode.containsKey('continuationItemRenderer') ||
          sectionNode.containsKey('appealSurveyShelfRenderer')) {
        continue;
      }

      final rawClusterShelf = sectionNode['clusterShelfRenderer'];
      if (rawClusterShelf != null) {
        sections.addAll(_parseSearchClusterShelf(rawClusterShelf));
        continue;
      }

      final rawShelf = sectionNode['shelfRenderer'];
      final rawItemSection = sectionNode['itemSectionRenderer'];
      if ((rawShelf != null) == (rawItemSection != null)) {
        throw FormatException(
          'YouTube 搜索 section 必须且只能包含 shelfRenderer 或 itemSectionRenderer；'
          '实际字段：${sectionNode.keys.toList()}；'
          '脱敏结构：${_describeJsonShape(sectionNode)}',
        );
      }

      final String? title;
      final List<dynamic> items;
      final String? continuationToken;
      if (rawShelf != null) {
        if (rawShelf is! Map<String, dynamic>) {
          throw const FormatException('YouTube 搜索 shelfRenderer 格式无效');
        }
        title = _extractShelfTitle(rawShelf);
        final rawItems = _extractShelfItems(sectionNode, rawShelf);
        if (rawItems == null) {
          throw FormatException(
            'YouTube 搜索 shelf 缺少受支持的条目列表；'
            'shelfRenderer 字段：${rawShelf.keys.toList()}',
          );
        }
        items = rawItems;
        continuationToken =
            _extractShelfContinuationToken(rawShelf) ??
            _findContinuationToken(items);
      } else {
        if (rawItemSection is! Map<String, dynamic>) {
          throw const FormatException('YouTube 搜索 itemSectionRenderer 格式无效');
        }
        final rawItems = rawItemSection['contents'];
        if (rawItems is! List) {
          throw FormatException(
            'YouTube 搜索 itemSectionRenderer 缺少 contents；'
            '字段：${rawItemSection.keys.toList()}',
          );
        }
        title = _extractText(
          rawItemSection['header']?['itemSectionHeaderRenderer']?['title'],
        );
        items = rawItems;
        continuationToken =
            _extractNextContinuationToken(rawItemSection) ??
            _findContinuationToken(items);
      }

      final videos = <Video>[];
      _extractSectionVideos(items, title ?? '', videos, categoryId: 'search');
      if (videos.isNotEmpty || continuationToken != null) {
        sections.add(
          VideoSection(
            title: title,
            videos: videos,
            continuationToken: continuationToken,
          ),
        );
      }
    }

    return (
      sections: sections,
      estimatedResults: data['estimatedResults']?.toString(),
    );
  }

  List<VideoSection> _parseSearchClusterShelf(dynamic rawClusterShelf) {
    if (rawClusterShelf is! Map<String, dynamic>) {
      throw const FormatException('YouTube 搜索 clusterShelfRenderer 格式无效');
    }
    final clusters = rawClusterShelf['clusters'];
    if (clusters is! List) {
      throw FormatException(
        'YouTube 搜索 clusterShelfRenderer 缺少 clusters；'
        '字段：${rawClusterShelf.keys.toList()}',
      );
    }

    final sections = <VideoSection>[];
    for (var index = 0; index < clusters.length; index++) {
      final clusterNode = clusters[index];
      if (clusterNode is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube 搜索 clusterShelfRenderer.clusters[$index] 格式无效',
        );
      }
      final cluster = clusterNode['clusterRenderer'];
      if (cluster is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube 搜索 clusters[$index] 缺少 clusterRenderer；'
          '字段：${clusterNode.keys.toList()}',
        );
      }

      final buttonViewModel = cluster['headerRenderer']?['buttonViewModel'];
      if (buttonViewModel is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube 搜索 clusters[$index].headerRenderer 缺少 buttonViewModel；'
          '字段：${(cluster['headerRenderer'] as Map?)?.keys.toList()}',
        );
      }
      final title = _extractText(buttonViewModel['title']);
      if (title == null || title.trim().isEmpty) {
        throw FormatException(
          'YouTube 搜索 clusters[$index].buttonViewModel.title 缺失或为空',
        );
      }

      final command = buttonViewModel['onTap']?['innertubeCommand'];
      if (command is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube 搜索 clusters[$index].buttonViewModel.onTap 缺少 innertubeCommand',
        );
      }
      final hasBrowseEndpoint = command.containsKey('browseEndpoint');
      final hasSearchEndpoint = command.containsKey('searchEndpoint');
      if (hasBrowseEndpoint == hasSearchEndpoint) {
        throw FormatException(
          'YouTube 搜索 clusters[$index] 必须且只能包含 browseEndpoint 或 searchEndpoint；'
          '实际字段：${command.keys.toList()}',
        );
      }

      String? browseId;
      String? browseParams;
      String? searchQuery;
      if (hasBrowseEndpoint) {
        final browseEndpoint = command['browseEndpoint'];
        if (browseEndpoint is! Map<String, dynamic>) {
          throw FormatException(
            'YouTube 搜索 clusters[$index].browseEndpoint 格式无效',
          );
        }
        final endpointBrowseId = browseEndpoint['browseId'];
        if (endpointBrowseId is! String || endpointBrowseId.isEmpty) {
          throw FormatException(
            'YouTube 搜索 clusters[$index].browseEndpoint 缺少 browseId',
          );
        }
        browseId = endpointBrowseId;
        browseParams = browseEndpoint['params']?.toString();
      } else {
        final searchEndpoint = command['searchEndpoint'];
        if (searchEndpoint is! Map<String, dynamic>) {
          throw FormatException(
            'YouTube 搜索 clusters[$index].searchEndpoint 格式无效',
          );
        }
        final endpointQuery = searchEndpoint['query'];
        if (endpointQuery is! String || endpointQuery.trim().isEmpty) {
          throw FormatException(
            'YouTube 搜索 clusters[$index].searchEndpoint 缺少 query',
          );
        }
        searchQuery = endpointQuery.trim();
      }

      final items = cluster['items'];
      if (items is! List) {
        throw FormatException(
          'YouTube 搜索 clusters[$index].clusterRenderer 缺少 items',
        );
      }
      final videos = <Video>[];
      _extractSectionVideos(items, title, videos, categoryId: 'search');
      final continuationToken =
          _extractNextContinuationToken(cluster) ??
          _findContinuationToken(items);
      if (videos.isEmpty && continuationToken == null) {
        throw FormatException(
          'YouTube 搜索 cluster「$title」没有可解析的媒体或 continuation；'
          'items 结构：${_describeJsonShape(items)}',
        );
      }

      sections.add(
        VideoSection(
          title: title,
          videos: videos,
          continuationToken: continuationToken,
          browseId: browseId,
          browseParams: browseParams,
          browseTitle: browseId == null ? null : title,
          searchQuery: searchQuery,
        ),
      );
    }
    return sections;
  }

  @visibleForTesting
  VideoSection parseSearchContinuationResponse(
    VideoSection section,
    dynamic data,
  ) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube 搜索 continuation 响应不是 JSON 对象');
    }
    final continuationContents = data['continuationContents'];
    if (continuationContents is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube 搜索 continuation 缺少 continuationContents；'
        '脱敏结构：${_describeJsonShape(data)}',
      );
    }

    final sectionList =
        continuationContents['sectionListContinuation'] ??
        continuationContents['tvSurfaceContentContinuation']?['content']?['sectionListRenderer'];
    final dynamic rawItems;
    Map<String, dynamic>? listRenderer;
    String? continuationToken;
    if (sectionList is Map<String, dynamic>) {
      final contents = sectionList['contents'];
      if (contents is! List) {
        throw FormatException(
          'YouTube 搜索 sectionListContinuation 缺少 contents；'
          '字段：${sectionList.keys.toList()}',
        );
      }
      rawItems = contents;
      listRenderer = sectionList;
      for (final item in contents) {
        if (item is! Map<String, dynamic>) continue;
        final shelf = item['shelfRenderer'];
        if (shelf is Map<String, dynamic>) {
          continuationToken ??= _extractShelfContinuationToken(shelf);
        }
        final itemSection = item['itemSectionRenderer'];
        if (itemSection is Map<String, dynamic>) {
          continuationToken ??= _extractNextContinuationToken(itemSection);
        }
      }
    } else {
      final rawRenderer =
          continuationContents['horizontalListContinuation'] ??
          continuationContents['itemSectionContinuation'] ??
          continuationContents['gridContinuation'] ??
          continuationContents['playlistVideoListContinuation'];
      if (rawRenderer is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube 搜索 continuation 缺少已支持的列表 renderer；'
          'continuationContents 字段：${continuationContents.keys.toList()}；'
          '脱敏结构：${_describeJsonShape(continuationContents)}',
        );
      }
      listRenderer = rawRenderer;
      final contents = rawRenderer['items'] ?? rawRenderer['contents'];
      if (contents is! List) {
        throw FormatException(
          'YouTube 搜索 continuation renderer 缺少 items/contents；'
          '字段：${rawRenderer.keys.toList()}',
        );
      }
      rawItems = contents;
    }

    final newVideos = <Video>[];
    _extractSectionVideos(
      rawItems,
      section.title ?? '',
      newVideos,
      categoryId: 'search',
    );
    final videos = List<Video>.of(section.videos);
    for (final video in newVideos) {
      final duplicate = videos.any((existing) {
        if (video.id != null) return existing.id == video.id;
        return video.browseId != null && existing.browseId == video.browseId;
      });
      if (!duplicate) videos.add(video);
    }
    continuationToken ??=
        _extractNextContinuationToken(listRenderer) ??
        _findContinuationToken(rawItems);

    return VideoSection(
      title: section.title,
      videos: videos,
      continuationToken: continuationToken,
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
  CategoryBrowsePage parseCategoryBrowseResponse(
    dynamic data, {
    required String topicName,
    required String categoryId,
  }) {
    if (data is! Map<String, dynamic>) {
      throw FormatException('YouTube TVHTML5 $topicName 响应不是 JSON 对象');
    }

    final sectionList = _initialSectionList(data);
    final rawShelves = sectionList?['contents'];
    if (rawShelves is! List) {
      throw FormatException(
        'YouTube TVHTML5 $topicName 响应缺少 sectionListRenderer.contents',
      );
    }

    final sections = _parseHomeShelves(rawShelves, categoryId: categoryId);
    if (sections.isEmpty) {
      throw FormatException('YouTube TVHTML5 $topicName 响应中没有可解析的内容分区');
    }
    if (sections.first.title == null && rawShelves.isNotEmpty) {
      final firstShelf = rawShelves.first;
      final shelfRenderer = firstShelf is Map<String, dynamic>
          ? firstShelf['shelfRenderer']
          : null;
      final shelfHeaderRenderer = shelfRenderer is Map<String, dynamic>
          ? shelfRenderer['headerRenderer']
          : null;
      final heroCarouselHeader = shelfHeaderRenderer is Map<String, dynamic>
          ? shelfHeaderRenderer['heroCarouselHeaderRenderer']
          : null;
      final heroHeader = heroCarouselHeader is Map<String, dynamic>
          ? heroCarouselHeader['header']
          : null;
      final heroShelfHeader = heroHeader is Map<String, dynamic>
          ? heroHeader['shelfHeaderRenderer']
          : null;
      throw FormatException(
        'YouTube $topicName 首栏缺少原生标题；'
        'hero shelf header 结构：${_describeJsonShape(heroShelfHeader)}',
      );
    }

    return (
      sections: sections,
      continuationToken: _homeSectionListContinuationToken(sectionList),
    );
  }

  @visibleForTesting
  SubscriptionBrowsePage parseSubscriptionsResponse(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube TV 订阅响应不是 JSON 对象');
    }
    final tvContent = data['contents']?['tvBrowseRenderer']?['content'];
    final secondaryNav = tvContent?['tvSecondaryNavRenderer'];
    final navSections = secondaryNav?['sections'];
    if (navSections is! List) {
      final surfaceRenderer = tvContent?['tvSurfaceContentRenderer'];
      final surfaceContent = surfaceRenderer?['content'];
      final genericPromo = surfaceContent?['genericPromoRenderer'];
      if (genericPromo is Map<String, dynamic>) {
        final promoTitle = _extractText(genericPromo['title']);
        final promoBody = _extractText(genericPromo['bodyText']);
        final surfaceTitle = _extractText(
          surfaceRenderer?['header']?['tvSurfaceHeaderRenderer']?['title'],
        );
        if (promoTitle == null ||
            promoTitle.trim().isEmpty ||
            promoBody == null ||
            promoBody.trim().isEmpty ||
            surfaceTitle == null ||
            surfaceTitle.trim().isEmpty) {
          throw FormatException(
            'YouTube TV 无订阅 genericPromoRenderer 缺少原生标题或正文；'
            '脱敏结构：${_describeJsonShape(surfaceRenderer)}',
          );
        }
        return (
          channels: const <Channel>[],
          sections: const <VideoSection>[],
          continuationToken: null,
        );
      }
      throw FormatException(
        'YouTube TV 订阅响应缺少 tvSecondaryNavRenderer.sections；'
        '脱敏结构：${_describeJsonShape(tvContent)}',
      );
    }

    final channels = <Channel>[];
    Map<String, dynamic>? selectedTab;
    for (final sectionNode in navSections) {
      final section = sectionNode?['tvSecondaryNavSectionRenderer'];
      if (section is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube TV 订阅 navigation section 缺少 '
          'tvSecondaryNavSectionRenderer；脱敏结构：'
          '${_describeJsonShape(sectionNode)}',
        );
      }
      final tabs = section['tabs'];
      if (tabs is! List) {
        throw FormatException(
          'YouTube TV 订阅 secondary nav 缺少 tabs；'
          '脱敏结构：${_describeJsonShape(section)}',
        );
      }

      for (final tabNode in tabs) {
        final tab = tabNode?['tabRenderer'];
        if (tab is! Map<String, dynamic>) {
          throw FormatException(
            'YouTube TV 订阅 tabs 项缺少 tabRenderer；'
            '脱敏结构：${_describeJsonShape(tabNode)}',
          );
        }
        if (tab['unselectable'] == true) break;
        if (tab['selected'] == true) {
          if (selectedTab != null) {
            throw FormatException(
              'YouTube TV 订阅响应包含多个 selected tab；'
              '脱敏结构：${_describeJsonShape(navSections)}',
            );
          }
          selectedTab = tab;
        }
        if (tab['unselectable'] == true || tab['selected'] == true) continue;

        final browseEndpoint = tab['endpoint']?['browseEndpoint'];
        if (browseEndpoint is! Map<String, dynamic>) {
          throw FormatException(
            'YouTube TV 订阅 tab 缺少 endpoint.browseEndpoint；'
            '脱敏结构：${_describeJsonShape(tab)}',
          );
        }
        final browseId = browseEndpoint['browseId']?.toString();
        if (browseId == null || browseId.isEmpty) {
          throw FormatException(
            'YouTube TV 订阅 tab 的 browseEndpoint 缺少 browseId；'
            '脱敏结构：${_describeJsonShape(browseEndpoint)}',
          );
        }
        final thumbnailUrl = _extractThumbnail(tab['thumbnail']);
        if (browseId == _subscriptionsBrowseId && thumbnailUrl == null) {
          continue;
        }

        final title = _extractText(tab['title']);
        if (title == null || title.trim().isEmpty) {
          throw FormatException(
            'YouTube TV 订阅频道 tab 缺少 title；'
            '脱敏结构：${_describeJsonShape(tab)}',
          );
        }
        final tabIdentifier = tab['tabIdentifier']?.toString();
        if (tabIdentifier == null || tabIdentifier.isEmpty) {
          throw FormatException(
            'YouTube TV 订阅频道 tab 缺少 tabIdentifier；'
            '脱敏结构：${_describeJsonShape(tab)}',
          );
        }
        channels.add(
          Channel(
            id: tabIdentifier,
            browseId: browseId,
            browseParams: browseEndpoint['params']?.toString(),
            name: title,
            avatarUrl: thumbnailUrl ?? '',
            subscriberCount: '',
            videoCount: '',
            description: '',
          ),
        );
      }
    }
    if (selectedTab == null) {
      throw FormatException(
        'YouTube TV 订阅响应没有 selected tab；'
        '脱敏结构：${_describeJsonShape(navSections)}',
      );
    }
    final surface = selectedTab['content']?['tvSurfaceContentRenderer'];
    final sectionList = surface?['content']?['sectionListRenderer'];
    if (sectionList is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube TV 订阅 selected tab 缺少 '
        'content.tvSurfaceContentRenderer.content.sectionListRenderer；'
        '脱敏结构：${_describeJsonShape(selectedTab['content'])}',
      );
    }
    final rawShelves = sectionList['contents'];
    if (rawShelves is! List) {
      throw FormatException(
        'YouTube TV 订阅 sectionListRenderer 缺少 contents；'
        '脱敏结构：${_describeJsonShape(sectionList)}',
      );
    }

    return (
      channels: channels,
      sections: _parseHomeShelves(rawShelves, categoryId: 'subscription'),
      continuationToken: _homeSectionListContinuationToken(sectionList),
    );
  }

  @visibleForTesting
  SubscriptionBrowsePage parseSubscriptionContinuationResponse(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube TV 订阅 continuation 响应不是 JSON 对象');
    }
    final sectionList = _continuationSectionList(data);
    final rawShelves = sectionList?['contents'];
    if (sectionList == null || rawShelves is! List) {
      throw FormatException(
        'YouTube TV 订阅 continuation 缺少 sectionListContinuation.contents；'
        '脱敏结构：${_describeJsonShape(data)}',
      );
    }
    return (
      channels: const [],
      sections: _parseHomeShelves(rawShelves, categoryId: 'subscription'),
      continuationToken: _homeSectionListContinuationToken(sectionList),
    );
  }

  @visibleForTesting
  SubscriptionChannelPage parseSubscriptionChannelResponse(
    Channel channel,
    dynamic data,
  ) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('YouTube TV 订阅频道响应不是 JSON 对象');
    }
    final tvContent = data['contents']?['tvBrowseRenderer']?['content'];
    final navSections = tvContent?['tvSecondaryNavRenderer']?['sections'];
    if (navSections is! List) {
      throw FormatException(
        'YouTube TV 订阅频道响应缺少 tvSecondaryNavRenderer.sections；'
        '脱敏结构：${_describeJsonShape(tvContent)}',
      );
    }

    final tabs = <Map<String, dynamic>>[];
    for (final sectionNode in navSections) {
      final section = sectionNode?['tvSecondaryNavSectionRenderer'];
      final rawTabs = section is Map<String, dynamic> ? section['tabs'] : null;
      if (rawTabs is! List) {
        throw FormatException(
          'YouTube TV 订阅频道 navigation section 缺少 tabs；'
          '脱敏结构：${_describeJsonShape(sectionNode)}',
        );
      }
      for (final tabNode in rawTabs) {
        final tab = tabNode?['tabRenderer'];
        if (tab is! Map<String, dynamic>) {
          throw FormatException(
            'YouTube TV 订阅频道 tabs 项缺少 tabRenderer；'
            '脱敏结构：${_describeJsonShape(tabNode)}',
          );
        }
        tabs.add(tab);
      }
    }

    final requestedBrowseId = channel.browseId;
    final requestedParams = channel.browseParams;
    if (requestedBrowseId == null || requestedBrowseId.isEmpty) {
      throw const FormatException('YouTube TV 订阅频道缺少 endpoint.browseId');
    }
    if (requestedParams == null || requestedParams.isEmpty) {
      throw const FormatException('YouTube TV 订阅频道缺少 endpoint.params');
    }

    final selectedTabs = tabs.where((tab) => tab['selected'] == true).toList();
    if (selectedTabs.length != 1) {
      throw FormatException(
        'YouTube TV 订阅频道响应要求唯一 selected tab；'
        '脱敏结构：${_describeJsonShape(navSections)}',
      );
    }
    final targetTab = selectedTabs.single;
    final selectedEndpoint = targetTab['endpoint']?['browseEndpoint'];
    if (selectedEndpoint is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube TV 订阅频道 selected tab 缺少 endpoint.browseEndpoint；'
        '脱敏结构：${_describeJsonShape(targetTab)}',
      );
    }
    final responseBrowseId = selectedEndpoint['browseId']?.toString();
    if (responseBrowseId == null || responseBrowseId != requestedBrowseId) {
      throw FormatException(
        'YouTube TV 订阅频道 selected tab 的 endpoint.browseId 缺失或与请求冲突；'
        '脱敏结构：${_describeJsonShape(selectedEndpoint)}',
      );
    }
    final responseParams = selectedEndpoint['params']?.toString();
    if (responseParams != null && responseParams != requestedParams) {
      throw FormatException(
        'YouTube TV 订阅频道 selected tab 的 endpoint.params 与请求冲突；'
        '脱敏结构：${_describeJsonShape(selectedEndpoint)}',
      );
    }

    final sectionList =
        targetTab['content']?['tvSurfaceContentRenderer']?['content']?['sectionListRenderer'];
    if (sectionList is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube TV 订阅频道 tab 缺少 '
        'content.tvSurfaceContentRenderer.content.sectionListRenderer；'
        '脱敏结构：${_describeJsonShape(targetTab['content'])}',
      );
    }
    final rawShelves = sectionList['contents'];
    if (rawShelves is! List) {
      throw FormatException(
        'YouTube TV 订阅频道 sectionListRenderer 缺少 contents；'
        '脱敏结构：${_describeJsonShape(sectionList)}',
      );
    }
    final sections = _parseHomeShelves(rawShelves, categoryId: 'subscription');
    final continuationToken = _homeSectionListContinuationToken(sectionList);
    if (sections.isEmpty && continuationToken == null) {
      throw const FormatException('YouTube TV 订阅频道 tab 没有可解析的内容');
    }
    return (sections: sections, continuationToken: continuationToken);
  }

  @visibleForTesting
  MusicBrowsePage parseMusicBrowseResponse(dynamic data) =>
      parseCategoryBrowseResponse(data, topicName: '音乐', categoryId: 'music');

  @visibleForTesting
  CategoryBrowsePage parseGamingBrowseResponse(dynamic data) =>
      parseCategoryBrowseResponse(data, topicName: '游戏', categoryId: 'gaming');

  @visibleForTesting
  CategoryBrowsePage parseLiveBrowseResponse(dynamic data) =>
      parseCategoryBrowseResponse(data, topicName: '直播', categoryId: 'live');

  @visibleForTesting
  MusicBrowsePage parseMusicBrowseContinuationResponse(dynamic data) =>
      parseCategoryBrowseContinuationResponse(
        data,
        topicName: '音乐',
        categoryId: 'music',
      );

  @visibleForTesting
  CategoryBrowsePage parseGamingBrowseContinuationResponse(dynamic data) =>
      parseCategoryBrowseContinuationResponse(
        data,
        topicName: '游戏',
        categoryId: 'gaming',
      );

  @visibleForTesting
  CategoryBrowsePage parseLiveBrowseContinuationResponse(dynamic data) =>
      parseCategoryBrowseContinuationResponse(
        data,
        topicName: '直播',
        categoryId: 'live',
      );

  @visibleForTesting
  CategoryBrowsePage parseCategoryBrowseContinuationResponse(
    dynamic data, {
    required String topicName,
    required String categoryId,
  }) {
    if (data is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube TVHTML5 $topicName continuation 响应不是 JSON 对象',
      );
    }
    final sections = parseHomeContinuationResponse(
      data,
      categoryId: categoryId,
    );
    final continuationToken = extractHomeSectionContinuationToken(data);
    return (sections: sections, continuationToken: continuationToken);
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

  List<VideoSection> _parseHomeShelves(
    List<dynamic> rawShelves, {
    String categoryId = 'home',
  }) {
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
      if (items != null) {
        _extractSectionVideos(
          items,
          title ?? '',
          videos,
          categoryId: categoryId,
        );
      }
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
    final heroShelfHeader =
        shelf['headerRenderer']?['heroCarouselHeaderRenderer']?['header']?['shelfHeaderRenderer'];
    return _extractText(shelf['title']) ??
        _extractText(
          heroShelfHeader?['avatarLockup']?['avatarLockupRenderer']?['title'],
        ) ??
        _extractText(heroShelfHeader?['title']) ??
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
    List<Video> result, {
    String categoryId = 'home',
  }) {
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
        'tvMusicVideoRenderer',
        'lockupViewModel',
      ].where(node.containsKey).toList();
      if (rendererKeys.length > 1 ||
          (rendererKeys.isNotEmpty && node.containsKey('tileRenderer'))) {
        throw FormatException(
          'YouTube 分区「$sectionTitle」条目包含多个内容 renderer：${node.keys.toList()}',
        );
      }
      if (rendererKeys.isNotEmpty) {
        final renderer = node[rendererKeys.single];
        final video = switch (rendererKeys.single) {
          'tvMusicVideoRenderer' => _parseMusicVideoRenderer(
            renderer,
            sectionTitle,
          ),
          'lockupViewModel' => _parseLockupViewModel(
            renderer,
            sectionTitle,
            categoryId: categoryId,
          ),
          _ => _parseVideoRenderer(
            renderer,
            sectionTitle,
            categoryId: categoryId,
          ),
        };
        final alreadyPresent = result.any((item) {
          if (video.id != null) return item.id == video.id;
          return video.browseId != null && item.browseId == video.browseId;
        });
        if (!alreadyPresent) result.add(video);
        return;
      }
      if (node['tileRenderer'] != null) {
        final video = _parseTileRenderer(
          node['tileRenderer'],
          sectionTitle,
          categoryId: categoryId,
        );
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
          categoryId: categoryId,
        );
        return;
      }
      if (node['itemSectionRenderer'] is Map<String, dynamic>) {
        _extractSectionVideos(
          node['itemSectionRenderer']['contents'],
          sectionTitle,
          result,
          categoryId: categoryId,
        );
        return;
      }
      if (node['shelfRenderer'] is Map<String, dynamic>) {
        final shelf = node['shelfRenderer'] as Map<String, dynamic>;
        final items = _extractShelfItems(node, shelf);
        if (items == null) {
          throw FormatException('YouTube 分区「$sectionTitle」的 shelf 缺少受支持的条目列表');
        }
        _extractSectionVideos(
          items,
          sectionTitle,
          result,
          categoryId: categoryId,
        );
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
        _extractSectionVideos(
          item,
          sectionTitle,
          result,
          categoryId: categoryId,
        );
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

  String? _extractGridButtonContinuation(dynamic rawButton) {
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

    final signalEndpoint = navigation['signalServiceEndpoint'];
    final reloadCommand = navigation['loadReloadContinuationCommand'];
    final clientActionEndpoint = navigation['clientActionEndpoint'];
    if (signalEndpoint != null) {
      if (signalEndpoint is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube gridButtonRenderer「$title」的 signalServiceEndpoint 格式无效',
        );
      }
      if (reloadCommand != null) {
        throw FormatException(
          'YouTube gridButtonRenderer「$title」同时包含 signal 和 reload 命令',
        );
      }
      return null;
    }

    if (clientActionEndpoint != null) {
      final navigationActions = navigation.keys
          .where((key) => key != 'clickTrackingParams')
          .toList();
      if (reloadCommand != null ||
          navigationActions.length != 1 ||
          navigationActions.single != 'clientActionEndpoint' ||
          clientActionEndpoint is! Map<String, dynamic> ||
          clientActionEndpoint.keys.any((key) => key != 'action')) {
        throw FormatException(
          'YouTube gridButtonRenderer「$title」的 clientActionEndpoint '
          '与其他 navigation command 冲突或格式无效；'
          '脱敏结构：${_describeJsonShape(navigation)}',
        );
      }

      final action = clientActionEndpoint['action'];
      if (action is Map<String, dynamic> &&
          action.length == 1 &&
          action['actionType'] == 'OPEN_SIGN_IN_PROMPT') {
        return null;
      }

      throw FormatException(
        'YouTube gridButtonRenderer「$title」包含未知 clientActionEndpoint；'
        '脱敏结构：${_describeJsonShape(navigation)}',
      );
    }

    if (reloadCommand is! Map<String, dynamic>) {
      final clientActionEndpoint = navigation['clientActionEndpoint'];
      final action = clientActionEndpoint is Map<String, dynamic>
          ? clientActionEndpoint['action']
          : null;
      final rawActionType = action is Map<String, dynamic>
          ? action['actionType']
          : null;
      final actionType =
          rawActionType is String &&
              RegExp(r'^[A-Z0-9_]+$').hasMatch(rawActionType)
          ? rawActionType
          : '<hidden-or-missing>';
      throw FormatException(
        'YouTube gridButtonRenderer「$title」缺少 loadReloadContinuationCommand；'
        'navigationEndpoint 字段：${navigation.keys.toList()}；'
        '脱敏结构：${_describeJsonShape(navigation)}；'
        'clientActionEndpoint.action.actionType：$actionType',
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

  Video _parseVideoRenderer(
    dynamic renderer,
    String sectionTitle, {
    String categoryId = 'home',
  }) {
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
    final thumbnailBadgeText =
        _extractThumbnailBadgeText(renderer['thumbnailOverlays']) ??
        _extractText(renderer['lengthText']) ??
        '';

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
      thumbnailBadgeText: thumbnailBadgeText,
      thumbnailUrl: thumbnailUrl,
      videoUrl: 'https://www.youtube.com/watch?v=$videoId',
      categoryId: categoryId,
      categoryName: sectionTitle,
      description: title,
      likesCount: 0,
    );
  }

  Video _parseLockupViewModel(
    dynamic renderer,
    String sectionTitle, {
    String categoryId = 'search',
  }) {
    if (renderer is! Map<String, dynamic>) {
      throw const FormatException('YouTube lockupViewModel 格式无效');
    }

    final rawCommand =
        renderer['rendererContext']?['commandContext']?['onTap']?['innertubeCommand'];
    if (rawCommand is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube lockupViewModel 缺少 rendererContext.commandContext.onTap.innertubeCommand；'
        '结构：${_describeJsonShape(renderer['rendererContext'])}',
      );
    }
    if (rawCommand.containsKey('commandExecutorCommand')) {
      throw FormatException(
        'YouTube lockupViewModel 使用了尚未确认的 commandExecutorCommand；'
        '结构：${_describeJsonShape(rawCommand)}',
      );
    }

    final commandKeys = rawCommand.keys
        .where((key) => key != 'clickTrackingParams')
        .toList();
    const endpointNames = {
      'watchEndpoint',
      'reelWatchEndpoint',
      'browseEndpoint',
    };
    final endpoints = commandKeys.where(endpointNames.contains).toList();
    if (endpoints.length != 1 || commandKeys.length != 1) {
      throw FormatException(
        'YouTube lockupViewModel 必须且只能包含一个已知 media endpoint；'
        '实际字段：${rawCommand.keys.toList()}；'
        '结构：${_describeJsonShape(rawCommand)}',
      );
    }

    final endpointName = endpoints.single;
    final rawEndpoint = rawCommand[endpointName];
    if (rawEndpoint is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube lockupViewModel 的 $endpointName 格式无效；'
        '结构：${_describeJsonShape(rawCommand)}',
      );
    }

    final VideoItemType itemType;
    String? videoId;
    String? browseId;
    String? browseParams;
    String? playlistId;
    switch (endpointName) {
      case 'watchEndpoint':
        itemType = VideoItemType.video;
        videoId = rawEndpoint['videoId']?.toString();
        playlistId = rawEndpoint['playlistId']?.toString();
        if (videoId == null || videoId.isEmpty) {
          throw const FormatException(
            'YouTube lockupViewModel.watchEndpoint 缺少 videoId',
          );
        }
      case 'reelWatchEndpoint':
        itemType = VideoItemType.shorts;
        videoId = rawEndpoint['videoId']?.toString();
        if (videoId == null || videoId.isEmpty) {
          throw const FormatException(
            'YouTube lockupViewModel.reelWatchEndpoint 缺少 videoId',
          );
        }
      case 'browseEndpoint':
        browseId = rawEndpoint['browseId']?.toString();
        browseParams = rawEndpoint['params']?.toString();
        if (browseId == null || browseId.isEmpty) {
          throw const FormatException(
            'YouTube lockupViewModel.browseEndpoint 缺少 browseId',
          );
        }
        itemType = _browseEndpointTileType(rawEndpoint);
      default:
        throw StateError('Unreachable lockup endpoint: $endpointName');
    }

    final metadata = renderer['metadata']?['lockupMetadataViewModel'];
    final title = _extractText(metadata?['title']);
    if (title == null || title.trim().isEmpty) {
      throw FormatException(
        'YouTube lockupViewModel 缺少 metadata.lockupMetadataViewModel.title；'
        'metadata 结构：${_describeJsonShape(renderer['metadata'])}',
      );
    }

    final rawMetadataRows =
        metadata?['metadata']?['contentMetadataViewModel']?['metadataRows'];
    final metadataLines = rawMetadataRows is List
        ? rawMetadataRows
              .map((row) {
                final parts = row?['metadataParts'];
                if (parts is! List) return '';
                return parts
                    .map((part) => _extractText(part?['text']))
                    .whereType<String>()
                    .where((text) => text.isNotEmpty)
                    .join(' • ');
              })
              .where((line) => line.isNotEmpty)
              .toList()
        : const <String>[];

    final contentImage = renderer['contentImage'];
    final thumbnailView = contentImage?['thumbnailViewModel'];
    final thumbnailUrl =
        _extractThumbnail(thumbnailView?['image']) ??
        _extractThumbnail(
          contentImage?['collectionThumbnailViewModel']?['primaryThumbnail']?['thumbnailViewModel']?['image'],
        );
    if ((itemType == VideoItemType.video || itemType == VideoItemType.shorts) &&
        (thumbnailUrl == null || thumbnailUrl.isEmpty)) {
      throw FormatException(
        'YouTube lockupViewModel 缺少 contentImage.thumbnailViewModel.image；'
        'contentImage 结构：${_describeJsonShape(contentImage)}',
      );
    }

    final videoUrl = videoId == null
        ? ''
        : itemType == VideoItemType.shorts
        ? 'https://www.youtube.com/shorts/$videoId'
        : playlistId == null || playlistId.isEmpty
        ? 'https://www.youtube.com/watch?v=$videoId'
        : Uri.https('www.youtube.com', '/watch', {
            'v': videoId,
            'list': playlistId,
          }).toString();

    return Video(
      id: videoId,
      itemType: itemType,
      isLive: _hasVideoState(thumbnailView?['overlays'], 'LIVE'),
      isUpcoming: _hasVideoState(thumbnailView?['overlays'], 'UPCOMING'),
      browseId: browseId,
      browseParams: browseParams,
      playlistId: playlistId,
      title: title,
      channelName: metadataLines.isEmpty ? '' : metadataLines.first,
      channelAvatar: '',
      views: metadataLines.skip(1).join(' • '),
      uploadTime: '',
      thumbnailBadgeText:
          _extractThumbnailBadgeText(thumbnailView?['overlays']) ?? '',
      thumbnailUrl: thumbnailUrl ?? '',
      videoUrl: videoUrl,
      categoryId: categoryId,
      categoryName: sectionTitle,
      description: title,
      likesCount: 0,
    );
  }

  Video _parseMusicVideoRenderer(dynamic renderer, String sectionTitle) {
    if (renderer is! Map<String, dynamic>) {
      throw const FormatException('YouTube tvMusicVideoRenderer 格式无效');
    }

    final title = _extractText(renderer['primaryText']);
    if (title == null || title.trim().isEmpty) {
      throw const FormatException(
        'YouTube tvMusicVideoRenderer 缺少 primaryText',
      );
    }

    final navigationEndpoint = renderer['navigationEndpoint'];
    final watchEndpoint = navigationEndpoint is Map<String, dynamic>
        ? navigationEndpoint['watchEndpoint']
        : null;
    if (watchEndpoint is! Map<String, dynamic>) {
      throw FormatException(
        'YouTube tvMusicVideoRenderer「$title」缺少 navigationEndpoint.watchEndpoint',
      );
    }

    final videoId = watchEndpoint['videoId']?.toString();
    if (videoId == null || videoId.isEmpty) {
      throw FormatException(
        'YouTube tvMusicVideoRenderer「$title」缺少 watchEndpoint.videoId',
      );
    }

    final thumbnailUrl = _extractThumbnail(renderer['thumbnail']);
    if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
      throw FormatException(
        'YouTube 音乐视频 $videoId 缺少缩略图地址；'
        'renderer 字段：${renderer.keys.toList()}',
      );
    }

    final playlistId = watchEndpoint['playlistId']?.toString();
    final playlistQuery = playlistId == null || playlistId.isEmpty
        ? ''
        : '&list=$playlistId';
    final thumbnailBadgeText = _extractText(renderer['lengthText']) ?? '';

    return Video(
      id: videoId,
      itemType: VideoItemType.video,
      playlistId: playlistId,
      title: title,
      channelName: _extractText(renderer['secondaryText']) ?? '',
      channelAvatar: '',
      views: _extractText(renderer['tertiaryText']) ?? '',
      uploadTime: '',
      thumbnailBadgeText: thumbnailBadgeText,
      thumbnailUrl: thumbnailUrl,
      videoUrl: 'https://www.youtube.com/watch?v=$videoId$playlistQuery',
      categoryId: 'music',
      categoryName: sectionTitle,
      description: title,
      likesCount: 0,
    );
  }

  /// Parse Cobalt / TVHTML5 tileRenderer
  Video _parseTileRenderer(
    dynamic renderer,
    String sectionTitle, {
    String categoryId = 'home',
  }) {
    if (renderer is! Map<String, dynamic>) {
      throw const FormatException('YouTube 磁贴视频条目格式无效');
    }

    final contentType = renderer['contentType'];
    final rawCommand = renderer['onSelectCommand'];
    if (rawCommand is! Map<String, dynamic>) {
      throw const FormatException('YouTube tile 缺少 onSelectCommand');
    }
    final command = contentType == 'TILE_CONTENT_TYPE_VIDEO'
        ? _unwrapVideoTileCommandExecutor(rawCommand)
        : rawCommand;
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
      if (itemType == VideoItemType.video) {
        final endpointPlaylistId = endpoint['playlistId']?.toString();
        if (endpointPlaylistId != null && endpointPlaylistId.isNotEmpty) {
          playlistId = endpointPlaylistId;
        }
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

    final thumbnailBadgeText =
        _extractThumbnailBadgeText(tileHeader?['thumbnailOverlays']) ??
        _extractText(trackTileHeader?['duration']) ??
        _extractText(renderer['lengthText']) ??
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
      thumbnailBadgeText: thumbnailBadgeText,
      thumbnailUrl: thumbnailUrl ?? '',
      videoUrl: videoId == null || videoId.isEmpty
          ? ''
          : itemType == VideoItemType.shorts
          ? 'https://www.youtube.com/shorts/$videoId'
          : playlistId == null || playlistId.isEmpty
          ? 'https://www.youtube.com/watch?v=$videoId'
          : Uri.https('www.youtube.com', '/watch', {
              'v': videoId,
              'list': playlistId,
            }).toString(),
      categoryId: categoryId,
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
        '实际字段：${command.keys.toList()}；'
        '脱敏结构：${_describeJsonShape(command)}',
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

  Map<String, dynamic> _unwrapVideoTileCommandExecutor(
    Map<String, dynamic> command,
  ) {
    final rawExecutor = command['commandExecutorCommand'];
    if (rawExecutor == null) return command;
    if (rawExecutor is! Map<String, dynamic> ||
        rawExecutor.keys.any((key) => key != 'commands')) {
      throw FormatException(
        'YouTube VIDEO tile commandExecutorCommand 格式无效；'
        '脱敏结构：${_describeJsonShape(command)}',
      );
    }

    final commands = rawExecutor['commands'];
    if (commands is! List) {
      throw FormatException(
        'YouTube VIDEO tile commandExecutorCommand 缺少 commands 列表；'
        '脱敏结构：${_describeJsonShape(command)}',
      );
    }

    const endpointNames = {
      'watchEndpoint',
      'reelWatchEndpoint',
      'browseEndpoint',
    };
    final endpoints = <MapEntry<String, dynamic>>[];
    for (var index = 0; index < commands.length; index++) {
      final action = commands[index];
      if (action is! Map<String, dynamic>) {
        throw FormatException(
          'YouTube VIDEO tile commandExecutorCommand.commands[$index] 格式无效；'
          '实际类型：${action.runtimeType}',
        );
      }

      final actionKeys = action.keys
          .where((key) => key != 'clickTrackingParams')
          .toList();
      final actionEndpoints = actionKeys.where(endpointNames.contains).toList();
      if (actionEndpoints.length == 1 && actionKeys.length == 1) {
        final endpointName = actionEndpoints.single;
        endpoints.add(MapEntry(endpointName, action[endpointName]));
        continue;
      }

      if (actionEndpoints.isEmpty &&
          actionKeys.length == 1 &&
          actionKeys.single == 'feedbackEndpoint' &&
          action['feedbackEndpoint'] is Map<String, dynamic>) {
        continue;
      }

      throw FormatException(
        'YouTube VIDEO tile commandExecutorCommand.commands[$index] '
        '包含不支持或冲突的动作；实际字段：${action.keys.toList()}；'
        '脱敏结构：${_describeJsonShape(action)}',
      );
    }

    if (endpoints.length != 1) {
      throw FormatException(
        'YouTube VIDEO tile commandExecutorCommand 必须且只能包含一个播放或浏览 endpoint；'
        '识别到 ${endpoints.length} 个 ${endpoints.map((endpoint) => endpoint.key).toList()}；'
        '脱敏结构：${_describeJsonShape(command)}',
      );
    }

    final endpoint = endpoints.single;
    return {endpoint.key: endpoint.value};
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
      final style = (node['style'] ?? node['badgeStyle'])
          ?.toString()
          .toUpperCase();
      final text =
          (_extractText(node['text']) ??
                  _extractText(
                    node['rendererContext']?['accessibilityContext']?['label'],
                  ))
              ?.toUpperCase();
      final badgeStyle = state == 'LIVE'
          ? 'BADGE_STYLE_TYPE_LIVE_NOW'
          : 'BADGE_STYLE_TYPE_UPCOMING';
      final localizedLabels = state == 'LIVE'
          ? const {'直播', '正在直播'}
          : const {'即将直播'};
      if (style == state ||
          style == badgeStyle ||
          text == state ||
          localizedLabels.contains(text)) {
        return true;
      }
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

  String? _extractThumbnailBadgeText(dynamic overlaysNode) {
    final overlays = overlaysNode as List?;
    if (overlays == null) return null;

    for (final overlay in overlays) {
      final timeStatusText = _extractText(
        overlay?['thumbnailOverlayTimeStatusRenderer']?['text'],
      );
      if (timeStatusText != null && timeStatusText.isNotEmpty) {
        return timeStatusText;
      }

      final bottomOverlay = overlay?['thumbnailBottomOverlayViewModel'];
      if (bottomOverlay == null) continue;
      final badges = bottomOverlay['badges'];
      if (badges is! List) {
        throw FormatException(
          'YouTube thumbnailBottomOverlayViewModel.badges 格式无效；'
          '结构：${_describeJsonShape(bottomOverlay)}',
        );
      }

      for (final badge in badges) {
        final badgeViewModel = badge?['thumbnailBadgeViewModel'];
        if (badgeViewModel == null) continue;
        final badgeText =
            _extractText(badgeViewModel['text']) ??
            _extractText(
              badgeViewModel['rendererContext']?['accessibilityContext']?['label'],
            );
        if (badgeText != null && badgeText.isNotEmpty) return badgeText;
      }
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
