# Plexus AI Handoff

## 新聊天首次会话必读

每次新建聊天后的首次会话，AI 都必须先将本文件从头到尾逐行完整详细读取，并把其中的项目上下文与工作约定导入自己的持久记忆（仓库记忆）。完成后再开始处理任务；不得只依赖旧聊天记录或已有记忆。后续工作仍须以当前仓库中的本文件和源代码为准，并重新核对可能过时的状态信息。

本文是 Plexus 后续 AI 助手的项目上下文与工作约定。开始改首页、YouTube 数据解析或导航前，先读本文和相关源文件；不要只根据旧聊天结论推断当前代码。

## 给接手 AI 的工作提示

将下面这段提示交给接手的 AI：

```text
你正在维护 Plexus，一个 Flutter/Material 3 的 YouTube TVHTML5 客户端，本机原项目路径为 `D:\Microsoft Edge下载\SmartTube-master\SmartTube-master`。开始工作前先读仓库根目录的 AI_HANDOFF.md，并查看当前 git status 与目标文件的最新内容；保留所有已有的用户修改。

首页横栏条目不全是视频。必须按 renderer 类型和 endpoint 决定动作，不能只看是否有 videoId。不要伪造 ID、标题、卡片或 continuation token；路由关键字段缺失、相互冲突或遇到未知 renderer 时，带上字段上下文直接报错，不要静默吞掉或退化成普通视频。只显式排除文档列出的已知非媒体 renderer。

修改前先提出一个可证伪的本地假设和最小验证；先找真实响应结构或 SmartTube MediaServiceCore fixture，再改代码并补回归测试。不要混淆首页 section-list continuation 和单栏 horizontal continuation。完成 Dart 修改后使用 Dart formatter，运行 flutter test 和相关 flutter analyze，并对运行中的 Flutter app 热重载或热重启；涉及界面时用新的 ADB 截图确认。除非用户明确要求，否则不要提交；用户要求提交时，只提交本次相关文件，commit subject/body 使用英文详细编写。
```

## 项目入口

- [lib/main.dart](lib/main.dart)、[lib/app.dart](lib/app.dart)：应用启动和根 widget。
- [lib/pages/home/home_page.dart](lib/pages/home/home_page.dart)：首页 progressive feed、横栏 UI、横向单栏续载及条目导航。
- [lib/pages/home/browse_destination_page.dart](lib/pages/home/browse_destination_page.dart)：browse endpoint 目的页及其列表续载；可通过 `destinationType` 标识 playlist、track、channel 或通用 browse 页面。
- [lib/pages/home/item_destination_pages.dart](lib/pages/home/item_destination_pages.dart)：playlist、track、channel、browse entry MVP 页面及共享 `VideoItemType` 点击路由；首页、Browse 列表和分类 feed 共用 `openVideoItemDestination()`。
- [lib/pages/search/search_page.dart](lib/pages/search/search_page.dart)：真实搜索界面，提交、建议词、历史、按栏续载及共享条目路由均已接线；变更前以当前代码复核。
- [lib/pages/category/category_page.dart](lib/pages/category/category_page.dart)：分类界面，拥有唯一的 Scaffold、AppBar 和分类 chips；私有 `_CategoryChip` 仅在本文件使用。音乐与游戏仍在其内容区域内切换，不 push 新路由。
- [lib/pages/subscription/subscription_page.dart](lib/pages/subscription/subscription_page.dart)：认证的 `FEsubscriptions` TV browse、真实频道 tabs、频道筛选、订阅 feed continuation 与登录门控。
- [lib/pages/category/music_page.dart](lib/pages/category/music_page.dart)、[lib/pages/category/gaming_page.dart](lib/pages/category/gaming_page.dart)、[lib/pages/category/live_page.dart](lib/pages/category/live_page.dart)：音乐、游戏、直播内容的独立 widget 文件，嵌入原分类界面显示。
- [lib/pages/category/category_topic_feed_page.dart](lib/pages/category/category_topic_feed_page.dart)：音乐/游戏/直播共享真实 topic feed、刷新、全局及单栏续载与条目导航；只返回内容，不创建 Scaffold/AppBar。
- [lib/services/youtube_data_service.dart](lib/services/youtube_data_service.dart)：TVHTML5 browse/search 请求、renderer 解析及全局/单栏 continuation。
- [lib/models/video.dart](lib/models/video.dart)：首页条目及路由语义。
- [lib/models/video_section.dart](lib/models/video_section.dart)：首页栏/浏览页的数据和 continuation 状态。
- [lib/pages/player/special_video_pages.dart](lib/pages/player/special_video_pages.dart)：Shorts 与直播/即将直播的 MVP 详情页面。
- [lib/pages/player/video_detail_page.dart](lib/pages/player/video_detail_page.dart)：普通视频当前详情页；截至本次交接更新已接入 `media_kit` 真实播放（进度/时长/seek/全屏/错误均由 player state 驱动），source 由 `YouTubeVideoPlaybackService` 提供，加载失败时显示可重试的真实错误；当前受 YouTube 网络风控影响，详见文末 2026-11-14 记录。
- [lib/widgets/feed_continuation_status.dart](lib/widgets/feed_continuation_status.dart)：首页与分类 topic feed 共用的首次加载、下拉重建刷新和纵向 continuation 状态；加载文案由页面传入。
- [lib/widgets/video_card.dart](lib/widgets/video_card.dart)：首页与搜索共用的缩略图卡片，只显示 `Video.thumbnailBadgeText`。角标文案来自 YouTube thumbnail overlay，可能是时长、合辑或状态文本；不要按 `itemType` 另造重复角标。`Video` 不再有独立的 `duration` 字段。
- [test/youtube_data_service_test.dart](test/youtube_data_service_test.dart)：解析器和 endpoint/continuation 回归测试。

依赖较少，主要运行方式：

```powershell
flutter pub get
flutter test
flutter test test/youtube_data_service_test.dart
flutter analyze
```

## 首页条目语义

`Video` 是兼容多种首页条目的通用数据对象，并不意味着一定可播放。`VideoItemType` 当前包括：

| 类型                | 关键数据                         | 点击动作                                                        |
| ------------------- | -------------------------------- | --------------------------------------------------------------- |
| `video`             | `id`                             | 普通视频打开现有详情页；`isLive`/`isUpcoming` 转到直播 MVP 页面 |
| `shorts`            | `id`，来自 Reel endpoint         | 打开专用 Shorts poster/details 页                               |
| `track`             | `browseId`                       | 打开带“音乐”身份头的 browse 目的页                              |
| `playlist`          | `browseId`，或 `id + playlistId` | 打开带“播放列表”身份头的 browse 目的页，不转入视频详情页        |
| `channel`           | `browseId`                       | 打开带“频道”身份头的 browse 目的页                              |
| `browseDestination` | `browseId`                       | 打开带“浏览内容”身份头的 browse 目的页                          |

`isLive`、`isUpcoming` 是状态，不是额外的条目类型。不要根据卡片是否有缩略图决定播放动作，也不要因 `contentType` 名称含 `VIDEO` 就忽略实际 endpoint。

## 类型专用 MVP 页面

- 普通 `video` 仍进入既有 `VideoDetailPage`；直播/预告状态优先进入 `LiveEventDetailPage`。
- `shorts` 进入 `ShortsDetailPage`，用竖屏 poster 展示标题/频道；它不伪称已经连接真实视频流。
- `track`、`playlist`、`channel`、`browseDestination` 分别进入 `TrackDetailPage`、`PlaylistDetailPage`、`ChannelDetailPage`、`BrowseEntryDetailPage`。
- 这几类目的页是可进入的 MVP，不代表已实现订阅、播放队列、音乐播放器等完整业务。只展示源数据真实提供的标题、缩略图和必要 endpoint 信息，不造播放量、订阅数或列表内容。
- 首页、Browse 列表和分类音乐 feed 必须共用 `openVideoItemDestination()`，不能根据当前页面把同一种 `VideoItemType` 路由到不同目标。新增 `VideoItemType` 时，更新共享路由 helper、Browse 目的页类型头和 widget/parser 测试。

