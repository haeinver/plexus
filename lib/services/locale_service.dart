import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Language, Region and UTC Offset Manager matching SmartTube LocaleManager
class LocaleService {
  static final LocaleService _instance = LocaleService._internal();
  factory LocaleService() => _instance;
  LocaleService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ObserverList<VoidCallback> _listeners = ObserverList<VoidCallback>();

  String _language = 'zh-CN';
  String _region = 'CN';
  bool _initialized = false;

  String get language => _language;
  String get region => _region;
  int get utcOffsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyLocaleChanged() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  /// Supported Languages (Language Code -> Display Name)
  static const Map<String, String> supportedLanguages = {
    'system': '跟随系统',
    'zh-CN': '简体中文 (zh-CN)',
    'zh-TW': '繁體中文 (zh-TW)',
    'en-US': 'English (en-US)',
    'ja-JP': '日本語 (ja-JP)',
    'ko-KR': '한국어 (ko-KR)',
    'ru-RU': 'Русский (ru-RU)',
    'es-ES': 'Español (es-ES)',
    'fr-FR': 'Français (fr-FR)',
  };

  /// Supported Regions / Countries (Region Code -> Display Name)
  static const Map<String, String> supportedRegions = {
    'system': '跟随系统',
    'CN': '中国大陆 (CN)',
    'HK': '中国香港 (HK)',
    'TW': '中国台湾 (TW)',
    'US': '美国 (US)',
    'JP': '日本 (JP)',
    'KR': '韩国 (KR)',
    'GB': '英国 (GB)',
    'SG': '新加坡 (SG)',
  };

  /// Initialize and load saved language & region settings
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final sysLocale = _getSystemLocale();
    final sysLang = sysLocale.languageCode == 'zh'
        ? (sysLocale.countryCode == 'TW' || sysLocale.countryCode == 'HK'
              ? 'zh-TW'
              : 'zh-CN')
        : '${sysLocale.languageCode}-${sysLocale.countryCode ?? "US"}';
    final sysRegion = sysLocale.countryCode ?? 'CN';

    try {
      final savedLang = await _storage.read(key: 'yt_pref_language');
      final savedRegion = await _storage.read(key: 'yt_pref_region');

      if (savedLang == null || savedLang.isEmpty || savedLang == 'system') {
        _language = sysLang;
      } else {
        _language = savedLang;
      }

      if (savedRegion == null ||
          savedRegion.isEmpty ||
          savedRegion == 'system') {
        _region = sysRegion;
      } else {
        _region = savedRegion;
      }
    } catch (_) {
      _language = sysLang;
      _region = sysRegion;
    }
  }

  ui.Locale _getSystemLocale() {
    try {
      return ui.PlatformDispatcher.instance.locale;
    } catch (_) {
      return const ui.Locale('zh', 'CN');
    }
  }

  Future<void> setLanguage(String langCode) async {
    _language = langCode;
    try {
      await _storage.write(key: 'yt_pref_language', value: langCode);
    } catch (_) {}
    _notifyLocaleChanged();
  }

  Future<void> setRegion(String regionCode) async {
    _region = regionCode;
    try {
      await _storage.write(key: 'yt_pref_region', value: regionCode);
    } catch (_) {}
    _notifyLocaleChanged();
  }
}
