import 'package:flutter/material.dart';

import '../../models/channel.dart';
import '../../models/video.dart';
import '../../models/video_section.dart';
import '../../services/youtube_auth_service.dart';
import '../../services/youtube_data_service.dart';
import '../../widgets/channel_tile.dart';
import '../../widgets/feed_continuation_status.dart';
import '../../widgets/sign_in_required_widget.dart';
import '../../widgets/video_card.dart';
import '../home/browse_destination_page.dart';
import '../home/item_destination_pages.dart';

typedef _ChannelFeedSnapshot = ({
  List<VideoSection> sections,
  String? continuationToken,
  Map<int, Set<String>> seenSectionTokens,
  Set<String> seenSectionListTokens,
});

abstract interface class SubscriptionSession {
  bool get isLoggedIn;
  Future<void> init();
  void addAccountListener(VoidCallback listener);
  void removeAccountListener(VoidCallback listener);
}

class _YouTubeSubscriptionSession implements SubscriptionSession {
  final YouTubeAuthService _service = YouTubeAuthService();

  @override
  bool get isLoggedIn => _service.isLoggedIn;

  @override
  Future<void> init() => _service.init();

  @override
  void addAccountListener(VoidCallback listener) =>
      _service.addAccountListener(listener);

  @override
  void removeAccountListener(VoidCallback listener) =>
      _service.removeAccountListener(listener);
}

class SubscriptionPage extends StatefulWidget {
  final SubscriptionDataSource? dataSource;
  final SubscriptionSession? session;

  const SubscriptionPage({super.key, this.dataSource, this.session});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  late final SubscriptionDataSource _dataService =
      widget.dataSource ?? YouTubeDataService();
  late final SubscriptionSession _session =
      widget.session ?? _YouTubeSubscriptionSession();

  List<Channel> _channels = [];
  List<VideoSection> _sections = [];
  List<VideoSection> _selectedChannelSections = [];
  Channel? _selectedChannel;
  String? _errorMessage;
  String? _sectionListError;
  String? _selectedChannelError;
  String? _sectionContinuationToken;
  String? _selectedChannelContinuationToken;
  final Map<int, String> _sectionErrors = {};
  final Map<int, Set<String>> _seenSectionTokens = {};
  final Map<int, Set<String>> _seenChannelSectionTokens = {};
  final Set<String> _seenSectionListTokens = {};
  final Set<String> _seenChannelSectionListTokens = {};
  final Map<Channel, _ChannelFeedSnapshot> _channelFeedCache = {};
  final Set<int> _loadingSectionIndexes = {};
  bool _isLoading = true;
  bool _isLoadingMoreSections = false;
  bool _isLoadingChannel = false;
  bool _isRefreshingSelectedChannel = false;
  int _loadGeneration = 0;
  int _channelGeneration = 0;
  int _feedGeneration = 0;

  @override
  void initState() {
    super.initState();
    _session.addAccountListener(_onAccountChanged);
    _loadSubscriptions(rebuildFeed: true);
  }

  @override
  void dispose() {
    _session.removeAccountListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    _loadSubscriptions(rebuildFeed: true);
  }

