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
- [lib/pages/category/music_page.dart](lib/pages/category/music_page.dart)、[lib/pages/category/gaming_page.dart](lib/pages/category/gaming_page.dart)、[lib/pages/category/live_page.dart](lib/pages/category/live_page.dart)：音乐、游戏、直播内容的独立 widget 文件，嵌入原分类界面显示。
- [lib/pages/category/category_topic_feed_page.dart](lib/pages/category/category_topic_feed_page.dart)：音乐/游戏/直播共享真实 topic feed、刷新、全局及单栏续载与条目导航；只返回内容，不创建 Scaffold/AppBar。
- [lib/services/youtube_data_service.dart](lib/services/youtube_data_service.dart)：TVHTML5 browse/search 请求、renderer 解析及全局/单栏 continuation。
- [lib/models/video.dart](lib/models/video.dart)：首页条目及路由语义。
- [lib/models/video_section.dart](lib/models/video_section.dart)：首页栏/浏览页的数据和 continuation 状态。
- [lib/pages/player/special_video_pages.dart](lib/pages/player/special_video_pages.dart)：Shorts 与直播/即将直播的 MVP 详情页面。
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

- 当前 HEAD：`291fd4c`，提交标题为 `Fix YouTube home feed continuation and tile routing`。
- 当前实现区分 item endpoint 类型、全局 section-list continuation、单栏 horizontal continuation，以及 reload-only 控制项。
- `TILE_CONTENT_TYPE_VIDEO` 已支持经实机确认的 command executor 包装；只提取唯一媒体 endpoint，并保留已提供的 `playlistId`。测试覆盖其有效和拒绝路径。
- 音乐/游戏/直播分别定义在独立 widget 文件中，但仍显示在分类界面的原内容区域，保留单一 AppBar、分类 chips 和原位切换；三者通过 `CategoryTopicFeedPage` 共用首次加载、下拉重建刷新、横栏续载及条目路由。
- 分类 chips 不是跨页面复用组件；`_CategoryChip` 保持内联在 `category_page.dart`，不恢复单独的 `lib/widgets/category_chip.dart`。
- 游戏分类通过 `FEtopics_gaming` 加载匿名真实数据；TV `sectionListRenderer`、avatar-lockup 标题和直接 `watchEndpoint` tile 结构已用匿名合成值覆盖 parser 回归测试。
- 直播分类通过 `FEtopics_live` 加载匿名真实数据；回归测试覆盖 `LIVE`/`UPCOMING` 状态路由及两层 continuation，实机已确认显示真实直播横栏。
- SearchPage 已接入真实查询、建议词、历史、按栏续载和共享点击路由；每次修改后仍须重新运行相关测试与 analyze，历史测试结果不代表当前工作区已验证。
- `VideoDetailPage` 仍是项目原有的模拟播放/展示页；不要在交接说明或 UI 中声称已经接入真实视频流播放。