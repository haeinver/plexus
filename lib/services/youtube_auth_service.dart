import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/youtube_account.dart';
import 'locale_service.dart';

/// Real YouTube OAuth 2.0 Device Flow & Innertube API Auth Service
/// Strictly matches SmartTube V2 MediaServiceCore auth implementation.
class YouTubeAuthService {
  static final YouTubeAuthService _instance = YouTubeAuthService._internal();
  factory YouTubeAuthService() => _instance;
  YouTubeAuthService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ObserverList<VoidCallback> _accountListeners = ObserverList<VoidCallback>();

  // SmartTube Standard YouTube TV OAuth Credentials & Fallbacks
  static const String _defaultClientId =
      '861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com';
  static const String _defaultClientSecret = 'SboVhoG9s0rNafixCSGGKXAT';

  // Alternative SmartTube TV Client ID fallback
  static const String _tvClientId =
      '864024727828-e2182nm8i3g9u1vj41v8tno5h5fsqpsd.apps.googleusercontent.com';

  static const String _appScope =
      'http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content';
  static const String _modelName = 'ytlr::';

  String _clientId = _defaultClientId;
  String _clientSecret = _defaultClientSecret;
  String? _deviceId;

  final List<YouTubeAccount> _accounts = [];
  YouTubeAccount? _selectedAccount;
  String? _accessToken;
  DateTime? _tokenExpiryTime;

  bool _initialized = false;

  /// Account Change Listener management (mirrors SmartTube MediaServiceManager.AccountChangeListener)
  void addAccountListener(VoidCallback listener) {
    _accountListeners.add(listener);
  }

  void removeAccountListener(VoidCallback listener) {
    _accountListeners.remove(listener);
  }

  void _notifyAccountChanged() {
    for (final listener in List<VoidCallback>.from(_accountListeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  /// Active Auth State
  bool get isLoggedIn => _selectedAccount != null && _selectedAccount!.refreshToken.isNotEmpty;
  YouTubeAccount? get selectedAccount => _selectedAccount;
  List<YouTubeAccount> get accounts => List.unmodifiable(_accounts);

  String get userName => _selectedAccount?.name ?? _selectedAccount?.channelHandle ?? '未登录用户';
  String get userEmail => _selectedAccount?.email ?? (_selectedAccount?.channelHandle ?? '');
  String get userAvatar => _selectedAccount?.avatarImageUrl ?? '';

  String? get accessToken => _accessToken;

  /// Initialize and load saved accounts from secure storage
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Load or generate persistent device ID
      _deviceId = await _storage.read(key: 'yt_device_id');
    } catch (_) {}

    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = 'plexus_dev_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (9000 * (DateTime.now().microsecond / 1000000))).toInt()}';
      try {
        await _storage.write(key: 'yt_device_id', value: _deviceId);
      } catch (_) {}
    }

    // Try fetching live dynamic client ID/secret from YouTube TV app JS
    await _fetchDynamicClientData();

    // Restore saved accounts list
    await _restoreAccounts();
  }