  Future<void> _loadSubscriptions({bool rebuildFeed = false}) async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      if (rebuildFeed) {
        _channels = [];
        _sections = [];
        _selectedChannel = null;
        _selectedChannelSections = [];
        _channelFeedCache.clear();
        _sectionContinuationToken = null;
        _selectedChannelContinuationToken = null;
        _sectionListError = null;
        _selectedChannelError = null;
        _sectionErrors.clear();
        _seenSectionTokens.clear();
        _seenChannelSectionTokens.clear();
        _seenSectionListTokens.clear();
        _seenChannelSectionListTokens.clear();
        _loadingSectionIndexes.clear();
        _isLoadingMoreSections = false;
        _isLoadingChannel = false;
        _isRefreshingSelectedChannel = false;
        _channelGeneration++;
        _feedGeneration++;
      }
    });

    try {
      await _session.init();
      if (!mounted || generation != _loadGeneration) return;
      if (!_session.isLoggedIn) {
        setState(() {
          _isLoading = false;
          _channels = [];
          _sections = [];
        });
        return;
      }

      final page = await _dataService.fetchSubscriptions();
      if (!mounted || generation != _loadGeneration) return;
      final token = page.continuationToken;
      if (token != null) _seenSectionListTokens.add(token);
      final seenSectionTokens = <int, Set<String>>{};
      for (var index = 0; index < page.sections.length; index++) {
        final sectionToken = page.sections[index].continuationToken;
        if (sectionToken != null) {
          seenSectionTokens[index] = {sectionToken};
        }
      }
      setState(() {
        _channels = page.channels;
        _sections = page.sections;
        _sectionContinuationToken = token;
        _seenSectionTokens
          ..clear()
          ..addAll(seenSectionTokens);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _selectChannel(Channel? channel) async {
    if (channel == null) {
      ++_channelGeneration;
      setState(() {
        _selectedChannel = null;
        _selectedChannelSections = [];
        _selectedChannelContinuationToken = null;
        _seenChannelSectionListTokens.clear();
        _seenChannelSectionTokens.clear();
        _selectedChannelError = null;
        _isLoadingChannel = false;
        _isRefreshingSelectedChannel = false;
        _sectionErrors.clear();
        _loadingSectionIndexes.clear();
      });
      return;
    }

    final cachedFeed = _channelFeedCache[channel];
    if (cachedFeed != null) {
      ++_channelGeneration;
      setState(() {
        _selectedChannel = channel;
        _selectedChannelSections = cachedFeed.sections;
        _selectedChannelContinuationToken = cachedFeed.continuationToken;
        _seenChannelSectionTokens
          ..clear()
          ..addAll({
            for (final entry in cachedFeed.seenSectionTokens.entries)
              entry.key: Set<String>.of(entry.value),
          });
        _seenChannelSectionListTokens
          ..clear()
          ..addAll(cachedFeed.seenSectionListTokens);
        _selectedChannelError = null;
        _isLoadingChannel = false;
        _isRefreshingSelectedChannel = false;
        _sectionListError = null;
        _sectionErrors.clear();
        _loadingSectionIndexes.clear();
        _isLoadingMoreSections = false;
        _feedGeneration++;
      });
      return;
    }

    await _loadSelectedChannel(channel, rebuildFeed: true);
  }

  Future<void> _loadSelectedChannel(
    Channel channel, {
    required bool rebuildFeed,
    bool preserveSections = false,
  }) async {
    if (!mounted) return;
    final generation = ++_channelGeneration;
    setState(() {
      _selectedChannel = channel;
      _isLoadingMoreSections = false;
      _sectionListError = null;
      _selectedChannelError = null;
      _isLoadingChannel = true;
      _isRefreshingSelectedChannel = preserveSections;
      _sectionErrors.clear();
      _loadingSectionIndexes.clear();
      if (rebuildFeed && !preserveSections) {
        _selectedChannelSections = [];
        _selectedChannelContinuationToken = null;
        _seenChannelSectionListTokens.clear();
        _seenChannelSectionTokens.clear();
        _feedGeneration++;
      }
    });
    try {
      final page = await _dataService.fetchSubscriptionChannelPage(channel);
      if (!mounted || generation != _channelGeneration) return;
      final token = page.continuationToken;
      final seenSectionTokens = <int, Set<String>>{};
      for (var index = 0; index < page.sections.length; index++) {
        final sectionToken = page.sections[index].continuationToken;
        if (sectionToken != null) {
          seenSectionTokens[index] = {sectionToken};
        }
      }
      setState(() {
        _selectedChannelSections = page.sections;
        _selectedChannelContinuationToken = token;
        _seenChannelSectionListTokens
          ..clear()
          ..addAll(token == null ? const <String>{} : {token});
        _seenChannelSectionTokens
          ..clear()
          ..addAll(seenSectionTokens);
        _isLoadingChannel = false;
        _isRefreshingSelectedChannel = false;
      });
      _cacheSelectedChannelFeed();
    } catch (error) {
      if (!mounted || generation != _channelGeneration) return;
      setState(() {
        _selectedChannelError = error.toString();
        _isLoadingChannel = false;
        _isRefreshingSelectedChannel = false;
      });
    }
  }

  void _cacheSelectedChannelFeed() {
    final channel = _selectedChannel;
    if (channel == null) return;
    _channelFeedCache[channel] = (
      sections: List<VideoSection>.of(_selectedChannelSections),
      continuationToken: _selectedChannelContinuationToken,
      seenSectionTokens: {
        for (final entry in _seenChannelSectionTokens.entries)
          entry.key: Set<String>.of(entry.value),
      },
      seenSectionListTokens: Set<String>.of(_seenChannelSectionListTokens),
    );
  }

  Future<void> _loadMoreSections() async {
    final selectedChannel = _selectedChannel;
    final isChannelFeed = selectedChannel != null;
    final token = isChannelFeed
        ? _selectedChannelContinuationToken
        : _sectionContinuationToken;
    if (!mounted || token == null || token.isEmpty || _isLoadingMoreSections) {
      return;
    }
    final generation = _loadGeneration;
    final channelGeneration = _channelGeneration;
    setState(() {
      _isLoadingMoreSections = true;
      _sectionListError = null;
    });
    try {
      final page = await _dataService.fetchMoreSubscriptionSections(token);
      if (!mounted ||
          generation != _loadGeneration ||
          channelGeneration != _channelGeneration ||
          selectedChannel != _selectedChannel) {
        return;
      }
      final nextToken = page.continuationToken;
      final seenTokens = isChannelFeed
          ? _seenChannelSectionListTokens
          : _seenSectionListTokens;
      if (nextToken == token ||
          (nextToken != null && !seenTokens.add(nextToken))) {
        throw const FormatException(
          'YouTube 订阅 section-list continuation token 重复',
        );
      }
      final existingSections = isChannelFeed
          ? _selectedChannelSections
          : _sections;
      for (var offset = 0; offset < page.sections.length; offset++) {
        final sectionToken = page.sections[offset].continuationToken;
        if (sectionToken != null) {
          final index = existingSections.length + offset;
          final sectionTokens = isChannelFeed
              ? _seenChannelSectionTokens
              : _seenSectionTokens;
          sectionTokens[index] = {sectionToken};
        }
      }
      setState(() {
        if (isChannelFeed) {
          _selectedChannelSections = [
            ..._selectedChannelSections,
            ...page.sections,
          ];
          _selectedChannelContinuationToken = nextToken;
        } else {
          _sections = [..._sections, ...page.sections];
          _sectionContinuationToken = nextToken;
        }
        _isLoadingMoreSections = false;
      });
      if (isChannelFeed) _cacheSelectedChannelFeed();
    } catch (error) {
      if (!mounted ||
          generation != _loadGeneration ||
          channelGeneration != _channelGeneration ||
          selectedChannel != _selectedChannel) {
        return;
      }
      setState(() {
        _sectionListError = error.toString();
        _isLoadingMoreSections = false;
      });
    }
  }

  Future<void> _loadMoreSection(int sectionIndex) async {
    final selectedChannel = _selectedChannel;
    final section = selectedChannel == null
        ? sectionIndex < _sections.length
              ? _sections[sectionIndex]
              : null
        : sectionIndex < _selectedChannelSections.length
        ? _selectedChannelSections[sectionIndex]
        : null;
    if (!mounted ||
        section == null ||
        _loadingSectionIndexes.contains(sectionIndex)) {
      return;
    }
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return;

    final generation = _loadGeneration;
    final channelGeneration = _channelGeneration;
    final sectionTokens = selectedChannel == null
        ? _seenSectionTokens
        : _seenChannelSectionTokens;
    final seenTokens = sectionTokens.putIfAbsent(sectionIndex, () => {token});
    setState(() {
      _loadingSectionIndexes.add(sectionIndex);
      _sectionErrors.remove(sectionIndex);
    });
    try {
      final updated = await _dataService.fetchMoreSubscriptionSectionVideos(
        section,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          channelGeneration != _channelGeneration ||
          selectedChannel != _selectedChannel) {
        return;
      }
      final nextToken = updated.continuationToken;
      if (nextToken == token ||
          (nextToken != null && !seenTokens.add(nextToken))) {
        throw const FormatException('YouTube 订阅横栏 continuation token 重复');
      }
      setState(() {
        if (selectedChannel == null && sectionIndex < _sections.length) {
          _sections[sectionIndex] = updated;
        } else if (selectedChannel != null &&
            sectionIndex < _selectedChannelSections.length) {
          _selectedChannelSections[sectionIndex] = updated;
        }
        _loadingSectionIndexes.remove(sectionIndex);
      });
      if (selectedChannel != null) _cacheSelectedChannelFeed();
    } catch (error) {
      if (!mounted ||
          generation != _loadGeneration ||
          channelGeneration != _channelGeneration ||
          selectedChannel != _selectedChannel) {
        return;
      }
      setState(() {
        _loadingSectionIndexes.remove(sectionIndex);
        _sectionErrors[sectionIndex] = error.toString();
      });
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical &&
        notification.metrics.extentAfter < 420 &&
        !_isLoadingChannel &&
        !_isLoadingMoreSections) {
      _loadMoreSections();
    }
    return false;
  }

  Future<void> _refreshSubscriptions({required bool rebuildFeed}) =>
      _selectedChannel == null
      ? _loadSubscriptions(rebuildFeed: rebuildFeed)
      : _loadSelectedChannel(
          _selectedChannel!,
          rebuildFeed: rebuildFeed,
          preserveSections: true,
        );

  void _retrySelectedChannel() {
    final selectedChannel = _selectedChannel;
    if (selectedChannel == null) return;
    _selectChannel(selectedChannel);
  }

  void _openSectionBrowse(VideoSection section) {
    final browseId = section.browseId;
    if (browseId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowseDestinationPage(
          destination: section,
          destinationType: browseId.startsWith('VL')
              ? VideoItemType.playlist
              : VideoItemType.browseDestination,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleSections = _selectedChannel == null
        ? _sections
        : _selectedChannelSections;
    final visibleSectionContinuation = _selectedChannel == null
        ? _sectionContinuationToken
        : _selectedChannelContinuationToken;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '订阅与动态',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: '查看订阅频道',
            onPressed: () => _showManageSubscriptionsModal(context),
          ),
        ],
      ),
      body: !_session.isLoggedIn
          ? SignInRequiredWidget(
              onLoginSuccess: () => _loadSubscriptions(rebuildFeed: true),
            )
          : _isLoading && _channels.isEmpty && _sections.isEmpty
          ? const FeedInitialLoading(message: '正在加载订阅内容...')
          : _errorMessage != null && _channels.isEmpty && _sections.isEmpty
          ? _buildLoadError(context, theme.colorScheme)
          : _channels.isEmpty && _sections.isEmpty
          ? _buildNoSubscriptionsState(theme)
          : _buildSubscriptionFeed(
              theme,
              colorScheme,
              visibleSections,
              visibleSectionContinuation,
            ),
    );
  }

  Widget _buildNoSubscriptionsState(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.subscriptions_outlined,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              '还没有订阅频道',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在 YouTube 订阅频道后，内容会显示在这里。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _loadSubscriptions(rebuildFeed: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重新检查'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadError(BuildContext context, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '订阅内容加载失败',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(_errorMessage ?? ''),
            TextButton.icon(
              onPressed: () => _loadSubscriptions(rebuildFeed: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionFeed(
    ThemeData theme,
    ColorScheme colorScheme,
    List<VideoSection> visibleSections,
    String? visibleSectionContinuation,
  ) {
    return Column(
      children: [
        _buildChannelSelector(theme, colorScheme),
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        Expanded(
          child: FeedRefreshIndicator(
            onRefresh: _refreshSubscriptions,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final channelLoadingHeight = (constraints.maxHeight - 24)
                    .clamp(0.0, constraints.maxHeight)
                    .toDouble();
                return NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: ListView(
                    key: ValueKey<String>(
                      'subscription-feed-$_feedGeneration-${identityHashCode(_selectedChannel)}',
                    ),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (_selectedChannel != null &&
                          (_selectedChannelError != null ||
                              (_isLoadingChannel &&
                                  !_isRefreshingSelectedChannel)))
                        FeedContinuationStatus(
                          isLoading:
                              _isLoadingChannel &&
                              !_isRefreshingSelectedChannel,
                          loadingHeight: channelLoadingHeight,
                          errorMessage: _selectedChannelError,
                          onRetry: _retrySelectedChannel,
                          loadingMessage: '正在加载频道内容...',
                          errorTitle: '订阅频道内容加载失败',
                          retryLabel: '重试加载频道',
                        ),
                      for (
                        var sectionIndex = 0;
                        sectionIndex < visibleSections.length;
                        sectionIndex++
                      )
                        _buildVideoSection(
                          visibleSections[sectionIndex],
                          sectionIndex,
                          theme,
                        ),
                      if (visibleSections.isEmpty &&
                          !_isLoadingChannel &&
                          _selectedChannelError == null &&
                          visibleSectionContinuation == null)
                        SizedBox(
                          height: 180,
                          child: Center(
                            child: Text(
                              '暂无相关订阅更新',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      if (visibleSectionContinuation != null ||
                          _isLoadingMoreSections ||
                          _sectionListError != null)
                        FeedContinuationStatus(
                          isLoading: _isLoadingMoreSections,
                          errorMessage: _sectionListError,
                          onRetry: _loadMoreSections,
                          loadingMessage: '正在加载更多订阅分区...',
                          errorTitle: '订阅后续分区加载失败',
                          retryLabel: '重试加载订阅内容',
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoSection(
    VideoSection section,
    int sectionIndex,
    ThemeData theme,
  ) {
    final title = section.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (section.browseId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openSectionBrowse(section),
              icon: const Icon(Icons.open_in_new),
              label: Text(section.browseTitle ?? '查看更多'),
            ),
          ),
        for (final video in section.videos)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: VideoCard(
              key: ValueKey<String>(
                'subscription-$_feedGeneration-$sectionIndex-${video.id ?? video.browseId ?? video.title}',
              ),
              video: video,
              onTap: () => openVideoItemDestination(context, video),
            ),
          ),
        if (section.continuationToken != null ||
            _loadingSectionIndexes.contains(sectionIndex) ||
            _sectionErrors.containsKey(sectionIndex))
          FeedContinuationStatus(
            isLoading: _loadingSectionIndexes.contains(sectionIndex),
            errorMessage: _sectionErrors[sectionIndex],
            onRetry: () => _loadMoreSection(sectionIndex),
            loadingMessage: '正在加载更多订阅视频...',
            errorTitle: '订阅频道后续内容加载失败',
            retryLabel: '重试加载订阅视频',
          ),
      ],
    );
  }

  Widget _buildChannelSelector(ThemeData theme, ColorScheme colorScheme) {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _channels.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = _selectedChannel == null;
            return _ChannelSelectorItem(
              title: '全部动态',
              isSelected: isSelected,
              colorScheme: colorScheme,
              theme: theme,
              onTap: () => _selectChannel(null),
            );
          }
          final channel = _channels[index - 1];
          return _ChannelSelectorItem(
            title: channel.name,
            imageUrl: channel.avatarUrl,
            isSelected: identical(_selectedChannel, channel),
            colorScheme: colorScheme,
            theme: theme,
            onTap: () => _selectChannel(channel),
          );
        },
      ),
    );
  }

  void _showManageSubscriptionsModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('订阅频道', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _channels.length,
                itemBuilder: (context, index) {
                  final channel = _channels[index];
                  return ChannelTile(
                    channel: channel,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _selectChannel(channel);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelSelectorItem extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final bool isSelected;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final VoidCallback onTap;

  const _ChannelSelectorItem({
    required this.title,
    this.imageUrl,
    required this.isSelected,
    required this.colorScheme,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
                  child: hasImage
                      ? null
                      : title == '全部动态'
                      ? Icon(
                          Icons.apps,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        )
                      : Text(title.substring(0, 1)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
