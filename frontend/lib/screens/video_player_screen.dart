import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../services/api.dart';
import 'package:http/http.dart' as http;

// ── Mini-player overlay (app-wide singleton) ──────────────────────────────────

class _MiniPlayerOverlay {
  static OverlayEntry? _entry;
  static Player? _player;

  static int get currentPosition => _player?.state.position.inSeconds ?? 0;

  static void show(
    BuildContext context, {
    required Player player,
    required VideoController controller,
    required String title,
    required VoidCallback onExpand,
  }) {
    stop(); // close any previous mini-player
    _player = player;

    _entry = OverlayEntry(
      builder: (ctx) => _FloatingMiniPlayer(
        controller: controller,
        title: title,
        onClose: stop,
        onExpand: onExpand,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  static void stop() {
    _entry?.remove();
    _entry = null;
    _player?.dispose();
    _player = null;
  }
}

class _FloatingMiniPlayer extends StatefulWidget {
  final VideoController controller;
  final String title;
  final VoidCallback onClose;
  final VoidCallback onExpand;
  const _FloatingMiniPlayer({
    required this.controller,
    required this.title,
    required this.onClose,
    required this.onExpand,
  });
  @override
  State<_FloatingMiniPlayer> createState() => _FloatingMiniPlayerState();
}

class _FloatingMiniPlayerState extends State<_FloatingMiniPlayer> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Docked in bottom-left corner
        Positioned(
          left: 12,
          bottom: 12,
          child: Material(
            color: Colors.transparent,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Container(
                width: 320,
                height: 190,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Video(
                        controller: widget.controller,
                        controls: (s) => const SizedBox.shrink(),
                      ),
                      // Top bar: title + close
                      Positioned(
                        top: 0, left: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.85),
                                Colors.transparent,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: widget.onClose,
                                child: const Icon(Icons.close,
                                    size: 16, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Hover overlay: expand button
                      if (_hovered)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.45),
                            child: Center(
                              child: GestureDetector(
                                onTap: widget.onExpand,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8A5BFF),
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8)],
                                  ),
                                  child: const Icon(Icons.open_in_full,
                                      color: Colors.white, size: 22),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── VideoPlayerScreen ─────────────────────────────────────────────────────────

class VideoPlayerScreen extends StatefulWidget {
  final String mediaId;
  final ApiService apiService;
  final Map<String, dynamic>? mediaData;
  final int startFromSeconds;
  final bool useTranscode;
  final String bitrate;
  final String? initialSubtitleIndex;
  final String? initialAudioIndex;
  // When set, plays this YouTube URL via backend trailer-stream proxy (no mediaId lookup)
  final String? trailerYoutubeUrl;

  const VideoPlayerScreen({
    super.key,
    required this.mediaId,
    required this.apiService,
    this.mediaData,
    this.startFromSeconds = 0,
    this.useTranscode = false,
    this.bitrate = '4000k',
    this.initialSubtitleIndex,
    this.initialAudioIndex,
    this.trailerYoutubeUrl,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  Player? player;
  VideoController? controller;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  Timer? _progressTimer;
  Timer? _hideControlsTimer;
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = true;
  String? _error;
  bool _goingToMiniPlayer = false;
  bool _isFullscreen = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = true;
  bool _isMuted = false;
  double _volume = 100.0;
  bool _showControls = true;
  bool _isDraggingProgress = false;
  double _dragProgressValue = 0.0;

  String _qualityMode = 'direct';
  String _subtitleIndex = 'none';
  String? _selectedAudioTrackIndex;
  bool _repeatEnabled = false;
  // Minimum resume position — prevents the position stream emitting 0 immediately
  // after player.open() from clobbering the intended start position before seek completes.
  int _pendingResumeSeconds = 0;
  // Offset added to the player-reported position for transcoded streams.
  // The backend starts FFmpeg at this second, so the player reports from 0
  // even though the content is at _transcodedStartSeconds in the source file.
  int _transcodedStartSeconds = 0;
  bool _shuffleEnabled = false;

  String _title = 'Uppspelning';
  String? _posterPath;
  String _year = '';
  List<Map<String, dynamic>> _audioTracks = [];
  List<Map<String, dynamic>> _subtitleTracks = [];

  final List<Map<String, dynamic>> _queue = [];
  int _queueIndex = 0;
  final Map<String, String> _fileUrlCache = {};
  List<Map<String, dynamic>> _versions = [];
  String? _selectedVersionId;
  List<dynamic> _markers = [];
  bool _showSkipIntro = false;
  int? _introEndSeconds;
  bool _showSkipOutro = false;
  int? _outroEndSeconds;

  @override
  void initState() {
    super.initState();
    _qualityMode = widget.useTranscode ? widget.bitrate : 'direct';
    // Pre-set track selections from media details screen if provided
    if (widget.initialSubtitleIndex != null) {
      _subtitleIndex = widget.initialSubtitleIndex!;
    }
    if (widget.initialAudioIndex != null) {
      _selectedAudioTrackIndex = widget.initialAudioIndex;
    }
    _loadAndStart();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _hideControlsTimer?.cancel();
    _progressTimer?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _completedSubscription?.cancel();
    _tracksSubscription?.cancel();
    // Save progress when the user exits via the ← back button (not stop button).
    // The periodic timer only saves every 10 s, so without this the last ~10 s are lost.
    if (!_goingToMiniPlayer && _position.inSeconds > 0 && widget.trailerYoutubeUrl == null) {
      widget.apiService
          .reportPlaybackProgress(widget.mediaId, _position.inSeconds, _duration.inSeconds)
          .catchError((_) {});
    }
    if (!_goingToMiniPlayer) {
      player?.dispose();
    }
    if (_isFullscreen && !kIsWeb) {
      windowManager.setFullScreen(false);
    }
    super.dispose();
  }

  // ── Controls visibility ───────────────────────────────────────────────────

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    if (!_showControls && mounted) setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  // ── Persistent settings ───────────────────────────────────────────────────

  Future<void> _loadPersistedSettings() async {
    final savedVolumeStr = widget.apiService.getUserPref('loom_player_volume');
    final savedVolume = savedVolumeStr != null ? double.tryParse(savedVolumeStr) ?? 100.0 : 100.0;

    // Only resolve language-based track selection if not pre-set from media details screen
    if (widget.initialSubtitleIndex == null) {
      String subtitleLang;
      if (widget.apiService.getUserPref('loom_player_subtitle_lang') != null) {
        // User has an explicit preference (possibly empty = "no subtitle")
        subtitleLang = widget.apiService.getUserPref('loom_player_subtitle_lang') ?? '';
      } else {
        // First time playing — fall back to the global default from settings
        final cache = widget.apiService.loadSettingsCache();
        final defaultLang = cache?['DEFAULT_SUBTITLE_LANG'] ?? '';
        subtitleLang = (defaultLang.toLowerCase() == 'none') ? '' : defaultLang;
      }
      if (subtitleLang.isNotEmpty) {
        final match = _subtitleTracks.firstWhere(
          (t) => (t['language']?.toString() ?? '').toLowerCase() ==
              subtitleLang.toLowerCase(),
          orElse: () => <String, dynamic>{},
        );
        // Don't auto-select bitmap/PGS tracks on startup — they require transcode.
        // The user can manually select them if desired.
        final codec = (match['codec'] as String? ?? '').toUpperCase();
        final isBitmap = codec.contains('PGS') || codec.contains('HDMV') ||
            codec.contains('VOBSUB') || codec.contains('DVD_SUBTITLE');
        if (match.isNotEmpty && !isBitmap && mounted) {
          setState(() => _subtitleIndex = match['index']?.toString() ?? 'none');
        }
      }
    }

    if (widget.initialAudioIndex == null) {
      final savedAudioLang = widget.apiService.getUserPref('loom_player_audio_lang') ?? '';
      if (savedAudioLang.isNotEmpty) {
        final match = _audioTracks.firstWhere(
          (t) => (t['language']?.toString() ?? '').toLowerCase() ==
              savedAudioLang.toLowerCase(),
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty && mounted) {
          setState(() => _selectedAudioTrackIndex = match['index']?.toString());
        }
      }
    }

    if (mounted) setState(() => _volume = savedVolume);
  }

  Future<void> _savePlayerSettings() async {
    // Save language so it can match across different films
    final subTrack = _subtitleTracks.firstWhere(
      (t) => t['index']?.toString() == _subtitleIndex,
      orElse: () => <String, dynamic>{},
    );
    await widget.apiService.setUserPref(
        'loom_player_subtitle_lang', subTrack['language']?.toString() ?? '');

    if (_selectedAudioTrackIndex != null) {
      final audioTrack = _audioTracks.firstWhere(
        (t) => t['index']?.toString() == _selectedAudioTrackIndex,
        orElse: () => <String, dynamic>{},
      );
      await widget.apiService.setUserPref(
          'loom_player_audio_lang', audioTrack['language']?.toString() ?? '');
    } else {
      await widget.apiService.removeUserPref('loom_player_audio_lang');
    }
    await widget.apiService.setUserPref('loom_player_volume', _volume.toString());
  }

  // ── Startup ───────────────────────────────────────────────────────────────

  Future<void> _loadAndStart() async {
    try {
      MediaKit.ensureInitialized();
      player = Player();
      controller = VideoController(player!);

      // Load media context FIRST so _subtitleTracks/_audioTracks are ready
      await _loadMediaContext();
      // Then load persisted settings (language matching uses the tracks above)
      await _loadPersistedSettings();
      await _fetchMarkers();
      await _openCurrentItem(startFromSeconds: widget.startFromSeconds);

      _positionSubscription = player!.stream.position.listen((pos) {
        if (!mounted) return;
        // Guard: don't let an immediate pos=0 from player.open() override the intended
        // resume position before the seek has had time to complete.
        if (_pendingResumeSeconds > 0 && pos.inSeconds < _pendingResumeSeconds) return;
        // For transcoded streams the player reports from 0 because FFmpeg was
        // started at _transcodedStartSeconds. Add the offset so _position always
        // reflects the absolute position in the source file.
        final absolute = _transcodedStartSeconds > 0
            ? Duration(seconds: _transcodedStartSeconds) + pos
            : pos;
        _checkMarkers(absolute.inSeconds);
        if (!_isDraggingProgress) setState(() => _position = absolute);
      });

      _durationSubscription = player!.stream.duration.listen((dur) {
        if (!mounted) return;
        // For transcoded (web-stream with empty_moov) the duration grows from 0
        // as data arrives. Ignore these updates — duration is pre-seeded from
        // metadata in _loadMediaContext so the seekbar always has the correct value.
        // For trailers, we always want the player's duration since we don't have metadata duration.
        if (_qualityMode == 'direct' || widget.trailerYoutubeUrl != null) setState(() => _duration = dur);
      });

      _completedSubscription = player!.stream.completed.listen((completed) {
        if (!mounted || !completed) return;
        _handlePlaybackCompleted();
      });

      player!.stream.error.listen((e) => debugPrint('Loom-Player error: $e'));

      // Apply subtitle/audio by language whenever the player discovers tracks.
      _tracksSubscription = player!.stream.tracks.listen(_applyTracksFromPlayer);
      // Also apply immediately: _openCurrentItem waits up to 8 s for the stream
      // to start, so the initial tracks event fires long before this listener is
      // registered. Calling with the current state ensures we don't miss it.
      _applyTracksFromPlayer(player!.state.tracks);

      _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _saveProgressPeriodic();
      });

      // Start the auto-hide timer once playback is ready
      _resetHideTimer();

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchMarkers() async {
    try {
      final markersData =
          await widget.apiService.getPlaybackMarkers(widget.mediaId);
      if (markersData != null && markersData['markers'] != null) {
        _markers = markersData['markers'];
      }
    } catch (e) {
      debugPrint('Loom-Player: markers fallback: $e');
      _markers = [];
    }
  }

  Future<void> _saveProgressPeriodic() async {
    if (widget.trailerYoutubeUrl != null) return;
    if (_position.inSeconds <= 0 || _duration.inSeconds <= 0) return;
    final currentId = _currentMediaId;
    try {
      await widget.apiService.reportPlaybackProgress(
        currentId,
        _position.inSeconds,
        _duration.inSeconds,
      );
    } catch (e) {
      debugPrint('Loom-Player: periodic progress save failed: $e');
    }
  }

  Future<void> _loadMediaContext() async {
    Map<String, dynamic> media = widget.mediaData ?? <String, dynamic>{};
    if (media.isEmpty && widget.mediaId.isNotEmpty && widget.mediaId != 'trailer') {
      try {
        media = await widget.apiService.fetchMediaDetails(widget.mediaId);
      } catch (e) {
        debugPrint('Loom-Player: fetchMediaDetails failed: $e');
      }
    }
    
    final metadata = (media['metadata'] is Map)
        ? Map<String, dynamic>.from(media['metadata'] as Map)
        : <String, dynamic>{};

    // Subtitle/audio tracks may arrive as a parsed List or as a JSON-encoded
    // String depending on how the backend serialises metadata rows.
    List<Map<String, dynamic>> _parseTrackList(dynamic raw) {
      dynamic value = raw;
      if (value is String && value.isNotEmpty) {
        try { value = jsonDecode(value); } catch (_) {}
      }
      if (value is! List) return [];
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    final audioTracks = _parseTrackList(metadata['audio_tracks']);
    final subtitleTracks = _parseTrackList(metadata['subtitle_tracks']);

    // Duration from metadata. web-stream uses empty_moov so the player never
    // reports a stable duration. Pre-seed it here so the seekbar always works.
    // Fall back to runtime (minutes → seconds) if the ffprobe duration is missing.
    final rawDurSec = int.tryParse(metadata['duration']?.toString() ?? '0') ?? 0;
    final runtimeMin = int.tryParse(metadata['runtime']?.toString() ?? '0') ?? 0;
    final metaDurSec = widget.trailerYoutubeUrl != null ? 0 : (rawDurSec > 0 ? rawDurSec : runtimeMin * 60);

    final queue = await _buildQueue(media);

    final rawVersions = media['versions'];
    final versions = (rawVersions is List)
        ? rawVersions.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
        : <Map<String, dynamic>>[];

    if (!mounted) return;
    setState(() {
      if (widget.trailerYoutubeUrl != null) {
        final baseTitle = media['title']?.toString() ?? 'Trailer';
        _title = baseTitle.toLowerCase().contains('trailer') ? baseTitle : '$baseTitle - Trailer';
      } else {
        _title = media['title']?.toString() ?? 'Uppspelning';
      }
      _year = media['year']?.toString() ?? '';
      _posterPath = media['poster_path']?.toString();
      _audioTracks = audioTracks;
      _subtitleTracks = subtitleTracks;
      _versions = versions;
      _selectedVersionId ??= widget.mediaId;
      _queue
        ..clear()
        ..addAll(queue);
      _queueIndex = 0;
      if (metaDurSec > 0) {
        _duration = Duration(seconds: metaDurSec);
      }
      // Default audio to first track if not already set
      if (_selectedAudioTrackIndex == null && audioTracks.isNotEmpty) {
        _selectedAudioTrackIndex = audioTracks.first['index']?.toString();
      }
    });
  }

  Future<List<Map<String, dynamic>>> _buildQueue(
      Map<String, dynamic> media) async {
    if (widget.trailerYoutubeUrl != null) return [];
    
    final queue = <Map<String, dynamic>>[
      {'id': widget.mediaId, 'title': media['title']?.toString() ?? 'Now Playing'}
    ];

    final mediaType = media['type']?.toString() ?? '';
    final title = media['title']?.toString() ?? '';
    final looksLikeSeries = mediaType.toLowerCase() == 'show' ||
        RegExp(r's\d{1,2}e\d{1,2}', caseSensitive: false).hasMatch(title);
    if (!looksLikeSeries) return queue;

    try {
      final shows = await widget.apiService.fetchShows();
      final normalizedTitle = _normalizeTitle(title);
      Map<String, dynamic>? matchedShow;

      for (final show in shows) {
        final showMap = Map<String, dynamic>.from(show as Map);
        final showTitle = _normalizeTitle(showMap['title']?.toString() ?? '');
        final mediaTmdbId = media['tmdb_id']?.toString();
        final showTmdbId = showMap['tmdb_id']?.toString();
        final tmdbMatches = mediaTmdbId != null &&
            mediaTmdbId.isNotEmpty &&
            showTmdbId != null &&
            showTmdbId.isNotEmpty &&
            showTmdbId == mediaTmdbId;
        if (tmdbMatches ||
            showTitle == normalizedTitle ||
            normalizedTitle.contains(showTitle) ||
            showTitle.contains(normalizedTitle)) {
          matchedShow = showMap;
          break;
        }
      }
      if (matchedShow == null) return queue;

      final episodes = (matchedShow['episodes'] is List)
          ? (matchedShow['episodes'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList()
              .cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      if (episodes.isEmpty) return queue;

      final selected = <Map<String, dynamic>>[...episodes];
      if (_shuffleEnabled) selected.shuffle(Random());
      return selected
          .where((e) => e['id'] != null)
          .map((e) => {'id': e['id']?.toString(), 'title': _formatEpisodeLabel(e)})
          .toList();
    } catch (_) {
      return queue;
    }
  }

  String _normalizeTitle(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _formatEpisodeLabel(Map<String, dynamic> episode) {
    final s = int.tryParse(episode['season_number']?.toString() ?? '') ?? 0;
    final e = int.tryParse(episode['episode_number']?.toString() ?? '') ?? 0;
    return 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')} - ${episode['title'] ?? 'Episode'}';
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  Future<void> _openCurrentItem({int startFromSeconds = 0}) async {
    final currentId = _currentMediaId;

    final isDirect = _qualityMode == 'direct';
    _transcodedStartSeconds = isDirect ? 0 : startFromSeconds;
    // Set pending resume so the position stream can't drop us back to 0 before seek.
    if (startFromSeconds > 0 && isDirect) _pendingResumeSeconds = startFromSeconds;
    // For transcoded streams, pass the start position to the backend so FFmpeg
    // begins encoding at the correct offset. No player-side seek needed.
    final openUrl = await _resolveUrl(currentId, startSeconds: isDirect ? 0 : startFromSeconds);
    await player!.open(Media(openUrl), play: false);
    await player!.play();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _applySelectedTrackChoices();
    await player!.setVolume(_isMuted ? 0 : _volume);
    if (startFromSeconds > 0 && isDirect) {
      // Direct play supports HTTP-range seeking. Wait until the player knows the
      // duration (stream headers parsed) before seeking — fixed delays are unreliable.
      try {
        await player!.stream.duration
            .firstWhere((d) => d.inSeconds > 0)
            .timeout(const Duration(seconds: 8));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      if (mounted) await player!.seek(Duration(seconds: startFromSeconds));
    }
    _pendingResumeSeconds = 0; // Seek is done (or not needed); resume guard cleared.
    _position = Duration(seconds: startFromSeconds);
  }

  String get _currentMediaId {
    if (_queue.isNotEmpty) {
      return _queue[_queueIndex]['id']?.toString() ?? (_selectedVersionId ?? widget.mediaId);
    }
    return _selectedVersionId ?? widget.mediaId;
  }

  String _buildStreamUrl(String mediaId, {int startSeconds = 0}) {
    if (_qualityMode == 'direct') {
      return '${widget.apiService.baseUrl}/api/playback/stream/$mediaId';
    }
    final startPart = startSeconds > 0 ? '&start=$startSeconds' : '';
    return '${widget.apiService.baseUrl}/api/playback/web-stream/$mediaId'
        '?bitrate=$_qualityMode&subtitleIndex=$_subtitleIndex$startPart';
  }

  // Returns file:// URI for direct play on desktop (PGS works natively with mpv).
  // Falls back to HTTP stream URL on web or if the backend can't resolve the path.
  Future<String> _resolveUrl(String mediaId, {int startSeconds = 0}) async {
    if (widget.trailerYoutubeUrl != null) {
      final title = widget.mediaData?['title'] ?? '';
      final year = widget.mediaData?['year'] ?? '';
      final trailerUrl = '${widget.apiService.baseUrl}/api/media/trailer-stream?url=${Uri.encodeComponent(widget.trailerYoutubeUrl!)}&title=${Uri.encodeComponent(title.toString())}&year=${Uri.encodeComponent(year.toString())}';
      
      try {
        // Pre-warm the backend cache. This forces yt-dlp to download and process the trailer,
        // so that when media_kit opens the stream, the file is already cached and won't trigger a network timeout.
        await http.head(Uri.parse(trailerUrl)).timeout(const Duration(seconds: 45));
      } catch (e) {
        debugPrint('Pre-warm trailer error: $e');
      }
      
      return trailerUrl;
    }
    if (_qualityMode != 'direct' || kIsWeb) {
      return _buildStreamUrl(mediaId, startSeconds: startSeconds);
    }
    if (!_fileUrlCache.containsKey(mediaId)) {
      final url = await widget.apiService.fetchFileUrl(mediaId);
      if (url != null) _fileUrlCache[mediaId] = url;
    }
    return _fileUrlCache[mediaId] ?? _buildStreamUrl(mediaId);
  }

  Future<void> _reloadStream({bool preservePosition = true, int? overridePosition}) async {
    final currentId = _currentMediaId;
    // Use _pendingResumeSeconds as a floor: if the position stream hasn't caught up yet
    // (pos < pendingResume), use the intended resume point instead of the stale zero.
    final rawPos = preservePosition ? _position.inSeconds : 0;
    final effectivePos = (_pendingResumeSeconds > 0 && rawPos < _pendingResumeSeconds)
        ? _pendingResumeSeconds
        : rawPos;
    final pos = overridePosition ?? effectivePos;
    final isDirect = _qualityMode == 'direct';
    _transcodedStartSeconds = isDirect ? 0 : pos;
    final reloadUrl = await _resolveUrl(currentId, startSeconds: isDirect ? 0 : pos);
    await player?.open(Media(reloadUrl), play: false);
    await player?.play();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _applySelectedTrackChoices();
    if (pos > 0 && isDirect) {
      try {
        await player!.stream.duration
            .firstWhere((d) => d.inSeconds > 0)
            .timeout(const Duration(seconds: 8));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      if (mounted) await player?.seek(Duration(seconds: pos));
    }
    _position = Duration(seconds: pos);
  }

  // Called when media_kit discovers tracks after open()/play().
  // Tries language-match first, falls back to position-based match.
  void _applyTracksFromPlayer(Tracks tracks) {
    if (!mounted || player == null || _qualityMode != 'direct') return;
    try {
      // ── Subtitle ──────────────────────────────────────────────────────
      debugPrint('Loom-Player: _applyTracksFromPlayer sub.length=${tracks.subtitle.length} _subtitleIndex=$_subtitleIndex');
      for (final t in tracks.subtitle) {
        debugPrint('  media_kit sub: id=${t.id} lang=${t.language} title=${t.title}');
      }

      if (_subtitleIndex != 'none' && tracks.subtitle.length > 1) {
        // Filter out pseudo-tracks ('no' = off, 'auto' = automatic selection)
        final playerSubs = tracks.subtitle
            .where((t) => t.id != 'no' && t.id != 'auto')
            .toList();
        SubtitleTrack? target;

        // 1. Language match (3-letter ISO 639-2 e.g. 'eng' vs 2-letter 'en' — try both)
        final storedLang = (_subtitleTracks.firstWhere(
          (t) => t['index']?.toString() == _subtitleIndex,
          orElse: () => <String, dynamic>{},
        )['language'] as String? ?? '').toLowerCase();

        if (storedLang.isNotEmpty) {
          // Try exact match first, then 2-letter prefix match
          target = playerSubs.where((t) => (t.language ?? '').toLowerCase() == storedLang).firstOrNull;
          target ??= playerSubs.where((t) {
            final pl = (t.language ?? '').toLowerCase();
            return pl.isNotEmpty && storedLang.startsWith(pl);
          }).firstOrNull;
        }

        // 2. Position-based fallback (ffprobe index → subtitle-only position)
        if (target == null && _subtitleTracks.isNotEmpty) {
          final sorted = [..._subtitleTracks]
            ..sort((a, b) => (int.tryParse(a['index']?.toString() ?? '0') ?? 0)
                .compareTo(int.tryParse(b['index']?.toString() ?? '0') ?? 0));
          final pos = sorted.indexWhere((t) => t['index']?.toString() == _subtitleIndex);
          if (pos >= 0 && pos < playerSubs.length) target = playerSubs[pos];
        }

        if (target != null) {
          player!.setSubtitleTrack(target);
          debugPrint('Loom-Player: subtitle → ${target.language ?? target.id} (id=${target.id})');
        } else {
          debugPrint('Loom-Player: no subtitle track matched for index=$_subtitleIndex lang=$storedLang');
        }
      }

      // ── Audio ─────────────────────────────────────────────────────────
      if (_selectedAudioTrackIndex != null && tracks.audio.length > 1) {
        final playerAudio = tracks.audio.where((t) => t.id != 'auto').toList();
        AudioTrack? target;

        // 1. Language match
        final lang = (_audioTracks.firstWhere(
          (t) => t['index']?.toString() == _selectedAudioTrackIndex,
          orElse: () => <String, dynamic>{},
        )['language'] as String? ?? '').toLowerCase();
        if (lang.isNotEmpty) {
          target = playerAudio
              .where((t) => (t.language ?? '').toLowerCase() == lang)
              .firstOrNull;
        }

        // 2. Position-based fallback
        if (target == null && _audioTracks.isNotEmpty) {
          final sorted = [..._audioTracks]
            ..sort((a, b) => (int.tryParse(a['index']?.toString() ?? '0') ?? 0)
                .compareTo(int.tryParse(b['index']?.toString() ?? '0') ?? 0));
          final pos = sorted.indexWhere((t) => t['index']?.toString() == _selectedAudioTrackIndex);
          if (pos >= 0 && pos < playerAudio.length) target = playerAudio[pos];
        }

        if (target != null) {
          player!.setAudioTrack(target);
          debugPrint('Loom-Player: audio → ${target.language ?? target.id}');
        }
      }
    } catch (e) {
      debugPrint('Failed to apply tracks from player: $e');
    }
  }

  // Kept for compatibility (called from _openCurrentItem / _reloadStream but now a no-op).
  Future<void> _applySelectedTrackChoices() async {
    // Track selection now handled via _applyTracksFromPlayer (player.stream.tracks listener).
    // Volume is still applied here.
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> _seekBy(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final targetSec = target.isNegative ? 0 : target.inSeconds;
    if (_qualityMode == 'direct') {
      await player?.seek(Duration(seconds: targetSec));
    } else {
      _position = Duration(seconds: targetSec);
      unawaited(_reloadStream(preservePosition: false, overridePosition: targetSec));
    }
    _resetHideTimer();
  }

  Future<void> _togglePlayPause() async {
    if (player == null) return;
    if (_isPlaying) {
      await player!.pause();
      // Keep controls visible while paused
      _hideControlsTimer?.cancel();
      if (mounted) setState(() => _showControls = true);
    } else {
      await player!.play();
      _resetHideTimer();
    }
    if (mounted) setState(() => _isPlaying = !_isPlaying);
  }

  Future<void> _toggleMute() async {
    _isMuted = !_isMuted;
    await player?.setVolume(_isMuted ? 0 : _volume);
    if (mounted) setState(() {});
    _resetHideTimer();
  }

  Future<void> _setVolume(double value) async {
    _volume = value.clamp(0.0, 100.0);
    _isMuted = _volume == 0;
    await player?.setVolume(_volume);
    if (mounted) setState(() {});
  }

  Future<void> _switchQuality(String qualityMode) async {
    if (_qualityMode == qualityMode) return;
    _qualityMode = qualityMode;
    await _reloadStream();
    unawaited(_savePlayerSettings());
    if (mounted) setState(() {});
  }

  // media_kit's libmpv on Windows returns sid=no for ALL PGS/VOBSUB bitmap subtitle
  // tracks — the embedded libmpv build does not support bitmap subtitle rendering.
  // PGS subtitles must be burned in by FFmpeg (same approach as Jellyfin Web).
  bool _isBitmapSubtitle(String subtitleIndex) {
    if (subtitleIndex == 'none') return false;
    final track = _subtitleTracks.firstWhere(
      (t) => t['index']?.toString() == subtitleIndex,
      orElse: () => <String, dynamic>{},
    );
    final codec = (track['codec'] as String? ?? '').toUpperCase();
    return codec.contains('PGS') || codec.contains('HDMV') ||
        codec.contains('VOBSUB') || codec.contains('DVD_SUBTITLE');
  }

  Future<void> _switchSubtitle(String subtitleIndex) async {
    _subtitleIndex = subtitleIndex;
    if (subtitleIndex != 'none' && _isBitmapSubtitle(subtitleIndex) && _qualityMode == 'direct') {
      // PGS/bitmap: switch to transcode so FFmpeg burns it in (Jellyfin Web approach).
      _qualityMode = '5000k';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('PGS kräver transkodning — bränner in undertext…'),
          backgroundColor: Color(0xFF8A5BFF),
          duration: Duration(seconds: 3),
        ));
      }
      await _reloadStream();
    } else if (_qualityMode == 'direct') {
      _applyTracksFromPlayer(player!.state.tracks);
    } else {
      await _reloadStream();
    }
    unawaited(_savePlayerSettings());
    if (mounted) setState(() {});
  }

  Future<void> _switchAudioTrack(String audioTrackIndex) async {
    _selectedAudioTrackIndex = audioTrackIndex;
    if (_qualityMode == 'direct') {
      _applyTracksFromPlayer(player!.state.tracks);
    }
    unawaited(_savePlayerSettings());
    if (mounted) setState(() {});
  }

  Future<void> _handlePlaybackCompleted() async {
    if (_repeatEnabled) {
      await player?.seek(Duration.zero);
      await player?.play();
      return;
    }
    if (_queue.isNotEmpty && _queueIndex + 1 < _queue.length) {
      _queueIndex += 1;
      final nextUrl = await _resolveUrl(_queue[_queueIndex]['id'].toString());
      await player?.open(Media(nextUrl), play: false);
      await _applySelectedTrackChoices();
      await player?.play();
      return;
    }
    await _stopAndSave();
  }

  Future<void> _stopAndSave() async {
    if (widget.trailerYoutubeUrl != null) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    try {
      await widget.apiService.reportPlaybackProgress(
        widget.mediaId,
        _position.inSeconds,
        _duration.inSeconds > 0 ? _duration.inSeconds : 0,
      );
    } catch (e) {
      debugPrint('Failed to save stop position: $e');
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _activateMiniPlayer() {
    if (player == null || controller == null) return;

    // Capture root navigator and media identity before this screen is popped.
    final nav = Navigator.of(context, rootNavigator: true);
    final capturedId = widget.mediaId;
    final capturedApiService = widget.apiService;

    _goingToMiniPlayer = true;
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();

    _MiniPlayerOverlay.show(
      context,
      player: player!,
      controller: controller!,
      title: _title,
      onExpand: () {
        // Read position from the still-running mini-player, then reopen full screen.
        final pos = _MiniPlayerOverlay.currentPosition;
        _MiniPlayerOverlay.stop();
        nav.push(MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            mediaId: capturedId,
            apiService: capturedApiService,
            startFromSeconds: pos,
          ),
        ));
      },
    );
    Navigator.pop(context);
  }

  Future<void> _toggleFullscreen() async {
    try {
      if (kIsWeb) {
        // Web fullscreen handled separately (can't use window_manager on web)
      } else {
        final isFs = await windowManager.isFullScreen();
        await windowManager.setFullScreen(!isFs);
        if (mounted) setState(() => _isFullscreen = !isFs);
      }
    } catch (e) {
      debugPrint('Fullscreen error: $e');
    }
  }

  // ── Keyboard ──────────────────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    _resetHideTimer();
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        _togglePlayPause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _seekBy(-10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _seekBy(30);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _setVolume(_volume + 5);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _setVolume(_volume - 5);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (_isFullscreen) _toggleFullscreen();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _checkMarkers(int currentSeconds) {
    bool foundIntro = false;
    bool foundOutro = false;

    for (final m in _markers) {
      final start = int.tryParse(m['start_time_seconds']?.toString() ?? '') ?? 0;
      final end = int.tryParse(m['end_time_seconds']?.toString() ?? '') ?? 0;
      if (currentSeconds >= start && currentSeconds < end) {
        if (m['marker_type'] == 'INTRO') {
          foundIntro = true;
          _introEndSeconds = end;
        } else if (m['marker_type'] == 'OUTRO') {
          foundOutro = true;
          _outroEndSeconds = end;
        }
      }
    }

    // Auto-detect credits zone: last 5 minutes of any content > 40 minutes.
    // Use the player's live duration as fallback if _duration hasn't been set yet.
    final effectiveDurSec = _duration.inSeconds > 0
        ? _duration.inSeconds
        : (player?.state.duration.inSeconds ?? 0);
    if (!foundOutro && effectiveDurSec > 40 * 60) {
      final creditsZoneStart = effectiveDurSec - 5 * 60;
      if (currentSeconds >= creditsZoneStart && currentSeconds < effectiveDurSec - 3) {
        foundOutro = true;
        _outroEndSeconds = effectiveDurSec;
      }
    }

    if (foundIntro != _showSkipIntro && mounted) setState(() => _showSkipIntro = foundIntro);
    if (foundOutro != _showSkipOutro && mounted) setState(() => _showSkipOutro = foundOutro);
  }

  void _skipIntro() {
    if (_introEndSeconds != null) {
      player?.seek(Duration(seconds: _introEndSeconds!));
      setState(() => _showSkipIntro = false);
    }
  }

  void _skipOutro() {
    if (_outroEndSeconds != null) {
      player?.seek(Duration(seconds: _outroEndSeconds!));
      setState(() => _showSkipOutro = false);
    }
  }

  // ── Dropdown builders ─────────────────────────────────────────────────────

  Future<void> _switchVersion(String versionId) async {
    if (_selectedVersionId == versionId) return;
    _selectedVersionId = versionId;
    await _reloadStream(preservePosition: true);
    if (mounted) setState(() {});
  }

  List<DropdownMenuItem<String>> _buildVersionItems() {
    return _versions.map((v) {
      final id = v['id']?.toString() ?? '';
      final resolution = v['resolution']?.toString() ?? '';
      final releaseVer = v['release_version']?.toString() ?? '';
      final label = releaseVer.isNotEmpty ? releaseVer : resolution;
      return DropdownMenuItem(value: id, child: Text(label, overflow: TextOverflow.ellipsis));
    }).toList();
  }

  List<DropdownMenuItem<String>> _buildQualityItems() => const [
        DropdownMenuItem(value: 'direct', child: Text('Direct play')),
        DropdownMenuItem(value: '2000k', child: Text('Transcode 2 Mb')),
        DropdownMenuItem(value: '5000k', child: Text('Transcode 5 Mb')),
        DropdownMenuItem(value: '8000k', child: Text('Transcode 8 Mb')),
      ];

  List<DropdownMenuItem<String>> _buildSubtitleItems() {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'none', child: Text('Av')),
    ];
    for (final t in _subtitleTracks) {
      final idx = t['index']?.toString();
      if (idx == null) continue;
      final label = t['label']?.toString() ?? t['codec']?.toString() ?? idx;
      final lang = t['language']?.toString() ?? '';
      items.add(DropdownMenuItem(
        value: idx,
        child: Text(lang.isEmpty ? label : '$label · $lang',
            overflow: TextOverflow.ellipsis),
      ));
    }
    return items;
  }

  List<DropdownMenuItem<String>> _buildAudioItems() {
    final items = <DropdownMenuItem<String>>[];
    for (final t in _audioTracks) {
      final idx = t['index']?.toString();
      if (idx == null) continue;
      final codec = t['codec']?.toString() ?? 'Audio';
      final lang = t['language']?.toString() ?? '';
      final ch = t['channels']?.toString() ?? '';
      final label = [codec, if (ch.isNotEmpty) '${ch}ch', if (lang.isNotEmpty) lang].join(' · ');
      items.add(DropdownMenuItem(value: idx, child: Text(label, overflow: TextOverflow.ellipsis)));
    }
    return items;
  }

  // ── Queue card ────────────────────────────────────────────────────────────

  Widget _queueCard() {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Kö',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._queue.asMap().entries.map((entry) {
            final isCurrent = entry.key == _queueIndex;
            return Material(
              type: MaterialType.transparency,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  entry.value['title']?.toString() ?? 'Item',
                  style: TextStyle(
                    color: isCurrent ? const Color(0xFFB593FF) : Colors.white70,
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isCurrent
                    ? const Icon(Icons.play_arrow, color: Color(0xFF8A5BFF), size: 16)
                    : null,
                onTap: () async {
                  _queueIndex = entry.key;
                  final queueUrl = await _resolveUrl(entry.value['id'].toString());
                  await player?.open(Media(queueUrl));
                  await player?.play();
                  if (mounted) setState(() {});
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Color(0xFF8A5BFF)),
            SizedBox(height: 16),
            Text('Laddar ström...', style: TextStyle(color: Colors.white70)),
          ]),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text('Ett fel uppstod: $_error',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A5BFF),
                    foregroundColor: Colors.white),
                child: const Text('Gå tillbaka'),
              ),
            ]),
          ),
        ),
      );
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _resetHideTimer(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _togglePlayPause();
              _focusNode.requestFocus();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Video ───────────────────────────────────────────
                if (controller != null)
                  Positioned.fill(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Video(
                          controller: controller!,
                          controls: (s) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),

                // ── Top bar ─────────────────────────────────────────
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.85),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Mini-player button (left)
                              _iconBtn(
                                icon: Icons.picture_in_picture_alt,
                                tooltip: 'Mini-spelare',
                                onTap: _activateMiniPlayer,
                                color: Colors.white70,
                                size: 22,
                              ),
                              const SizedBox(width: 4),
                              // Back button
                              _iconBtn(
                                icon: Icons.arrow_back,
                                tooltip: 'Tillbaka',
                                onTap: _stopAndSave,
                                size: 26,
                              ),
                              const SizedBox(width: 8),
                              // Poster + title
                              if (_posterPath != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(_posterPath!,
                                      width: 34, height: 51, fit: BoxFit.cover),
                                )
                              else
                                Container(
                                  width: 34,
                                  height: 51,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.movie,
                                      color: Colors.white70, size: 18),
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_title,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    if (_year.isNotEmpty)
                                      Text(_year,
                                          style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.5),
                                              fontSize: 12)),
                                  ],
                                ),
                              ),
                              // Fullscreen button (right)
                              _iconBtn(
                                icon: _isFullscreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                                tooltip: _isFullscreen
                                    ? 'Avsluta helskärm (F)'
                                    : 'Helskärm (F)',
                                onTap: _toggleFullscreen,
                                color: Colors.white70,
                                size: 26,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Bottom controls ─────────────────────────────────
                Positioned(
                  left: 14, right: 14, bottom: 14,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: AnimatedSlide(
                      offset: _showControls ? Offset.zero : const Offset(0, 1.5),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        opacity: _showControls ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress bar
                              Row(children: [
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6),
                                      overlayShape: const RoundSliderOverlayShape(
                                          overlayRadius: 12),
                                      activeTrackColor: const Color(0xFF8A5BFF),
                                      inactiveTrackColor:
                                          Colors.white.withValues(alpha: 0.15),
                                      thumbColor: const Color(0xFF8A5BFF),
                                    ),
                                    child: Slider(
                                      value: _isDraggingProgress
                                          ? _dragProgressValue
                                          : (_duration.inMilliseconds > 0
                                              ? (_position.inMilliseconds /
                                                      _duration.inMilliseconds)
                                                  .clamp(0.0, 1.0)
                                              : 0.0),
                                      onChangeStart: (v) => setState(() {
                                        _isDraggingProgress = true;
                                        _dragProgressValue = v;
                                      }),
                                      onChanged: (v) =>
                                          setState(() => _dragProgressValue = v),
                                      onChangeEnd: (v) {
                                        if (_duration.inMilliseconds > 0) {
                                          final targetMs = (v * _duration.inMilliseconds).round();
                                          final targetSec = (targetMs / 1000).round();
                                          if (_qualityMode == 'direct') {
                                            player?.seek(Duration(milliseconds: targetMs));
                                          } else {
                                            // Transcoded: restart the stream from the target position.
                                            setState(() => _position = Duration(seconds: targetSec));
                                            unawaited(_reloadStream(preservePosition: false, overridePosition: targetSec));
                                          }
                                        }
                                        setState(() => _isDraggingProgress = false);
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ]),
                              const SizedBox(height: 4),

                              // All controls in one row
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _iconBtn(
                                        icon: Icons.replay_10,
                                        tooltip: '−10 sek (←)',
                                        onTap: () => _seekBy(-10)),
                                    const SizedBox(width: 2),
                                    _iconBtn(
                                      icon: _isPlaying
                                          ? Icons.pause_circle_filled
                                          : Icons.play_circle_filled,
                                      size: 38,
                                      tooltip: _isPlaying
                                          ? 'Paus (Space)'
                                          : 'Spela (Space)',
                                      onTap: _togglePlayPause,
                                    ),
                                    const SizedBox(width: 2),
                                    _iconBtn(
                                        icon: Icons.forward_30,
                                        tooltip: '+30 sek (→)',
                                        onTap: () => _seekBy(30)),
                                    const SizedBox(width: 4),
                                    _iconBtn(
                                        icon: Icons.stop_circle_outlined,
                                        tooltip: 'Stopp',
                                        onTap: _stopAndSave,
                                        color: Colors.white54),
                                    const SizedBox(width: 10),
                                    if (widget.trailerYoutubeUrl == null) ...[
                                      if (_versions.isNotEmpty) ...[
                                        _compactDropdown<String>(
                                          icon: Icons.layers_outlined,
                                          value: _selectedVersionId ?? widget.mediaId,
                                          items: _buildVersionItems(),
                                          onChanged: _versions.length > 1
                                              ? (v) { if (v != null) _switchVersion(v); }
                                              : null,
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      _compactDropdown<String>(
                                        icon: Icons.hd_outlined,
                                        value: _qualityMode,
                                        items: _buildQualityItems(),
                                        onChanged: (v) {
                                          if (v != null) _switchQuality(v);
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      _compactDropdown<String>(
                                        icon: Icons.subtitles_outlined,
                                        value: _subtitleIndex,
                                        items: _buildSubtitleItems(),
                                        onChanged: (v) {
                                          if (v != null) _switchSubtitle(v);
                                        },
                                      ),
                                      if (_audioTracks.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        _compactDropdown<String>(
                                          icon: Icons.audio_file_outlined,
                                          value: _selectedAudioTrackIndex ?? _audioTracks.first['index']!.toString(),
                                          items: _buildAudioItems(),
                                          onChanged: (v) { if (v != null) _switchAudioTrack(v); },
                                        ),
                                      ],
                                      const SizedBox(width: 10),
                                    ],
                                    _iconBtn(
                                      icon: _repeatEnabled
                                          ? Icons.repeat_one
                                          : Icons.repeat,
                                      tooltip: 'Upprepa',
                                      onTap: () => setState(
                                          () => _repeatEnabled = !_repeatEnabled),
                                      color: _repeatEnabled
                                          ? const Color(0xFF8A5BFF)
                                          : Colors.white54,
                                    ),
                                    const SizedBox(width: 2),
                                    _iconBtn(
                                      icon: Icons.shuffle,
                                      tooltip: 'Shuffle',
                                      onTap: () => setState(
                                          () => _shuffleEnabled = !_shuffleEnabled),
                                      color: _shuffleEnabled
                                          ? const Color(0xFF8A5BFF)
                                          : Colors.white54,
                                    ),
                                    const SizedBox(width: 10),
                                    _iconBtn(
                                      icon: _isMuted
                                          ? Icons.volume_off
                                          : (_volume < 40
                                              ? Icons.volume_down
                                              : Icons.volume_up),
                                      tooltip: 'Ljud av/på',
                                      onTap: _toggleMute,
                                      color: _isMuted
                                          ? Colors.white30
                                          : Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(
                                      width: 28,
                                      height: 72,
                                      child: RotatedBox(
                                        quarterTurns: -1,
                                        child: SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            trackHeight: 3,
                                            thumbShape:
                                                const RoundSliderThumbShape(
                                                    enabledThumbRadius: 5),
                                            overlayShape:
                                                const RoundSliderOverlayShape(
                                                    overlayRadius: 10),
                                            activeTrackColor:
                                                const Color(0xFF8A5BFF),
                                            inactiveTrackColor: Colors.white
                                                .withValues(alpha: 0.18),
                                            thumbColor: Colors.white,
                                          ),
                                          child: Slider(
                                            value: _volume.clamp(0, 100) / 100,
                                            onChanged: (v) => _setVolume(v * 100),
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 34,
                                      child: Text(
                                        '${_volume.round()}%',
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Queue card ──────────────────────────────────────
                if (_showControls && _queue.length > 1 && widget.trailerYoutubeUrl == null)
                  Positioned(right: 18, top: 90, child: _queueCard()),

                // ── Skip intro / outro — sits above the controls panel ──
                if ((_showSkipIntro || _showSkipOutro) && widget.trailerYoutubeUrl == null)
                  Positioned(
                    bottom: 140,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showSkipIntro)
                          _skipButton(
                            label: 'Hoppa över intro',
                            onTap: _skipIntro,
                          ),
                        if (_showSkipOutro) ...[
                          if (_showSkipIntro) const SizedBox(height: 8),
                          _skipButton(
                            label: 'Hoppa över eftertexterna',
                            onTap: _skipOutro,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _skipButton({required String label, required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.skip_next, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = Colors.white,
    double size = 26,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, color: color, size: size),
        ),
      ),
    );
  }

  Widget _compactDropdown<T>({
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    final disabled = onChanged == null;
    return Opacity(
      opacity: disabled ? 0.45 : 1.0,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 13),
            const SizedBox(width: 4),
            DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                dropdownColor: const Color(0xFF15102A),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                isDense: true,
                items: items,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
