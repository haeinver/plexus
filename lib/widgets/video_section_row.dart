import 'package:flutter/material.dart';

import '../models/video.dart';
import '../models/video_section.dart';
import 'video_card.dart';

class VideoSectionRow extends StatelessWidget {
  final String sectionKey;
  final String itemKeyPrefix;
  final VideoSection section;
  final double cardWidth;
  final double rowHeight;
  final ScrollController? scrollController;
  final bool isLoadingMore;
  final String? errorMessage;
  final String loadingMessage;
  final VoidCallback onLoadMore;
  final VoidCallback onOpenSection;
  final ValueChanged<Video> onVideoTap;

  const VideoSectionRow({
    super.key,
    required this.sectionKey,
    required this.section,
    required this.cardWidth,
    required this.rowHeight,
    required this.isLoadingMore,
    required this.errorMessage,
    required this.onLoadMore,
    required this.onOpenSection,
    required this.onVideoTap,
    this.itemKeyPrefix = 'video-section-item',
    this.scrollController,
    this.loadingMessage = '正在加载本栏更多视频...',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title != null && section.title!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
            child: Text(
              section.title!,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        SizedBox(
          height: rowHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              final isNearEnd = notification.metrics.extentAfter < 560;
              final shouldCheckEnd =
                  notification is ScrollUpdateNotification ||
                  notification is OverscrollNotification ||
                  notification is ScrollMetricsNotification;
              if (notification.metrics.axis == Axis.horizontal &&
                  section.browseId == null &&
                  shouldCheckEnd &&
                  isNearEnd) {
                onLoadMore();
              }
              return false;
            },
            child: ListView.builder(
              controller: scrollController,
              key: PageStorageKey<String>(sectionKey),
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount:
                  section.videos.length +
                  (section.browseId != null ||
                          isLoadingMore ||
                          errorMessage != null
                      ? 1
                      : 0),
              itemBuilder: (context, videoIndex) {
                if (videoIndex == section.videos.length) {
                  if (section.browseId != null) {
                    return _SectionBrowseCard(
                      cardWidth: cardWidth,
                      title: section.browseTitle!,
                      onTap: onOpenSection,
                    );
                  }
                  return _SectionLoadMoreCard(
                    cardWidth: cardWidth,
                    isLoading: isLoadingMore,
                    errorMessage: errorMessage,
                    loadingMessage: loadingMessage,
                    onRetry: onLoadMore,
                  );
                }

                final video = section.videos[videoIndex];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: cardWidth,
                    child: video.thumbnailUrl.isEmpty
                        ? _SectionBrowseCard(
                            cardWidth: cardWidth,
                            title: video.title,
                            onTap: () => onVideoTap(video),
                          )
                        : VideoCard(
                            key: ValueKey<String>(
                              '$itemKeyPrefix-${video.id ?? video.browseId}-$videoIndex',
                            ),
                            video: video,
                            onTap: () => onVideoTap(video),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _SectionLoadMoreCard extends StatelessWidget {
  final double cardWidth;
  final bool isLoading;
  final String? errorMessage;
  final String loadingMessage;
  final VoidCallback onRetry;

  const _SectionLoadMoreCard({
    required this.cardWidth,
    required this.isLoading,
    required this.errorMessage,
    required this.loadingMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: cardWidth,
      child: Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: isLoading
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(loadingMessage),
                    ],
                  )
                : errorMessage != null
                ? SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          errorMessage!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('更多...'),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SectionBrowseCard extends StatelessWidget {
  final double cardWidth;
  final String title;
  final VoidCallback onTap;

  const _SectionBrowseCard({
    required this.cardWidth,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardWidth,
      child: Card(
        child: Center(
          child: TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.open_in_new),
            label: Text(title),
          ),
        ),
      ),
    );
  }
}
