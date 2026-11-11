import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/video.dart';
import '../../models/video_section.dart';
import 'search_history_service.dart';
import '../../services/youtube_data_service.dart';
import '../../widgets/error_state_widget.dart';
import '../../widgets/feed_continuation_status.dart';
import '../../widgets/video_card.dart';
import '../home/browse_destination_page.dart';
import '../home/item_destination_pages.dart';

/// Standalone Search Screen (独立搜索界面)
class SearchPage extends StatefulWidget {
  final String? initialQuery;
  final SearchDataSource? dataSource;
  final SearchHistoryStore? historyStore;

  const SearchPage({
    super.key,
    this.initialQuery,
    this.dataSource,
    this.historyStore,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final YouTubeDataService _defaultDataService = YouTubeDataService();
  late TextEditingController _searchController;
  late final ScrollController _resultsScrollController;
  final FocusNode _focusNode = FocusNode();
  Timer? _suggestionDebounce;
  late final Future<void> _historyReady;
  Future<void> _historyWrite = Future<void>.value();
  final List<String> _searchHistory = [];
  final Set<int> _loadingSectionIndexes = {};
  final Map<int, String> _sectionErrors = {};
  final Map<int, Set<String>> _seenSectionTokens = {};
  List<VideoSection> _sections = [];
  List<String> _suggestions = [];
  String _query = '';
  String? _errorMessage;
  String? _historyErrorMessage;
  String? _suggestionErrorMessage;
  String _suggestionQuery = '';
  String? _estimatedResults;
  bool _isLoading = false;
  bool _isShowingSuggestions = false;
  bool _isLoadingSuggestions = false;
  bool _autoLoadArmed = true;
  int _searchGeneration = 0;
  int _suggestionGeneration = 0;

  SearchDataSource get _dataService => widget.dataSource ?? _defaultDataService;
  SearchHistoryStore get _historyStore =>
      widget.historyStore ?? const SecureSearchHistoryStore();

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery?.trim() ?? '';
    _searchController = TextEditingController(text: _query);
    _resultsScrollController = ScrollController()
      ..addListener(_onResultsScrollChanged);
    _historyReady = _restoreSearchHistory();
    if (_query.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submitSearch(_query);
      });
    }
  }

  @override
  void dispose() {
    _searchGeneration++;
    _suggestionGeneration++;
    _suggestionDebounce?.cancel();
    _searchController.dispose();
    _resultsScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _restoreSearchHistory() async {
    try {
      final storedHistory = await _historyStore.load();
      if (!mounted) return;
      setState(() {
        final submittedDuringLoad = List<String>.of(_searchHistory);
        _searchHistory
          ..clear()
          ..addAll(submittedDuringLoad)
          ..addAll(
            storedHistory.where(
              (query) => !submittedDuringLoad.contains(query),
            ),
          );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _historyErrorMessage = '读取失败：$error');
    }
  }

  void _persistSearchHistory() {
    final snapshot = List<String>.unmodifiable(_searchHistory);
    _historyWrite = _historyWrite.then((_) async {
      await _historyReady;
      try {
        await _historyStore.save(snapshot);
        if (mounted && _historyErrorMessage != null) {
          setState(() => _historyErrorMessage = null);
        }
      } catch (error) {
        if (mounted) {
          setState(() => _historyErrorMessage = '保存失败：$error');
        }
      }
    });
  }

  Future<void> _submitSearch(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      _clearSearch();
      return;
    }

    _focusNode.unfocus();
    _suggestionDebounce?.cancel();
    _suggestionGeneration++;
    final generation = ++_searchGeneration;
    setState(() {
      _query = query;
      _autoLoadArmed = true;
      _isShowingSuggestions = false;
      _isLoadingSuggestions = false;
      _suggestions = [];
      _suggestionErrorMessage = null;
      _searchController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
      _searchHistory.remove(query);
      _searchHistory.insert(0, query);
      if (_searchHistory.length > 20) {
        _searchHistory.removeRange(20, _searchHistory.length);
      }
      _sections = [];
      _errorMessage = null;
      _estimatedResults = null;
      _isLoading = true;
      _loadingSectionIndexes.clear();
      _sectionErrors.clear();
      _seenSectionTokens.clear();
    });
    _persistSearchHistory();

    try {
      final page = await _dataService.fetchSearchResults(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _sections = List<VideoSection>.of(page.sections);
        _estimatedResults = page.estimatedResults;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchTextChanged(String value) {
    _suggestionDebounce?.cancel();
    final query = value.trim();
    final generation = ++_suggestionGeneration;
    if (query.isEmpty) {
      _searchGeneration++;
      setState(() {
        _query = '';
        _sections = [];
        _errorMessage = null;
        _estimatedResults = null;
        _isLoading = false;
        _isShowingSuggestions = false;
        _isLoadingSuggestions = false;
        _suggestionQuery = '';
        _suggestionErrorMessage = null;
        _suggestions = [];
      });
      return;
    }

    setState(() {
      _isShowingSuggestions = true;
      _isLoadingSuggestions = true;
      _suggestionQuery = query;
      _suggestionErrorMessage = null;
      _suggestions = [];
    });
    _suggestionDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final suggestions = await _dataService.fetchSearchSuggestions(query);
        if (!mounted ||
            generation != _suggestionGeneration ||
            _searchController.text.trim() != query) {
          return;
        }
        setState(() {
          _suggestions = suggestions.isNotEmpty
              ? suggestions
              : _matchingSearchHistory(query);
          _isLoadingSuggestions = false;
        });
      } catch (error) {
        if (!mounted ||
            generation != _suggestionGeneration ||
            _searchController.text.trim() != query) {
          return;
        }
        setState(() {
          _suggestions = _matchingSearchHistory(query);
          _suggestionErrorMessage = error.toString();
          _isLoadingSuggestions = false;
        });
      }
    });
  }

  List<String> _matchingSearchHistory(String query) => _searchHistory
      .where((item) => item.toLowerCase().startsWith(query.toLowerCase()))
      .toList();

  bool _onSearchScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (_isUserScrollNotification(notification)) {
      _loadMoreAtExtent(notification.metrics.extentAfter);
    }
    return false;
  }

  void _onResultsScrollChanged() {
    if (_resultsScrollController.hasClients) {
      _loadMoreAtExtent(_resultsScrollController.position.extentAfter);
    }
  }

  void _loadMoreAtExtent(double extentAfter) {
    const loadMoreThreshold = 320.0;
    if (extentAfter >= loadMoreThreshold) {
      _autoLoadArmed = true;
      return;
    }
    if (!_autoLoadArmed) return;

    int? sectionIndex;
    for (var index = _sections.length - 1; index >= 0; index--) {
      final section = _sections[index];
      final token = section.continuationToken;
      if (token != null &&
          token.isNotEmpty &&
          !_loadingSectionIndexes.contains(index) &&
          !_sectionErrors.containsKey(index)) {
        sectionIndex = index;
        break;
      }
    }
    if (sectionIndex == null) return;

    _autoLoadArmed = false;
    _loadMoreSection(sectionIndex);
  }

  bool _isUserScrollNotification(ScrollNotification notification) =>
      notification is ScrollUpdateNotification ||
      notification is OverscrollNotification ||
      notification is ScrollEndNotification;

  Future<void> _loadMoreSection(int sectionIndex) async {
    if (!mounted ||
        sectionIndex >= _sections.length ||
        _loadingSectionIndexes.contains(sectionIndex)) {
      return;
    }

    final section = _sections[sectionIndex];
    final token = section.continuationToken;
    if (token == null || token.isEmpty) return;

    final generation = _searchGeneration;
    final seenTokens = _seenSectionTokens.putIfAbsent(
      sectionIndex,
      () => {token},
    );
    setState(() {
      _loadingSectionIndexes.add(sectionIndex);
      _sectionErrors.remove(sectionIndex);
    });

    try {
      final updatedSection = await _dataService.fetchMoreSearchSectionVideos(
        section,
      );
      if (!mounted || generation != _searchGeneration) return;
      final nextToken = updatedSection.continuationToken;
      if (nextToken == token ||
          (nextToken != null && !seenTokens.add(nextToken))) {
        throw const FormatException('YouTube 搜索横栏 continuation token 重复');
      }
      setState(() {
        if (sectionIndex < _sections.length &&
            _sections[sectionIndex].continuationToken == token) {
          _sections[sectionIndex] = updatedSection;
        }
        _loadingSectionIndexes.remove(sectionIndex);
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loadingSectionIndexes.remove(sectionIndex);
        _sectionErrors[sectionIndex] = error.toString();
      });
    }
  }

  void _clearSearch() {
    _searchGeneration++;
    _suggestionGeneration++;
    _suggestionDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _autoLoadArmed = true;
      _sections = [];
      _errorMessage = null;
      _estimatedResults = null;
      _isLoading = false;
      _isShowingSuggestions = false;
      _isLoadingSuggestions = false;
      _suggestionQuery = '';
      _suggestionErrorMessage = null;
      _suggestions = [];
      _loadingSectionIndexes.clear();
      _sectionErrors.clear();
      _seenSectionTokens.clear();
    });
  }

  void _clearSearchHistory() {
    setState(() {
      _searchHistory.clear();
      _historyErrorMessage = null;
    });
    _persistSearchHistory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索 YouTube 内容...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
          onChanged: _onSearchTextChanged,
          onSubmitted: _submitSearch,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: '清除搜索',
              onPressed: () {
                _clearSearch();
              },
            ),
        ],
      ),
      body: _isShowingSuggestions
          ? _buildSearchSuggestions(colorScheme)
          : _query.trim().isEmpty
          ? _buildDefaultSearchContent(colorScheme, theme)
          : _isLoading && _sections.isEmpty
          ? const FeedInitialLoading(message: '正在搜索 YouTube...')
          : _errorMessage != null && _sections.isEmpty
          ? ErrorStateWidget(
              errorMessage: _errorMessage!,
              retryText: '重试搜索',
              onRetry: () => _submitSearch(_query),
            )
          : _sections.isEmpty
          ? _buildNoResults(colorScheme, theme)
          : _buildSearchResults(colorScheme, theme),
    );
  }

  Widget _buildSearchSuggestions(ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_isLoadingSuggestions) const LinearProgressIndicator(minHeight: 2),
        if (_suggestionErrorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '搜索提示加载失败：$_suggestionErrorMessage',
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        for (final suggestion in _suggestions)
          ListTile(
            leading: const Icon(Icons.search),
            title: Text(suggestion),
            onTap: () => _submitSearch(suggestion),
          ),
        if (!_isLoadingSuggestions && _suggestions.isEmpty)
          ListTile(
            leading: const Icon(Icons.subdirectory_arrow_left),
            title: Text('搜索“$_suggestionQuery”'),
            onTap: () => _submitSearch(_suggestionQuery),
          ),
      ],
    );
  }

  /// Shows only queries actually submitted during this session.
  Widget _buildDefaultSearchContent(ColorScheme colorScheme, ThemeData theme) {
    if (_searchHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 56, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '搜索 YouTube 内容',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (_historyErrorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                '搜索历史${_historyErrorMessage!}',
                style: TextStyle(color: colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '搜索历史',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '清空历史',
              onPressed: _clearSearchHistory,
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _searchHistory.map((item) {
            return ActionChip(
              avatar: const Icon(Icons.history, size: 16),
              label: Text(item),
              onPressed: () {
                _searchController.text = item;
                _submitSearch(item);
              },
            );
          }).toList(),
        ),
        if (_historyErrorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '搜索历史$_historyErrorMessage',
              style: TextStyle(color: colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _buildNoResults(ColorScheme colorScheme, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 56, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            '没有找到相关内容',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme colorScheme, ThemeData theme) {
    final hasEstimate =
        _estimatedResults != null && _estimatedResults!.trim().isNotEmpty;
    final contentWidth = MediaQuery.sizeOf(context).width - 24;
    final cardWidth = (contentWidth - 12) / 2;
    final cardHeight = cardWidth * 9 / 16 + 88;
    final resultItems = <({int sectionIndex, int videoIndex, Video video})>[
      for (
        var sectionIndex = 0;
        sectionIndex < _sections.length;
        sectionIndex++
      )
        for (
          var videoIndex = 0;
          videoIndex < _sections[sectionIndex].videos.length;
          videoIndex++
        )
          (
            sectionIndex: sectionIndex,
            videoIndex: videoIndex,
            video: _sections[sectionIndex].videos[videoIndex],
          ),
    ];

    return NotificationListener<ScrollNotification>(
      onNotification: _onSearchScroll,
      child: ListView(
        controller: _resultsScrollController,
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    '“$_query” 的搜索结果',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (hasEstimate) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '约 ${_estimatedResults!} 条结果',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (resultItems.isNotEmpty)
            GridView.builder(
              key: ValueKey<String>('search-grid-$_searchGeneration'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: cardHeight,
              ),
              itemCount: resultItems.length,
              itemBuilder: (context, videoIndex) {
                final item = resultItems[videoIndex];
                final video = item.video;
                return VideoCard(
                  key: ValueKey<String>(
                    'search-item-$_searchGeneration-${item.sectionIndex}-${item.videoIndex}-${video.id ?? video.browseId ?? video.title}',
                  ),
                  video: video,
                  onTap: () => openVideoItemDestination(context, video),
                );
              },
            ),
          for (
            var sectionIndex = 0;
            sectionIndex < _sections.length;
            sectionIndex++
          ) ...[
            if (_sections[sectionIndex].browseId != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openSectionBrowse(_sections[sectionIndex]),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(_sections[sectionIndex].browseTitle ?? '查看更多'),
                ),
              ),
            if (_sections[sectionIndex].searchQuery != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      _submitSearch(_sections[sectionIndex].searchQuery!),
                  icon: const Icon(Icons.search),
                  label: const Text('查看更多相关搜索'),
                ),
              ),
            if (_loadingSectionIndexes.contains(sectionIndex) ||
                _sectionErrors.containsKey(sectionIndex))
              _buildSectionContinuation(sectionIndex, theme, colorScheme),
          ],
        ],
      ),
    );
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

  Widget _buildSectionContinuation(
    int sectionIndex,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return FeedContinuationStatus(
      isLoading: _loadingSectionIndexes.contains(sectionIndex),
      errorMessage: _sectionErrors[sectionIndex],
      onRetry: () => _loadMoreSection(sectionIndex),
      loadingMessage: '正在加载更多搜索结果...',
      errorTitle: '搜索结果后续内容加载失败',
      retryLabel: '重试加载搜索结果',
    );
  }
}
