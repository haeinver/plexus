import 'package:flutter/material.dart';

import '../models/video.dart';

/// MD3 Styled Video Card Widget
class VideoCard extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;

  const VideoCard({super.key, required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final details = [
      video.channelName,
      video.views,
      video.uploadTime,
    ].where((value) => value.isNotEmpty).join(' · ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final fillHeight = constraints.hasBoundedHeight;
        final detailsContent = Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: () => _showOptionsMenu(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        video.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            ColoredBox(
                              color: colorScheme.errorContainer,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(8),
                                child: SelectableText(
                                  '缩略图加载失败：$error',
                                  style: TextStyle(
                                    color: colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: loadingProgress.expectedTotalBytes == null
                                  ? null
                                  : loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!,
                            ),
                          );
                        },
                      ),
                      if (video.thumbnailBadgeText.isNotEmpty)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              child: Text(
                                video.thumbnailBadgeText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (fillHeight)
                  Expanded(child: detailsContent)
                else
                  detailsContent,
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('保存到稍后再看'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已添加到稍后再看')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享视频'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('链接已复制到剪贴板')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('不感兴趣'),
                onTap: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        );
      },
    );
  }
}
