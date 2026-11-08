import 'package:flutter/material.dart';
import '../../models/video.dart';
import '../../services/mock_data_service.dart';
import '../../widgets/video_card.dart';

/// Video Detail and Player Screen
class VideoDetailPage extends StatefulWidget {
  final Video video;

  const VideoDetailPage({
    super.key,
    required this.video,
  });

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  bool _isPlaying = true;
  double _currentSliderValue = 0.35;
  bool _isDescriptionExpanded = false;
  late Video _currentVideo;

  @override
  void initState() {
    super.initState();
    _currentVideo = widget.video;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mockService = MockDataService();
    final relatedVideos = mockService.videos
        .where((v) => v.id != _currentVideo.id)
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Video Player Container
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: Colors.black,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background image / Video frame preview
                        Image.network(
                          _currentVideo.thumbnailUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                            child: Icon(Icons.play_circle_outline,
                                size: 64, color: Colors.white54),
                          ),
                        ),
                        Container(color: Colors.black45),

                        // Center Play / Pause Icon Button
                        IconButton(
                          iconSize: 64,
                          icon: Icon(
                            _isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPlaying = !_isPlaying;
                            });
                          },
                        ),

                        // Bottom Control Overlay
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black87],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '05:12 / ${_currentVideo.duration}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6),
                                      trackHeight: 3,
                                    ),
                                    child: Slider(
                                      value: _currentSliderValue,
                                      activeColor: colorScheme.primary,
                                      inactiveColor: Colors.white30,
                                      onChanged: (val) {
                                        setState(() {
                                          _currentSliderValue = val;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.settings,
                                      color: Colors.white, size: 20),
                                  tooltip: '画质设置',
                                  onPressed: () => _showQualityDialog(context),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.fullscreen,
                                      color: Colors.white, size: 22),
                                  tooltip: '全屏',
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('切至横屏4K全屏播放')),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Top Back Button
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Video Title
                  Text(
                    _currentVideo.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Metadata & Description Toggle
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isDescriptionExpanded = !_isDescriptionExpanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${_currentVideo.views} • ${_currentVideo.uploadTime}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                _isDescriptionExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 20,
                              ),
                            ],
                          ),
                          if (_isDescriptionExpanded) ...[
                            const Divider(height: 16),
                            Text(
                              _currentVideo.description,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Channel Bar
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage:
                            NetworkImage(_currentVideo.channelAvatar),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentVideo.channelName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '120万 订阅者',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('已订阅 ${_currentVideo.channelName}')),
                          );
                        },
                        child: const Text('订阅'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Action Buttons Row (Like, Favorite, Share, Download)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() {
                              _currentVideo.isLiked = !_currentVideo.isLiked;
                            });
                          },
                          icon: Icon(_currentVideo.isLiked
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined),
                          label: Text('${_currentVideo.likesCount}'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _currentVideo.isFavorited =
                                  !_currentVideo.isFavorited;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_currentVideo.isFavorited
                                    ? '已添加到收藏夹'
                                    : '取消收藏'),
                              ),
                            );
                          },
                          icon: Icon(_currentVideo.isFavorited
                              ? Icons.bookmark
                              : Icons.bookmark_border),
                          label: const Text('收藏'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已分享播放链接')),
                            );
                          },
                          icon: const Icon(Icons.share),
                          label: const Text('分享'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('正在下载高画质缓存...')),
                            );
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('离线缓存'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),

                  // Related Videos Header
                  Text(
                    '相关推荐视频',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Related Video List
                  ...relatedVideos.map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: VideoCard(
                        video: v,
                        onTap: () {
                          setState(() {
                            _currentVideo = v;
                            _currentSliderValue = 0.0;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQualityDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('画质与解包选择'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('4K 2160p (HDR) - AV1 硬件解码'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('1080P 60FPS - 高码率全高清'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('720P - 高清省流量'),
              ),
            ),
          ],
        );
      },
    );
  }
}
