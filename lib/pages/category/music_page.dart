import 'package:flutter/material.dart';

import 'category_topic_feed_page.dart';

class MusicPage extends StatelessWidget {
  const MusicPage({super.key});

  @override
  Widget build(BuildContext context) => const CategoryTopicFeedPage(
    categoryId: 'music',
    title: '音乐',
    icon: Icons.music_note,
  );
}
