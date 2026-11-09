// This is a basic Flutter widget test for Plexus.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/app.dart';
import 'package:plexus/models/video.dart';
import 'package:plexus/models/video_section.dart';
import 'package:plexus/pages/category/category_page.dart';
import 'package:plexus/pages/home/browse_destination_page.dart';
import 'package:plexus/pages/home/item_destination_pages.dart';
import 'package:plexus/pages/player/special_video_pages.dart';
import 'package:plexus/widgets/feed_continuation_status.dart';

void main() {
  testWidgets('Plexus app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PlexusApp());

    // Verify that Plexus app launches.
    expect(find.byType(PlexusApp), findsOneWidget);
  });

  testWidgets('category filters are hidden while signed out', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: const CategoryPage()));

    expect(find.text('音乐'), findsNothing);
    expect(find.text('探索主题'), findsNothing);
    expect(find.text('登录账号'), findsOneWidget);
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
}

Video _video({
  required VideoItemType itemType,
  required String title,
  bool isLive = false,
  bool isUpcoming = false,
}) => Video(
  id: 'item-id',
  itemType: itemType,
  isLive: isLive,
  isUpcoming: isUpcoming,
  title: title,
  channelName: 'Channel',
  channelAvatar: '',
  views: '',
  uploadTime: '',
  duration: '',
  thumbnailUrl: '',
  videoUrl: '',
  categoryId: 'home',
  categoryName: 'Home',
  description: title,
  likesCount: 0,
);
