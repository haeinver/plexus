import 'package:flutter/material.dart';

import 'category_topic_feed_page.dart';

class LivePage extends StatelessWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context) => const CategoryTopicFeedPage(
    categoryId: 'live',
    title: '直播',
    icon: Icons.live_tv,
  );
}
