import 'package:flutter/material.dart';

import 'category_topic_feed_page.dart';

class GamingPage extends StatelessWidget {
  const GamingPage({super.key});

  @override
  Widget build(BuildContext context) => const CategoryTopicFeedPage(
    categoryId: 'gaming',
    title: '游戏',
    icon: Icons.sports_esports,
  );
}
