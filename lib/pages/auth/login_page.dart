import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';

import '../../services/youtube_auth_service.dart';

/// YouTube Device OAuth 2.0 Activation Login Screen
/// Strictly matches SmartTube V2 device code login UX logic.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final YouTubeAuthService _authService = YouTubeAuthService();
  DeviceCodeResult? _deviceCodeResult;
  bool _isLoadingCode = true;
  bool _isFetchingAccounts = false;
  bool _isWebViewOpen = false;
  String? _errorMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchDeviceCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDeviceCode() async {
    setState(() {
      _isLoadingCode = true;
      _errorMessage = null;
    });

    final DeviceCodeResult codeResult = await _authService.getDeviceCode();

    if (!mounted) return;

    if (codeResult.isError || codeResult.deviceCode.isEmpty) {
      setState(() {
        _isLoadingCode = false;
        _errorMessage = codeResult.errorMsg ?? '获取配对激活码失败，请重试';
      });
    } else {
      setState(() {
        _deviceCodeResult = codeResult;
        _isLoadingCode = false;
      });

      _startAutoPolling(codeResult);
    }
  }

  void _startAutoPolling(DeviceCodeResult codeResult) {
    _pollTimer?.cancel();
    final interval = codeResult.interval.clamp(3, 10);

    _pollTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      final AccessTokenResult tokenResult = await _authService.pollAccessToken(
        codeResult.deviceCode,
      );

      if (!mounted) return;

      if (tokenResult.isSuccess) {
        _pollTimer?.cancel();

        if (mounted) {
          setState(() {
            _isFetchingAccounts = true;
          });
        }

        // Fetch real user accounts & brand profiles via Innertube API
        try {
          await _authService.fetchAccountsList(
            tokenResult.accessToken,
            tokenResult.refreshToken,
          );

          if (!mounted) return;

          // If the in-app authorization WebView is open on top, pop it first!
          if (_isWebViewOpen && Navigator.canPop(context)) {
            Navigator.of(context).pop();
            _isWebViewOpen = false;
          }

          // Now pop LoginPage returning true to ProfilePage
          if (mounted && Navigator.canPop(context)) {
            Navigator.of(context).pop(true);
          }
        } catch (e) {
          _pollTimer?.cancel();
          if (!mounted) return;

          // If webview open, pop webview so user sees error on LoginPage
          if (_isWebViewOpen && Navigator.canPop(context)) {
            Navigator.of(context).pop();
            _isWebViewOpen = false;
          }

          setState(() {
            _isFetchingAccounts = false;
            _errorMessage = e.toString().replaceAll('Exception: ', '');
          });
        }
      } else if (!tokenResult.isPending && tokenResult.errorMsg != null) {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _errorMessage = tokenResult.errorMsg;
          });
        }
      }
    });
  }

  Future<void> _openAuthorization(String userCode, String activationUrl) async {
    await Clipboard.setData(ClipboardData(text: userCode));

    final normalizedUrl = activationUrl.startsWith('http')
        ? activationUrl
        : 'https://$activationUrl';

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('配对码已自动复制至剪贴板')));

    _isWebViewOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AuthorizationWebViewPage(url: normalizedUrl),
      ),
    );
    _isWebViewOpen = false;
  }

  Future<void> _openAuthorizationExternally(String userCode, String url) async {
    await Clipboard.setData(ClipboardData(text: userCode));

    final normalizedUrl = url.startsWith('http') ? url : 'https://$url';
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(normalizedUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched ? '配对码已复制，请在浏览器中完成授权' : '配对码已复制，请手动访问 $normalizedUrl',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userCode = _deviceCodeResult?.userCode ?? '';
    final activationUrl =
        _deviceCodeResult?.verificationUrl ?? 'https://youtube.com/activate';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '登录账号',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoadingCode
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: colorScheme.primary),
                  const SizedBox(height: 20),
                  const Text('正在获取 YouTube TV 官方设备许可码...'),
                ],
              ),
            )
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _fetchDeviceCode,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新获取'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Header Banner Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            Icons.qr_code_2,
                            color: colorScheme.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SmartTube TV 设备码登录',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '遵循 YouTube TV 官方 OAuth 2.0 协议',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Step 1: Activation URL
                Text(
                  '第一步：使用手机或电脑浏览器访问网址',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.language,
                        size: 22,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          activationUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.open_in_browser),
                        tooltip: '在浏览器中打开授权页',
                        onPressed: () => _openAuthorizationExternally(
                          userCode,
                          activationUrl,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Step 2: Device Code
                Text(
                  '第二步：在激活页面中输入下方设备配对码',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            userCode,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4.0,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: userCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('设备配对码已复制')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('复制配对码'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Polling Status Indicator
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isFetchingAccounts
                              ? '授权成功，正在通过 InnerTube API 获取账户资料...'
                              : '正在实时轮询授权状态，完成授权后自动登录...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Main Action Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await _openAuthorization(userCode, activationUrl);
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text(
                      '前往授权',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AuthorizationWebViewPage extends StatefulWidget {
  const _AuthorizationWebViewPage({required this.url});

  final String url;

  @override
  State<_AuthorizationWebViewPage> createState() =>
      _AuthorizationWebViewPageState();
}

class _AuthorizationWebViewPageState extends State<_AuthorizationWebViewPage> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted && progress != _progress) {
              setState(() => _progress = progress);
            }
          },
          onWebResourceError: (error) {
            debugPrint('Authorization WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openInBrowser() async {
    try {
      await launchUrl(
        Uri.parse(widget.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Nothing else to offer: the embedded page stays visible.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: _handleBack,
        ),
        title: const Text('账号授权'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '在浏览器中打开',
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100)
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress / 100,
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
