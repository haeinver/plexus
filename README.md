# Plexus

[中文](README.md) | [English](README_EN.md)

<p align="center">
  <img src="assets/icon/app_icon.png" alt="Plexus icon" width="128">
</p>

Plexus 是一个使用 Flutter 和 Material 3 构建的 YouTube TV 客户端，面向 Android、Windows、Linux、macOS、iOS 和 Web。它以真实 TV HTML5 浏览数据为基础，提供首页、分类、搜索、订阅和视频详情功能。

## 免责声明与版权声明

> 本节是一般性项目说明，不构成法律意见。

- **Plexus 是非官方、独立的第三方客户端。** 本项目不隶属于、未获得 YouTube、Google LLC 或任何相关主体的授权、赞助或认可。YouTube、Google 及其相关商标、名称、徽标和服务均归其各自所有者所有。
- **本项目不进行商业化。** 维护者不通过本项目收取费用、展示广告、接受付费赞助、出售用户数据或以该项目直接盈利；除非另行发布明确的书面说明，否则不存在商业赞助、赞助商或付费背书关系。
- **本项目不托管、镜像或提供 YouTube 内容。** Plexus 不存储任何第三方视频、音频、字幕、封面或上传者内容，不经营或提供媒体文件下载、离线缓存或播放资源代理服务。
- 播放功能只在用户主动打开内容时，通过公开或用户已授权的网络接口解析并请求相应媒体地址。视频流的播放、缓冲及可用性由 YouTube 或第三方服务及其条款控制。
- 本项目不绕过、破坏或规避访问控制、数字版权管理、年龄验证、地区限制或其他平台保护措施。若接口、数据或服务条款发生变化，本项目可能失效或停止相关功能。
- 应用可能保存登录状态、账号标识、搜索历史、主题偏好等本地用户数据。敏感登录信息应通过系统安全存储保存；具体行为以本仓库当前源码和平台权限为准。
- 用户应遵守 YouTube 服务条款、适用版权法、隐私法以及所在地法律。用户对使用本项目、访问第三方内容以及分享、保存或播放受保护内容的行为自行承担责任。
- 不保证任何内容、链接、接口、播放地址或功能持续可用、合法、准确或无侵权；本项目按“现状”和“可用状态”提供，不提供明示或默示担保。
- **侵权通知与下架请求：** 如果您认为本仓库中的代码、文档、资源或链接侵犯了您的合法权益，请先通过本仓库维护者公开提供的联系方式、Issue 或相应平台投诉渠道直接联系；无意扩大影响或诉诸公开争议。请附上权利证明、侵权位置及期望处理方式。维护者收到有效、可核实的通知后会立即停止相关分发并进行核查，确认后尽快删除相关代码、资源或仓库副本；如权利方明确要求移除整个仓库，维护者将配合立即下架，不希望让事情升级或闹大。
- 因本项目无法控制第三方平台、第三方链接或第三方内容，维护者不为第三方站点、版权方或平台的操作承担责任。仓库维护者保留根据法律或平台要求修改、限制、暂停或删除全部或部分代码的权利。
- 使用者不得利用本项目上传、分发或传播未经授权的受版权保护内容，也不得将本项目用于绕过平台保护、商业盗播或其他非法目的。

本项目仅供个人学习、研究和技术交流，不以盈利为目的。接收善意侵权通知后，维护者会优先采取非对抗性、快速和直接的处理方式，但不能承诺构成法律豁免或消除第三方平台带来的风险。

## 功能

- 首页：加载实时 YouTube TV 首页横栏和分页内容。
- 分类：浏览全部、音乐、游戏和直播内容。
- 搜索：支持关键词搜索、搜索建议、搜索历史及按栏加载更多。
- 订阅：登录后查看订阅频道、频道动态和频道筛选。
- 视频详情：使用 `media_kit` 播放、暂停、拖动进度、切换画质和全屏。
- 播放源：优先解析自适应视频与音频流，最高保留到 1080p；不支持分离音轨时回退到 HLS/muxed 流。
- 内容路由：普通视频、直播、Shorts、播放列表、频道和浏览入口使用各自的目标页面。
- 界面：支持明暗主题切换和 Material 3 导航。

## 播放说明

