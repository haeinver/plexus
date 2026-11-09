import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../models/video_section.dart';
import '../player/special_video_pages.dart';
import '../player/video_detail_page.dart';
import '../../services/locale_service.dart';
import '../../services/youtube_auth_service.dart';
import '../../services/youtube_data_service.dart';
import '../../widgets/error_state_widget.dart';
import '../../widgets/feed_continuation_status.dart';
import '../../widgets/sign_in_required_widget.dart';
import '../../widgets/video_section_row.dart';
import 'browse_destination_page.dart';
import 'item_destination_pages.dart';
import '../search/search_page.dart';

/// 首页 (Home Page strictly following SmartTube SignInError & TVHTML5 loading logic)
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final YouTubeDataService _dataService = YouTubeDataService();
  final YouTubeAuthService _authService = YouTubeAuthService();
  final LocaleService _localeService = LocaleService();

  List<VideoSection> _sections = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _loadGeneration = 0;
  int _feedLayoutGeneration = 0;
  final Set<int> _loadingSectionIndexes = {};
  final Map<int, String> _sectionErrors = {};
  final Map<int, ScrollController> _sectionScrollControllers = {};

  @override
  void initState() {
    super.initState();
    _authService.addAccountListener(_onAccountChanged);
    _localeService.addListener(_onLocaleChanged);
    _loadHomeFeed();
  }

  @override
  void dispose() {
    _authService.removeAccountListener(_onAccountChanged);
    _localeService.removeListener(_onLocaleChanged);
    for (final controller in _sectionScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) {
      _loadHomeFeed();
    }
  }

  void _onLocaleChanged() {
    if (mounted) {
      _loadHomeFeed();
    }
  }

  Future<void> _loadHomeFeed({bool rebuildFeed = false}) async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final oldScrollControllers = rebuildFeed
        ? _sectionScrollControllers.values.toList()
        : const <ScrollController>[];
    if (rebuildFeed) _sectionScrollControllers.clear();

    // Check if user is logged in
    if (!_authService.isLoggedIn) {
      if (generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _sections = [];
        if (rebuildFeed) _feedLayoutGeneration++;
      });
      _disposeScrollControllersAfterLayout(oldScrollControllers);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (rebuildFeed) {
        _sections = [];
        _feedLayoutGeneration++;
      }
      _loadingSectionIndexes.clear();
      _sectionErrors.clear();
    });
    _disposeScrollControllersAfterLayout(oldScrollControllers);

    try {
      var refreshedSections = <VideoSection>[];
      await for (final sections in _dataService.fetchHomeFeedProgressively()) {
        if (!mounted || generation != _loadGeneration) return;
        if (rebuildFeed) {
          refreshedSections = List<VideoSection>.of(sections);
        } else {
          setState(() => _sections = List<VideoSection>.of(sections));
        }
      }
      if (mounted && generation == _loadGeneration) {
        setState(() {
          if (rebuildFeed) _sections = refreshedSections;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _disposeScrollControllersAfterLayout(
    List<ScrollController> controllers,
  ) {
    if (controllers.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
  }

  Future<void> _loadMoreSection(int sectionIndex) async {
    if (!mounted ||
        sectionIndex >= _sections.length ||
        _loadingSectionIndexes.contains(sectionIndex)) {
      return;
    }

    final section = _sections[sectionIndex];
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return;

    final generation = _loadGeneration;
    setState(() {
      _loadingSectionIndexes.add(sectionIndex);
      _sectionErrors.remove(sectionIndex);
    });

    try {
      final updatedSection = await _dataService.fetchMoreHomeSectionVideos(
        section,
      );
      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        if (sectionIndex < _sections.length &&
            _sections[sectionIndex].continuationToken == token) {
          _sections[sectionIndex] = updatedSection;
        }
        _loadingSectionIndexes.remove(sectionIndex);
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadingSectionIndexes.remove(sectionIndex);
        _sectionErrors[sectionIndex] = error.toString();
      });
    }
  }

  void _openBrowseDestination(
    VideoSection destination, {
    VideoItemType? destinationType,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BrowseDestinationPage(
          destination: destination,
          destinationType: destinationType,
        ),
      ),
    );
  }

  void _openVideoOrBrowseDestination(Video video) {
    switch (video.itemType) {
      case VideoItemType.video:
        if (video.id == null || video.id!.isEmpty || video.browseId != null) {
          throw StateError(
            'YouTube ${video.itemType.name} 条目 endpoint 与内容类型不匹配',
          );
        }
        if (video.isLive || video.isUpcoming) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LiveEventDetailPage(video: video),
            ),
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoDetailPage(video: video),
          ),
        );
        return;
      case VideoItemType.shorts:
        if (video.id == null || video.id!.isEmpty || video.browseId != null) {
          throw StateError('YouTube Shorts 条目 endpoint 与内容类型不匹配');
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShortsDetailPage(video: video),
          ),
        );
        return;
      case VideoItemType.track:
        _openItemDestination(
          video,
          TrackDetailPage(video: video),
          requiresBrowseId: true,
        );
        return;
      case VideoItemType.channel:
        _openItemDestination(
          video,
          ChannelDetailPage(video: video),
          requiresBrowseId: true,
        );
        return;
      case VideoItemType.browseDestination:
        if (video.id != null ||
            video.browseId == null ||
            video.browseId!.isEmpty) {
          throw StateError(
            'YouTube ${video.itemType.name} 条目 endpoint 与内容类型不匹配',
          );
        }
        _openItemDestination(
          video,
          BrowseEntryDetailPage(video: video),
          requiresBrowseId: true,
        );
        return;
      case VideoItemType.playlist:
        if ((video.browseId == null || video.browseId!.isEmpty) &&
            (video.playlistId == null || video.playlistId!.isEmpty)) {
          throw StateError('YouTube playlist 条目缺少 browseId 或 videoId');
        }
        if (video.browseId != null && video.id != null) {
          throw StateError('YouTube playlist 条目同时含 browseId 和 videoId');
        }
        _openItemDestination(video, PlaylistDetailPage(video: video));
        return;
    }
  }

  void _openItemDestination(
    Video video,
    Widget destination, {
    bool requiresBrowseId = false,
  }) {
    if (requiresBrowseId &&
        (video.id != null ||
            video.browseId == null ||
            video.browseId!.isEmpty)) {
      throw StateError('YouTube ${video.itemType.name} 条目缺少有效 browseId');
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (context) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = _authService.isLoggedIn;
    const horizontalPageInset = 16.0;
    const horizontalItemInset = 4.0;
    final feedWidth =
        MediaQuery.sizeOf(context).width - horizontalPageInset * 2;
    final cardWidth = ((feedWidth - horizontalItemInset * 4) / 2)
        .clamp(136.0, 280.0)
        .toDouble();
    final rowHeight = cardWidth * 9 / 16 + 84;
    final sectionKeys = List<String>.generate(
      _sections.length,
      (index) => 'home-section-$_feedLayoutGeneration-$index',
    );
    final sectionIndexByKey = {
      for (var index = 0; index < sectionKeys.length; index++)
        sectionKeys[index]: index,
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.smart_display, color: colorScheme.primary, size: 28),
            const SizedBox(width: 8),
            Text(
              'Plexus',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            tooltip: '通知',
            onPressed: () {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('暂无新通知')));
            },
          ),
        ],
      ),
      body: !isLoggedIn
          ? SignInRequiredWidget(
              message: 'YouTube TV 官方接口要求登录账号后才能获取首页推荐内容',
              onLoginSuccess: _loadHomeFeed,
            )
          : _isLoading && _sections.isEmpty
          ? const FeedInitialLoading(message: '正在加载 YouTube 首页推荐视频...')
          : _errorMessage != null && _sections.isEmpty
          ? ErrorStateWidget(
              errorMessage: _errorMessage!,
              onRetry: _loadHomeFeed,
            )
          : FeedRefreshIndicator(
              onRefresh: _loadHomeFeed,
              child: ListView.builder(
                key: PageStorageKey<String>('home-feed-$_feedLayoutGeneration'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount:
                    _sections.length +
                    (_isLoading || _errorMessage != null ? 1 : 0),
                findChildIndexCallback: (key) {
                  if (key == const ValueKey<String>('home-feed-status')) {
                    return _isLoading || _errorMessage != null
                        ? _sections.length
                        : null;
                  }
                  if (key is ValueKey<String>) {
                    return sectionIndexByKey[key.value];
                  }
                  return null;
                },
                itemBuilder: (context, index) {
                  if (index == _sections.length) {
                    return KeyedSubtree(
                      key: const ValueKey<String>('home-feed-status'),
                      child: FeedContinuationStatus(
                        isLoading: _isLoading,
                        errorMessage: _errorMessage,
                        onRetry: _loadHomeFeed,
                      ),
                    );
                  }
                  final section = _sections[index];
                  final sectionKey = sectionKeys[index];
                  return VideoSectionRow(
                    key: ValueKey<String>(sectionKey),
                    sectionKey: sectionKey,
                    itemKeyPrefix: 'home-item',
                    section: section,
                    cardWidth: cardWidth,
                    rowHeight: rowHeight,
                    scrollController: _sectionScrollControllers.putIfAbsent(
                      index,
                      () => ScrollController(keepScrollOffset: false),
                    ),
                    isLoadingMore: _loadingSectionIndexes.contains(index),
                    errorMessage: _sectionErrors[index],
                    onLoadMore: () => _loadMoreSection(index),
                    onOpenSection: () => _openBrowseDestination(section),
                    onVideoTap: _openVideoOrBrowseDestination,
                  );
                },
              ),
            ),
    );
  }
}
