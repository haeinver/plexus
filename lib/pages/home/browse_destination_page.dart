import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../models/video_section.dart';
import '../../services/youtube_data_service.dart';
import 'item_destination_pages.dart';

class BrowseDestinationPage extends StatefulWidget {
  final VideoSection destination;
  final VideoItemType? destinationType;

  const BrowseDestinationPage({
    super.key,
    required this.destination,
    this.destinationType,
  });

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
    final videos = section?.videos ?? const <Video>[];
    final hasFooter =
        section?.continuationToken != null ||
        _isLoadingMore ||
        _continuationError != null;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          if (widget.destinationType != null)
            _BrowseDestinationTypeHeader(itemType: widget.destinationType!),
          Expanded(
            child: _isLoading && section == null
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
                        itemCount: videos.length + (hasFooter ? 1 : 0),
                        itemBuilder: (context, index) {
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
          ),
        ],
      ),
    );
  }

  void _openVideo(Video video) {
    openVideoItemDestination(context, video);
  }
}

class _BrowseDestinationTypeHeader extends StatelessWidget {
  final VideoItemType itemType;

  const _BrowseDestinationTypeHeader({required this.itemType});

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (itemType) {
      VideoItemType.playlist => ('播放列表', Icons.queue_music),
      VideoItemType.track => ('音乐', Icons.music_note),
      VideoItemType.channel => ('频道', Icons.account_circle_outlined),
      VideoItemType.browseDestination => ('浏览内容', Icons.explore_outlined),
      VideoItemType.video => ('视频', Icons.play_circle_outline),
      VideoItemType.shorts => ('Shorts', Icons.smart_display_outlined),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
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
