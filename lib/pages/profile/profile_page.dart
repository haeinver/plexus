import 'package:flutter/material.dart';
import '../../services/youtube_auth_service.dart';
import '../auth/login_page.dart';
import '../settings/settings_page.dart';

/// 个人中心界面 (Profile / Me Page with Instant Rendering)
class ProfilePage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onThemeModeChanged;

  const ProfilePage({
    super.key,
    required this.isDarkMode,
    required this.onThemeModeChanged,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final YouTubeAuthService _authService = YouTubeAuthService();

  @override
  void initState() {
    super.initState();
    _initAuth();
  }

  Future<void> _initAuth() async {
    await _authService.init();
    if (mounted) {
      setState(() {});
    }
  }

  /// 确认退出当前账号对话框 (防误触)
  Future<void> _confirmLogout() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认退出登录？'),
          content: const Text('退出当前登录账号后，部分云端同步功能及订阅动态将无法使用。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认退出'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _authService.logout();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已成功退出当前账号')),
        );
      }
    }
  }

  void _showAccountSelectionModal() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final accounts = _authService.accounts;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '切换或管理账号',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(modalContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (accounts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '当前暂未绑定任何 YouTube 账号',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          margin: EdgeInsets.zero,
                          child: Column(
                            children: List.generate(accounts.length, (index) {
                              final acc = accounts[index];
                              final isSelected = acc.isSelected;
                              final isLast = index == accounts.length - 1;

                              return Column(
                                children: [
                                  ListTile(
                                    selected: isSelected,
                                    selectedTileColor: colorScheme.primaryContainer
                                        .withValues(alpha: 0.3),
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected
                                          ? colorScheme.primaryContainer
                                          : colorScheme.surfaceContainerHighest,
                                      backgroundImage: acc.avatarImageUrl != null &&
                                              acc.avatarImageUrl!.isNotEmpty
                                          ? NetworkImage(acc.avatarImageUrl!)
                                          : null,
                                      child: (acc.avatarImageUrl == null ||
                                              acc.avatarImageUrl!.isEmpty)
                                          ? Icon(
                                              Icons.person,
                                              color: isSelected
                                                  ? colorScheme.primary
                                                  : colorScheme.onSurfaceVariant,
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      acc.name ?? acc.channelHandle ?? 'YouTube 账号',
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? colorScheme.primary
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                    subtitle: Text(
                                      acc.email ?? acc.channelHandle ?? '',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: isSelected
                                        ? Icon(
                                            Icons.check_circle,
                                            color: colorScheme.primary,
                                          )
                                        : null,
                                    onTap: () async {
                                      await _authService.selectAccount(acc);
                                      if (mounted) {
                                        setState(() {});
                                      }
                                      if (modalContext.mounted) {
                                        Navigator.pop(modalContext);
                                      }
                                    },
                                  ),
                                  if (!isLast)
                                    Divider(
                                      height: 1,
                                      indent: 16,
                                      endIndent: 16,
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.3),
                                    ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            side: BorderSide(
                              color: colorScheme.error.withValues(alpha: 0.5),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(modalContext);
                            _confirmLogout();
                          },
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text('退出登录'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            final navContext = context;
                            Navigator.pop(modalContext);
                            final result = await Navigator.push<bool>(
                              navContext,
                              MaterialPageRoute(
                                builder: (context) => const LoginPage(),
                              ),
                            );
                            if (result == true && mounted) {
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('绑定新账号'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoggedIn = _authService.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '用户与设置',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '应用设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsPage(
                    isDarkMode: widget.isDarkMode,
                    onThemeModeChanged: widget.onThemeModeChanged,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Header Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: isLoggedIn
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    backgroundImage: isLoggedIn &&
                            _authService.userAvatar.isNotEmpty
                        ? NetworkImage(_authService.userAvatar)
                        : null,
                    child: !isLoggedIn || _authService.userAvatar.isEmpty
                        ? Icon(
                            Icons.person_outline,
                            size: 32,
                            color: isLoggedIn
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isLoggedIn ? _authService.userName : '未登录用户',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isLoggedIn
                              ? (_authService.userEmail.isNotEmpty
                                  ? _authService.userEmail
                                  : '已连接 SmartTube OAuth 授权')
                              : '点击右侧按钮登录同步云端数据',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isLoggedIn)
                    IconButton.filledTonal(
                      icon: const Icon(Icons.switch_account_outlined),
                      tooltip: '切换/管理账号',
                      onPressed: _showAccountSelectionModal,
                    )
                  else
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginPage(),
                          ),
                        );
                        if (result == true && mounted) {
                          setState(() {});
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('登录成功！已无缝同步云端账号数据'),
                            ),
                          );
                        }
                      },
                      child: const Text('登录'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
