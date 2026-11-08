import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../models/video_section.dart';
import '../../services/youtube_data_service.dart';
import '../player/video_detail_page.dart';

class BrowseDestinationPage extends StatefulWidget {
  final VideoSection destination;

  const BrowseDestinationPage({super.key, required this.destination});

  @override
  State<BrowseDestinationPage> createState() => _BrowseDestinationPageState();
}

class _BrowseDestinationPageState extends State<BrowseDestinationPage> {
  final YouTubeDataService _dataService = YouTubeDataService();
  VideoSection? _section;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _continuationError;

  @override
  void initState() {
    super.initState();
    _loadDestination();
  }

  Future<void> _loadDestination() async {
    setState(() {
      _section = null;
      _isLoading = true;
      _errorMessage = null;
      _continuationError = null;
    });

    try {
      final section = await _dataService.fetchBrowseDestination(
        widget.destination,
      );
      if (!mounted) return;
      setState(() {
        _section = section;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final section = _section;
    if (section == null ||
        section.continuationToken == null ||
        _isLoadingMore) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
      _continuationError = null;
    });

    try {
      final updatedSection = await _dataService
          .fetchMoreBrowseDestinationVideos(section);
      if (!mounted) return;
      setState(() {
        _section = updatedSection;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _continuationError = error.toString();
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = _section;
    final title = widget.destination.title ?? widget.destination.browseTitle!;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _isLoading && section == null
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && section == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(_errorMessage!),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loadDestination,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadDestination,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.axis == Axis.vertical &&
                      notification.metrics.extentAfter < 320 &&
                      section?.continuationToken != null &&
                      _continuationError == null) {
                    _loadMore();
                  }
                  return false;
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount:
                      (section?.videos.length ?? 0) +
                      (section?.continuationToken != null ||
                              _isLoadingMore ||
                              _continuationError != null
                          ? 1
                          : 0),
                  itemBuilder: (context, index) {
                    final videos = section!.videos;
                    if (index == videos.length) {
                      return _BrowsePageFooter(
                        isLoading: _isLoadingMore,
                        errorMessage: _continuationError,
                        onRetry: _loadMore,
                      );
                    }
                    return _BrowseVideoTile(
                      video: videos[index],
                      onTap: () => _openVideo(videos[index]),
                    );
                  },
                ),
              ),
            ),
    );
  }

  void _openVideo(Video video) {
    switch (video.itemType) {
      case VideoItemType.video:
      case VideoItemType.shorts:
        if (video.id == null || video.id!.isEmpty || video.browseId != null) {
          throw StateError(
            'YouTube ${video.itemType.name} 条目 endpoint 与内容类型不匹配',
          );
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoDetailPage(video: video),
          ),
        );
        return;
      case VideoItemType.track:
      case VideoItemType.channel:
      case VideoItemType.browseDestination:
        if (video.id != null ||
            video.browseId == null ||
            video.browseId!.isEmpty) {
          throw StateError(
            'YouTube ${video.itemType.name} 条目 endpoint 与内容类型不匹配',
          );
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BrowseDestinationPage(
              destination: VideoSection(
                title: video.title,
                videos: const [],
                browseId: video.browseId,
                browseParams: video.browseParams,
                browseTitle: video.title,
              ),
            ),
          ),
        );
        return;
      case VideoItemType.playlist:
        if (video.id != null) {
          if (video.id!.isEmpty ||
              video.playlistId == null ||
              video.playlistId!.isEmpty ||
              video.browseId != null) {
            throw StateError('YouTube playlist 条目 endpoint 与内容类型不匹配');
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoDetailPage(video: video),
            ),
          );
          return;
        }
        if (video.browseId == null || video.browseId!.isEmpty) {
          throw StateError('YouTube playlist 条目缺少 browseId 或 videoId');
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BrowseDestinationPage(
              destination: VideoSection(
                title: video.title,
                videos: const [],
                browseId: video.browseId,
                browseParams: video.browseParams,
                browseTitle: video.title,
              ),
            ),
          ),
        );
        return;
    }
  }
}

class _BrowseVideoTile extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;

  const _BrowseVideoTile({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final details = [
      video.channelName,
      video.views,
      video.uploadTime,
    ].where((value) => value.isNotEmpty).join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (video.thumbnailUrl.isNotEmpty)
                SizedBox(
                  width: 120,
                  height: 68,
                  child: Image.network(
                    video.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: colorScheme.errorContainer,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(4),
                        child: SelectableText(
                          '缩略图加载失败：$error',
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (video.thumbnailUrl.isEmpty)
                const SizedBox(
                  width: 120,
                  height: 68,
                  child: Icon(Icons.open_in_new),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (video.browseId != null)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.chevron_right),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowsePageFooter extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  const _BrowsePageFooter({
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SelectableText(errorMessage!),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.arrow_downward),
          label: const Text('加载更多'),
        ),
      ),
    );
  }
}
