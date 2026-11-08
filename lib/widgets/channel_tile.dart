import 'package:flutter/material.dart';
import '../models/channel.dart';

/// MD3 Styled Subscription / Channel Tile
class ChannelTile extends StatefulWidget {
  final Channel channel;
  final VoidCallback? onTap;

  const ChannelTile({
    super.key,
    required this.channel,
    this.onTap,
  });

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSubscribed = widget.channel.isSubscribed;

    return ListTile(
      onTap: widget.onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage: NetworkImage(widget.channel.avatarUrl),
          ),
          if (widget.channel.hasUnreadUpdate)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        widget.channel.name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        '${widget.channel.subscriberCount} 订阅者 • ${widget.channel.videoCount} 个视频',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isSubscribed
          ? OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  widget.channel.isSubscribed = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已取消订阅 ${widget.channel.name}')),
                );
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('已订阅'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            )
          : FilledButton(
              onPressed: () {
                setState(() {
                  widget.channel.isSubscribed = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('成功订阅 ${widget.channel.name}')),
                );
              },
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('订阅'),
            ),
    );
  }
}