## 真实视频播放：状态与后续约定

### 当前状态（2026-11-11）

- `VideoDetailPage` 仍是模拟页面：播放器区域用 `Image.network(thumbnailUrl)` 和黑色遮罩，不是真实视频画面；`_isPlaying` 只切换图标；进度条固定使用 `0.35`，时间文案固定为 `05:12`；画质对话框列出写死的选项；频道订阅者数和点赞/收藏/下载/分享动作也不是来自播放服务的真实状态。不要在产品文案或交接中称这些控件已能真实播放、切换画质或执行远端 mutation。
- `Video.videoUrl` 当前是由 parser 生成的 `https://www.youtube.com/watch?v=...` 页面 URL（playlist 场景可能附 playlist query），不是 HLS/DASH/渐进式媒体 URL；不得直接把它传给 `media_kit` 并将其称为已接入真实播放。保留 `VideoItemType` 和 `openVideoItemDestination()` 的 endpoint 路由语义：只有普通 `video` 进入 `VideoDetailPage`；直播/预告和 Shorts 仍走各自类型页面，除非后续以真实数据和测试明确扩展。
- `pubspec.yaml`/`pubspec.lock` 当前已声明并锁定：`media_kit: 1.2.6`、`media_kit_video: 2.0.1`、`media_kit_libs_video: 1.0.7`、`youtube_explode_dart: 3.1.0`。截至本次复读，`lib/` 尚无这些包的 import、初始化或播放器实例，故依赖存在不代表播放已集成。插件注册生成文件也有未提交变化；开始时检查 `git status`，保留用户修改，不要盲目重写 registrant 或 lockfile。
- 用户已指定真实播放引擎使用 `media_kit: ^1.2.6`。`media_kit` 是媒体播放/解码层，不负责把 YouTube watch 页面转换成可播放 source；播放 source 获取仍是独立、尚未解决并验证的边界。`youtube_explode_dart` 已在依赖中但当前未使用；后续需先核实其当前 API、平台兼容性、授权/使用约束和真实视频可用性，不能仅因依赖已存在就假设解析稳定。

### 原 SmartTube 播放链路

- TV 页面入口是 `smarttubetv/src/main/java/com/liskovsoft/smartyoutubetv2/tv/ui/playback/PlaybackActivity.java` 与 `PlaybackFragment.java`；`PlaybackFragment` 用 ExoPlayer 建立播放引擎，并委派给 `PlaybackPresenter`。
- `common/src/main/java/com/liskovsoft/smartyoutubetv2/common/app/presenters/PlaybackPresenter.java` 协调当前 `Video` 与 playback controllers。`common/.../models/playback/controllers/VideoLoaderController.java` 在播放新视频时调用 `YouTubeServiceManager.instance().getMediaItemService().getFormatInfoObserve(video.videoId)` 获取 `MediaItemFormatInfo`。
- `VideoLoaderController.processFormatInfo()` 根据真实格式信息分支：普通 adaptive DASH、SABR、直播 DASH/HLS 或 URL formats；不可播放和空格式有明确错误/重试流程。`common/.../exoplayer/controller/ExoPlayerController.java` 和 `common/.../exoplayer/ExoMediaSourceFactory.java` 负责把格式信息构成 ExoPlayer `MediaSource`。这些是 SmartTube 的架构参考，不等于 Plexus 已具备同样协议能力。
- 原项目 `.gitmodules` 中 `MediaServiceCore` 指向 `https://github.com/yuliskov/MediaServiceCore`，但本机 `MediaServiceCore` 子模块目录为空；缺失的接口和真实 player/format fixtures 不能从当前 checkout 假定已完整核查。必要时可按本文件既有约定 clone 到 `%TEMP%` 只读检查，勿把整份依赖副本或大 fixture 加入 Plexus。不要把 SmartTube 的 ExoPlayer/SABR 实现伪称为 media_kit 可直接复用。

### 后续实现要求

- 播放源解析、播放控制与 Flutter UI 分层；页面不能自己拼造流 URL。仅使用已验证、当前视频对应的实际 media source 和必要请求头；临时/签名 URL 不应写回通用 `Video` 模型或持久化。解析失败应显示真实、可重试的错误，不得退回缩略图伪装成播放成功。
- 用 `media_kit` 的真实 player state 驱动画面：初始化、解析 source、buffering、playing、paused、completed 和 error 状态；进度、时长、seek、play/pause 必须读写播放器状态，不能用固定时长或模拟 slider。离开页面时释放 controller/player，处理异步加载期间页面销毁、快速切换视频和旧请求回写。
- 按实际 source 提供的能力呈现轨道/画质选项；只有服务端返回且播放器支持的 audio/video/subtitle tracks 才能作为选项。没有实现远端操作的订阅、点赞、下载等按钮不可显示成功假反馈。
- 按 `media_kit` 1.2.6 及配套包的实际文档/本地 package API 核对初始化、video surface、播放器销毁和目标平台原生库配置；新增平台 manifest/registrant/build 配置前先验证 Android（本项目运行设备）和其他 declared targets，不要只按新版本示例臆测 API。
- 补针对 source 解析、状态迁移、seek/暂停恢复、加载失败及页面 dispose 的测试。用授权可播放的真实 YouTube 视频在设备上验证画面、声音、缓冲、进度、暂停/恢复和失败提示；截图/测试报告只能证明实际观察到的状态。
- 本次更新只记录调查结果和后续约束；未添加播放器实现、未更改依赖，也未声称接入真实流。继续实现前重新核对工作区、原项目/MediaServiceCore 当前内容及包 API。

### Endpoint 分类规则

这些规则集中在 `YouTubeDataService._parseTileRenderer` 及其 endpoint 分类 helper 中：

- `TILE_CONTENT_TYPE_VIDEO`：必须能从**唯一 endpoint**识别动作。`watchEndpoint` 是视频；`reelWatchEndpoint` 是 Shorts；`browseEndpoint` 按 browse ID 分类。
- `TILE_CONTENT_TYPE_VIDEO` 的 `onSelectCommand` 也可能使用 `commandExecutorCommand.commands` 包装动作。只在命令列表中存在且仅存在一个 `watchEndpoint`、`reelWatchEndpoint` 或 `browseEndpoint` 时分类；当前已由实机响应确认的 `feedbackEndpoint` 可作为 sidecar 忽略。未知命令、多个媒体 endpoint、缺少 endpoint 或无效结构仍须报 `FormatException`，不能把任意 command executor 当作播放动作。
- executor 中的 watch endpoint 若提供 `playlistId`，应保留在 `Video` 和对应的 watch URL 中，不要丢掉真实播放上下文。
- browse ID 以 `VL` 开头时按 playlist browse 处理；其他 browse ID 是普通 browse destination。此判断应由真实 YouTube/SmartTube fixture 支撑，若格式变化先增加真实样例和测试，不要猜前缀。
- `TILE_CONTENT_TYPE_SHORTS` 必须有 `reelWatchEndpoint`。
- `TILE_CONTENT_TYPE_PLAYLIST` 支持两种互斥形态：`browseEndpoint`，或同时含 `videoId` 与 `playlistId` 的 `watchEndpoint`。缺字段或两者并存都报错。
- `TRACK`、`CHANNEL` 使用 browse endpoint。
- 没有 `contentType` 时，只能在唯一 endpoint 明确时推断；endpoint 缺失、多 endpoint 冲突或 renderer 未知都直接失败。

