import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_video;

import '../../models/video.dart';
import '../../services/video_playback_service.dart';
import '../../services/youtube_auth_service.dart';

class VideoDetailPage extends StatefulWidget {
  final Video video;

  const VideoDetailPage({super.key, required this.video});

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  late final Player _player;
  late final media_video.VideoController _videoController;
  late final YouTubeVideoPlaybackService _playbackService;
  late final StreamSubscription<String> _playerErrorSubscription;

  List<VideoPlaybackSource> _sources = const [];
  VideoPlaybackSource? _selectedSource;
  Duration? _scrubPosition;
  String? _errorMessage;
  bool _isLoadingSource = true;
  bool _isOpeningSource = false;
  bool _isDescriptionExpanded = false;
  bool _isFullscreen = false;
  int _operationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = media_video.VideoController(_player);
    _playbackService = YouTubeVideoPlaybackService();
    _playerErrorSubscription = _player.stream.error.listen((_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '播放器无法读取当前媒体源，请检查网络后重试。';
        _isOpeningSource = false;
      });
    });
    _loadSource();
  }

  @override
  void didUpdateWidget(covariant VideoDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _loadSource();
    }
  }

  @override
  void dispose() {
    _operationGeneration++;
    unawaited(_playerErrorSubscription.cancel());
    _playbackService.dispose();
    unawaited(_player.dispose());
    if (_isFullscreen) {
      unawaited(_restoreScreenMode());
    }
    super.dispose();
  }

  Future<void> _loadSource() async {
    final operation = ++_operationGeneration;
    setState(() {
      _isLoadingSource = true;
      _isOpeningSource = false;
      _errorMessage = null;
      _sources = const [];
      _selectedSource = null;
    });

    try {
      final videoId = widget.video.id;
      if (videoId == null) {
        throw const VideoPlaybackSourceException('视频缺少有效的 YouTube ID。');
      }
      final authHeaders = await YouTubeAuthService().getAuthHeaders();
      final sources = await _playbackService.resolveSources(
        videoId,
        authHeaders: authHeaders,
      );
      if (!mounted || operation != _operationGeneration) return;
      setState(() {
        _sources = sources;
        _isLoadingSource = false;
      });
      await _openSource(sources.first, play: true);
    } catch (error) {
      if (!mounted || operation != _operationGeneration) return;
      setState(() {
        _isLoadingSource = false;
        _errorMessage = error is VideoPlaybackSourceException
            ? error.toString()
            : '无法获取此视频的播放源。该视频可能不可用，或当前网络/地区无法访问。';
      });
    }
  }

  Future<void> _openSource(
    VideoPlaybackSource source, {
    required bool play,
    Duration? startPosition,
  }) async {
    final operation = ++_operationGeneration;
    setState(() {
      _isOpeningSource = true;
      _errorMessage = null;
    });

    try {
      await _player.open(
        Media(source.uri.toString()),
        play: source.audioUri == null && play,
      );
      if (source.audioUri case final audioUri?) {
        await _player.setAudioTrack(AudioTrack.uri(audioUri.toString()));
        if (play) {
          await _player.play();
        }
      }
      if (startPosition != null && startPosition > Duration.zero) {
        await _player.seek(startPosition);
      }
      if (!mounted || operation != _operationGeneration) return;
      setState(() {
        _selectedSource = source;
        _isOpeningSource = false;
      });
    } catch (_) {
      if (!mounted || operation != _operationGeneration) return;
      setState(() {
        _isOpeningSource = false;
        _errorMessage = '播放器无法打开当前媒体源，请重试。';
      });
    }
  }

  Future<void> _selectSource(VideoPlaybackSource source) async {
    if (source.uri == _selectedSource?.uri || _isOpeningSource) return;
    final position = _player.state.position;
    final wasPlaying = _player.state.playing;
    await _openSource(source, play: wasPlaying, startPosition: position);
  }

  Future<void> _togglePlayback() async {
    if (_isOpeningSource || _isLoadingSource || _errorMessage != null) return;
    if (_player.state.completed) {
      await _player.seek(Duration.zero);
    }
    if (_player.state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seek(Duration position) async {
    await _player.seek(position);
    if (mounted) {
      setState(() => _scrubPosition = null);
    }
  }

  Future<void> _toggleFullscreen() async {
    final entering = !_isFullscreen;
    await SystemChrome.setPreferredOrientations(
      entering
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
    await SystemChrome.setEnabledSystemUIMode(
      entering ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (mounted) {
      setState(() => _isFullscreen = entering);
    }
  }

  Future<void> _restoreScreenMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }

  void _showQualityPicker() {
    if (_sources.length < 2) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final source in _sources)
              ListTile(
                title: Text(source.qualityLabel),
                subtitle: source.frameRate > 30
                    ? Text('${source.frameRate.toStringAsFixed(0)} fps')
                    : null,
                trailing: source.uri == _selectedSource?.uri
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _selectSource(source);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    return Scaffold(
      body: SafeArea(
        top: !_isFullscreen,
        bottom: !_isFullscreen,
        child: _isFullscreen
            ? SizedBox.expand(child: _buildPlayerSurface(context))
            : Column(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildPlayerSurface(context),
                  ),
                  Expanded(child: _buildDetails(context, video)),
                ],
              ),
      ),
    );
  }

  Widget _buildPlayerSurface(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: media_video.Video(
              controller: _videoController,
              controls: media_video.NoVideoControls,
              fit: BoxFit.contain,
              pauseUponEnteringBackgroundMode: true,
              resumeUponEnteringForegroundMode: false,
            ),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: IconButton(
              tooltip: '返回',
              color: Colors.white,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          if (_isLoadingSource)
            const _PlayerStatus(
              message: '正在解析视频源',
              child: CircularProgressIndicator(color: Colors.white),
            )
          else if (_errorMessage case final error?)
            _PlayerStatus(
              message: error,
              child: FilledButton.icon(
                onPressed: _loadSource,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            )
          else if (_isOpeningSource)
            const CircularProgressIndicator(color: Colors.white)
          else
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              initialData: _player.state.buffering,
              builder: (context, snapshot) => snapshot.data == true
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const SizedBox.shrink(),
            ),
          if (!_isLoadingSource && _errorMessage == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildControls(context),
            ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black87],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 24, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<bool>(
              stream: _player.stream.playing,
              initialData: _player.state.playing,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? false;
                return IconButton(
                  tooltip: isPlaying ? '暂停' : '播放',
                  iconSize: 54,
                  color: Colors.white,
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _player.state.completed
                        ? Icons.replay_circle_filled
                        : isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                );
              },
            ),
            StreamBuilder<Duration>(
              stream: _player.stream.position,
              initialData: _player.state.position,
              builder: (context, positionSnapshot) => StreamBuilder<Duration>(
                stream: _player.stream.duration,
                initialData: _player.state.duration,
                builder: (context, durationSnapshot) {
                  final duration =
                      durationSnapshot.data ?? _player.state.duration;
                  final position =
                      _scrubPosition ??
                      positionSnapshot.data ??
                      _player.state.position;
                  final max = duration.inMilliseconds > 0
                      ? duration.inMilliseconds.toDouble()
                      : 1.0;
                  final value = position.inMilliseconds.toDouble().clamp(
                    0.0,
                    max,
                  );

                  return Row(
                    children: [
                      SizedBox(
                        width: 42,
                        child: Text(
                          _formatDuration(position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: value,
                            max: max,
                            activeColor: colorScheme.primary,
                            inactiveColor: Colors.white30,
                            onChanged: duration.inMilliseconds <= 0
                                ? null
                                : (milliseconds) => setState(
                                    () => _scrubPosition = Duration(
                                      milliseconds: milliseconds.round(),
                                    ),
                                  ),
                            onChangeEnd: duration.inMilliseconds <= 0
                                ? null
                                : (milliseconds) => _seek(
                                    Duration(
                                      milliseconds: milliseconds.round(),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 42,
                        child: Text(
                          _formatDuration(duration),
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '画质',
                        onPressed: _sources.length > 1
                            ? _showQualityPicker
                            : null,
                        color: Colors.white,
                        icon: const Icon(Icons.settings),
                      ),
                      IconButton(
                        tooltip: _isFullscreen ? '退出全屏' : '全屏',
                        onPressed: _toggleFullscreen,
                        color: Colors.white,
                        icon: Icon(
                          _isFullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, Video video) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metadata = [
      video.views,
      video.uploadTime,
    ].where((value) => value.isNotEmpty).join(' • ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          video.title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            metadata,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (video.channelName.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: colorScheme.surfaceContainerHighest,
                backgroundImage: video.channelAvatar.isNotEmpty
                    ? NetworkImage(video.channelAvatar)
                    : null,
                child: video.channelAvatar.isEmpty
                    ? Icon(
                        Icons.person_outline,
                        color: colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  video.channelName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (video.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Material(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(
                () => _isDescriptionExpanded = !_isDescriptionExpanded,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isDescriptionExpanded ? '收起简介' : '简介',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Icon(
                          _isDescriptionExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                        ),
                      ],
                    ),
                    if (_isDescriptionExpanded) ...[
                      const Divider(height: 16),
                      Text(video.description),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final seconds = totalSeconds % 60;
    final minutes = (totalSeconds ~/ 60) % 60;
    final hours = totalSeconds ~/ 3600;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${totalSeconds ~/ 60}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PlayerStatus extends StatelessWidget {
  final String message;
  final Widget child;

  const _PlayerStatus({required this.message, required this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black87,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 150),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
                const SizedBox(height: 8),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