当前播放链路使用 `youtube_explode_dart` 和 Android SDK-less YouTube 客户端解析媒体源，再由 `media_kit` 播放。

- 登录请求失败后会匿名重试。
- YouTube 的机器人校验、地区限制、年龄限制或网络出口限制可能导致无法获取播放地址。
- 播放源解析失败时会显示真实错误和重试按钮，不会用缩略图伪装成正在播放。
- 项目目前不包含 TV PO token、SABR 解码或代理播放链路。
- 直播流和 Shorts 的完整播放能力不属于当前实现承诺。

## 环境要求

- Flutter 3.47 或兼容的新版稳定版
- Dart 3.13.5 或兼容版本
- Android 构建需要 JDK 17 和已配置的 Android SDK
- Windows 桌面构建需要对应的 Flutter Windows 工具链
- Linux 构建需要 `libwebkit2gtk-4.1-dev`（应用内授权页使用 WebKitGTK），运行分发包的机器需要安装 `webkit2gtk-4.1`
- Windows 运行应用内授权页需要 Microsoft Edge WebView2 Runtime（Windows 10/11 通常已预装）

## 安装与运行

```powershell
flutter pub get
flutter run
```

指定设备运行：

```powershell
flutter devices
flutter run -d <device-id>
```

常用平台构建：

```powershell
flutter build apk --release
flutter build windows --release
flutter build web --release
```

Android release APK 默认位于：

```text
build/app/outputs/flutter-apk/app-release.apk
```

## 测试与检查

运行全部测试：

```powershell
flutter test
```

运行播放服务测试：

```powershell
flutter test test/video_playback_service_test.dart
```

运行静态分析：

```powershell
flutter analyze
```

## 项目结构

```text
lib/
  app.dart                  应用根组件和主题切换
  main.dart                 启动与 media_kit 初始化
  models/                   视频、频道和分页数据模型
  pages/
    home/                   首页、浏览目的页和条目路由
    category/               分类、音乐、游戏和直播
    subscription/           登录和订阅频道
    search/                 搜索、建议词和历史
    player/                 普通视频、直播和 Shorts 页面
    profile/                账号和主题设置
  services/                 YouTube 数据、认证和播放源解析
  theme/                    Material 主题
  widgets/                  卡片、加载和续载状态组件
 test/                       Widget、数据解析和播放服务测试
 assets/icon/                应用图标
```

## 技术栈

- Flutter / Dart
- Material 3
- `media_kit` 与 `media_kit_video`
- `youtube_explode_dart`
- `flutter_secure_storage`
- `webview_all`（跨平台应用内 WebView）
- `url_launcher`
- HTTP / YouTube TV HTML5 API

## 开发约定

- 保留现有用户和工作区修改，不要用提交覆盖未提交内容。
- 不伪造不存在的播放地址、标题、角标或分页 token。
- 未知 renderer 或缺失必需字段应抛出明确错误，不应静默降级。
- 播放源和播放控制应与页面 UI 分层。
- 修改 Dart 文件后运行格式化、相关测试和分析。

## 发布与版本 Tag

推送符合 `v*.*.*` 格式的 Git 标签会自动构建并发布 Release：

```powershell
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会构建 3 种 Android ABI APK，以及 Windows、Linux、macOS、Web 和未签名 iOS 包，自动汇总从上一个 `v*.*.*` tag 到当前 tag 的提交标题和提交正文，并生成完整差异比较链接与 SHA-256 校验清单。iOS 未签名包不能直接用于 App Store 或未授权设备；如需签名安装或上架，需要配置 Apple 签名证书和描述文件。

## 许可证

Plexus 源代码采用 [GNU Affero General Public License v3.0（AGPL-3.0）](LICENSE) 许可。完整许可证文本见根目录 [LICENSE](LICENSE)。

依据 AGPL-3.0：修改并分发本项目，或通过网络向用户提供修改后的版本时，需要向相应接收者提供相应源代码，并保留许可证与版权声明。不得移除、替换或隐藏适用的许可证信息。

AGPL-3.0 不改变 YouTube、Google、Flutter 或其他第三方依赖所拥有的权利；本项目使用的第三方库仍按其各自许可证授权。分发前请核对依赖许可证、商标和第三方服务条款。
