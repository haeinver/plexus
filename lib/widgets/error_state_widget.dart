import 'package:flutter/material.dart';

/// Reusable Widget for Network / API Load Errors with Retry Button
class ErrorStateWidget extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;
  final String retryText;

  const ErrorStateWidget({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    this.retryText = '重新加载',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            SelectableText(
              errorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(retryText),
            ),
          ],
        ),
      ),
    );
  }
}
