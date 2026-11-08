import 'package:flutter/material.dart';
import '../../models/video.dart';
import '../../services/mock_data_service.dart';
import '../../widgets/video_card.dart';
import '../player/video_detail_page.dart';

/// Standalone Search Screen (独立搜索界面)
class SearchPage extends StatefulWidget {
  final String? initialQuery;

  const SearchPage({
    super.key,
    this.initialQuery,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final MockDataService _dataService = MockDataService();
  late TextEditingController _searchController;
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  // Mock search history & trending tags
  final List<String> _searchHistory = ['4K HDR', '极客湾', '影视飓风', 'Lofi Girl'];
  final List<String> _trendingKeywords = [
    '4K 60FPS 芯片横评',
    '影视飓风 长镜头',
    '虚幻5.5 实机演示',
    '2026年10月新番',
    'SmartTube 20.0',
    'Lofi Beats 直播',
  ];

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery ?? '';
    _searchController = TextEditingController(text: _query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<Video> get _searchResults {
    if (_query.trim().isEmpty) return [];
    final keyword = _query.toLowerCase();
    return _dataService.videos.where((v) {
      return v.title.toLowerCase().contains(keyword) ||
          v.channelName.toLowerCase().contains(keyword) ||
          v.categoryName.toLowerCase().contains(keyword) ||
          v.description.toLowerCase().contains(keyword);
    }).toList();
  }

  void _onSearchSubmitted(String val) {
    setState(() {
      _query = val;
      if (val.trim().isNotEmpty && !_searchHistory.contains(val.trim())) {
        _searchHistory.insert(0, val.trim());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final results = _searchResults;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索 Plexus 视频、频道或内容...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
          onChanged: (val) {
            setState(() {
              _query = val;
            });
          },
          onSubmitted: _onSearchSubmitted,
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _query = '';
                  _searchController.clear();
                });
              },
            ),
        ],
      ),
      body: _query.trim().isEmpty
          ? _buildDefaultSearchContent(colorScheme, theme)
          : _buildSearchResults(results, colorScheme, theme),
    );
  }

  /// Initial content before typing search query (History + Trending)
  Widget _buildDefaultSearchContent(
      ColorScheme colorScheme, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Search History Section
        if (_searchHistory.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '搜索历史',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: '清空历史',
                onPressed: () {
                  setState(() {
                    _searchHistory.clear();
                  });
                },
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _searchHistory.map((item) {
              return ActionChip(
                avatar: const Icon(Icons.history, size: 16),
                label: Text(item),
                onPressed: () {
                  setState(() {
                    _query = item;
                    _searchController.text = item;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Trending / Hot Search Section
        Text(
          '热门搜索',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ..._trendingKeywords.asMap().entries.map((entry) {
          final index = entry.key;
          final keyword = entry.value;

          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: index < 3
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: index < 3
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            title: Text(
              keyword,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.north_west, size: 16),
            onTap: () {
              setState(() {
                _query = keyword;
                _searchController.text = keyword;
              });
            },
          );
        }),
      ],
    );
  }

  /// Search Results List
  Widget _buildSearchResults(
      List<Video> results, ColorScheme colorScheme, ThemeData theme) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off,
                size: 64, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '未找到相关视频内容',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '尝试搜索其他关键词或频道名称',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final video = results[index];
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
}
