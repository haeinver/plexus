import 'package:flutter/material.dart';
import '../models/category.dart';

/// MD3 FilterChip for Category Selection (不显示选中勾选 Icon)
class CategoryChip extends StatelessWidget {
  final Category category;
  final bool isSelected;
  final ValueChanged<bool> onSelected;

  const CategoryChip({
    super.key,
    required this.category,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: isSelected,
      showCheckmark: false, // 选中时不显示勾选对勾图标
      label: Text(category.name),
      avatar: Icon(
        category.icon,
        size: 18,
        color: isSelected
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onSelected: onSelected,
    );
  }
}
