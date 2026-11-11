import 'package:flutter/material.dart';

typedef FeedRefreshCallback = Future<void> Function({
  required bool rebuildFeed,
});

class FeedInitialLoading extends StatelessWidget {
  final String message;

  const FeedInitialLoading({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
    );
  }
}

class FeedRefreshIndicator extends StatelessWidget {
  final FeedRefreshCallback onRefresh;
  final Widget child;

  const FeedRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () => onRefresh(rebuildFeed: true),
      child: child,
    );
  }
}

class FeedContinuationStatus extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;
  final String loadingMessage;
  final double loadingHeight;
  final String errorTitle;
  final String retryLabel;

  const FeedContinuationStatus({
    super.key,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    this.loadingMessage = '正在加载更多首页分区...',
    this.loadingHeight = 112,
    this.errorTitle = '首页后续内容加载失败',
    this.retryLabel = '重新加载',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (isLoading) {
      return SizedBox(
        height: loadingHeight,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colorScheme.primary),
              const SizedBox(height: 8),
              Text(loadingMessage),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            errorTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(errorMessage ?? ''),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}