## Continuation：不要混淆两层

### 首页全局 section-list continuation

首页响应路径为 `tvBrowseRenderer → tvSurfaceContentRenderer → sectionListRenderer`。后续响应可能是顶层 `sectionListContinuation`，也可能是 `tvSurfaceContentContinuation.content.sectionListRenderer`；它包含多条 shelf，每条 shelf 有自己的原生标题和一组条目。

音乐首栏可能通过 `headerRenderer.heroCarouselHeaderRenderer.header.shelfHeaderRenderer.title` 提供标题，而不是 shelf 直接标题或常规 `headerRenderer.shelfHeaderRenderer.title`。解析时读取该原生路径；不要因首栏无常规 shelf header 就生成标题或丢掉真实标题。

`fetchHomeFeedProgressively()` 负责按首页级 token 请求并逐步 yield 新的有标题 sections。全局 token 的来源遵循 SmartTube `SectionListContinuation.getContinuationToken()` 语义：先读 section-list 自身 `continuations`，必要时读第一条 shelf 的 horizontal continuation。**不得把任意 `gridButtonRenderer.loadReloadContinuationCommand` 提升为全局首页 token。**某些 refresh-only 按钮只是控制项；若把它当 root token 循环请求，会造成首页不断追加横栏。

只含已知 reload 控制项的 shelf 不显示为 section，不得生成无标题横栏。首页纵向 `ListView` 只呈现已经拿到的 sections；纵向滚动不应直接发起横栏 continuation 请求。若用户报告“向上滑无限增加横栏”，先查全局 token 来源和 `fetchHomeFeedProgressively()` 循环，不要先改纵向列表触发器。

### 单栏 horizontal continuation

`VideoSection.continuationToken` 也可能属于某个 shelf 的 horizontal continuation。`_HomeFeedSection` 仅在**横向**滚动/横向 metrics 接近尾部时调用 `_loadMoreSection()`；它更新当前 section 的视频，不应创建新的无标题 section。

单栏 continuation 解析需支持实际响应中的 `horizontalListContinuation`、grid/playlist renderer，以及 TV surface 下的 grid/section-list 外壳。多 shelf 的条目合并到当前组时应保留并去重现有 item，token 取自对应 continuation 数据。不要把这两种 continuation 混为同一 UI 动作。

实机曾观察到 HTTP 200 的横向 continuation 响应只有 `responseContext` 和 `trackingParams`，没有列表或下一页数据；不要把它当作正常结束并清除 token，否则会隐藏续载失败。SmartTube `AppClient.TV.browseTemplate` 提供 `tvAppInfo`、`webpSupport`、`animatedWebpSupport`，`QueryBuilder` 在 visitor data 可用时也会放入 `context.client.visitorData`；其所有 browse continuation POST 还会带 `racyCheckOk: true` 和 `contentCheckOk: true`。本项目应匹配这些 TV browse context 字段，并从响应的 `responseContext.visitorData` 更新后续请求。若响应仍是 metadata-only，应继续展示脱敏结构错误并检查 token/请求上下文，不要把失败伪装成栏位耗尽。

栏头 `moreContentButton` 是另一种语义：它含 `browseEndpoint` 时表示进入目的页，可渲染为栏尾 browse 入口。它不等于 continuation token，也不能因为它存在就自动启动无限分页。

## 错误和非媒体节点

- 解析结构不完整或未知时抛出 `FormatException`，错误应包含 renderer/endpoint 的字段名和可用的脱敏结构；不要记录认证 header、token 或其他秘密值。
- 不要把 browse-only item 改成 video，不要补造 `videoId`、标题或缩略图，也不要把错误转换成空视频列表。
- 已知非媒体结构要显式处理：`adSlotRenderer`、`continuationItemRenderer`、已确认的 `appealSurveyShelfRenderer`。这不是通用 catch-all；其他未知 renderer 继续报错。
- `gridButtonRenderer` 需检查具体 navigation command。`signalServiceEndpoint`/soft reload 与真正 continuation 不是同一个动作；不能只看按钮标题“更多”或“刷新”就决定行为。已由实机确认 `clientActionEndpoint.action.actionType == OPEN_SIGN_IN_PROMPT` 是登录提示控制项，可显式忽略且不能产生 continuation token；其他 client action 仍按未知动作报错。
- `commandExecutorCommand` 只按已确认的 renderer 上下文和命令类型处理；错误上下文可用 `_describeJsonShape` 输出字段名/类型，禁止输出 tracking 参数、ID、token 或原始秘密值。
- 加载失败应留在页面上并显示真实错误，不能静默退回 mock 数据。

## Feed 加载与刷新

- 首页及分类界面中的音乐/游戏/直播内容使用 `FeedInitialLoading`、`FeedRefreshIndicator`、`FeedContinuationStatus`；topic feed 由 `CategoryTopicFeedPage` 共享加载和刷新行为。代码按文件拆分时保持原界面行为：分类 Scaffold、AppBar 和 chips 留在 `CategoryPage`，topic widget 只渲染内容，切换分类不 push 新路由或创建额外 Scaffold。首次加载文案由页面显式传入，公共 widget 只统一布局和主色，不要硬编码成首页文案。
- 游戏分类使用 SmartTube `MediaServiceCore` 确认的 `FEtopics_gaming` browse ID，通过 TVHTML5 未登录请求获取真实数据。SmartTube `BrowsePresenter` 将 `TYPE_GAMING` 映射为横向 `TYPE_ROW`，`BrowseService2.getGaming()` 使用 `getBrowseRowsTV()`。实测响应为 TV `sectionListRenderer` shelf，栏标题可位于 `shelfHeaderRenderer.avatarLockup.avatarLockupRenderer.title`，视频 tile 使用 `TILE_CONTENT_TYPE_VIDEO` 与直接 `watchEndpoint`；解析继续复用严格的 topic shelf/tile parser，不要猜测或静默接受未知 renderer。topic parser 必须将 `categoryId` 传递到递归 renderer、全局 section-list continuation 和单栏 horizontal continuation；游戏条目标记为 `gaming`，`categoryName` 保留原生 shelf 标题。点击路由依据 endpoint 得出的 `VideoItemType` 并共用 `openVideoItemDestination()`，不可因来自游戏 feed 就把频道、playlist、Shorts 强制当普通 video。
- 直播分类使用 SmartTube `MediaServiceCore` 确认的 `FEtopics_live` browse ID。SmartTube `BrowsePresenter` 将 `TYPE_LIVE` 映射为横向 `TYPE_ROW`，`BrowseService2.getLive()` 使用 `getBrowseRowsTV()`。匿名 TVHTML5 实测响应有 section-list continuation 和每栏 horizontal continuation；栏标题使用 avatar-lockup，条目为直接 `watchEndpoint` tile，直播状态通过 thumbnail overlay 的 `LIVE`/`UPCOMING` 标记。复用共享 topic feed；普通 live/upcoming video 依据状态经 `openVideoItemDestination()` 进入 `LiveEventDetailPage`。这不代表已经接入直播流播放。
- `FeedRefreshIndicator` 接收 `FeedRefreshCallback`，统一以 `rebuildFeed: true` 调用页面加载回调。首页及分类界面内音乐/游戏/直播 feed 在该模式下清空旧 sections、重置各自的 feed layout generation，并在新 feed 完成后整体展示；页面的登录、数据请求和错误处理仍由页面自身负责。
- 页面后续新增 feed 时，复用这些 widget；不要在页面重新直接构造不同参数的 `RefreshIndicator` 或另写一套首次加载 spinner。

## 订阅界面

