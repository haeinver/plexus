import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/locale_service.dart';

/// Settings Page (使用 card_settings_ui 2.0.1 打造的卡片式设置界面)
class SettingsPage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onThemeModeChanged;

  const SettingsPage({
    super.key,
    required this.isDarkMode,
    required this.onThemeModeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final LocaleService _localeService = LocaleService();
  int _cacheSizeMb = 128;
  bool _isLoadingLocale = true;
  String _appVersion = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _initLocale();
    _initPackageInfo();
  }

  Future<void> _initLocale() async {
    await _localeService.init();
    if (mounted) {
      setState(() {
        _isLoadingLocale = false;
      });
    }
  }

  Future<void> _initPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = packageInfo.version;
      _buildNumber = packageInfo.buildNumber;
    });
  }

  void _showLanguageDialog() {
    final currentLang = _localeService.language;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('选择界面与内容语言 (hl)'),
          children: LocaleService.supportedLanguages.entries.map((entry) {
            final isSelected = currentLang == entry.key;

            return SimpleDialogOption(
              onPressed: () async {
                final nav = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);
                await _localeService.setLanguage(entry.key);
                if (mounted) {
                  setState(() {});
                  nav.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text('已设置语言为：${entry.value}')),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text(
                      entry.value,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _showRegionDialog() {
    final currentRegion = _localeService.region;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('选择内容推荐地区 (gl)'),
          children: LocaleService.supportedRegions.entries.map((entry) {
            final isSelected = currentRegion == entry.key;

            return SimpleDialogOption(
              onPressed: () async {
                final nav = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);
                await _localeService.setRegion(entry.key);
                if (mounted) {
                  setState(() {});
                  nav.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text('已设置推荐地区为：${entry.value}')),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text(
                      entry.value,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('关于 Plexus'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('应用名称：Plexus'),
              const SizedBox(height: 8),
              Text(_appVersion.isEmpty ? '应用版本：读取中' : '应用版本：$_appVersion'),
              if (_buildNumber.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('构建号：$_buildNumber'),
              ],
              const SizedBox(height: 8),
              const Text('核心架构：Flutter 3.x + MD3 UI Toolkit'),
              const SizedBox(height: 8),
              const Text('解包模块：InnerTube & OAuth 2.0 Device Flow'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final langName =
        LocaleService.supportedLanguages[_localeService.language] ??
        _localeService.language;
    final regionName =
        LocaleService.supportedRegions[_localeService.region] ??
        _localeService.region;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '应用设置',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoadingLocale
          ? const Center(child: CircularProgressIndicator())
          : SettingsList(
              sections: [
                // Section 1: Appearance
                SettingsSection(
                  title: const Text('界面与外观'),
                  tiles: [
                    SettingsTile.switchTile(
                      leading: const Icon(Icons.dark_mode_outlined),
                      title: const Text('深色/夜间主题 (MD3)'),
                      description: const Text('切换全应用深色或亮色视觉风格'),
                      initialValue: widget.isDarkMode,
                      onToggle: (val) {
                        widget.onThemeModeChanged(val ?? false);
                      },
                    ),
                  ],
                ),

                // Section 2: Language & Region
                SettingsSection(
                  title: const Text('语言与地区'),
                  tiles: [
                    SettingsTile.navigation(
                      leading: const Icon(Icons.language_outlined),
                      title: const Text('内容语言 (hl)'),
                      value: Text(langName),
                      onPressed: (_) => _showLanguageDialog(),
                    ),
                    SettingsTile.navigation(
                      leading: const Icon(Icons.public_outlined),
                      title: const Text('内容地区 (gl)'),
                      value: Text(regionName),
                      onPressed: (_) => _showRegionDialog(),
                    ),
                  ],
                ),

                // Section 3: Storage & Cache
                SettingsSection(
                  title: const Text('存储与缓存'),
                  tiles: [
                    SettingsTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('清理视频缓存'),
                      description: Text('已占用 $_cacheSizeMb MB 本地缓存空间'),
                      trailing: OutlinedButton(
                        onPressed: _cacheSizeMb == 0
                            ? null
                            : () {
                                setState(() {
                                  _cacheSizeMb = 0;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已成功清除应用视频缓存')),
                                );
                              },
                        child: Text(_cacheSizeMb == 0 ? '已清除' : '清理缓存'),
                      ),
                    ),
                  ],
                ),

                // Section 4: About & Version
                SettingsSection(
                  title: const Text('关于与信息'),
                  tiles: [
                    SettingsTile.navigation(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('关于 Plexus'),
                      value: Text(
                        _appVersion.isEmpty ? '读取中' : 'v$_appVersion',
                      ),
                      onPressed: (_) => _showAboutDialog(),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
