import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../models/video_section.dart';
import '../../services/youtube_auth_service.dart';
import '../../services/youtube_data_service.dart';
import '../../widgets/error_state_widget.dart';
import '../../widgets/feed_continuation_status.dart';
import '../../widgets/video_section_row.dart';
import '../home/browse_destination_page.dart';
import '../home/item_destination_pages.dart';
import '../search/search_page.dart';

class CategoryTopicFeedPage extends StatefulWidget {
  const CategoryTopicFeedPage({
    required this.categoryId,
    required this.title,
    required this.icon,
    super.key,
  });

  final String categoryId;
  final String title;
  final IconData icon;

  @override
  State<CategoryTopicFeedPage> createState() => _CategoryTopicFeedPageState();
}

class _CategoryTopicFeedPageState extends State<CategoryTopicFeedPage> {
  final YouTubeAuthService _authService = YouTubeAuthService();
  final YouTubeDataService _youtubeDataService = YouTubeDataService();
  List<VideoSection> _sections = [];
  final Set<int> _loadingShelfIndexes = {};
  final Map<int, String> _shelfErrors = {};
  final Map<int, Set<String>> _seenShelfTokens = {};
  String? _error;
  bool _isLoading = false;
  int _loadGeneration = 0;
  int _feedLayoutGeneration = 0;

  @override
  void initState() {
    super.initState();
    _authService.addAccountListener(_onAccountChanged);
    _loadFeed();
  }

  @override
  void dispose() {
    _authService.removeAccountListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) _loadFeed(rebuildFeed: true);
  }

  Future<void> _loadFeed({bool rebuildFeed = false}) async {
    if (!mounted || (_isLoading && !rebuildFeed)) return;
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
      if (rebuildFeed) {
        _sections = [];
        _feedLayoutGeneration++;
      }
      _seenShelfTokens.clear();
      _shelfErrors.clear();
      _loadingShelfIndexes.clear();
    });

    try {
      var refreshedSections = <VideoSection>[];
      await for (final page
          in _youtubeDataService.fetchCategoryFeedProgressively(
            widget.categoryId,
          )) {
        if (!mounted || generation != _loadGeneration) return;
        if (rebuildFeed) {
          refreshedSections = List<VideoSection>.of(page.sections);
        } else {
          setState(() => _sections = List<VideoSection>.of(page.sections));
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (rebuildFeed) _sections = refreshedSections;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreShelf(int sectionIndex) async {
    if (!mounted ||
        sectionIndex >= _sections.length ||
        _loadingShelfIndexes.contains(sectionIndex)) {
      return;
    }
    final section = _sections[sectionIndex];
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return;

    final seenTokens = _seenShelfTokens.putIfAbsent(
      sectionIndex,
      () => {token},
    );
    setState(() {
      _loadingShelfIndexes.add(sectionIndex);
      _shelfErrors.remove(sectionIndex);
    });

    try {
      final updatedSection = await _youtubeDataService
          .fetchMoreCategorySectionVideos(widget.categoryId, section);
      if (!mounted) return;
      final nextToken = updatedSection.continuationToken;
      if (nextToken == token ||
          (nextToken != null && !seenTokens.add(nextToken))) {
        throw FormatException(
          'YouTube ${widget.title}横栏 continuation token 重复',
        );
      }
      setState(() {
        if (sectionIndex < _sections.length &&
            _sections[sectionIndex].continuationToken == token) {
          _sections[sectionIndex] = updatedSection;
        }
        _loadingShelfIndexes.remove(sectionIndex);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingShelfIndexes.remove(sectionIndex);
        _shelfErrors[sectionIndex] = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _buildFeed(theme);
  }

  Widget _buildFeed(ThemeData theme) {
    if (_isLoading && _sections.isEmpty) {
      return FeedInitialLoading(message: '正在加载 YouTube ${widget.title}内容...');
    }
    if (_error != null && _sections.isEmpty) {
      return ErrorStateWidget(
        errorMessage: _error!,
        retryText: '重新加载${widget.title}',
        onRetry: _loadFeed,
      );
    }
    if (_sections.isEmpty) return _buildEmptyState(theme);

    const horizontalPageInset = 16.0;
    const horizontalItemInset = 4.0;
    final feedWidth =
        MediaQuery.sizeOf(context).width - horizontalPageInset * 2;
    final cardWidth = ((feedWidth - horizontalItemInset * 4) / 2)
        .clamp(136.0, 280.0)
        .toDouble();
    final rowHeight = cardWidth * 9 / 16 + 84;
    final hasFooter = _isLoading || _error != null;

    return FeedRefreshIndicator(
      onRefresh: ({required bool rebuildFeed}) =>
          _loadFeed(rebuildFeed: rebuildFeed),
      child: ListView.builder(
        key: PageStorageKey<String>(
          '${widget.categoryId}-feed-$_feedLayoutGeneration',
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: _sections.length + (hasFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _sections.length) {
            return FeedContinuationStatus(
              isLoading: _isLoading,
              errorMessage: _error,
              loadingMessage: '正在加载更多${widget.title}分区...',
              errorTitle: '${widget.title}后续分区加载失败',
              retryLabel: '重新加载${widget.title}',
              onRetry: _loadFeed,
            );
          }

          final section = _sections[index];
          return VideoSectionRow(
            key: ValueKey<String>(
              '${widget.categoryId}-section-$_feedLayoutGeneration-$index',
            ),
            sectionKey:
                '${widget.categoryId}-section-$_feedLayoutGeneration-$index',
            itemKeyPrefix: '${widget.categoryId}-item',
            section: section,
            cardWidth: cardWidth,
            rowHeight: rowHeight,
            isLoadingMore: _loadingShelfIndexes.contains(index),
            errorMessage: _shelfErrors[index],
            loadingMessage: '正在加载本栏更多${widget.title}...',
            onLoadMore: () => _loadMoreShelf(index),
            onOpenSection: () => _openShelfDestination(section),
            onVideoTap: _openVideo,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Center(
      key: ValueKey('category-empty-${widget.categoryId}'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(widget.icon, size: 34, color: colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              '该分类下暂无视频',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '试试搜索其他内容',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SearchPage()),
                );
              },
              icon: const Icon(Icons.search),
              label: const Text('搜索内容'),
            ),
          ],
        ),
      ),
    );
  }

  void _openVideo(Video video) {
    openVideoItemDestination(context, video);
  }

  void _openShelfDestination(VideoSection section) {
    final browseId = section.browseId;
    if (browseId == null || browseId.isEmpty) return;
    final title = section.browseTitle ?? section.title;
    if (title == null || title.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BrowseDestinationPage(
          destination: VideoSection(
            title: title,
            browseTitle: title,
            videos: const [],
            browseId: browseId,
            browseParams: section.browseParams,
          ),
        ),
      ),
    );
  }
}
