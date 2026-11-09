import 'package:flutter/material.dart';

import '../../models/category.dart';
import '../../models/video.dart';
import '../../models/video_section.dart';
import '../../services/mock_data_service.dart';
import '../../services/youtube_auth_service.dart';
import '../../services/youtube_data_service.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/feed_continuation_status.dart';
import '../../widgets/sign_in_required_widget.dart';
import '../../widgets/video_card.dart';
import '../../widgets/video_section_row.dart';
import '../home/browse_destination_page.dart';
import '../player/video_detail_page.dart';
import '../search/search_page.dart';

/// 分类界面 (Categories Page)
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final MockDataService _dataService = MockDataService();
  final YouTubeAuthService _authService = YouTubeAuthService();
  final YouTubeDataService _youtubeDataService = YouTubeDataService();
  String _selectedCategoryId = 'all';
  List<VideoSection> _musicSections = [];
  final Set<int> _loadingMusicShelfIndexes = {};
  final Map<int, String> _musicShelfErrors = {};
  final Map<int, Set<String>> _seenMusicShelfTokens = {};
  String? _musicError;
  bool _isLoadingMusic = false;
  bool _musicRequiresSignIn = false;
  int _musicLoadGeneration = 0;
  int _musicFeedLayoutGeneration = 0;

  @override
  void initState() {
    super.initState();
    _authService.addAccountListener(_onAccountChanged);
  }

  @override
  void dispose() {
    _authService.removeAccountListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {});
    if (_authService.isLoggedIn && _selectedCategoryId == 'music') {
      _loadMusicFeed();
    }
  }

  void _selectCategory(String categoryId) {
    setState(() => _selectedCategoryId = categoryId);
    if (categoryId == 'music' && _musicSections.isEmpty && !_isLoadingMusic) {
      _loadMusicFeed();
    }
  }

  Future<void> _loadMusicFeed({bool rebuildFeed = false}) async {
    if (!mounted || (_isLoadingMusic && !rebuildFeed)) return;
    final generation = ++_musicLoadGeneration;
    setState(() {
      _isLoadingMusic = true;
      _musicError = null;
      _musicRequiresSignIn = false;
      if (rebuildFeed) {
        _musicSections = [];
        _musicFeedLayoutGeneration++;
      }
      _seenMusicShelfTokens.clear();
      _musicShelfErrors.clear();
      _loadingMusicShelfIndexes.clear();
    });

    try {
      await _authService.init();
      if (!mounted || generation != _musicLoadGeneration) return;
      if (!_authService.isLoggedIn) {
        setState(() {
          _musicSections = [];
          _musicRequiresSignIn = true;
          _isLoadingMusic = false;
        });
        return;
      }

      var refreshedSections = <VideoSection>[];
      await for (final page
          in _youtubeDataService.fetchMusicFeedProgressively()) {
        if (!mounted || generation != _musicLoadGeneration) return;
        if (rebuildFeed) {
          refreshedSections = List<VideoSection>.of(page.sections);
        } else {
          setState(() => _musicSections = List<VideoSection>.of(page.sections));
        }
      }
      if (!mounted || generation != _musicLoadGeneration) return;
      setState(() {
        if (rebuildFeed) _musicSections = refreshedSections;
        _isLoadingMusic = false;
      });
    } catch (error) {
      if (!mounted || generation != _musicLoadGeneration) return;
      setState(() {
        _musicError = error.toString();
        _isLoadingMusic = false;
      });
    }
  }

  Future<void> _loadMoreMusicShelf(int sectionIndex) async {
    if (!mounted ||
        sectionIndex >= _musicSections.length ||
        _loadingMusicShelfIndexes.contains(sectionIndex)) {
      return;
    }
    final section = _musicSections[sectionIndex];
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return;

    final seenTokens = _seenMusicShelfTokens.putIfAbsent(
      sectionIndex,
      () => {token},
    );
    setState(() {
      _loadingMusicShelfIndexes.add(sectionIndex);
      _musicShelfErrors.remove(sectionIndex);
    });

    try {
      final updatedSection = await _youtubeDataService
          .fetchMoreHomeSectionVideos(section);
      if (!mounted) return;
      final nextToken = updatedSection.continuationToken;
      if (nextToken == token ||
          (nextToken != null && !seenTokens.add(nextToken))) {
        throw const FormatException('YouTube 音乐横栏 continuation token 重复');
      }
      setState(() {
        if (sectionIndex < _musicSections.length &&
            _musicSections[sectionIndex].continuationToken == token) {
          _musicSections[sectionIndex] = updatedSection;
        }
        _loadingMusicShelfIndexes.remove(sectionIndex);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMusicShelfIndexes.remove(sectionIndex);
        _musicShelfErrors[sectionIndex] = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = _authService.isLoggedIn;
    final categories = _dataService.categories;
    final selectedCategory = categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => categories.first,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedCategoryId == 'all' ? '频道与分类' : selectedCategory.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
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
        ],
      ),
      body: !isLoggedIn
          ? SignInRequiredWidget(
              message: 'YouTube TV 官方接口要求登录账号后才能获取分类内容',
              onLoginSuccess: _onAccountChanged,
            )
          : Column(
              children: [
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: categories.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return CategoryChip(
                        category: category,
                        isSelected: _selectedCategoryId == category.id,
                        onSelected: (_) => _selectCategory(category.id),
                      );
                    },
                  ),
                ),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _buildCategoryContent(
                      selectedCategory,
                      categories,
                      theme,
                      colorScheme,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryContent(
    Category category,
    List<Category> categories,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (category.id == 'music') {
      return _buildMusicFeed(category, theme, colorScheme);
    }

    final videos = _dataService.getVideosByCategory(category.id);

    if (videos.isNotEmpty) {
      return ListView.builder(
        key: ValueKey('category-videos-${category.id}'),
        padding: const EdgeInsets.all(12),
        itemCount: videos.length,
        itemBuilder: (context, index) {
          final video = videos[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: VideoCard(
              video: video,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoDetailPage(video: video),
                  ),
                );
              },
            ),
          );
        },
      );
    }

    if (category.id != 'all') {
      return _buildEmptyState(category, theme, colorScheme);
    }

    final visibleCategories = categories
        .where((item) => item.id != 'all')
        .toList();
    return CustomScrollView(
      key: const ValueKey('category-directory'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '探索主题',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '选择一个分类开始浏览',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${visibleCategories.length} 个分类',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 132,
            ),
            itemCount: visibleCategories.length,
            itemBuilder: (context, index) {
              final item = visibleCategories[index];
              return _buildCategoryTile(item, theme, colorScheme);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryTile(
    Category category,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final accent = _categoryAccent(category.id, colorScheme);

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey('category-tile-${category.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => _selectCategory(category.id),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(category.icon, color: accent, size: 23),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    Category category,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final accent = _categoryAccent(category.id, colorScheme);

    return Center(
      key: ValueKey('category-empty-${category.id}'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(category.icon, size: 34, color: accent),
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

  Widget _buildMusicFeed(
    Category category,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (_musicRequiresSignIn) {
      return SignInRequiredWidget(onLoginSuccess: _loadMusicFeed);
    }
    if (_isLoadingMusic && _musicSections.isEmpty) {
      return const FeedInitialLoading(message: '正在加载 YouTube 音乐内容...');
    }
    if (_musicError != null && _musicSections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(_musicError!),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadMusicFeed,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_musicSections.isEmpty) {
      return _buildEmptyState(category, theme, colorScheme);
    }

    const horizontalPageInset = 16.0;
    const horizontalItemInset = 4.0;
    final feedWidth =
        MediaQuery.sizeOf(context).width - horizontalPageInset * 2;
    final cardWidth = ((feedWidth - horizontalItemInset * 4) / 2)
        .clamp(136.0, 280.0)
        .toDouble();
    final rowHeight = cardWidth * 9 / 16 + 84;
    final hasFooter = _isLoadingMusic || _musicError != null;
    return FeedRefreshIndicator(
      onRefresh: _loadMusicFeed,
      child: ListView.builder(
        key: PageStorageKey<String>('music-feed-$_musicFeedLayoutGeneration'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: _musicSections.length + (hasFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _musicSections.length) {
            return FeedContinuationStatus(
              isLoading: _isLoadingMusic,
              errorMessage: _musicError,
              loadingMessage: '正在加载更多音乐分区...',
              errorTitle: '音乐后续分区加载失败',
              retryLabel: '重新加载音乐',
              onRetry: _loadMusicFeed,
            );
          }

          final section = _musicSections[index];
          return VideoSectionRow(
            key: ValueKey<String>(
              'music-section-$_musicFeedLayoutGeneration-$index',
            ),
            sectionKey: 'music-section-$_musicFeedLayoutGeneration-$index',
            itemKeyPrefix: 'music-item',
            section: section,
            cardWidth: cardWidth,
            rowHeight: rowHeight,
            isLoadingMore: _loadingMusicShelfIndexes.contains(index),
            errorMessage: _musicShelfErrors[index],
            loadingMessage: '正在加载本栏更多音乐...',
            onLoadMore: () => _loadMoreMusicShelf(index),
            onOpenSection: () => _openMusicShelfDestination(section),
            onVideoTap: _openMusicVideo,
          );
        },
      ),
    );
  }

  void _openMusicVideo(Video video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => VideoDetailPage(video: video)),
    );
  }

  void _openMusicShelfDestination(VideoSection section) {
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

  Color _categoryAccent(String categoryId, ColorScheme colorScheme) {
    return switch (categoryId) {
      'music' => colorScheme.tertiary,
      'gaming' => colorScheme.primary,
      'tech' => colorScheme.secondary,
      'movie' => colorScheme.error,
      'anime' => colorScheme.tertiary,
      'news' => colorScheme.secondary,
      'live' => colorScheme.error,
      _ => colorScheme.primary,
    };
  }
}
