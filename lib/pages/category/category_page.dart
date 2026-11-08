import 'package:flutter/material.dart';
import '../../models/category.dart';
import '../../services/mock_data_service.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/video_card.dart';
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
  String _selectedCategoryId = 'all';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
                MaterialPageRoute(
                  builder: (context) => const SearchPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Horizontal Category Filter Chips Bar
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = categories[index];
                return CategoryChip(
                  category: cat,
                  isSelected: _selectedCategoryId == cat.id,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategoryId = cat.id;
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Content Area
          Expanded(
            child: _buildCategoryVideoFeed(selectedCategory, colorScheme, theme),
          ),
        ],
      ),
    );
  }

  /// Videos under selected category
  Widget _buildCategoryVideoFeed(
      Category category, ColorScheme colorScheme, ThemeData theme) {
    final videos = _dataService.getVideosByCategory(category.id);

    return videos.isEmpty
        ? Center(
            child: Text(
              '该分类下暂无视频',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : ListView.builder(
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
}