  /// Attempts to extract live client_id & client_secret from YouTube TV app JS (matching SmartTube ClientData regex)
  Future<void> _fetchDynamicClientData() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.youtube.com/tv'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (PlayStation 4 5.05) AppleWebKit/601.2 (KHTML, like Gecko) Cobalt/17.168300-qa (gzip)',
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final scriptMatch = RegExp(r'src="([^"]*?(?:app|tv-player|m=base)[^"]*?\.js)"')
            .firstMatch(response.body);
        if (scriptMatch != null) {
          var scriptUrl = scriptMatch.group(1)!;
          if (scriptUrl.startsWith('//')) {
            scriptUrl = 'https:$scriptUrl';
          } else if (scriptUrl.startsWith('/')) {
            scriptUrl = 'https://www.youtube.com$scriptUrl';
          }

          final jsResponse = await http
              .get(Uri.parse(scriptUrl))
              .timeout(const Duration(seconds: 3));

          if (jsResponse.statusCode == 200) {
            final idMatch = RegExp(
                    r'clientId:"([-\w]+\.apps\.googleusercontent\.com)",\n?[$\w]+:"(\w+)"')
                .firstMatch(jsResponse.body);
            if (idMatch != null) {
              _clientId = idMatch.group(1)!;
              _clientSecret = idMatch.group(2)!;
              return;
            }
          }
        }
      }
    } catch (_) {
      // Fallback to official SmartTube TV credentials
    }
  }

  /// Step 1: Request Device Code & User Code from YouTube OAuth API
  Future<DeviceCodeResult> getDeviceCode() async {
    await init();

    final uri = Uri.parse('https://www.youtube.com/o/oauth2/device/code');
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode({
      'client_id': _clientId,
      'device_id': _deviceId,
      'model_name': _modelName,
      'scope': _appScope,
    });

    try {
      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return DeviceCodeResult(
          deviceCode: data['device_code']?.toString() ?? '',
          userCode: data['user_code']?.toString() ?? '',
          verificationUrl: data['verification_url']?.toString() ??
              data['user_code_url']?.toString() ??
              'https://youtube.com/activate',
          interval: (data['interval'] as num?)?.toInt() ?? 5,
          expiresIn: (data['expires_in'] as num?)?.toInt() ?? 1800,
        );
      } else {
        // Fallback retry with TV Client ID if primary ID fails
        if (_clientId != _tvClientId) {
          _clientId = _tvClientId;
          return await getDeviceCode();
        }
        return DeviceCodeResult.error(
            '获取设备码失败 (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      return DeviceCodeResult.error('网络连接错误: $e');
    }
  }

  /// Step 2: Poll Access Token until User Authorizes on youtube.com/activate
  Future<AccessTokenResult> pollAccessToken(String deviceCode) async {
    final uri = Uri.parse('https://www.youtube.com/o/oauth2/token');
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode({
      'code': deviceCode,
      'client_id': _clientId,
      'client_secret': _clientSecret,
      'grant_type': 'http://oauth.net/grant_type/device/1.0',
    });

    try {
      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final accessToken = data['access_token']?.toString();
        final refreshToken = data['refresh_token']?.toString();
        final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;

        if (accessToken != null && refreshToken != null) {
          _accessToken = accessToken;
          _tokenExpiryTime = DateTime.now().add(Duration(seconds: expiresIn - 60));

          return AccessTokenResult.success(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
          );
        }
      } else {
        final Map<String, dynamic> data = json.decode(response.body);
        final error = data['error']?.toString() ?? '';
        if (error == 'authorization_pending') {
          return const AccessTokenResult.pending();
        } else if (error == 'slow_down') {
          return const AccessTokenResult.pending(isSlowDown: true);
        } else {
          return AccessTokenResult.error('授权中断: $error');
        }
      }
    } catch (e) {
      return AccessTokenResult.error('网络轮询失败: $e');
    }

    return const AccessTokenResult.pending();
  }

  /// Step 3: Refresh Access Token using Refresh Token
  Future<String?> updateAccessToken([String? refreshToken]) async {
    final tokenToUse = refreshToken ?? _selectedAccount?.refreshToken;
    if (tokenToUse == null || tokenToUse.isEmpty) return null;

    final uri = Uri.parse('https://www.youtube.com/o/oauth2/token');
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode({
      'refresh_token': tokenToUse,
      'client_id': _clientId,
      'client_secret': _clientSecret,
      'grant_type': 'refresh_token',
    });

    try {
      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final accessToken = data['access_token']?.toString();
        final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;

        if (accessToken != null) {
          if (tokenToUse == _selectedAccount?.refreshToken) {
            _accessToken = accessToken;
            _tokenExpiryTime = DateTime.now().add(Duration(seconds: expiresIn - 60));
          }
          return accessToken;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Step 4: Fetch user accounts & brand profiles via Innertube accounts_list API & OAuth UserInfo
  Future<List<YouTubeAccount>> fetchAccountsList(
    String accessToken,
    String refreshToken,
  ) async {
    final List<YouTubeAccount> fetchedAccounts = [];
    String? userInfoName;
    String? userInfoEmail;
    String? userInfoPicture;
    int userInfoStatus = -1;
    String userInfoError = '';

    // Step A: Fetch real Google Account Profile via OAuth2 UserInfo API
    try {
      final userInfoResponse = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 6));

      userInfoStatus = userInfoResponse.statusCode;
      if (userInfoResponse.statusCode == 200) {
        final Map<String, dynamic> userInfoData =
            json.decode(userInfoResponse.body);
        userInfoName = userInfoData['name']?.toString();
        userInfoEmail = userInfoData['email']?.toString();
        userInfoPicture = userInfoData['picture']?.toString();
      } else {
        userInfoError = userInfoResponse.body;
      }
    } catch (e) {
      userInfoError = e.toString();
    }

    // Step B: Fetch YouTube Brand Channels & Accounts via InnerTube API
    int accountsListStatus = -1;
    String accountsListError = '';

    try {
      final localeService = LocaleService();
      await localeService.init();

      final uri = Uri.parse(
          'https://www.youtube.com/youtubei/v1/account/accounts_list?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8');
      final headers = {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
      };
      final body = json.encode({
        'context': {
          'client': {
            'clientName': 'TVHTML5',
            'clientVersion': '7.20260901.15.00',
            'acceptLanguage': localeService.language,
            'acceptRegion': localeService.region,
            'utcOffsetMinutes': localeService.utcOffsetMinutes,
            'hl': localeService.language,
            'gl': localeService.region,
          }
        },
        'accountReadMask': {
          'returnOwner': true,
          'returnBrandAccounts': true,
          'returnPersonaAccounts': false,
        }
      });

      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 6));

      accountsListStatus = response.statusCode;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        final contents = data['contents'] as List?;
        if (contents != null && contents.isNotEmpty) {
          final accountSectionList =
              contents[0]['accountSectionListRenderer']?['contents'] as List?;
          if (accountSectionList != null && accountSectionList.isNotEmpty) {
            final items = accountSectionList[0]['accountItemSectionRenderer']
                ?['contents'] as List?;
            if (items != null) {
              for (final item in items) {
                final accountItem = item['accountItem'];
                if (accountItem != null &&
                    accountItem is Map<String, dynamic>) {
                  final name =
                      _extractText(accountItem['accountName']) ?? userInfoName;
                  final email =
                      _extractText(accountItem['accountByline']) ?? userInfoEmail;
                  final channelHandle =
                      _extractText(accountItem['channelHandle']);
                  final avatarUrl =
                      _extractThumbnail(accountItem['accountPhoto']) ??
                          userInfoPicture;
                  final pageIdToken =
                      _extractPageIdToken(accountItem['serviceEndpoint']);
                  final isSelected = accountItem['isSelected'] == true;
                  final hasChannel = accountItem['hasChannel'] != false;

                  final id = pageIdToken ?? (email ?? name ?? refreshToken);

                  fetchedAccounts.add(YouTubeAccount(
                    id: id,
                    name: name,
                    email: email,
                    channelHandle: channelHandle,
                    avatarImageUrl: avatarUrl,
                    refreshToken: refreshToken,
                    pageIdToken: pageIdToken,
                    isSelected: isSelected,
                    hasChannel: hasChannel,
                  ));
                }
              }
            }
          }
        }
      } else {
        accountsListError = response.body;
      }
    } catch (e) {
      accountsListError = e.toString();
    }

    // Step C: If UserInfo succeeded, use it to construct or enrich primary account
    if (userInfoName != null || userInfoEmail != null) {
      if (fetchedAccounts.isEmpty) {
        fetchedAccounts.add(YouTubeAccount(
          id: userInfoEmail ?? refreshToken,
          name: userInfoName,
          email: userInfoEmail,
          avatarImageUrl: userInfoPicture,
          refreshToken: refreshToken,
          isSelected: true,
        ));
      } else {
        for (var i = 0; i < fetchedAccounts.length; i++) {
          final acc = fetchedAccounts[i];
          fetchedAccounts[i] = acc.copyWith(
            name: acc.name ?? userInfoName,
            email: acc.email ?? userInfoEmail,
            avatarImageUrl: acc.avatarImageUrl ?? userInfoPicture,
          );
        }
      }
    }

    // STRICT: NO FAKE MOCK FALLBACKS! Throws real error if no real account profile could be fetched!
    if (fetchedAccounts.isEmpty) {
      throw Exception(
        '获取真实账户资料失败：\n'
        '• OAuth UserInfo [HTTP $userInfoStatus]: $userInfoError\n'
        '• InnerTube API [HTTP $accountsListStatus]: $accountsListError',
      );
    }

    // Ensure at least one account is selected
    if (!fetchedAccounts.any((a) => a.isSelected)) {
      fetchedAccounts[0] = fetchedAccounts[0].copyWith(isSelected: true);
    }

    // Merge accounts into stored state
    for (final account in fetchedAccounts) {
      _mergeAccount(account);
    }

    await _persistAccounts();
    _notifyAccountChanged();
    return _accounts;
  }

  void _mergeAccount(YouTubeAccount newAccount) {
    final index = _accounts.indexWhere((a) => a == newAccount || (a.id == newAccount.id && a.id.isNotEmpty));
    if (index != -1) {
      _accounts[index] = newAccount;
    } else {
      _accounts.add(newAccount);
    }

    if (newAccount.isSelected) {
      for (var i = 0; i < _accounts.length; i++) {
        if (_accounts[i] != newAccount) {
          _accounts[i] = _accounts[i].copyWith(isSelected: false);
        }
      }
      _selectedAccount = newAccount;
    }
  }

  /// Helper to extract string from Innertube TextItem JSON node
  String? _extractText(dynamic textNode) {
    if (textNode == null) return null;
    if (textNode is String) return textNode;
    if (textNode is Map<String, dynamic>) {
      if (textNode['simpleText'] != null) {
        return textNode['simpleText'].toString();
      }
      if (textNode['snippet'] != null && textNode['snippet']['text'] != null) {
        return textNode['snippet']['text'].toString();
      }
      final runs = textNode['runs'] as List?;
      if (runs != null && runs.isNotEmpty) {
        return runs.map((r) => r['text'] ?? '').join('');
      }
    }
    return null;
  }

  /// Helper to extract highest resolution avatar thumbnail URL
  String? _extractThumbnail(dynamic photoNode) {
    if (photoNode == null || photoNode is! Map<String, dynamic>) return null;
    final thumbnails = photoNode['thumbnails'] as List?;
    if (thumbnails == null || thumbnails.isEmpty) return null;

    String? bestUrl;
    int maxRes = -1;

    for (final thumb in thumbnails) {
      final url = thumb['url']?.toString();
      final width = (thumb['width'] as num?)?.toInt() ?? 0;
      if (url != null && width >= maxRes) {
        maxRes = width;
        bestUrl = url;
      }
    }

    if (bestUrl != null && bestUrl.startsWith('//')) {
      bestUrl = 'https:$bestUrl';
    }
    return bestUrl;
  }

  /// Helper to extract Page ID Token for brand accounts
  String? _extractPageIdToken(dynamic endpoint) {
    if (endpoint == null || endpoint is! Map<String, dynamic>) return null;
    final selectActiveIdentity = endpoint['selectActiveIdentityEndpoint'];
    if (selectActiveIdentity is Map<String, dynamic>) {
      final tokens = selectActiveIdentity['supportedTokens'] as List?;
      if (tokens != null && tokens.isNotEmpty) {
        for (final t in tokens) {
          final pageId = t['pageIdToken']?['pageId']?.toString();
          if (pageId != null && pageId.isNotEmpty) {
            return pageId;
          }
        }
      }
    }
    return null;
  }

  /// Switch currently selected account
  Future<void> selectAccount(YouTubeAccount account) async {
    for (var i = 0; i < _accounts.length; i++) {
      final isTarget = _accounts[i] == account;
      _accounts[i] = _accounts[i].copyWith(isSelected: isTarget);
      if (isTarget) {
        _selectedAccount = _accounts[i];
      }
    }
    _accessToken = null;
    await updateAccessToken();
    await _persistAccounts();
    _notifyAccountChanged();
  }

  /// Remove specified account
  Future<void> removeAccount(YouTubeAccount account) async {
    _accounts.removeWhere((a) => a == account);
    if (_selectedAccount == account) {
      _selectedAccount = _accounts.isNotEmpty ? _accounts[0] : null;
      if (_selectedAccount != null) {
        _accounts[0] = _selectedAccount!.copyWith(isSelected: true);
      }
      _accessToken = null;
    }
    await _persistAccounts();
    _notifyAccountChanged();
  }

  /// Sign out current selected account
  Future<void> logout() async {
    if (_selectedAccount != null) {
      await removeAccount(_selectedAccount!);
    }
  }

  /// Get headers for authenticated API requests
  Future<Map<String, String>> getAuthHeaders() async {
    if (!isLoggedIn) return {};

    if (_accessToken == null ||
        _tokenExpiryTime == null ||
        DateTime.now().isAfter(_tokenExpiryTime!)) {
      await updateAccessToken();
    }

    final headers = <String, String>{};
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    if (_selectedAccount?.pageIdToken != null &&
        _selectedAccount!.pageIdToken!.isNotEmpty) {
      headers['X-Goog-Pageid'] = _selectedAccount!.pageIdToken!;
    }

    return headers;
  }

  /// Save accounts list to secure storage
  Future<void> _persistAccounts() async {
    try {
      final accountsJson = jsonEncode(_accounts.map((a) => a.toJson()).toList());
      await _storage.write(key: 'yt_accounts_list', value: accountsJson);
      if (_selectedAccount != null) {
        await _storage.write(
            key: 'yt_selected_account_id', value: _selectedAccount!.id);
      } else {
        await _storage.delete(key: 'yt_selected_account_id');
      }
    } catch (_) {}
  }

  /// Restore accounts list from secure storage
  Future<void> _restoreAccounts() async {
    try {
      final rawAccounts = await _storage.read(key: 'yt_accounts_list');
      final selectedId = await _storage.read(key: 'yt_selected_account_id');

      _accounts.clear();
      _selectedAccount = null;

      if (rawAccounts != null && rawAccounts.isNotEmpty) {
        final List<dynamic> list = jsonDecode(rawAccounts);
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final acc = YouTubeAccount.fromJson(item);
            _accounts.add(acc);
          }
        }
      }

      if (_accounts.isNotEmpty) {
        var foundIndex = -1;
        if (selectedId != null) {
          foundIndex = _accounts.indexWhere((a) => a.id == selectedId);
        }

        if (foundIndex == -1) {
          foundIndex = _accounts.indexWhere((a) => a.isSelected);
        }

        if (foundIndex == -1) {
          foundIndex = 0;
        }

        for (var i = 0; i < _accounts.length; i++) {
          final isSelected = i == foundIndex;
          _accounts[i] = _accounts[i].copyWith(isSelected: isSelected);
        }

        _selectedAccount = _accounts[foundIndex];
        await updateAccessToken();
      }
    } catch (_) {}
    _notifyAccountChanged();
  }
}