- `SubscriptionPage` 需要 YouTube 登录态，使用 TVHTML5 `/browse` 请求 `FEsubscriptions`；未登录时显示 `SignInRequiredWidget`，账号切换后重新读取。加载错误应显示真实错误，不退回 mock 数据。
- 退订全部后的真实响应可不含 `tvSecondaryNavRenderer.sections`，而是 `tvSurfaceContentRenderer.content.genericPromoRenderer`，同时有 `tvSurfaceContentRenderer.header.tvSurfaceHeaderRenderer.title`。只有 promo `title`、`bodyText` 与 surface 标题均能解析为非空原生文本时，才按无订阅空页返回空 channels/sections；字段缺失或其他未知 renderer 继续报 `FormatException`，不能通用降级为空列表。订阅页此时显示专属“还没有订阅频道”空状态；有频道但无内容时仍显示“暂无相关订阅更新”。
- 实测响应路径为 `contents.tvBrowseRenderer.content.tvSecondaryNavRenderer.sections[].tvSecondaryNavSectionRenderer.tabs[]`。频道 tabs 从原始 `tabRenderer.title`、`endpoint.browseEndpoint.browseId/params` 与 `thumbnail` 解析；不得生成订阅数、视频数或未读状态。频道请求必须发送原 endpoint 的非空 `browseId + params`。实机返回的单个 tabs 列表在频道项之后含 `unselectable == true` 分隔项，后面会重复出现前面的频道 renderer；该标志是可选频道段的边界，解析应停止读取当前 tabs，不做通用 endpoint 去重。频道 browse 响应的 `tabIdentifier` 可能重复，UI 选择状态不得用它作为唯一键，使用频道对象身份区分条目；`全部动态` 是独立的空选择状态。响应内容以唯一 `selected == true` 的 tab 为准，且其 `endpoint.browseEndpoint.browseId` 必须与请求一致。实测该 selected tab 可能不回显 `params`；若响应提供了 `params`，必须与请求一致，矛盾时直接报带脱敏结构的 `FormatException`。缺少/多个 selected tab、缺少或冲突的 browseId、以及请求 endpoint 字段缺失均报错，不得改用 tabIdentifier 或其他 tab 猜测。
- 选中 tab 的视频内容位于 `tabRenderer.content.tvSurfaceContentRenderer.content.sectionListRenderer`。频道响应要解析该列表中的全部 sections，并保留频道自己的 section-list continuation；它与“全部动态”的 section-list continuation 及每个 `VideoSection.continuationToken` 栏内 continuation 分离。全局续页追加 sections，栏内续页只更新对应栏。条目点击仍用 `openVideoItemDestination()`。
- 选中频道后的列表初始加载、错误和 continuation 状态使用 `FeedContinuationStatus`。重复点击当前频道仍保持该频道选中，不切回“全部动态”。已访问频道缓存 sections、全局 continuation 和 token 状态；切换回缓存频道直接恢复，不自动重请求。下拉刷新按选择分流：选中具体频道时只重新请求该频道的 browse endpoint 并重建其 sections，不刷新/清空频道目录或“全部动态”feed；刷新期间保留已有频道 sections，由外层 `RefreshIndicator` 单独显示加载状态，内层 `FeedContinuationStatus` 不得再显示第二个 spinner。选择“全部动态”时才刷新 `FEsubscriptions` 全局 feed；全局重建/账号切换清空频道缓存。
- 频道列表是服务器订阅关系的只读展示/筛选；本项目尚未实现 subscribe/unsubscribe mutation。不要用本地状态切换提示“已订阅/已取消订阅”，也不要声称已修改 YouTube 订阅。

## 搜索界面现状

- `SearchPage` 已接入真实搜索工作流：调用 `fetchSearchResults()` 与 `fetchSearchSuggestions()`，通过 `SearchHistoryStore` 保存/恢复历史，按栏续载结果，并通过 `openVideoItemDestination()` 统一处理结果点击。suggestions 是查询建议，不应描述为已验证的热门榜单。
- 搜索结果卡片在 UI 层按原顺序跨 section 放入同一个两列网格，避免每个奇数条目 shelf 独立起网格产生空槽；browse/query 操作和加载状态仍按原 section 顺序展示，section 数据与 continuation token 不合并。
- `YouTubeDataService` 提供 TVHTML5 `/search`、`fetchSearchResults()`、`fetchMoreSearchSectionVideos()` 和初始/continuation parser。请求以 `query` 和 TV browse context 提交，带 `racyCheckOk`、`contentCheckOk`；`estimatedResults` 可选。
- 匿名 TV 实测响应为 `contents.sectionListRenderer.contents`，结果按 `shelfRenderer` 分组；当前样本条目为 `lockupViewModel`。标题路径为 `metadata.lockupMetadataViewModel.title`，缩略图路径为 `contentImage.thumbnailViewModel.image`，点击命令来自 `rendererContext.commandContext.onTap.innertubeCommand`。endpoint 必须继续决定 `VideoItemType`，不能将所有搜索结果强制当成 video。
- 搜索续页应按对应 `VideoSection.continuationToken` 单栏续载；TV search continuation 当前实测外壳为 `continuationContents.sectionListContinuation`。SmartTube v2 也把响应映射为多个 `SearchSection`，并按组调用 `continueSearch()`；不要把组级 continuation 合并为首页全局分页。
- 搜索 lockup 的图标角标可没有 `thumbnailBadgeViewModel.text`；显示文本回退到 `rendererContext.accessibilityContext.label`，状态从 `badgeStyle` 或已知本地化文案（`直播`、`正在直播`、`即将直播`）识别 LIVE/UPCOMING。无可显示文本的纯图标 badge 不应让整页分页失败。首页/tile 仍支持 `thumbnailOverlayTimeStatusRenderer.text`。只展示响应提供的文本，不根据条目类型臆造标签；结构错误用脱敏 shape 上下文报告。
- SmartTube 搜索参考：`common/.../app/presenters/SearchPresenter.java`（提交查询、逐组更新与滚动续载、点击委派 `VideoActionPresenter`）；`MediaServiceCore/youtubeapi/.../search/v2/SearchService2.kt`、`SearchApiHelper.java`/`SearchApiHelper.kt`（TV search query、visitor data 与结果组解析）。搜索建议由本项目调用 `fetchSearchSuggestions()`；如需改变其数据来源，应以真实响应验证，不要将建议词称作热门榜单。

## SmartTube 对照资料

本机原项目路径曾为 `D:\Microsoft Edge下载\SmartTube-master\SmartTube-master`。其 `.gitmodules` 指向 `MediaServiceCore` 和 `SharedModules`，但原 checkout 的子模块目录可能为空；不要把 ExoPlayer 的 `.dump` 分片误认为 YouTube JSON。

相关 SmartTube 逻辑可在这些文件中核对：

- `common/.../app/models/data/Video.java`：用 `videoId`、`playlistId`、`channelId`、`isLive`、`isUpcoming`、`isShorts` 等区分条目。
- `common/.../app/presenters/dialogs/VideoActionPresenter.java`：依据视频、频道、playlist、chapter 等数据分发点击动作。
- `smarttubetv/src/main/java/com/liskovsoft/smartyoutubetv2/tv/ui/playback/PlaybackActivity.java`、`PlaybackFragment.java`：TV 播放页面容器和 ExoPlayer UI/生命周期。
- `common/.../app/presenters/PlaybackPresenter.java`：播放视图与 controllers 的协调入口。
- `common/.../app/models/playback/controllers/VideoLoaderController.java`：通过 `getFormatInfoObserve(video.videoId)` 请求真实播放格式，并分派 DASH/SABR/HLS/URL source。
- `common/.../exoplayer/controller/ExoPlayerController.java`、`common/.../exoplayer/ExoMediaSourceFactory.java`：SmartTube ExoPlayer source/control 参考；不要直接假定兼容 `media_kit`。
- `common/.../app/presenters/SearchPresenter.java`：搜索提交、按组续载，点击委派统一视频动作路由。
- `MediaServiceCore/youtubeapi/.../search/v2/SearchService2.kt`、`SearchApiHelper.kt`：TV search query、search section 分组及 continuation。
- `common/.../app/presenters/BrowsePresenter.java`：单组滚动结束调用 `continueGroup()`。
- `MediaServiceCore/youtubeapi/.../browse/v2/BrowseService2.kt`：区分 `continueSectionList()` 和 `continueGroupTV()`。
- `MediaServiceCore/youtubeapi/.../next/v2/gen/WatchNextHelper.kt`：解析 `sectionListContinuation`、TV surface continuation、items、shelves 和 token。

