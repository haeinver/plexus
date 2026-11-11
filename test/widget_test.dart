// This is a basic Flutter widget test for Plexus.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/app.dart';
import 'package:plexus/models/video.dart';
import 'package:plexus/models/video_section.dart';
import 'package:plexus/pages/category/category_page.dart';
import 'package:plexus/pages/category/category_topic_feed_page.dart';
import 'package:plexus/pages/category/gaming_page.dart';
import 'package:plexus/pages/category/live_page.dart';
import 'package:plexus/pages/category/music_page.dart';
import 'package:plexus/pages/home/browse_destination_page.dart';
import 'package:plexus/pages/home/item_destination_pages.dart';
import 'package:plexus/pages/player/special_video_pages.dart';
import 'package:plexus/pages/player/video_detail_page.dart';
import 'package:plexus/pages/search/search_page.dart';
import 'package:plexus/pages/search/search_history_service.dart';
import 'package:plexus/services/youtube_data_service.dart';
import 'package:plexus/widgets/error_state_widget.dart';
import 'package:plexus/widgets/feed_continuation_status.dart';
import 'package:plexus/widgets/video_card.dart';

void main() {
  testWidgets('Plexus app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PlexusApp());

    // Verify that Plexus app launches.
    expect(find.byType(PlexusApp), findsOneWidget);
  });

  testWidgets('video card displays its normalized thumbnail badge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: VideoCard(
              video: _video(
                itemType: VideoItemType.video,
                title: 'Live entry',
                isLive: true,
                thumbnailBadgeText: 'LIVE',
              ),
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('category filters remain available while signed out', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: const CategoryPage()));

    expect(find.text('音乐'), findsWidgets);
    expect(find.text('探索主题'), findsOneWidget);
    expect(find.text('登录账号'), findsNothing);
  });

  testWidgets('music feed stays inside the category page scaffold', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: const CategoryPage()));
    await tester.tap(find.byKey(const ValueKey('category-tile-music')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CategoryPage), findsOneWidget);
    expect(find.byType(MusicPage), findsOneWidget);
    expect(find.byType(CategoryTopicFeedPage), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('音乐')),
      findsOneWidget,
    );
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('游戏'), findsOneWidget);
  });

  testWidgets('gaming feed stays inside the category page scaffold', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: const CategoryPage()));
    await tester.tap(find.byKey(const ValueKey('category-tile-gaming')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CategoryPage), findsOneWidget);
    expect(find.byType(GamingPage), findsOneWidget);
    expect(find.byType(CategoryTopicFeedPage), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('游戏')),
      findsOneWidget,
    );
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('音乐'), findsOneWidget);
  });

  testWidgets('live feed stays inside the category page scaffold', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: const CategoryPage()));
    await tester.drag(
      find.byKey(const ValueKey('category-directory')),
      const Offset(0, -600),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('category-tile-live')),
    );
    await tester.tap(find.byKey(const ValueKey('category-tile-live')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CategoryPage), findsOneWidget);
    expect(find.byType(LivePage), findsOneWidget);
    expect(find.byType(CategoryTopicFeedPage), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('直播')),
      findsOneWidget,
    );
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('游戏'), findsOneWidget);
  });

  testWidgets('continuation failure shows details and retry action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedContinuationStatus(
            isLoading: false,
            errorMessage: 'HTTP 500: continuation failed',
            errorTitle: '音乐后续分区加载失败',
            retryLabel: '重试加载更多音乐',
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('音乐后续分区加载失败'), findsOneWidget);
    expect(find.text('HTTP 500: continuation failed'), findsOneWidget);
    expect(find.text('重试加载更多音乐'), findsOneWidget);
  });

  testWidgets('feed error state shows details and retries', (
    WidgetTester tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
    );
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: ErrorStateWidget(
            errorMessage: 'HTTP 403: music feed unavailable',
            retryText: '重新加载音乐',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    final errorIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(errorIcon.size, 64);
    expect(errorIcon.color, theme.colorScheme.error);
    expect(find.text('HTTP 403: music feed unavailable'), findsOneWidget);
    expect(find.text('重新加载音乐'), findsOneWidget);

    await tester.tap(find.text('重新加载音乐'));
    expect(retried, isTrue);
  });

  testWidgets('feed loading and refresh widgets use the theme primary color', (
    WidgetTester tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
    );
    var rebuildRequested = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(
                child: FeedInitialLoading(message: '正在加载 YouTube 首页推荐视频...'),
              ),
              Expanded(
                child: FeedRefreshIndicator(
                  onRefresh: ({required bool rebuildFeed}) async {
                    rebuildRequested = rebuildFeed;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [Text('Feed')],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator).first,
    );
    final refreshIndicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );

    expect(find.text('正在加载 YouTube 首页推荐视频...'), findsOneWidget);
    expect(progress.color, theme.colorScheme.primary);
    expect(refreshIndicator.color, theme.colorScheme.primary);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: FeedRefreshIndicator(
            onRefresh: ({required bool rebuildFeed}) async {
              rebuildRequested = rebuildFeed;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [Text('Feed')],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.text('Feed'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(rebuildRequested, isTrue);
  });

  testWidgets('Shorts has a dedicated detail screen', (
    WidgetTester tester,
  ) async {
    final video = _video(itemType: VideoItemType.shorts, title: 'Short clip');

    await tester.pumpWidget(MaterialApp(home: ShortsDetailPage(video: video)));

    expect(find.text('Shorts'), findsOneWidget);
    expect(find.text('Short clip'), findsOneWidget);
  });

  testWidgets('live and upcoming videos have a dedicated screen', (
    WidgetTester tester,
  ) async {
    final video = _video(
      itemType: VideoItemType.video,
      title: 'Scheduled event',
      isUpcoming: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: LiveEventDetailPage(video: video)),
    );

    expect(find.text('即将直播'), findsNWidgets(2));
    expect(find.text('Scheduled event'), findsOneWidget);
  });

  testWidgets('playlist browse screen identifies its item type', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowseDestinationPage(
          destination: const VideoSection(
            title: 'Playlist title',
            videos: [],
            browseId: 'VLplaylist-id',
          ),
          destinationType: VideoItemType.playlist,
        ),
      ),
    );

    expect(find.text('Playlist title'), findsOneWidget);
    expect(find.text('播放列表'), findsOneWidget);
  });

  testWidgets('browse item types open their dedicated MVP pages', (
    WidgetTester tester,
  ) async {
    final destinations = [
      (
        page: PlaylistDetailPage(
          video: _video(itemType: VideoItemType.playlist, title: 'Playlist'),
        ),
        label: '播放列表',
        title: 'Playlist',
      ),
      (
        page: TrackDetailPage(
          video: _video(itemType: VideoItemType.track, title: 'Track'),
        ),
        label: '音乐曲目',
        title: 'Track',
      ),
      (
        page: ChannelDetailPage(
          video: _video(itemType: VideoItemType.channel, title: 'Channel'),
        ),
        label: '频道',
        title: 'Channel',
      ),
      (
        page: BrowseEntryDetailPage(
          video: _video(
            itemType: VideoItemType.browseDestination,
            title: 'Topic',
          ),
        ),
        label: '浏览入口',
        title: 'Topic',
      ),
    ];

    for (final destination in destinations) {
      await tester.pumpWidget(MaterialApp(home: destination.page));
      expect(find.text(destination.label), findsOneWidget);
      expect(find.text(destination.title), findsWidgets);
    }
  });

  testWidgets('search submits query and uses shared item destination routing', (
    WidgetTester tester,
  ) async {
    final historyStore = _FakeSearchHistoryStore();
    final dataSource = _FakeSearchDataSource(
      result: (
        sections: [
          VideoSection(
            title: '频道',
            videos: [
              _video(
                itemType: VideoItemType.channel,
                title: 'Search channel result',
                id: null,
                browseId: 'channel-browse-id',
              ),
            ],
          ),
        ],
        estimatedResults: '1',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(dataSource: dataSource, historyStore: historyStore),
      ),
    );
    await tester.enterText(find.byType(TextField), '  search term  ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    expect(dataSource.queries, ['search term']);
    expect(historyStore.history, ['search term']);
    expect(find.text('“search term” 的搜索结果'), findsOneWidget);
    expect(find.text('约 1 条结果'), findsOneWidget);
    expect(find.text('频道'), findsNothing);
    expect(find.text('Search channel result'), findsOneWidget);
    expect(find.byType(VideoCard), findsOneWidget);
    final resultGrid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (resultGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );

    await tester.tap(find.text('Search channel result'));
    await tester.pumpAndSettle();

    expect(find.byType(ChannelDetailPage), findsOneWidget);
    expect(find.text('频道'), findsOneWidget);
  });

  testWidgets('search results header and grid fit a narrow screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final longQuery = '这是一个用于检查搜索结果标题省略效果的很长查询词';
    final dataSource = _FakeSearchDataSource(
      result: (
        sections: [
          VideoSection(
            title: '视频',
            videos: [
              _video(itemType: VideoItemType.video, title: '第一条搜索结果'),
              _video(itemType: VideoItemType.video, title: '第二条搜索结果'),
            ],
          ),
        ],
        estimatedResults: '331868205123456',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          initialQuery: longQuery,
          dataSource: dataSource,
          historyStore: _FakeSearchHistoryStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('的搜索结果'), findsOneWidget);
    expect(find.text('约 331868205123456 条结果'), findsOneWidget);
    expect(find.byType(VideoCard), findsNWidgets(2));
    final resultGrid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (resultGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );
  });

  testWidgets('search cards fill rows across section boundaries', (
    WidgetTester tester,
  ) async {
    final dataSource = _FakeSearchDataSource(
      result: (
        sections: [
          VideoSection(
            title: 'First section',
            videos: [
              _video(itemType: VideoItemType.video, title: 'First result'),
            ],
          ),
          VideoSection(
            title: 'Second section',
            videos: [
              _video(itemType: VideoItemType.video, title: 'Second result'),
            ],
          ),
        ],
        estimatedResults: null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          initialQuery: 'search',
          dataSource: dataSource,
          historyStore: _FakeSearchHistoryStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstPosition = tester.getTopLeft(find.text('First result'));
    final secondPosition = tester.getTopLeft(find.text('Second result'));
    expect(secondPosition.dx, greaterThan(firstPosition.dx));
    expect(secondPosition.dy, closeTo(firstPosition.dy, 0.1));
  });

  testWidgets('scrolling to the bottom loads more search results', (
    WidgetTester tester,
  ) async {
    final continuation = Completer<VideoSection>();
    final initialSection = VideoSection(
      title: 'Hidden section title',
      videos: List.generate(
        24,
        (index) => _video(
          itemType: VideoItemType.video,
          title: 'Search result $index',
        ),
      ),
      continuationToken: 'search-next',
    );
    final dataSource = _FakeSearchDataSource(
      result: (sections: [initialSection], estimatedResults: null),
      onFetchMore: (_) => continuation.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          initialQuery: 'search',
          dataSource: dataSource,
          historyStore: _FakeSearchHistoryStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(dataSource.queries, ['search']);
    expect(find.text('Search result 0'), findsOneWidget);

    final resultsList = find.byType(ListView).last;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: resultsList, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(320));

    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();

    expect(scrollable.position.extentAfter, lessThan(320));
    expect(dataSource.continuedSections, hasLength(1));

    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    expect(find.byType(FeedContinuationStatus), findsOneWidget);
    expect(find.text('正在加载更多搜索结果...'), findsOneWidget);

    continuation.complete(
      VideoSection(
        title: initialSection.title,
        videos: [
          ...initialSection.videos,
          _video(itemType: VideoItemType.video, title: 'Continuation result'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continuation result'), findsOneWidget);
    expect(find.byType(FeedContinuationStatus), findsNothing);
  });

  testWidgets('typing shows related suggestions before submitting search', (
    WidgetTester tester,
  ) async {
    final dataSource = _FakeSearchDataSource(
      result: (sections: [], estimatedResults: null),
      suggestions: ['王者荣耀', '王一博'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          dataSource: dataSource,
          historyStore: _FakeSearchHistoryStore(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '王');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(dataSource.suggestionQueries, ['王']);
    expect(dataSource.queries, isEmpty);
    expect(find.text('王者荣耀'), findsOneWidget);
    expect(find.text('王一博'), findsOneWidget);

    await tester.tap(find.text('王者荣耀'));
    await tester.pump();
    await tester.pump();
    expect(dataSource.queries, ['王者荣耀']);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isFalse,
    );
  });

  testWidgets('search refinement submits its endpoint query', (
    WidgetTester tester,
  ) async {
    final dataSource = _FakeSearchDataSource(
      result: (
        sections: [
          VideoSection(
            title: '更多王剑结果',
            videos: const [],
            searchQuery: '王剑相关搜索',
          ),
        ],
        estimatedResults: null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          initialQuery: '王剑',
          dataSource: dataSource,
          historyStore: _FakeSearchHistoryStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(dataSource.queries, ['王剑']);
    expect(find.text('查看更多相关搜索'), findsOneWidget);

    await tester.tap(find.text('查看更多相关搜索'));
    await tester.pump();
    await tester.pump();

    expect(dataSource.queries, ['王剑', '王剑相关搜索']);
  });

  testWidgets('search history restores and clears persisted queries', (
    WidgetTester tester,
  ) async {
    final historyStore = _FakeSearchHistoryStore(['saved query']);

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          dataSource: _FakeSearchDataSource(
            result: (sections: [], estimatedResults: null),
          ),
          historyStore: historyStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('saved query'), findsOneWidget);
    await tester.tap(find.byTooltip('清空历史'));
    await tester.pumpAndSettle();

    expect(historyStore.history, isEmpty);
    expect(find.text('搜索 YouTube 内容'), findsOneWidget);
  });

  testWidgets('selecting saved search history hides the keyboard', (
    WidgetTester tester,
  ) async {
    final dataSource = _FakeSearchDataSource(
      result: (sections: [], estimatedResults: null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          dataSource: dataSource,
          historyStore: _FakeSearchHistoryStore(['saved query']),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('saved query'));
    await tester.pump();
    await tester.pump();

    expect(dataSource.queries, ['saved query']);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isFalse,
    );
  });

  test('shared video routing maps each item type to its destination', () {
    final routes = [
      (
        video: _video(itemType: VideoItemType.video, title: 'Video'),
        destination: VideoDetailPage,
      ),
      (
        video: _video(
          itemType: VideoItemType.video,
          title: 'Live event',
          isLive: true,
        ),
        destination: LiveEventDetailPage,
      ),
      (
        video: _video(itemType: VideoItemType.shorts, title: 'Shorts'),
        destination: ShortsDetailPage,
      ),
      (
        video: _video(
          itemType: VideoItemType.track,
          title: 'Track',
          id: null,
          browseId: 'track-browse-id',
        ),
        destination: TrackDetailPage,
      ),
      (
        video: _video(
          itemType: VideoItemType.playlist,
          title: 'Playlist',
          playlistId: 'RDplaylist',
        ),
        destination: PlaylistDetailPage,
      ),
      (
        video: _video(
          itemType: VideoItemType.channel,
          title: 'Channel',
          id: null,
          browseId: 'channel-browse-id',
        ),
        destination: ChannelDetailPage,
      ),
      (
        video: _video(
          itemType: VideoItemType.browseDestination,
          title: 'Browse entry',
          id: null,
          browseId: 'browse-id',
        ),
        destination: BrowseEntryDetailPage,
      ),
    ];

    for (final route in routes) {
      expect(
        buildVideoItemDestination(route.video).runtimeType,
        route.destination,
      );
    }
  });
}

Video _video({
  required VideoItemType itemType,
  required String title,
  String? id = 'item-id',
  String? browseId,
  String? playlistId,
  bool isLive = false,
  bool isUpcoming = false,
  String thumbnailBadgeText = '',
}) => Video(
  id: id,
  itemType: itemType,
  isLive: isLive,
  isUpcoming: isUpcoming,
  browseId: browseId,
  playlistId: playlistId,
  title: title,
  channelName: 'Channel',
  channelAvatar: '',
  views: '',
  uploadTime: '',
  thumbnailBadgeText: thumbnailBadgeText,
  thumbnailUrl: '',
  videoUrl: '',
  categoryId: 'home',
  categoryName: 'Home',
  description: title,
  likesCount: 0,
);

class _FakeSearchDataSource implements SearchDataSource {
  _FakeSearchDataSource({
    required this.result,
    this.suggestions = const [],
    this.onFetchMore,
  });

  final SearchBrowsePage result;
  final List<String> suggestions;
  final List<String> queries = [];
  final List<String> suggestionQueries = [];
  final Future<VideoSection> Function(VideoSection section)? onFetchMore;
  final List<VideoSection> continuedSections = [];

  @override
  Future<List<String>> fetchSearchSuggestions(String query) async {
    suggestionQueries.add(query);
    return suggestions;
  }

  @override
  Future<SearchBrowsePage> fetchSearchResults(String query) async {
    queries.add(query);
    return result;
  }

  @override
  Future<VideoSection> fetchMoreSearchSectionVideos(
    VideoSection section,
  ) async {
    continuedSections.add(section);
    return onFetchMore?.call(section) ?? section;
  }
}

class _FakeSearchHistoryStore implements SearchHistoryStore {
  _FakeSearchHistoryStore([List<String> initialHistory = const []])
    : history = List<String>.of(initialHistory);

  final List<String> history;

  @override
  Future<List<String>> load() async => List<String>.of(history);

  @override
  Future<void> save(List<String> queries) async {
    history
      ..clear()
      ..addAll(queries);
  }
}