class DeviceCodeResult {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int interval;
  final int expiresIn;
  final bool isError;
  final String? errorMsg;

  const DeviceCodeResult({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresIn,
    this.isError = false,
    this.errorMsg,
  });

  factory DeviceCodeResult.error(String msg) {
    return DeviceCodeResult(
      deviceCode: '',
      userCode: '',
      verificationUrl: '',
      interval: 5,
      expiresIn: 0,
      isError: true,
      errorMsg: msg,
    );
  }
}

class AccessTokenResult {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final bool isSuccess;
  final bool isPending;
  final bool isSlowDown;
  final String? errorMsg;

  const AccessTokenResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.isSuccess,
    required this.isPending,
    required this.isSlowDown,
    this.errorMsg,
  });

  factory AccessTokenResult.success({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) {
    return AccessTokenResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
      isSuccess: true,
      isPending: false,
      isSlowDown: false,
    );
  }

  const AccessTokenResult.pending({this.isSlowDown = false})
      : accessToken = '',
        refreshToken = '',
        expiresIn = 0,
        isSuccess = false,
        isPending = true,
        errorMsg = null;

  factory AccessTokenResult.error(String msg) {
    return AccessTokenResult(
      accessToken: '',
      refreshToken: '',
      expiresIn: 0,
      isSuccess: false,
      isPending: false,
      isSlowDown: false,
      errorMsg: msg,
    );
  }
}