已找到的真实 JSON fixture 在 `MediaServiceCore/youtubeapi/src/test/resources/browse/tv/`，包括 `2025.07.25_home_continuation.json`、`2025.07.30_home_continuation.json`、`2025.07.30_home.json`。若原 checkout 子模块为空，可将公开 `MediaServiceCore` 临时 clone 到 `%TEMP%` 只读检查，不要把依赖副本或大 JSON 任意复制进应用代码。原项目的 `common/src/test` app 单测数量少；真正的 YouTube response fixtures 在 MediaServiceCore。

上述 2025 TV 首页 fixture 中的 `TILE_CONTENT_TYPE_VIDEO` 使用直接 endpoint，没有覆盖实机遇到的 `onSelectCommand.commandExecutorCommand.commands` 媒体包装。该包装已由设备错误结构确认：命令列表包含一个 `watchEndpoint` 和一个 `feedbackEndpoint`。真实字段值不应复制到文档或测试；解析回归测试使用脱敏/合成值验证唯一 endpoint、feedback sidecar、歧义 endpoint 和未知 sidecar。原 checkout 的 MediaServiceCore 子模块为空时，临时 clone 到 `%TEMP%` 后可检查这些旧 fixture，但不要误称它们包含这次新发现的包装形态。

SmartTube 应用层消费的是已归一化的 `MediaGroup`/`Video`，不一定直接解析现代 Cobalt `tileRenderer`。应借用其数据语义和 continuation 分层，同时以当前真实 TVHTML5 响应为准。

## 实机验证

Flutter app 已通过 DTD 注册时，先用 DTD 列出/连接正确 workspace，再 hot reload 或 hot restart。该 app 没启用 `flutter_driver`，因此设备截图使用 ADB：

```powershell
adb devices
adb shell screencap -p /sdcard/plexus_screen.png
adb pull /sdcard/plexus_screen.png "$env:TEMP\plexus_screen.png"
```

每次检查用新的文件名，避免把旧截图当成当前状态。屏幕验证要分别检查：初始标题栏是否原样显示、首页级加载是否有限停止、尾部 reload-only 控制项有没有变成无标题横栏、横向单栏续载是否只更新本栏、纵向滚动是否仅浏览已加载 rows。

## 当前状态

- 当前 HEAD 快照：`9a63b4e`，提交标题为 `Complete search flows and consolidate category feeds`；开始工作时仍需重新核对当前 HEAD。
- 当前实现区分 item endpoint 类型、全局 section-list continuation、单栏 horizontal continuation，以及 reload-only 控制项。
- `TILE_CONTENT_TYPE_VIDEO` 已支持经实机确认的 command executor 包装；只提取唯一媒体 endpoint，并保留已提供的 `playlistId`。测试覆盖其有效和拒绝路径。
- 音乐/游戏/直播分别定义在独立 widget 文件中，但仍显示在分类界面的原内容区域，保留单一 AppBar、分类 chips 和原位切换；三者通过 `CategoryTopicFeedPage` 共用首次加载、下拉重建刷新、横栏续载及条目路由。
- 分类 chips 不是跨页面复用组件；`_CategoryChip` 保持内联在 `category_page.dart`，不恢复单独的 `lib/widgets/category_chip.dart`。
- 游戏分类通过 `FEtopics_gaming` 加载匿名真实数据；TV `sectionListRenderer`、avatar-lockup 标题和直接 `watchEndpoint` tile 结构已用匿名合成值覆盖 parser 回归测试。
- 直播分类通过 `FEtopics_live` 加载匿名真实数据；回归测试覆盖 `LIVE`/`UPCOMING` 状态路由及两层 continuation，实机已确认显示真实直播横栏。
- SearchPage 已接入真实查询、建议词、历史、按栏续载和共享点击路由；每次修改后仍须重新运行相关测试与 analyze，历史测试结果不代表当前工作区已验证。
- SubscriptionPage 已按认证 `FEsubscriptions` response 加载频道 tabs 和 section-list 视频，支持频道 browse、section-list 与单栏续载；尚未实现远端订阅/取消订阅操作。
- 截至 2026-11-11 的历史状态：`VideoDetailPage` 是模拟播放/展示页，`lib/` 未集成 `media_kit` source/player。当前进展见下方 2026-11-12 与 2026-11-14 记录。

## 播放器进展（2026-11-12）

- `VideoDetailPage` 已接入 `media_kit` `Player`/`VideoController`，播放、暂停、完成、缓冲、进度、时长、seek、全屏和 dispose 使用真实播放器状态；不显示伪造的订阅/点赞/下载成功反馈。source 解析和播放器 UI 分离，临时 stream URL 不写入 `Video`。
- `YouTubeVideoPlaybackService` 目前只请求 SmartTube 当前 `AppClient.TV` 对应的 TVHTML5 profile；实验性 PO-token provider 从同一个 `/tv` 页面会话读取 visitorData 和 living-room id。调试 probe 仅输出这些字段是否存在，以及 Authorization、X-Goog-Pageid 是否存在；不输出 video ID、header 值、原始 logger message、URL、token 或 stack trace。
- PHM110 实测两个普通推荐视频：TV `/player` manifest 请求均由 `youtube_explode_dart 3.1.0` 返回 `VideoUnavailableException`，没有得到可播放格式。该库的 TV 请求没有实现 SmartTube 的 TV PO-token 流程；`VideoUnavailableException` 只说明库没有提取到可用 streams，不能据此宣称视频源已播放或确定服务器端具体拒绝原因。
- Plexus 已添加实验性的 Android TV PO-token provider：从同一个 `/tv` 页面读取 visitor/living-room id，从 `tv_config` 读取 request key，并按 SmartTube 当前实现使用 TV `/att/get` challenge；修正了 `tv_config` 的反 XSSI 前缀及 PO-token URL-safe Base64 编码。PHM110 在上述请求下仍收到 HTTP 200、`playabilityStatus=UNPLAYABLE`、无 `formats`/`adaptiveFormats`；尝试使用 `tv_config.challengeParams.R` 也未改变结果。字段存在不代表 token 被服务器接受，真实播放仍未验证成功。
- SmartTube `AppClient.TV` 标记 `isTvPotRequired`，播放请求使用 `PoTokenGate.getPoToken()` 与 `getLivingRoomPoTokenId()`。`TvPoTokenProvider` 需要同一 `/tv` session 的 visitor data、living-room token id、`tv_config` BotGuard request key/challenge，并通过 `TvPoTokenWebView4` 生成 TV PO token；只向 `YoutubeApiClient` 添加 TV headers/clientVersion 或 visitorData 不等价于这条链路。
- SmartTube `VideoInfoService.CLIENT_LIST` 包含 TV client rotation，但每项由完整 `AppClient`/`QueryBuilder`/PO-token/signature-decipher 流程执行。不要将 `TV_DOWNGRADED` 简化成另一个 `YoutubeApiClient` profile 后声称等价；Plexus 已移除该不完整 fallback。
- 当前详情页在 source 解析失败时显示可重试的 `FormatException:` 错误；小屏播放器错误区限高并可滚动。真实视频播放仍受网络出口限制，不能将实验性 PO-token 调查作为可用修复；后续继续补 source/state/失败/dispose 测试并在授权可播放视频上做真机验证。
- 最近一次验证：`flutter test test/video_playback_service_test.dart` 的 18 项通过，相关服务和测试的 `flutter analyze` 通过。经用户确认，本轮在已连接的 SM S9280 上测试了单个公开视频：认证请求的 Authorization 存在、X-Goog-Pageid 不存在，但仍为 HTTP 200 / `UNPLAYABLE`；同一 TV PO-token 会话去掉认证 header 后返回 `LOGIN_REQUIRED`，本次对比不支持移除认证作为修复。对照 SmartTube 后，已将 TV `/att/get` 请求的 Content-Type 改为 `application/json+protobuf` 并添加回归断言（**此判断后来被推翻，见“`/att/get` 头部修正”一节**）；修正后的真机重试未到达 `/player`，PO-token 初始化先后遇到 `tv_player_script` 超时和 `tv_page` HandshakeException，之后又有一次重试在等待超过 60 秒后仍停留在加载界面、没有新的 `/player` probe，因此尚不能判断该修正是否恢复播放。该设备不是 PHM110，仍需在 PHM110 上复测。

