import 'package:flutter/material.dart';

import '../../models/category.dart';
import '../search/search_page.dart';
import 'gaming_page.dart';
import 'live_page.dart';
import 'music_page.dart';

/// 分类界面 (Categories Page)
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  static const List<Category> _categories = [
    Category(
      id: 'all',
      name: '全部',
      icon: Icons.all_inclusive,
      videoCount: 0,
      description: '热门综合视频',
    ),
    Category(
      id: 'music',
      name: '音乐',
      icon: Icons.music_note,
      videoCount: 0,
      description: '流行高清MV与无损音质体验',
    ),
    Category(
      id: 'gaming',
      name: '游戏',
      icon: Icons.sports_esports,
      videoCount: 0,
      description: '热门3A大作与电竞赛事直播',
    ),
    Category(
      id: 'live',
      name: '直播',
      icon: Icons.live_tv,
      videoCount: 0,
      description: '高清无缓冲4K视听直播',
    ),
  ];
  String _selectedCategoryId = 'all';

  void _selectCategory(String categoryId) {
    setState(() => _selectedCategoryId = categoryId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final categories = _categories;
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
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = categories[index];
                return _CategoryChip(
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
      return const MusicPage(key: ValueKey('category-music-feed'));
    }
    if (category.id == 'gaming') {
      return const GamingPage(key: ValueKey('category-gaming-feed'));
    }
    if (category.id == 'live') {
      return const LivePage(key: ValueKey('category-live-feed'));
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

  Color _categoryAccent(String categoryId, ColorScheme colorScheme) {
    return switch (categoryId) {
      'music' => colorScheme.tertiary,
      'gaming' => colorScheme.primary,
      'live' => colorScheme.error,
      _ => colorScheme.primary,
    };
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.onSelected,
  });

  final Category category;
  final bool isSelected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      label: Text(category.name),
      avatar: Icon(
        category.icon,
        size: 18,
        color: isSelected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
      ),
      onSelected: onSelected,
    );
  }
}
