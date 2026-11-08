import 'package:flutter/material.dart';
import '../models/video.dart';
import '../models/category.dart';
import '../models/channel.dart';

/// Data Service (已移除所有静态模拟视频数据，仅保留分类结构)
class MockDataService {
  static final MockDataService _instance = MockDataService._internal();
  factory MockDataService() => _instance;
  MockDataService._internal();

  /// Categories List
  final List<Category> categories = const [
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
      id: 'tech',
      name: '科技',
      icon: Icons.computer,
      videoCount: 0,
      description: '最新数码评测与极客极简教程',
    ),
    Category(
      id: 'movie',
      name: '影视',
      icon: Icons.movie,
      videoCount: 0,
      description: '经典电影解说与预告片',
    ),
    Category(
      id: 'anime',
      name: '动漫',
      icon: Icons.animation,
      videoCount: 0,
      description: '番剧剪辑与二次元优质内容',
    ),
    Category(
      id: 'news',
      name: '新闻',
      icon: Icons.newspaper,
      videoCount: 0,
      description: '全球即时资讯与深度报道',
    ),
    Category(
      id: 'live',
      name: '直播',
      icon: Icons.live_tv,
      videoCount: 0,
      description: '高清无缓冲4K视听直播',
    ),
  ];

  /// Subscribed Channels List
  final List<Channel> channels = [];

  /// Videos List
  final List<Video> videos = [];

  /// Get videos filtered by category id
  List<Video> getVideosByCategory(String categoryId) {
    if (categoryId == 'all') {
      return videos;
    }
    return videos.where((v) => v.categoryId == categoryId).toList();
  }

  /// Get subscription timeline feed
  List<Video> getSubscriptionFeed() {
    return [];
  }
}
