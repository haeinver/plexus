import 'package:flutter/material.dart';
import '../../services/mock_data_service.dart';
import '../../widgets/channel_tile.dart';
import '../../widgets/video_card.dart';
import '../player/video_detail_page.dart';

/// 订阅界面 (Subscription Feed Page)
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final MockDataService _dataService = MockDataService();
  String? _selectedChannelId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subscribedChannels =
        _dataService.channels.where((c) => c.isSubscribed).toList();
    final feedVideos = _dataService.getSubscriptionFeed();

    final filteredVideos = _selectedChannelId == null
        ? feedVideos
        : feedVideos
            .where((v) =>
                v.channelName ==
                subscribedChannels
                    .firstWhere((c) => c.id == _selectedChannelId)
                    .name)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '订阅与动态',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: '管理订阅',
            onPressed: () {
              _showManageSubscriptionsModal(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Subscribed Channels Avatars Row
          Container(
            height: 96,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: subscribedChannels.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  // "All" filter chip
                  final isAllSelected = _selectedChannelId == null;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedChannelId = null;
                        });
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isAllSelected
                                    ? colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: isAllSelected
                                  ? colorScheme.primary
                                  : colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.apps,
                                color: isAllSelected
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '全部动态',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isAllSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final channel = subscribedChannels[index - 1];
                final isSelected = _selectedChannelId == channel.id;

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedChannelId =
                            isSelected ? null : channel.id;
                      });
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? colorScheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundImage:
                                    NetworkImage(channel.avatarUrl),
                              ),
                            ),
                            if (channel.hasUnreadUpdate)
                              Positioned(
                                right: 2,
                                top: 2,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: colorScheme.surface, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 72,
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Subscription Feed Video List
          Expanded(
            child: filteredVideos.isEmpty
                ? Center(
                    child: Text(
                      '暂无相关订阅更新',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredVideos.length,
                    itemBuilder: (context, index) {
                      final video = filteredVideos[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: VideoCard(
                          video: video,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    VideoDetailPage(video: video),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showManageSubscriptionsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        '管理频道订阅',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _dataService.channels.length,
                    itemBuilder: (context, index) {
                      final channel = _dataService.channels[index];
                      return ChannelTile(channel: channel);
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
