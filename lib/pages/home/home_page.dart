import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../models/video_section.dart';
import '../../services/locale_service.dart';
import '../../services/youtube_auth_service.dart';
import '../../services/youtube_data_service.dart';
import '../../widgets/error_state_widget.dart';
import '../../widgets/sign_in_required_widget.dart';
import '../../widgets/video_card.dart';
import 'browse_destination_page.dart';
import '../player/video_detail_page.dart';
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

  void _openBrowseDestination(VideoSection destination) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BrowseDestinationPage(destination: destination),
      ),
    );
  }

  void _openVideoOrBrowseDestination(Video video) {
    if (video.id == null) {
      final browseId = video.browseId;
      if (browseId == null || browseId.isEmpty) {
        throw StateError('YouTube 浏览入口缺少 browseId');
      }
      _openBrowseDestination(
        VideoSection(
          title: video.title,
          videos: const [],
          browseId: browseId,
          browseParams: video.browseParams,
          browseTitle: video.title,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => VideoDetailPage(video: video)),
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
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text('正在加载 YouTube 首页推荐视频...'),
                ],
              ),
            )
          : _errorMessage != null && _sections.isEmpty
          ? ErrorStateWidget(
              errorMessage: _errorMessage!,
              onRetry: _loadHomeFeed,
            )
          : RefreshIndicator(
              onRefresh: () => _loadHomeFeed(rebuildFeed: true),
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
                      child: _HomeFeedStatus(
                        isLoading: _isLoading,
                        errorMessage: _errorMessage,
                        onRetry: _loadHomeFeed,
                      ),
                    );
                  }
                  final section = _sections[index];
                  final sectionKey = sectionKeys[index];
                  return _HomeFeedSection(
                    key: ValueKey<String>(sectionKey),
                    sectionKey: sectionKey,
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

class _HomeFeedSection extends StatelessWidget {
  final String sectionKey;
  final VideoSection section;
  final double cardWidth;
  final double rowHeight;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final String? errorMessage;
  final VoidCallback onLoadMore;
  final VoidCallback onOpenSection;
  final ValueChanged<Video> onVideoTap;

  const _HomeFeedSection({
    super.key,
    required this.sectionKey,
    required this.section,
    required this.cardWidth,
    required this.rowHeight,
    required this.scrollController,
    required this.isLoadingMore,
    required this.errorMessage,
    required this.onLoadMore,
    required this.onOpenSection,
    required this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title != null && section.title!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
            child: Text(
              section.title!,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        SizedBox(
          height: rowHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.horizontal &&
                  section.browseId == null &&
                  (notification is ScrollUpdateNotification ||
                      notification is OverscrollNotification) &&
                  notification.metrics.extentAfter < 560) {
                onLoadMore();
              }
              return false;
            },
            child: ListView.builder(
              controller: scrollController,
              key: PageStorageKey<String>(sectionKey),
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount:
                  section.videos.length +
                  (section.browseId != null ||
                          section.continuationToken != null ||
                          isLoadingMore ||
                          errorMessage != null
                      ? 1
                      : 0),
              itemBuilder: (context, videoIndex) {
                if (videoIndex == section.videos.length) {
                  if (section.browseId != null) {
                    return _SectionBrowseCard(
                      cardWidth: cardWidth,
                      title: section.browseTitle!,
                      onTap: onOpenSection,
                    );
                  }
                  return _SectionLoadMoreCard(
                    cardWidth: cardWidth,
                    isLoading: isLoadingMore,
                    errorMessage: errorMessage,
                    onRetry: onLoadMore,
                  );
                }

                final video = section.videos[videoIndex];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: cardWidth,
                    child: video.thumbnailUrl.isEmpty
                        ? _SectionBrowseCard(
                            cardWidth: cardWidth,
                            title: video.title,
                            onTap: () => onVideoTap(video),
                          )
                        : VideoCard(
                            key: ValueKey<String>(
                              'home-item-${video.id ?? video.browseId}-$videoIndex',
                            ),
                            video: video,
                            onTap: () => onVideoTap(video),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _SectionLoadMoreCard extends StatelessWidget {
  final double cardWidth;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  const _SectionLoadMoreCard({
    required this.cardWidth,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: cardWidth,
      child: Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: isLoading
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('正在加载本栏更多视频...'),
                    ],
                  )
                : errorMessage != null
                ? SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          errorMessage!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('更多...'),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SectionBrowseCard extends StatelessWidget {
  final double cardWidth;
  final String title;
  final VoidCallback onTap;

  const _SectionBrowseCard({
    required this.cardWidth,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardWidth,
      child: Card(
        child: Center(
          child: TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.open_in_new),
            label: Text(title),
          ),
        ),
      ),
    );
  }
}

class _HomeFeedStatus extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  const _HomeFeedStatus({
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (isLoading) {
      return const SizedBox(
        height: 112,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('正在加载更多首页分区...'),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '首页后续内容加载失败',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(errorMessage ?? ''),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }
}
