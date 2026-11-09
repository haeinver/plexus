import 'package:flutter/material.dart';

import '../../models/video.dart';

class ShortsDetailPage extends StatelessWidget {
  final Video video;

  const ShortsDetailPage({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Shorts'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: _VideoPoster(video: video),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (video.channelName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      video.channelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveEventDetailPage extends StatelessWidget {
  final Video video;

  const LiveEventDetailPage({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final statusLabel = video.isUpcoming ? '即将直播' : '正在直播';

    return Scaffold(
      appBar: AppBar(title: Text(statusLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _VideoPoster(video: video),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.error,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onError,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            video.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (video.channelName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              video.channelName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VideoPoster extends StatelessWidget {
  final Video video;

  const _VideoPoster({required this.video});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (video.thumbnailUrl.isEmpty) {
      return ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: colorScheme.onSurfaceVariant,
            size: 40,
          ),
        ),
      );
    }

    return Image.network(
      video.thumbnailUrl,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: colorScheme.errorContainer,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: colorScheme.onErrorContainer,
            size: 40,
          ),
        ),
      ),
    );
  }
}
