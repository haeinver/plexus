import 'package:flutter/material.dart';

import '../../models/video.dart';

class PlaylistDetailPage extends StatelessWidget {
  final Video video;

  const PlaylistDetailPage({super.key, required this.video});

  @override
  Widget build(BuildContext context) => _ItemDestinationPage(
    video: video,
    typeLabel: '播放列表',
    icon: Icons.queue_music,
  );
}

class TrackDetailPage extends StatelessWidget {
  final Video video;

  const TrackDetailPage({super.key, required this.video});

  @override
  Widget build(BuildContext context) => _ItemDestinationPage(
    video: video,
    typeLabel: '音乐曲目',
    icon: Icons.music_note,
  );
}

class ChannelDetailPage extends StatelessWidget {
  final Video video;

  const ChannelDetailPage({super.key, required this.video});

  @override
  Widget build(BuildContext context) => _ItemDestinationPage(
    video: video,
    typeLabel: '频道',
    icon: Icons.account_circle_outlined,
  );
}

class BrowseEntryDetailPage extends StatelessWidget {
  final Video video;

  const BrowseEntryDetailPage({super.key, required this.video});

  @override
  Widget build(BuildContext context) => _ItemDestinationPage(
    video: video,
    typeLabel: '浏览入口',
    icon: Icons.explore_outlined,
  );
}

class _ItemDestinationPage extends StatelessWidget {
  final Video video;
  final String typeLabel;
  final IconData icon;

  const _ItemDestinationPage({
    required this.video,
    required this.typeLabel,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metadata = [
      video.channelName,
      video.views,
      video.uploadTime,
    ].where((value) => value.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: Text(video.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _DestinationImage(video: video),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(typeLabel, style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            video.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final value in metadata) ...[
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _DestinationImage extends StatelessWidget {
  final Video video;

  const _DestinationImage({required this.video});

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
      fit: BoxFit.cover,
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