## 播放器修复（2026-11-14）

- 默认播放链路不再经过 TV PO-token：`YouTubeVideoPlaybackService` 现在直接用 `YoutubeApiClient.androidSdkless` 请求 manifest，并继续把登录 header 作为可选项附加。原因是实测该客户端无需 PO token 就能返回可播放格式，而 TVHTML5 在相同视频上返回 `VideoUnplayableException`/`UNPLAYABLE`。
- `youtube_explode_dart 3.1.0` 的 `androidSdkless` 实测返回 1 条 muxed（360p）和 26 条 adaptive。`_sourcesFromManifest()` 优先用 adaptive video-only 流配对一条 audio-only 流（优先 AAC，其次 Opus），最高保留 1080p；没有 adaptive 轨道时回退到 muxed/HLS muxed。
- `VideoPlaybackSource` 增加 `audioUri`。`VideoDetailPage` 打开 video-only 源后通过 `player.setAudioTrack(AudioTrack.uri(...))` 加载外部音轨；暂停/播放/seek 仍由 `media_kit` 状态驱动。
- 已在 Windows 桌面用真实公开视频做端到端探针：解析到 1080p adaptive 源，`media_kit` 播放到 4 秒、时长 3:33、选中 AAC 外部音轨、无 error 事件。该探针只是本机验证，Android 真机仍需复测。
- `android/app/src/main/AndroidManifest.xml` 已补上 `android.permission.INTERNET`；此前只有 debug/profile manifest 带该权限，release 包无法联网。
- TV PO-token/BotGuard 实验实现及资产已弃用并移除，不是当前播放依赖，不再出现在源码、测试、资源或第三方许可清单中。

### PHM110 真机复测：YouTube 反机器人拦截（2026-11-14 晚）

- 结论先行：当前 PHM110 的网络出口被 YouTube 判定为“机器人流量”，匿名播放绝大多数视频都会返回 `playabilityStatus=LOGIN_REQUIRED`、`reason="Sign in to confirm you’re not a bot"`。同一网络下官方 SmartTube（`org.smarttube.stable`）也只能停在 “SABR server requested a player response reload”，因此这不是 Plexus 的解析/播放代码问题，而是网络出口 + 账号鉴权（PO token/SABR）问题。
- 设备出口与 PC 出口都是云主机 IP，均被拦截：PHM110 走 `Clash Meta` TUN（`tun0`）到 `52.197.139.226`（AWS 东京），PC 走 FlClash 到 `54.255.247.79`（AWS 新加坡）；`adb reverse tcp:17890 tcp:7890` 把手机流量转给 PC 代理后结果相同。设备上系统 `http_proxy` 对 Flutter `dart:io` 无效，应用仍走 TUN（已用应用内 egress 探针确认）。
- 用一个固定视频 `dQw4w9WgXcQ` 做对照：匿名 /player 返回 `OK` + adaptive 流；而推荐页的真实视频（如 `C0I8PPJsrmA`）返回 `LOGIN_REQUIRED`。用设备上的 curl 直连 YouTube 复现了同样结果，并逐一排除了客户端差异：ANDROID / IOS / ANDROID_VR / MWEB / WEB、补 `CONSENT` 与 `VISITOR_INFO1_LIVE` cookie、补 watch 页 `visitorData` + `playbackContext.signatureTimestamp` 均仍是 `LOGIN_REQUIRED`。
- 登录态请求的实测矩阵（PHM110、真实 TV OAuth token）：
  - `ANDROID`（`androidSdkless`，带/不带 API key）、`IOS`、`ANDROID_VR`、`WEB` → `HTTP 400` / `INVALID_ARGUMENT` / “Request contains an invalid argument.”，说明该 TV OAuth token 与这些客户端不匹配。
  - `TVHTML5` → `HTTP 200` / `UNPLAYABLE` / `reason="The page needs to be reloaded."`，无 `formats`/`adaptiveFormats`/`serverAbrStreamingUrl`/`videoPlaybackUstreamerConfig`。即 token 只被 TV 客户端接受，但 TV 客户端仍需要有效的 PO token / SABR 上下文才会下发流。
- 因此现在的代码状态是“正确的降级链，但环境不允许成功”：默认 `androidSdkless` + 登录 header，失败后匿名重试；两条路径在 PHM110 上都会被 `LOGIN_REQUIRED` 拦住。不要把 `dQw4w9WgXcQ` 的成功当成通用结论。
- 本轮新增的调试探针（均 `kDebugMode` 且 `manifestLoader == null` 时输出，不打印 token/URL/videoId）：
  - `阶段：egress`：用 `https://api64.ipify.org` 记录应用实际出口 IP，用于判断 VPN/代理走向。
  - `YouTube player error body`：`code/status/message（截断）/reasons`，用于定位 400 这类非 200 响应。
  - player 响应摘要新增 `reason=`（截断 120 字符），用于看清 `UNPLAYABLE`/`LOGIN_REQUIRED` 的具体原因文本。
- 下一步建议（按优先级）：
  1. 换能通过 YouTube 机器校验的出口（住宅/移动网络或服务商标注可看 YouTube 的节点），再用推荐页真实视频复测；如果换节点后匿名就 OK，则无需改客户端。
  2. 若必须留在云主机 IP，则需重新评估并验证 SABR 或其他可支持的播放链路；已移除的 TV PO-token 实验不应恢复为临时修复。
  3. 复测前先清理手机代理设置：`adb -s a4512963 shell settings put global http_proxy :0`，并 `adb -s a4512963 reverse --remove-all`（本轮曾临时设成 `127.0.0.1:17890`）。
- 本轮未提交任何 commit；`flutter analyze` 无问题。真机“可播放”仍未验证成功。

### SmartTube 上游调研 + 客户端矩阵复测（2026-11-14 深夜）

