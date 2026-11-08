import 'package:flutter/material.dart';
import '../pages/auth/login_page.dart';

/// Reusable Widget for SmartTube SignInError prompt
class SignInRequiredWidget extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onLoginSuccess;

  const SignInRequiredWidget({
    super.key,
    this.title = '需要登录账号',
    this.message = '该页面需要登录账号后才能获取个人云端数据',
    this.onLoginSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 80,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginPage(),
                  ),
                );
                if (result == true && onLoginSuccess != null) {
                  onLoginSuccess!();
                }
              },
              icon: const Icon(Icons.login),
              label: const Text(
                '登录账号',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
