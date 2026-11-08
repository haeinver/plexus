import 'package:flutter/material.dart';

/// Model representing a Video Category
class Category {
  final String id;
  final String name;
  final IconData icon;
  final int videoCount;
  final String description;

  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.videoCount,
    required this.description,
  });
}