- 看了 SmartTube 仓库的相关讨论（issue `#4287`、`#6030`）。`#6030` 已有 1000+ 条回复，就是本轮同款故障：视频无限加载/播放不了，官方 YouTube 客户端正常。yuliskov 在 32.65+ 用 “playback fixes”（SABR 相关）修了一部分，之后 32.67 继续修 `SABR: fail over from stalling media networks`（PR `#6320`）。他在同帖明确说 Revanced/Morphe “still have problems from time to time”。
- SmartTube 的做法不是“换个 client 就完事”，而是 **WebView 里跑 BotGuard 生成 PO token**：logcat 里能看到 `TvPoTokenWebView4: Generated poToken`，player 脚本是 `tv-player-ias-tcl.js`，且 PO token 有 12 小时有效期（`expiration=43200s`）。本仓库的 `assets/po_token2.html`（移植自 MediaServiceCore，MIT，见 `THIRD_PARTY_NOTICES.md`）与 `YouTubeTvPoTokenProvider` 走的就是这条路线，方向没错，但还没打通。
- 同帖还有一条有用但不同因的线索：部分用户“无限加载”是后台 app 抢 CPU（例：VLC 占满一个核）+ DNS 问题，PO token/JS 解释器跑得极慢，force-stop 后 3~7 秒开播。这类延迟不要和 `LOGIN_REQUIRED` 混为一谈。
- 本轮用设备上的 curl 跑了一版 7 客户端矩阵（`/data/local/tmp/probe/probe11.sh`，视频 `C0I8PPJsrmA`，均带 watch 页 `visitorData` + `signatureTimestamp`）：
  - `ANDROID` / `IOS` / `ANDROID_VR` / `MWEB` → `LOGIN_REQUIRED`，“Sign in to confirm you’re not a bot”。
  - `ANDROID_TESTSUITE` → `UNPLAYABLE` “This video is not available”（该客户端基本已废弃）。
  - `TVHTML5_SIMPLY_EMBEDDED_PLAYER` → `ERROR` “YouTube is no longer supported in this application or device”（已下线）。
  - `WEB_EMBEDDED_PLAYER` → `ERROR` “This video is unavailable”。
  - 结论：**客户端轮换对当前拦截无效**，不要再用“换 profile”当解法。
- 同一出口 IP 上把视频换成 `dQw4w9WgXcQ`，`ANDROID`/`IOS`/`ANDROID_VR`/`MWEB` 全部 `OK`，同时返回 adaptive + muxed + 直链 URL **和** `serverAbrStreamingUrl`。这说明现在的拦截是**按视频的机器人风控**，不是整站 IP 封禁；`serverAbrStreamingUrl` 存在也不代表没有直链，`media_kit` 该走直链仍能走。
- 当轮出口：设备 `18.181.219.42` / IPv6 `2406:da14:1913:4300:...`（AWS 东京，Clash Meta TUN），PC `18.141.176.109`（AWS 新加坡）——PC 侧代理其实仍在生效，所以“PC 直连对比”还没真正做过。
- 登录态的结构性限制（已确认，不是 bug）：`youtube_auth_service.dart` 用的是 SmartTube 的 **TV OAuth**（`_tvClientId`，`/o/oauth2/device/code`），这类 token 只有 `TVHTML5` 接受；其它客户端一律 `400 INVALID_ARGUMENT`。而 `TVHTML5` 现在要求 SABR/PO token 才出流，`media_kit` 不能播 SABR。因此“登录 + 非 TV 客户端”这条路在当前架构下走不通，别反复试。
- 本轮验证：`flutter analyze` 无问题；`flutter test` **122 项全部通过**（含 `video_playback_service_test.dart` 的 adaptive 配对、muxed 回退、匿名重试、摘要脱敏等 23 项）。
- 目前剩下两条互斥路线，需要用户拍板：
  1. **换出口**（住宅/移动网络，或服务商明确标注可看 YouTube 的节点），然后直接用推荐页真实视频复测。代码大概率不用改。
  2. **打通 TVHTML5 的 PO token + SABR**：把 `YouTubeTvPoTokenProvider` 的 `serviceIntegrityDimensions.poToken`、`clientVersion`、`visitorData`、`livingRoomPoTokenId` 与 `/tv` 会话对齐，并处理 “The page needs to be reloaded.” 的重试语义。即便打通，若响应只给 SABR 不给直链，`media_kit` 仍然播不了——需要额外做 SABR→fMP4 代理，属于大工程。

### PC 侧对照实验：拦截发生在服务端（决定性证据，2026-11-14）

为回答“能不能不依赖网络”，在 PC 上做了三组对照（同一出口 IP、同一时刻）：

1. **同一客户端、同一请求形状，只换 videoId**：`ANDROID` + `androidSdkless` 请求
   - `C0I8PPJsrmA` → `LOGIN_REQUIRED` / “Sign in to confirm you're not a bot”，响应里**连 `videoDetails` 都没有**（服务端在解析视频前就拒绝）。
   - `dQw4w9WgXcQ` → `OK`，30 个 itag。
   - 两者请求只差 `videoId`，没有任何客户端字段能翻转结果。
2. **用真实 Chrome 打开 youtube.com 的播放页**（`potest.js` / `webtest.js` / `freshtest.js`，puppeteer-core + 本机 Chrome）：
   - `C0I8PPJsrmA` 页面直接显示“请登录，以便我们确认你不是聊天机器人”。
   - `dQw4w9WgXcQ` 正常播放（`readyState=4`，`currentTime` 在走）。
   - 换**全新无痕配置**（全新 `visitorData`、无 cookie、无历史）结果完全相同。
   - 结论：**YouTube 自己的网页在这个 IP 上也播不了该视频**。不是 Plexus 的客户端行为问题，也不是会话/visitorData 被标记。
3. **PO token 实测**：按 bgutil（yt-dlp 生态）的做法在真实 Chrome 里现造 token——取首页 `window.ytAtN({'R': '...'})` 的挑战（`\xNN` 转义，需要先解码再 `JSON.parse`），加载解释器执行 BotGuard，`GenerateIT` 得到 integrity token，再 mint 出 `visitorData` 绑定的 poToken（长度 521，`ttl=43200`，即 12 小时）。
   - 带 token 与不带 token 的 player 响应**逐字段完全一致**：被拦的仍然 `LOGIN_REQUIRED`，能播的仍然 `UNPLAYABLE / “需要重新加载页面”`。
   - 即 PO token 在本 IP 上不改变判定。注意 `/att/get` 拿到的挑战生成的 token 会被拒，必须用首页 `ytAtN` 的挑战（bgutil 源码已注明），否则实验会得到“加了等于没加”的假结论。

补充事实（影响架构选择）：
- 现在只有 **`ANDROID` 客户端返回直链**（`adaptiveFormats[].url`）。`WEB` 客户端对能播的视频返回的是 `adaptive=26, directUrl=0, sabr=1`，即**只给 SABR**，`media_kit` 播不了。
- `MWEB` / `ANDROID_VR` 在有 `visitorData` + `signatureTimestamp` 时仍返回直链，但同样受机器人风控约束。
- 所以“任意网络都能播”只剩两条路：**登录态**（风控提示本身就是让你登录）或 **实现 SABR 播放**。

下一步（需要账号配合，二选一）：
- **A. 验证登录态 + TVHTML5**：用 TV 设备码授权拿真实 token，配合首页挑战 mint 出的 TV poToken 请求 `TVHTML5`，看是否返回直链。返回直链就能在现有 `media_kit` 架构里直接修好；只返回 SABR 则这条路封死。
- **B. 验证登录态 + cookie（MWEB）**：在浏览器/WebView 里登录拿到 cookie，用 `MWEB`（仍给直链）发请求，验证机器人拦截是否消失。这条最可能同时满足“任意网络 + media_kit”，代价是要在 App 里加网页登录 UI 和 cookie/`SAPISIDHASH` 维护。

### 结论收口：匿名播放无法绕过网络风控（2026-11-14 深夜续）

上一节留的 A 路（登录态 + TVHTML5）已实测，结果是**否定**。本轮新增的证据与代码改动：

#### `/att/get` 头部修正（推翻 2026-11-14 早先的判断）

