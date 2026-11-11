import 'package:flutter/material.dart';

import '../models/channel.dart';

/// MD3 Styled Subscription / Channel Tile
class ChannelTile extends StatelessWidget {
  final Channel channel;
  final VoidCallback? onTap;

  const ChannelTile({super.key, required this.channel, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metadata = [
      if (channel.subscriberCount.isNotEmpty) '${channel.subscriberCount} 订阅者',
      if (channel.videoCount.isNotEmpty) '${channel.videoCount} 个视频',
    ].join(' • ');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: channel.avatarUrl.isEmpty
            ? null
            : NetworkImage(channel.avatarUrl),
        child: channel.avatarUrl.isEmpty && channel.name.isNotEmpty
            ? Text(channel.name.substring(0, 1))
            : null,
      ),
      title: Text(
        channel.name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        metadata.isEmpty
            ? channel.description.isEmpty
                  ? '已订阅频道'
                  : channel.description
            : metadata,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