- 真实浏览器里 `/youtubei/v1/att/get` 必须用 `Content-Type: application/json`；用 `application/json+protobuf` 会得到 `400` + “Invalid value (), JSPB Fava message don't accept top-level braces.”。
- 已改 `youtube_tv_po_token_provider.dart` 的 `_buildTvAttGetHeaders()` 并同步更新测试断言。`GenerateIT`（`/api/jnn/v1/GenerateIT`）仍然使用 `application/json+protobuf`，因为它的 body 是 `[requestKey, response]` 这种 JSPB 数组，不要一起改。
- `LIVING_ROOM_PO_TOKEN_ID` 的 `\u003d` 反转义此前已在代码里（`replaceAll(r'\u003d', '=')`），本轮确认正确。

#### `params: 'CgIQBg=='` 是**广告**播放上下文，不是可用解法

- 这个值解码是字节 `0a 02 10 06`。加上它以后 `ANDROID`/`IOS`/`MWEB` 的 playability 检查确实从 `LOGIN_REQUIRED` 变成 `OK`，也返回 35 条 adaptive + 1 条 muxed 直链——看起来“绕过成功”。
- 但响应实际是**广告上下文**：`is_ad=1`、`adformat=0_6`、`pltype=adpromoted`（`ptrackingUrl` 里同样是 `ptype=adpromoted`）。这些广告 URL 全部 `HTTP 403`，加不带 `pot` 都一样。
- 5 个被拦视频（`C0I8PPJsrmA`、`gR3lN5rkH9k`、`a4IIm-vGCu4`、`q_eFl5juJtg`、`jNQXAC9IVRw`）全部 403；对照 `dQw4w9WgXcQ` 无论加不加 `params` 都是 206。PC 和手机两个出口结论一致。
- 因此 `params` 不是修复，**不要提交这条路径**。

#### 全客户端扫描：14 个客户端没有一个能播

用 yt-dlp `_base.py` 的 `INNERTUBE_CLIENTS` 里的全部 profile（含各自的 `userAgent`、`PLAYER_PARAMS`、`SUPPORTS_AD_PLAYBACK_CONTEXT`）在同一出口 `13.250.121.47` 上打同一个被拦视频：

- `web` / `web_safari` / `web_creator` / `android` / `android_vr` / `ios` / `visionos` / `mweb` / `tv_downgraded` / `tv_samsung` → `LOGIN_REQUIRED`。
- `web_embedded` → `ERROR` “This video is unavailable”；`web_music` / `tv_simply` → `UNPLAYABLE`。
- `tv`（TVHTML5 匿名）→ `OK`，但只给 1 条 muxed 直链（itag 18），取流 `403`；adaptive 全部无 `url`（只给 `serverAbrStreamingUrl`，`sabr=1`）。没有 `hlsManifestUrl` / `dashManifestUrl` 可用。
- 结论：**客户端轮换、`params`、PO token 三条路都不改变结果**。

#### PO token 绑定规则（来自 yt-dlp，已被本轮实验印证）

- yt-dlp `_video.py` 明确：**PLAYER token 绑定 `videoId`**（并且要求 `visitor_data` 存在），**GVS token 绑定 `visitorData`**（除非命中 `html5_generate_content_po_token` 实验，那时也绑 `videoId`）。
- GVS token 不是由服务端回填，而是 yt-dlp 自己拼到媒体 URL 上：`fmt_url = update_url_query(fmt_url, {'pot': po_token})`（`_video.py:3583`）。
- 之前按 `visitorData` 铸 player token，所以服务端直接忽略（`pot=false`），这是“加了等于没加”的原因。
- 按正确绑定重铸（player→`videoId`，gvs→`visitorData`）后：player 仍是 `LOGIN_REQUIRED`；媒体 URL 依次试 `no pot` / `pot=visitorData` / `pot=videoId` 全部 `403`。
- 把同一批 token 交给 yt-dlp（`po_token=mweb.player+…;po_token=mweb.gvs+…`）也一样是 “Sign in to confirm you're not a bot”。即**不是我们的请求形状写错**。

#### 登录态 + TVHTML5：仍然拿不到可播直链

- TV 设备码授权拿到的真实 OAuth token 只被 `TVHTML5` 接受（`ANDROID`/`IOS`/`MWEB`/`WEB` 都是 `400 INVALID_ARGUMENT`，body 已核对不是 JSON 写坏）。
- 用 TV 自己的 requestKey（`Z1elNkAKLpSR3oPOUMSN`）+ 三种绑定（`video` / `living` / `visitor`）分别请求：`noToken` / `videoTok` / `livingTok` / `visitorTok` 全部 `UNPLAYABLE` + “The page needs to be reloaded.”。
- 排除了 `signatureTimestamp` 过期的可能：从 `/tv` 页 `player_url` 拉到的 `tv-player-es6.js` 里 `signatureTimestamp` 就是 **20767**，与请求里用的值一致。
- 带 `params` 的登录态请求虽然 `OK`，但 adaptive 全是 SABR、唯一 muxed（itag 18）取流 `403`。
- 结论：**A 路封死**，而且即使用户愿意登录也不行。

#### 因此现在的代码行为

- 保持 `androidSdkless` 为默认客户端 + 登录 header → 失败后匿名重试（不动）。
- 新增：`_PlaybackResponseProbeClient` 现在在**所有 build**（不只 debug）记录 `/youtubei/v1/player` 的 `playabilityStatus.status/reason`，`_resolveSources()` 用它把失败翻译成用户能行动的文案（`playabilityFailureMessage`）：
  - 机器人风控 → “YouTube 要求先验证「你不是机器人」…这项检查按网络出口判定：请关闭代理/VPN，或改用其它网络（例如手机流量）后重试。”
  - 年龄限制 → 提示需要已通过年龄验证的账号。
  - 其它 `LOGIN_REQUIRED` → 提示需要登录。
  - 其它情况保持原来的通用诊断文案（仍然不输出 URL/token/videoId）。
- 详情页本来就有“重试”按钮，文案变准确即可，没有新增 UI 组件。
- 本轮验证：`flutter analyze` 无问题；`flutter test` **127 项全部通过**（`video_playback_service_test.dart` 28 项，新增 5 项风控文案分类断言 + `/att/get` 头部断言改为 `application/json`）。
- 端到端验证（PC，真实 network）：用生产 `YouTubeVideoPlaybackService` 直接解析 `C0I8PPJsrmA`，debug probe 打印 `playabilityStatus=LOGIN_REQUIRED` / `reason=Sign in to confirm you’re not a bot`，抛出的异常文案即为新的“请关闭代理/VPN，或改用其它网络”提示。该验证用临时测试跑完后已删除（不留在仓库里）。
- 真机（PHM110 `/a4512963`）：已 `flutter build apk --debug` 并安装、启动。首页停在登录门控（符合预期），搜索页先 `TimeoutException after 0:00:08`、重试后 `HandshakeException: Connection terminated during handshake`，说明当时设备侧的代理隧道不可用，**未能截到详情页新文案的截图**。设备网络恢复后需补一次截图确认（预期：详情页显示“YouTube 要求先验证「你不是机器人」…”+ 重试按钮）。
- 仍然**没有提交任何 commit**。

#### 还剩的唯一有效手段

1. **换出口**：住宅宽带或移动数据直连（不要经过云主机/VPN 出口）。这是本轮所有证据指向的唯一无需改代码的解。
2. **登录 + cookie（MWEB）**：需要在 App 内做网页登录并维护 cookie/`SAPISIDHASH`，尚未验证；但 TV token 已证明无效，只有网页会话可能有效。
3. **SABR 播放**：`media_kit` 不支持 `serverAbrStreamingUrl`，要做 SABR→fMP4 代理，属于大工程。
