import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:io' show Process;
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'episode_details_screen.dart';
import 'fix_match_dialog.dart';
import 'media_info_dialog.dart';
import 'person_details_screen.dart';
import 'resume_playback_modal.dart';
import 'video_player_screen.dart';
import '../widgets/hoverable_builder.dart';

class MediaDetailsScreen extends StatefulWidget {
  final String mediaId;
  final ApiService apiService;
  final VoidCallback? onBack;
  final ValueChanged<String>? onGenreSelected;
  final ValueChanged<String>? onShowGenreSelected;
  final ValueChanged<String>? onKeywordSelected;
  final ValueChanged<String>? onMediaSelected;
  final ValueChanged<String>? onPersonSelected;
  final int? autoPlaySeconds;
  final VoidCallback? onVideoPlayerClosed;
  final VoidCallback? onEdit;
  final void Function(String mediaId, Offset pos)? onContextMenu;
  final void Function(Map<String, dynamic> episode, Map<String, dynamic> showData)? onEpisodeSelected;
  final void Function(String epId, Map<String, dynamic> ep)? onEditEpisode;
  final int? initialSeasonNumber;

  const MediaDetailsScreen({
    super.key,
    required this.mediaId,
    required this.apiService,
    this.onBack,
    this.onGenreSelected,
    this.onShowGenreSelected,
    this.onKeywordSelected,
    this.onMediaSelected,
    this.onPersonSelected,
    this.autoPlaySeconds,
    this.onVideoPlayerClosed,
    this.onEdit,
    this.onContextMenu,
    this.onEpisodeSelected,
    this.onEditEpisode,
    this.initialSeasonNumber,
  });

  @override
  State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _mediaData;
  double _myRating = 0.0;
  double? _ratingPreview;
  bool _isRatingHovering = false;
  bool _isResetHovering = false;
  bool _isRatingFlashing = false;
  int _ratingFlashNonce = 0;
  Timer? _ratingFlashTimer;
  bool _isWatched = false;
  int _savedProgressSeconds = 0;
  String _titleDisplayStyle = 'Translated';
  bool _showReleaseVersion = true;
  bool _isCoverHovered = false;
  bool _isInWatchlist = false;
  bool _isWatchlistLoading = false;
  bool _isFavorite = false;
  final ScrollController _scrollController = ScrollController();
  Future<Map<String, dynamic>>? _similarItemsFuture;
  Future<Map<String, dynamic>>? _collectionItemsFuture;

  // Playback settings — persisted across sessions
  String _selectedQuality = 'direct';
  String _selectedSubtitleIndex = 'none';
  String? _selectedAudioIndex;

  // Version selection
  String? _selectedVersionId;
  String _versionPriority = '1080p,720p,4K'; // loaded from settings

  // TV-serie avsnitt
  int _selectedSeasonNumber = -1;
  bool _episodeViewIsGrid = false;
  bool _seasonOverviewMode = true; // true = show season cards, false = show episodes
  bool _showUpcomingEpisodes = true;

  // ── Version helpers ──────────────────────────────────────────────────────

  static String _normalizeResForVersion(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final s = raw.trim();
    final u = s.toUpperCase();
    if (u.contains('2160') || u.contains('4K') || u.contains('UHD')) return '4K';
    if (u.contains('1080')) return '1080p';
    if (u.contains('720'))  return '720p';
    if (u.contains('576'))  return '576p';
    if (u.contains('480'))  return '480p';
    if (u.contains('360'))  return '360p';
    final dim = RegExp(r'^(\d+)[Xx](\d+)$').firstMatch(s);
    if (dim != null) {
      final w = int.tryParse(dim.group(1)!) ?? 0;
      final h = int.tryParse(dim.group(2)!) ?? 0;
      if (w >= 3200 || h >= 2000) return '4K';
      if (w >= 1900 || h >= 1000) return '1080p';
      if (w >= 1100 || h >= 650)  return '720p';
      if (w >= 700  || h >= 420)  return '480p';
      return '${h}p';
    }
    return s;
  }

  static String _extractVersionTag(String filePath) {
    if (filePath.isEmpty) return '';
    final name = filePath.replaceAll('\\', '/').split('/').last;
    final noExt = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

    // Ordered: most specific first
    final patterns = <(RegExp, String)>[
      (RegExp(r'4K[\s._-]?Remaster(?:ed)?', caseSensitive: false), '4K Remaster'),
      (RegExp(r"Director['’s]?s?[\s._-]?Cut", caseSensitive: false), "Director's Cut"),
      (RegExp(r'Extended[\s._-]?Cut', caseSensitive: false), 'Extended Cut'),
      (RegExp(r'Extended[\s._-]?Edition', caseSensitive: false), 'Extended Edition'),
      (RegExp(r'Theatrical[\s._-]?Cut', caseSensitive: false), 'Theatrical Cut'),
      (RegExp(r'Special[\s._-]?Edition', caseSensitive: false), 'Special Edition'),
      (RegExp(r'Ultimate[\s._-]?Edition', caseSensitive: false), 'Ultimate Edition'),
      (RegExp(r'Ultimate[\s._-]?Cut', caseSensitive: false), 'Ultimate Cut'),
      (RegExp(r'Final[\s._-]?Cut', caseSensitive: false), 'Final Cut'),
      (RegExp(r'International[\s._-]?Cut', caseSensitive: false), 'International Cut'),
      (RegExp(r'Open[\s._-]?Matte', caseSensitive: false), 'Open Matte'),
      (RegExp(r'\bRemaster(?:ed)?\b', caseSensitive: false), 'Remastered'),
      (RegExp(r'\bExtended\b', caseSensitive: false), 'Extended'),
      (RegExp(r'\bTheatrical\b', caseSensitive: false), 'Theatrical'),
      (RegExp(r'\bUnrated\b', caseSensitive: false), 'Unrated'),
      (RegExp(r'\bCriterion\b', caseSensitive: false), 'Criterion'),
      (RegExp(r'\bIMAX\b', caseSensitive: false), 'IMAX'),
      (RegExp(r'\bHybrid\b', caseSensitive: false), 'Hybrid'),
      (RegExp(r'\bProper\b', caseSensitive: false), 'Proper'),
      (RegExp(r'\bHDR10\+|\bHDR10\b|\bHDR\b', caseSensitive: false), 'HDR'),
      (RegExp(r'\bBluRay|Blu-Ray|BDRip|BDRemux\b', caseSensitive: false), 'Blu-ray'),
      (RegExp(r'\bWEB-DL|WEBRip|WebRip\b', caseSensitive: false), 'WEB-DL'),
    ];

    // Check bracketed/parenthesized sections first
    final bracketRe = RegExp(r'[\[(]([^\])\r\n]{2,40})[\])]');
    for (final m in bracketRe.allMatches(noExt)) {
      final content = m.group(1)!.trim();
      if (RegExp(r'^\d{4}$').hasMatch(content)) continue;
      if (RegExp(r'^(1080p?|720p?|2160p?|4K|UHD|480p?|576p?|360p?)$', caseSensitive: false).hasMatch(content)) continue;
      for (final (re, label) in patterns) {
        if (re.hasMatch(content)) return label;
      }
      if (!RegExp(r'^\d+$').hasMatch(content) && content.length >= 2) return content;
    }

    // Check full filename
    for (final (re, label) in patterns) {
      if (re.hasMatch(noExt)) return label;
    }
    return '';
  }

  static String _buildVersionLabel(Map<String, dynamic> v) {
    final filePath  = v['file_path']       as String? ?? '';
    final resRaw    = v['resolution']      as String? ?? '';
    final stored    = v['release_version'] as String? ?? '';
    final res = _normalizeResForVersion(resRaw);
    final tag = stored.isNotEmpty ? stored : _extractVersionTag(filePath);
    if (res.isEmpty && tag.isEmpty) return 'Version';
    if (res.isEmpty) return tag;
    if (tag.isEmpty) return res;
    return '$res – $tag';
  }

  List<Map<String, dynamic>> _sortedVersions() {
    final versions = (_mediaData?['versions'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (versions.isEmpty) return versions;
    final order = _versionPriority
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .toList();
    return [...versions]..sort((a, b) {
        final ra = _normalizeResForVersion(a['resolution'] as String?).toUpperCase();
        final rb = _normalizeResForVersion(b['resolution'] as String?).toUpperCase();
        int ia = order.indexOf(ra); if (ia < 0) ia = order.length + 1;
        int ib = order.indexOf(rb); if (ib < 0) ib = order.length + 1;
        return ia.compareTo(ib);
      });
  }

  Future<void> _toggleFavorite() async {
    if (widget.mediaId.startsWith('external_')) return;
    final newVal = !_isFavorite;
    setState(() => _isFavorite = newVal);
    try {
      await widget.apiService.toggleFavorite(widget.mediaId, isFavorite: newVal);
    } catch (e) {
      if (mounted) setState(() => _isFavorite = !newVal);
    }
  }

  Future<void> _toggleWatchlist() async {
    if (_mediaData == null) return;
    setState(() {
      _isWatchlistLoading = true;
    });
    try {
      final tmdbId = _mediaData!['tmdb_id']?.toString();
      final title = _mediaData!['title']?.toString() ?? '';
      final type = _mediaData!['type']?.toString() ?? 'Movie';
      final year = int.tryParse(_mediaData!['year']?.toString() ?? '');
      final posterPath = _mediaData!['poster_path']?.toString();

      if (tmdbId == null) throw Exception('Saknar TMDB ID');

      if (_isInWatchlist) {
        await widget.apiService.removeFromWatchlist(tmdbId);
        setState(() {
          _isInWatchlist = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$title" har tagits bort från din bevakningslista.'),
            backgroundColor: const Color(0xFF15102A),
          ),
        );
      } else {
        await widget.apiService.addToWatchlist(
          tmdbId: tmdbId,
          title: title,
          type: type,
          year: year,
          posterPath: posterPath,
        );
        setState(() {
          _isInWatchlist = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '"$title" har lagts till i din bevakningslista för nerladdning!'),
            backgroundColor: const Color(0xFF8A5BFF),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ett fel uppstod: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() {
        _isWatchlistLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialSeasonNumber != null) {
      _selectedSeasonNumber = widget.initialSeasonNumber!;
      _seasonOverviewMode = false;
    }
    _loadPlaybackSettings();
    _fetchDetails();
    // Pre-warm HLS cache so playback starts instantly
    if (!widget.mediaId.startsWith('external_')) {
      widget.apiService.warmupStream(widget.mediaId);
    }
  }

  Future<void> _loadPlaybackSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedQuality = prefs.getString('loom_player_quality_pref') ?? 'direct';
    final savedSubLang = prefs.getString('loom_player_subtitle_lang') ?? '';
    final savedAudioLang = prefs.getString('loom_player_audio_lang') ?? '';
    final savedEpGrid = prefs.getBool('loom_episode_view_is_grid') ?? false;
    if (!mounted) return;
    setState(() {
      _selectedQuality = savedQuality;
      _selectedSubtitleIndex = 'none';
      _selectedAudioIndex = null;
      _pendingSubtitleLang = savedSubLang;
      _pendingAudioLang = savedAudioLang;
      _episodeViewIsGrid = savedEpGrid;
    });
  }

  Future<void> _saveEpisodeViewPref(bool isGrid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loom_episode_view_is_grid', isGrid);
  }

  // Resolved once tracks are known
  String _pendingSubtitleLang = '';
  String _pendingAudioLang = '';

  void _applyLanguageDefaults(Map<String, dynamic> metadata) {
    final subtitleTracks = (metadata['subtitle_tracks'] is List)
        ? (metadata['subtitle_tracks'] as List).cast<Map>()
        : <Map>[];
    final audioTracks = (metadata['audio_tracks'] is List)
        ? (metadata['audio_tracks'] as List).cast<Map>()
        : <Map>[];

    String resolvedSub = 'none';
    if (_pendingSubtitleLang.isNotEmpty) {
      final match = subtitleTracks.firstWhere(
        (t) => (t['language']?.toString() ?? '').toLowerCase() ==
            _pendingSubtitleLang.toLowerCase(),
        orElse: () => {},
      );
      if (match.isNotEmpty) resolvedSub = match['index']?.toString() ?? 'none';
    }

    String? resolvedAudio;
    if (_pendingAudioLang.isNotEmpty) {
      final match = audioTracks.firstWhere(
        (t) => (t['language']?.toString() ?? '').toLowerCase() ==
            _pendingAudioLang.toLowerCase(),
        orElse: () => {},
      );
      if (match.isNotEmpty) resolvedAudio = match['index']?.toString();
    }

    if (!mounted) return;
    setState(() {
      _selectedSubtitleIndex = resolvedSub;
      _selectedAudioIndex = resolvedAudio;
    });
  }

  Future<void> _savePlaybackSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loom_player_quality_pref', _selectedQuality);
  }

  @override
  void dispose() {
    _ratingFlashTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    // Capture before any await — widget props can change while async work runs.
    final pendingAutoPlay = widget.autoPlaySeconds;
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _similarItemsFuture = widget.apiService.fetchSimilarItems(widget.mediaId);
      });
      final data = await widget.apiService.fetchMediaDetails(widget.mediaId);

      if (data['collection_id'] != null) {
        _collectionItemsFuture = widget.apiService.fetchCollectionItems(data['collection_id'].toString());
      }

      // Extract ratings / watch status if saved
      final metadata = data['metadata'] ?? {};
      final savedRating =
          double.tryParse(metadata['my_rating']?.toString() ?? '0') ?? 0.0;
      final savedWatchStatus = metadata['watch_status'] == 'watched';
      final progress =
          int.tryParse(metadata['playback_progress']?.toString() ?? '0') ?? 0;

      // Load settings to fetch default options
      String titleStyle = 'Translated';
      bool showReleaseVersion = true;
      String versionPriority = '1080p,720p,4K';
      try {
        final settings = await widget.apiService.getSettings();
        if (settings.containsKey('TITLE_DISPLAY_STYLE')) {
          titleStyle = settings['TITLE_DISPLAY_STYLE'];
        }
        if (settings.containsKey('SHOW_RELEASE_VERSION')) {
          showReleaseVersion = settings['SHOW_RELEASE_VERSION'] != 'false';
        }
        if (settings.containsKey('VERSION_PRIORITY')) {
          versionPriority = settings['VERSION_PRIORITY'];
        }
        if (mounted) {
          setState(() => _showUpcomingEpisodes = settings['SHOW_UPCOMING_EPISODES'] != 'false');
        }
        // Apply default language preferences from settings (overrides empty SharedPreferences)
        final defaultSubLang = settings['DEFAULT_SUBTITLE_LANG'] as String? ?? '';
        final defaultAudioLang = settings['DEFAULT_AUDIO_LANG'] as String? ?? '';
        if (_pendingSubtitleLang.isEmpty && defaultSubLang.isNotEmpty) {
          _pendingSubtitleLang = defaultSubLang;
        }
        if (_pendingAudioLang.isEmpty && defaultAudioLang.isNotEmpty) {
          _pendingAudioLang = defaultAudioLang;
        }
      } catch (e) {
        debugPrint('Error loading settings in details: $e');
      }

      final bool isInWatchlist = data['is_in_watchlist'] as bool? ?? false;

      // Pick best version based on priority
      final versions = (data['versions'] as List? ?? []).cast<Map<String, dynamic>>();
      final order = versionPriority.split(',').map((s) => s.trim().toUpperCase()).toList();
      String? bestVersionId;
      if (versions.isNotEmpty) {
        final sorted = [...versions]..sort((a, b) {
            final ra = _normalizeResForVersion(a['resolution'] as String?).toUpperCase();
            final rb = _normalizeResForVersion(b['resolution'] as String?).toUpperCase();
            int ia = order.indexOf(ra); if (ia < 0) ia = order.length + 1;
            int ib = order.indexOf(rb); if (ib < 0) ib = order.length + 1;
            return ia.compareTo(ib);
          });
        bestVersionId = sorted.first['id']?.toString();
      }

      setState(() {
        _mediaData = data;
        _myRating = savedRating > 0 ? savedRating : 0.0;
        _isWatched = savedWatchStatus;
        _savedProgressSeconds = progress;
        _titleDisplayStyle = titleStyle;
        _showReleaseVersion = showReleaseVersion;
        _isInWatchlist = isInWatchlist;
        _isFavorite = data['is_favorite'] as bool? ?? false;
        _isLoading = false;
        _versionPriority = versionPriority;
        _selectedVersionId = bestVersionId ?? widget.mediaId;
      });
      // Resolve saved language preferences using the best version's tracks
      final bestVer = versions.isNotEmpty
          ? versions.firstWhere(
              (v) => v['id']?.toString() == (bestVersionId ?? widget.mediaId),
              orElse: () => <String, dynamic>{},
            )
          : <String, dynamic>{};
      final tracksForDefaults = bestVer.isNotEmpty
          ? Map<String, dynamic>.from(bestVer)
          : (data['metadata'] is Map ? Map<String, dynamic>.from(data['metadata'] as Map) : <String, dynamic>{});
      _applyLanguageDefaults(tracksForDefaults);

      // 4K media should default to direct play — transcoding 4K at 5 Mbit wastes quality.
      // Override the saved pref only if a transcode bitrate was remembered.
      final bestResolution = _normalizeResForVersion(bestVer['resolution'] as String?);
      if (bestResolution == '4K' && _selectedQuality != 'direct') {
        setState(() => _selectedQuality = 'direct');
      }

      // If parent requested autoplay on open, start playback now.
      if (pendingAutoPlay != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startPlayback(pendingAutoPlay);
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onRatingChanged(double val) {
    final rating = _normalizeRating(val);
    setState(() {
      _myRating = rating;
      _ratingPreview = rating;
      _isRatingHovering = true;
    });
  }

  Future<void> _onRatingChangeEnd(double val) async {
    final rating = _normalizeRating(val);
    _ratingFlashTimer?.cancel();
    setState(() {
      _myRating = rating;
      _ratingPreview = rating;
      _isRatingHovering = false;
      _isRatingFlashing = true;
      _ratingFlashNonce++;
    });
    _ratingFlashTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      setState(() {
        _isRatingFlashing = false;
      });
    });

    // Sync locally and queue background Trakt/Simkl syncs once dragging stops
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Betyg uppdaterat till ${rating.toStringAsFixed(0)}! Synkas med Trakt/Simkl.'),
            backgroundColor: const Color(0xFF8A5BFF),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      // Persist rating to server
      try {
        await widget.apiService.saveRating(widget.mediaId, rating);
      } catch (e) {
        debugPrint('Failed to save rating: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Misslyckades spara betyg: $e'),
                backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _toggleWatchStatus() async {
    final targetState = !_isWatched;
    setState(() {
      _isWatched = targetState;
    });
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(targetState
                ? 'Markerad som sedd! Synkar...'
                : 'Markerad som osedd! Synkar...'),
            backgroundColor: const Color(0xFF8A5BFF),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await widget.apiService.toggleSeenStatus(widget.mediaId, targetState);
    } catch (e) {
      debugPrint('Failed to toggle seen status: $e');
      if (mounted) {
        setState(() {
          _isWatched = !targetState; // Revert
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Misslyckades att synka visningsstatus: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showFixMatchDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return FixMatchDialog(
          mediaId: widget.mediaId,
          apiService: widget.apiService,
          currentTitle: _mediaData?['title'] ?? '',
          currentYear: _mediaData?['year']?.toString() ?? '',
          isShow: _mediaData?['type']?.toString() == 'Show',
          onMatchSuccess: () {
            _fetchDetails();
          },
        );
      },
    );
  }

  void _playMedia() {
    if (_savedProgressSeconds > 0) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => ResumePlaybackModal(
          savedPositionSeconds: _savedProgressSeconds,
          onResume: () {
            Navigator.pop(dialogContext);
            _startPlayback(_savedProgressSeconds);
          },
          onStartOver: () {
            Navigator.pop(dialogContext);
            _startPlayback(0);
          },
        ),
      );
    } else {
      _startPlayback(0);
    }
  }

  void _startPlayback(int startFromSeconds) {
    final useTranscode = _selectedQuality != 'direct';
    final bitrate = useTranscode ? _selectedQuality : '4000k';
    unawaited(_savePlaybackSettings());
    final playId = _selectedVersionId ?? widget.mediaId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          mediaId: playId,
          apiService: widget.apiService,
          mediaData: _mediaData == null ? null : Map<String, dynamic>.from(_mediaData!),
          startFromSeconds: startFromSeconds,
          useTranscode: useTranscode,
          bitrate: bitrate,
          initialSubtitleIndex: _selectedSubtitleIndex,
          initialAudioIndex: _selectedAudioIndex,
        ),
      ),
    ).then((_) {
      _fetchDetails();
      widget.onVideoPlayerClosed?.call();
    });
  }

  double _normalizeRating(double value) {
    return value.clamp(0.0, 10.0).roundToDouble();
  }

  void _updateRatingPreviewFromHover(dynamic event, double width) {
    final usableWidth = width <= 0 ? 1.0 : width;
    final localPosition = event.localPosition;
    final clampedDx = (localPosition.dx as double).clamp(0.0, usableWidth);
    final preview =
        _normalizeRating(((clampedDx / usableWidth) * 10.0).ceilToDouble());
    setState(() {
      _ratingPreview = preview;
      _isRatingHovering = true;
    });
  }

  Widget _buildPlaybackSelectors(Map<String, dynamic> metadata) {
    // Prefer tracks from the selected version; fall back to global metadata
    final allVersions = (_mediaData?['versions'] as List? ?? []).cast<Map<String, dynamic>>();
    final selectedVer = allVersions.isNotEmpty
        ? allVersions.firstWhere(
            (v) => v['id']?.toString() == _selectedVersionId,
            orElse: () => {},
          )
        : <String, dynamic>{};
    final subtitleTracks = (selectedVer['subtitle_tracks'] is List)
        ? (selectedVer['subtitle_tracks'] as List).cast<Map>()
        : (metadata['subtitle_tracks'] is List)
            ? (metadata['subtitle_tracks'] as List).cast<Map>()
            : <Map>[];
    final audioTracks = (selectedVer['audio_tracks'] is List)
        ? (selectedVer['audio_tracks'] as List).cast<Map>()
        : (metadata['audio_tracks'] is List)
            ? (metadata['audio_tracks'] as List).cast<Map>()
            : <Map>[];

    Widget dropdown<T>({
      required IconData icon,
      required String label,
      required T value,
      required List<DropdownMenuItem<T>> items,
      required ValueChanged<T?> onChanged,
    }) {
      return Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF8A5BFF), size: 14),
            const SizedBox(width: 6),
            Text('$label: ',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
            Flexible(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  dropdownColor: const Color(0xFF15102A),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  isDense: true,
                  isExpanded: true,
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Quality items
    final qualityItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'direct', child: Text('Direct play')),
      const DropdownMenuItem(value: '2000k', child: Text('Transcode 2 Mb')),
      const DropdownMenuItem(value: '5000k', child: Text('Transcode 5 Mb')),
      const DropdownMenuItem(value: '8000k', child: Text('Transcode 8 Mb')),
    ];

    // Subtitle items
    final subtitleItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'none', child: Text('Av')),
      ...subtitleTracks.map((t) {
        final idx = t['index']?.toString() ?? '';
        final label = t['label']?.toString() ?? t['codec']?.toString() ?? idx;
        final lang = t['language']?.toString() ?? '';
        return DropdownMenuItem(
          value: idx,
          child: Text(lang.isEmpty ? label : '$label · $lang',
              overflow: TextOverflow.ellipsis),
        );
      }),
    ];

    // Audio items — no "Auto", user must pick a track
    final audioItems = <DropdownMenuItem<String?>>[
      ...audioTracks.map((t) {
        final idx = t['index']?.toString() ?? '';
        final codec = t['codec']?.toString() ?? 'Audio';
        final lang = t['language']?.toString() ?? '';
        final ch = t['channels']?.toString() ?? '';
        final label = [codec, if (ch.isNotEmpty) '${ch}ch', if (lang.isNotEmpty) lang].join(' · ');
        return DropdownMenuItem(value: idx, child: Text(label, overflow: TextOverflow.ellipsis));
      }),
    ];

    // Build version items
    final versions = _sortedVersions();
    final singleVersion = versions.length <= 1;
    final versionItems = versions.map((v) {
      final id = v['id']?.toString() ?? '';
      return DropdownMenuItem<String>(
        value: id,
        child: Text(_buildVersionLabel(v), overflow: TextOverflow.ellipsis),
      );
    }).toList();
    // Ensure selected value is valid
    final effectiveVersionId = versionItems.any((i) => i.value == _selectedVersionId)
        ? _selectedVersionId
        : (versionItems.isNotEmpty ? versionItems.first.value : widget.mediaId);

    String? effectiveAudio;
    if (audioTracks.isNotEmpty) {
      final firstIdx = audioTracks.first['index']?.toString();
      effectiveAudio = audioItems.any((i) => i.value == _selectedAudioIndex)
          ? _selectedAudioIndex
          : firstIdx;
      if (effectiveAudio != _selectedAudioIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedAudioIndex = effectiveAudio);
        });
      }
    }

    return Row(
      children: [
        if (versionItems.isNotEmpty) ...[
          Expanded(
            child: Opacity(
              opacity: singleVersion ? 0.45 : 1.0,
              child: dropdown<String>(
                icon: Icons.layers_outlined,
                label: 'Version',
                value: effectiveVersionId!,
                items: versionItems,
                onChanged: singleVersion
                    ? (_) {}
                    : (v) {
                        if (v == null) return;
                        setState(() {
                          _selectedVersionId = v;
                          _selectedSubtitleIndex = 'none';
                          _selectedAudioIndex = null;
                        });
                        final ver = (_mediaData?['versions'] as List? ?? [])
                            .cast<Map<String, dynamic>>()
                            .firstWhere((ver) => ver['id']?.toString() == v, orElse: () => {});
                        if (ver.isNotEmpty) _applyLanguageDefaults(Map<String, dynamic>.from(ver));
                      },
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: dropdown<String>(
            icon: Icons.hd_outlined,
            label: 'Kvalitet',
            value: _selectedQuality,
            items: qualityItems,
            onChanged: (v) {
              if (v != null) setState(() => _selectedQuality = v);
              _savePlaybackSettings();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: dropdown<String>(
            icon: Icons.subtitles_outlined,
            label: 'Undertext',
            value: subtitleItems.any((i) => i.value == _selectedSubtitleIndex)
                ? _selectedSubtitleIndex
                : 'none',
            items: subtitleItems,
            onChanged: (v) {
              if (v != null) setState(() => _selectedSubtitleIndex = v);
            },
          ),
        ),
        if (audioTracks.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: dropdown<String?>(
              icon: Icons.audio_file_outlined,
              label: 'Ljud',
              value: effectiveAudio,
              items: audioItems,
              onChanged: (v) => setState(() => _selectedAudioIndex = v),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMyRatingControl() {
    final displayRating = _isRatingHovering && _ratingPreview != null
        ? _ratingPreview!
        : _myRating;
    final displayText = displayRating.toStringAsFixed(0);
    final glowColor = _isRatingFlashing
        ? const Color(0xFFFFD65C)
        : (_isRatingHovering
            ? const Color(0xFFB593FF)
            : const Color(0xFF8A5BFF));

    Widget buildChip(int rating) {
      final isSelected = rating == displayRating.round();
      final isHovered = _isRatingHovering && _ratingPreview?.round() == rating;
      final chipGlow = _isRatingFlashing && isSelected
          ? const Color(0xFFFFD65C)
          : (isHovered ? const Color(0xFFB593FF) : const Color(0xFF8A5BFF));

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() {
          _isRatingHovering = true;
          _ratingPreview = rating.toDouble();
        }),
        child: GestureDetector(
          onTap: () => _onRatingChangeEnd(rating.toDouble()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? chipGlow.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: chipGlow.withValues(
                      alpha: isSelected || isHovered ? 0.9 : 0.22),
                  width: isSelected ? 1.3 : 1.0),
              boxShadow: [
                BoxShadow(
                  color: chipGlow.withValues(
                      alpha: isHovered || isSelected ? 0.36 : 0.08),
                  blurRadius: isHovered || isSelected ? 10 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              '$rating',
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onExit: (_) => setState(() {
        _isRatingHovering = false;
        _ratingPreview = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Colors.white.withValues(
                  alpha: _isRatingHovering || _isRatingFlashing ? 0.12 : 0.04)),
        ),
        child: Row(
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isResetHovering = true),
              onExit: (_) => setState(() => _isResetHovering = false),
              child: GestureDetector(
                onTap: () => _onRatingChangeEnd(0.0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isResetHovering
                        ? const Color(0xFFB9536F)
                        : const Color(0xFF8A5BFF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Text(
                    _isResetHovering ? 'NOLLSTÄLL BETYG' : 'MITT BETYG',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(10, (index) {
                    final rating = index + 1;
                    if (index != 0) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: buildChip(rating),
                      );
                    }
                    return buildChip(rating);
                  }),
                ),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedScale(
              scale: _isRatingFlashing ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 1.3, end: 1.0).animate(
                          CurvedAnimation(
                              parent: animation, curve: Curves.easeOutBack)),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  displayText,
                  key: ValueKey('rating-$_ratingFlashNonce-$displayText'),
                  style: TextStyle(
                    color: _isRatingFlashing
                        ? const Color(0xFFFFF4B0)
                        : const Color(0xFFE7D7FF),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    shadows: [
                      Shadow(
                          color: glowColor.withValues(alpha: 0.8),
                          blurRadius: _isRatingFlashing ? 12 : 8),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('/ 10',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildShowStatusBadge(String status, {Map<String, dynamic>? nextEpisodeToAir}) {
    final String label;
    final Color color;
    final IconData icon;
    String? returnDate;

    switch (status.toLowerCase()) {
      case 'returning series':
        color = const Color(0xFF4CAF50);
        icon = Icons.fiber_manual_record;
        if (nextEpisodeToAir != null) {
          final airDate = nextEpisodeToAir['air_date']?.toString() ?? '';
          if (airDate.isNotEmpty) {
            returnDate = airDate;
            label = 'Återkommer $airDate';
          } else {
            label = 'Pågående';
          }
        } else {
          label = 'Pågående';
        }
        break;
      case 'ended':
        label = 'Avslutat';
        color = Colors.white38;
        icon = Icons.stop_circle_outlined;
        break;
      case 'canceled':
      case 'cancelled':
        label = 'Inställt';
        color = Colors.redAccent;
        icon = Icons.cancel_outlined;
        break;
      case 'in production':
        label = 'Under produktion';
        color = const Color(0xFFFFAB40);
        icon = Icons.construction_outlined;
        break;
      case 'planned':
        label = 'Planerad';
        color = const Color(0xFF64B5F6);
        icon = Icons.schedule_outlined;
        break;
      default:
        label = status;
        color = Colors.white38;
        icon = Icons.info_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(returnDate != null ? Icons.calendar_today_outlined : icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        ],
      ),
    );
  }

  Widget _buildCrewRow(String label, List<Map<String, dynamic>> people) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: people.map((person) {
          final name = person['name'] as String? ?? '';
          final id = person['id']?.toString();
          return ActionChip(
            mouseCursor: id != null ? SystemMouseCursors.click : MouseCursor.defer,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            label: RichText(
              text: TextSpan(children: [
                TextSpan(text: '$label ', style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                TextSpan(text: name, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ),
            onPressed: id != null ? () {
              if (widget.onPersonSelected != null) {
                widget.onPersonSelected!(id);
              } else {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => PersonDetailsScreen(personId: id, apiService: widget.apiService),
                ));
              }
            } : null,
          );
        }).toList(),
      ),
    );
  }

  String _buildTrailerSearchUrl(String title, String year) {
    return 'https://www.youtube.com/results?search_query=${Uri.encodeComponent("$title $year Official Trailer")}';
  }

  Future<void> _launchTrailer(
      String? trailerUrl, String title, String year) async {
    final finalTrailerUrl = trailerUrl ?? _buildTrailerSearchUrl(title, year);
    
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => VideoPlayerScreen(
        mediaId: widget.mediaId,
        apiService: widget.apiService,
        mediaData: _mediaData,
        trailerYoutubeUrl: finalTrailerUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0714),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF))),
      );
    }

    if (_error != null || _mediaData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0714),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              Text('Failed to load media details:\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              const Text(
                'Använd vänstermenyn för att gå tillbaka.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    final media = _mediaData!;

    // Intercept system back when viewing episode list — go to season overview first
    return PopScope(
      canPop: _seasonOverviewMode,
      onPopInvoked: (didPop) {
        if (!didPop) setState(() => _seasonOverviewMode = true);
      },
      child: _buildContent(context, media),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> media) {
    final title = media['title'] ?? 'Unknown Title';
    final year = media['year']?.toString() ?? '';
    final plot = media['plot'] ?? 'Ingen beskrivning tillgänglig.';
    final posterPath = media['poster_path'];
    final fanartPath = media['fanart_path'];
    final collectionName = media['collection_name'];
    final collectionId = media['collection_id'];
    final trailerUrl = media['metadata']?['trailer_url'];
    final metadata = (media['metadata'] is Map)
        ? media['metadata'] as Map<String, dynamic>
        : {};
    final tagline = metadata['tagline'] as String?;
    final genresList = (media['genre'] as String? ?? '')
        .split(', ')
        .where((g) => g.isNotEmpty)
        .toList();
    final ratings = (metadata['ratings'] is Map)
        ? metadata['ratings'] as Map<String, dynamic>
        : {};
    final cast =
        (metadata['cast'] is List) ? metadata['cast'] as List<dynamic> : [];
    final keywords = (metadata['keywords'] is List)
        ? metadata['keywords'] as List<dynamic>
        : [];
    final productionCompanies = (metadata['production_companies'] is List)
        ? metadata['production_companies'] as List<dynamic>
        : [];
    final productionCountries = (metadata['production_countries'] is List)
        ? metadata['production_countries'] as List<dynamic>
        : [];
    // Director is now stored as an object with id and name
    final directorData = metadata['director'] is Map
        ? metadata['director'] as Map<String, dynamic>
        : metadata['director'] is String
            ? {'name': metadata['director']}
            : null;
    final directorName = directorData?['name'] as String?;
    final directorId = directorData?['id']?.toString();

    List<Map<String, dynamic>> parseCrewList(dynamic raw) {
      if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (raw is String) {
        try { return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(); } catch (_) {}
      }
      return [];
    }
    final producers = parseCrewList(metadata['producers']);
    final writers = parseCrewList(metadata['writers']);
    final composers = parseCrewList(metadata['composers']);

    // TV-serie specifik data
    final isShow = (media['type']?.toString() ?? '') == 'Show';
    final showStatus = metadata['status']?.toString();
    final nextEpisodeRaw = metadata['next_episode_to_air'];
    final nextEpisodeToAir = nextEpisodeRaw is Map<String, dynamic>
        ? nextEpisodeRaw
        : (nextEpisodeRaw is String && nextEpisodeRaw.isNotEmpty)
            ? (() { try { return Map<String, dynamic>.from(jsonDecode(nextEpisodeRaw) as Map); } catch (_) { return null; } })()
            : null;
    final createdBy = parseCrewList(metadata['created_by']);
    final networks = (metadata['networks'] is List)
        ? (metadata['networks'] as List<dynamic>).map((n) => n.toString()).toList()
        : metadata['networks'] is String
            ? [metadata['networks'].toString()]
            : <String>[];

    final logoPath = metadata['logo_path'] as String?;
    final providers = (metadata['watch_providers'] is Map &&
            metadata['watch_providers']['SE'] is Map)
        ? (metadata['watch_providers']['SE']['flatrate'] as List<dynamic>? ??
            [])
        : [];
    final awardsValue = metadata['awards'] ??
        metadata['awards_text'] ??
        metadata['award'] ??
        metadata['prizes'] ??
        metadata['omdb_awards'] ??
        metadata['imdb_awards'];
    final awardsString =
        awardsValue is String ? awardsValue : awardsValue?.toString();

    debugPrint(
        '[Flutter Details] Metadata rating keys present: ${metadata.keys.where((k) => k.contains("rating") || k.contains("vote")).toList()}');
    debugPrint(
        '[Flutter Details] imdb_rating: ${metadata["imdb_rating"]} (${metadata["imdb_rating"].runtimeType}), simkl_rating: ${metadata["simkl_rating"]} (${metadata["simkl_rating"].runtimeType}), trakt_rating: ${metadata["trakt_rating"]} (${metadata["trakt_rating"].runtimeType})');

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fanart & Hero Column
            Stack(
              children: [
                // Background fanart with mask
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  width: double.infinity,
                  child: fanartPath != null
                      ? ShaderMask(
                          shaderCallback: (rect) {
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black,
                                Colors.black,
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.45, 1.0],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.dstIn,
                          child: Image.network(fanartPath, fit: BoxFit.cover),
                        )
                      : Container(color: const Color(0xFF15102A)),
                ),

                // Hero Content overlay
                Positioned(
                  bottom: 0,
                  left: 40,
                  right: 40,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Poster column with logo above
                      if (posterPath != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ClearLOGO above poster (constrained to poster width)
                            if (logoPath != null) ...[
                              SizedBox(
                                width: 220,
                                height: 80,
                                child: Image.network(
                                  logoPath,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            // Poster with hover effect
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              onEnter: (_) =>
                                  setState(() => _isCoverHovered = true),
                              onExit: (_) =>
                                  setState(() => _isCoverHovered = false),
                              child: Listener(
                                onPointerDown: widget.mediaId.startsWith('external_') ? null : (event) {
                                  if (event.buttons == kSecondaryMouseButton) {
                                    widget.onContextMenu?.call(widget.mediaId, event.position);
                                  }
                                },
                                child: GestureDetector(
                                onTap: widget.mediaId.startsWith('external_')
                                    ? _toggleWatchlist
                                    : _playMedia,
                                child: Container(
                                  width: 220,
                                  height: 330,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.6),
                                          blurRadius: 24,
                                          offset: const Offset(0, 12)),
                                    ],
                                    image: DecorationImage(
                                        image: NetworkImage(posterPath),
                                        fit: BoxFit.cover),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      children: [
                                        AnimatedOpacity(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          opacity: _isCoverHovered ? 1.0 : 0.0,
                                          child: Container(
                                            color: Colors.black
                                                .withValues(alpha: 0.55),
                                            child: Center(
                                              child: CircleAvatar(
                                                radius: 36,
                                                backgroundColor:
                                                    const Color(0xFF8A5BFF),
                                                child: Icon(
                                                  widget.mediaId.startsWith(
                                                          'external_')
                                                      ? (_isInWatchlist
                                                          ? Icons
                                                              .playlist_add_check
                                                          : Icons.playlist_add)
                                                      : Icons.play_arrow,
                                                  size: 40,
                                                  color: Colors.white,
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
                            // Runtime (speltid) under poster
                            Builder(builder: (context) {
                              final meta = _mediaData?['metadata'] ?? {};
                              int durationSec = int.tryParse(meta['duration']?.toString() ?? '') ?? 0;
                              if (durationSec == 0) {
                                final runtimeMinutes = int.tryParse(meta['runtime']?.toString() ?? '') ?? 0;
                                durationSec = runtimeMinutes * 60;
                              }
                              if (durationSec == 0) return const SizedBox.shrink();
                              final totalMin = (durationSec / 60).round();
                              final h = totalMin ~/ 60;
                              final m = totalMin % 60;
                              final label = h > 0 ? '${h}h ${m}min' : '${m}min';
                              return Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Container(
                                  width: 220,
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.schedule, color: Colors.white38, size: 13),
                                      const SizedBox(width: 5),
                                      Text(
                                        label,
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),

                            // Progress bar and minutes-left when in-progress
                            if (_savedProgressSeconds > 0) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 220,
                                child: Builder(builder: (context) {
                                  final meta = _mediaData?['metadata'] ?? {};
                                  int durationSec = int.tryParse(
                                          meta['duration']?.toString() ?? '') ??
                                      0;
                                  if (durationSec == 0) {
                                    final runtimeMinutes = int.tryParse(
                                            meta['runtime']?.toString() ??
                                                '') ??
                                        0;
                                    durationSec = runtimeMinutes * 60;
                                  }
                                  if (durationSec == 0) {
                                    durationSec =
                                        7200; // 120 min fallback to prevent indeterminate/rolling line
                                  }
                                  final progress = _savedProgressSeconds;
                                  final ratio =
                                      (progress / durationSec).clamp(0.0, 1.0);
                                  final playedMin = (progress / 60).ceil();
                                  final leftMin =
                                      ((durationSec - progress) / 60).ceil();

                                  return Column(
                                    children: [
                                      LinearProgressIndicator(
                                        value: ratio,
                                        color: const Color(0xFF8A5BFF),
                                        backgroundColor: Colors.white12,
                                        minHeight: 4,
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8, horizontal: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.08)),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$playedMin min spelat, ${leftMin > 0 ? leftMin : 0} min kvar',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ] else if (_isWatched) ...[
                              const SizedBox(height: 12),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: _toggleWatchStatus,
                                  child: Container(
                                    width: 220,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: const Color(0xFF00E676)
                                              .withValues(alpha: 0.4),
                                          width:
                                              1.2), // neon green glowing border
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF00E676)
                                              .withValues(alpha: 0.1),
                                          blurRadius: 4,
                                        )
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            color: Color(0xFF00E676), size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Sedd',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      const SizedBox(width: 40),

                      // Title & Metadata info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Favorite star + Title row
                            if (!widget.mediaId.startsWith('external_'))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: _isFavorite ? 'Ta bort favorit' : 'Markera som favorit',
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: _toggleFavorite,
                                          child: AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 200),
                                            child: Text(
                                              String.fromCharCode((_isFavorite ? Icons.star : Icons.star_border).codePoint),
                                              key: ValueKey(_isFavorite),
                                              style: TextStyle(
                                                fontFamily: Icons.star.fontFamily,
                                                package: Icons.star.fontPackage,
                                                fontSize: 28,
                                                color: _isFavorite ? const Color(0xFFFFD65C) : Colors.white,
                                                shadows: const [
                                                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1.5, 1.5)),
                                                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(-1.5, 1.5)),
                                                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1.5, -1.5)),
                                                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(-1.5, -1.5)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Title (Year) with translated/original logic
                            Builder(
                              builder: (context) {
                                final originalTitle =
                                    media['original_title'] as String?;
                                final hasOriginal = originalTitle != null &&
                                    originalTitle.isNotEmpty;
                                final isOriginalStyle =
                                    _titleDisplayStyle == 'Original';

                                String mainDisplayTitle = title;
                                String? subtitleDisplayTitle;

                                if (isOriginalStyle && hasOriginal) {
                                  mainDisplayTitle = originalTitle;
                                  if (originalTitle.toLowerCase() !=
                                      title.toLowerCase()) {
                                    subtitleDisplayTitle =
                                        'Översatt titel: $title';
                                  }
                                } else if (!isOriginalStyle && hasOriginal) {
                                  mainDisplayTitle = title;
                                  if (originalTitle.toLowerCase() !=
                                      title.toLowerCase()) {
                                    subtitleDisplayTitle =
                                        'Originaltitel: $originalTitle';
                                  }
                                }

                                final releaseVersion =
                                    metadata['release_version']?.toString() ??
                                        '';
                                final versionSuffix = _showReleaseVersion && releaseVersion.isNotEmpty
                                    ? ' [$releaseVersion]'
                                    : '';

                                // For ended shows show year range (xxxx–xxxx), for ongoing show (xxxx–)
                                String yearDisplay = year;
                                if (isShow && year.isNotEmpty) {
                                  final statusLower = (showStatus ?? '').toLowerCase();
                                  if (statusLower == 'ended' || statusLower == 'canceled' || statusLower == 'cancelled') {
                                    final lastAirRaw = metadata['last_air_date']?.toString() ?? '';
                                    if (lastAirRaw.length >= 4) {
                                      final endYear = lastAirRaw.substring(0, 4);
                                      if (endYear != year) yearDisplay = '$year–$endYear';
                                    }
                                  } else if (statusLower.isNotEmpty) {
                                    yearDisplay = '$year–';
                                  }
                                }

                                final displayTitle = yearDisplay.isNotEmpty
                                    ? '$mainDisplayTitle ($yearDisplay)$versionSuffix'
                                    : '$mainDisplayTitle$versionSuffix';

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Stack(
                                      children: [
                                        Text(
                                          displayTitle,
                                          style: TextStyle(
                                            fontSize: 44,
                                            fontWeight: FontWeight.bold,
                                            height: 1.1,
                                            letterSpacing: -0.5,
                                            foreground: Paint()
                                              ..style = PaintingStyle.stroke
                                              ..strokeWidth = 2.2
                                              ..color = Colors.black,
                                          ),
                                        ),
                                        Text(
                                          displayTitle,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 44,
                                            fontWeight: FontWeight.bold,
                                            height: 1.1,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (subtitleDisplayTitle != null) ...[
                                      const SizedBox(height: 6),
                                      Stack(
                                        children: [
                                          Text(
                                            subtitleDisplayTitle,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontStyle: FontStyle.italic,
                                              fontWeight: FontWeight.w500,
                                              foreground: Paint()
                                                ..style = PaintingStyle.stroke
                                                ..strokeWidth = 1.8
                                                ..color = Colors.black,
                                            ),
                                          ),
                                          Text(
                                            subtitleDisplayTitle,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.85),
                                              fontSize: 16,
                                              fontStyle: FontStyle.italic,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),

                            // Show status badge
                            if (isShow && showStatus != null && showStatus.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _buildShowStatusBadge(showStatus, nextEpisodeToAir: nextEpisodeToAir),
                            ],

                            // Skapare (Creator/Showrunner) for shows
                            if (isShow && createdBy.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildCrewRow('Skapare', createdBy),
                            ],

                            // Director for movies
                            if (!isShow && directorName != null) ...[
                              const SizedBox(height: 8),
                              _buildCrewRow('Regi', [{'name': directorName, 'id': directorId}]),
                            ],

                            // Producers (Producent)
                            if (producers.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _buildCrewRow('Producent', producers),
                            ],

                            // Writers (Manus)
                            if (writers.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _buildCrewRow('Manus', writers),
                            ],

                            // Composers (Musik)
                            if (composers.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _buildCrewRow('Musik', composers),
                            ],

                            const SizedBox(height: 12),

                            // Subtitle Metadata details with highly legible high-contrast outlines
                            Row(
                              children: [
                                // PG Box with drop shadow and outline
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    border: Border.all(
                                        color: Colors.black, width: 2),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.5),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2)),
                                    ],
                                  ),
                                  child: const Text('PG-13',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      )),
                                ),
                                const SizedBox(width: 16),

                                // Collection Banner with clear black outline
                                if (collectionName != null &&
                                    collectionName.toString().isNotEmpty) ...[
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () {
                                        _showCollectionDialog(
                                            collectionName.toString(),
                                            collectionId?.toString());
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFB593FF)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2)),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.layers,
                                                color: Color(0xFFB593FF),
                                                size: 14),
                                            const SizedBox(width: 6),
                                            Text(
                                              collectionName.toString(),
                                              style: const TextStyle(
                                                color: Color(0xFFB593FF),
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (productionCompanies.isNotEmpty ||
                                productionCountries.isNotEmpty) ...[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ...productionCompanies.take(3).map((company) {
                                    final companyName = company is Map
                                        ? (company['name']?.toString() ?? '')
                                        : company.toString();
                                    final logoPath = company is Map
                                        ? company['logo_path']?.toString()
                                        : null;

                                    if (companyName.isEmpty)
                                      return const SizedBox.shrink();

                                    if (logoPath != null && logoPath.isNotEmpty) {
                                      return Tooltip(
                                        message: companyName,
                                        child: Container(
                                          height: 32,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.06),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                          ),
                                          child: Image.network(
                                            logoPath,
                                            height: 24,
                                            fit: BoxFit.contain,
                                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.business, size: 16),
                                          ),
                                        ),
                                      );
                                    }

                                    return Chip(
                                      avatar: const Icon(Icons.business,
                                          size: 16, color: Color(0xFF8A5BFF)),
                                      label: Text(companyName,
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.06),
                                      side: BorderSide(
                                          color: Colors.white
                                              .withValues(alpha: 0.08)),
                                    );
                                  }),
                                  ...productionCountries.map((country) {
                                    final countryName = country is Map
                                        ? (country['name']?.toString() ?? '')
                                        : country.toString();
                                    final isoRaw = country is Map
                                        ? (country['iso_3166_1']?.toString() ??
                                            '')
                                        : '';
                                    final iso = isoRaw.toUpperCase();
                                    if (countryName.isEmpty)
                                      return const SizedBox.shrink();

                                    return Tooltip(
                                      message: countryName,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.06),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.08)),
                                        ),
                                        child: (iso.length == 2)
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                                child: Image.network(
                                                  'https://flagcdn.com/w20/${iso.toLowerCase()}.png',
                                                  width: 20,
                                                  height: 14,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      Text(iso,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .white54)),
                                                ),
                                              )
                                            : Text(
                                                countryName,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white70),
                                              ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],

                            // Clickable Genre Badges
                            Wrap(
                              spacing: 8,
                              children: genresList.map((g) {
                                return ActionChip(
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.06),
                                  side: BorderSide(
                                      color:
                                          Colors.white.withValues(alpha: 0.08)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  label: Text(g,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                  onPressed: () {
                                    final isShow = _mediaData?['type']?.toString() == 'Show';
                                    if (isShow && widget.onShowGenreSelected != null) {
                                      widget.onShowGenreSelected!(g);
                                    } else if (widget.onGenreSelected != null) {
                                      widget.onGenreSelected!(g);
                                    } else {
                                      Navigator.pop(context, g);
                                    }
                                  },
                                );
                              }).toList(),
                            ),

                            // Awards / Priser placed directly under Genre
                            _buildAwardsRow(awardsString),
                            const SizedBox(height: 24),

                            // Control Actions Row
                            Row(
                              children: [
                                if (widget.mediaId.startsWith('external_')) ...[
                                  // Watchlist Add/Remove Action for external item
                                  ElevatedButton.icon(
                                    onPressed: _isWatchlistLoading
                                        ? null
                                        : _toggleWatchlist,
                                    icon: _isWatchlistLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2),
                                          )
                                        : Icon(
                                            _isInWatchlist
                                                ? Icons.playlist_add_check
                                                : Icons.playlist_add,
                                            size: 28),
                                    label: Text(
                                      _isInWatchlist
                                          ? 'I bevakningslistan'
                                          : 'Lägg till i bevakningslista',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isInWatchlist
                                          ? const Color(0xFF281E46)
                                          : const Color(0xFF8A5BFF),
                                      foregroundColor: Colors.white,
                                      side: _isInWatchlist
                                          ? const BorderSide(
                                              color: Color(0xFF8A5BFF),
                                              width: 1.5)
                                          : null,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 36, vertical: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(30)),
                                      elevation: 8,
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  if (trailerUrl != null &&
                                      trailerUrl.toString().isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(right: 16),
                                      child: OutlinedButton.icon(
                                        onPressed: () => _launchTrailer(
                                            trailerUrl.toString(),
                                            title.toString(),
                                            year.toString()),
                                        icon: const Icon(Icons.slideshow,
                                            size: 22, color: Colors.white),
                                        label: const Text('Trailer',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold)),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                              color: Colors.white54,
                                              width: 1.5),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 16),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(30)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ] else ...[
                                  ElevatedButton.icon(
                                    onPressed: _playMedia,
                                    icon:
                                        const Icon(Icons.play_arrow, size: 28),
                                    label: Text(
                                      _savedProgressSeconds > 0
                                          ? 'Återuppta'
                                          : 'Spela',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF8A5BFF),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 36, vertical: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(30)),
                                      elevation: 8,
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  Padding(
                                    padding: const EdgeInsets.only(right: 16),
                                    child: OutlinedButton.icon(
                                      onPressed: () => _launchTrailer(
                                          trailerUrl?.toString(),
                                          title.toString(),
                                          year.toString()),
                                      icon: const Icon(Icons.slideshow,
                                          size: 22, color: Colors.white),
                                      label: const Text('Trailer',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: Colors.white54, width: 1.5),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 16),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(30)),
                                      ),
                                    ),
                                  ),

                                  // Dynamic kebab Menu button frambringande av actions
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Theme(
                                      data: Theme.of(context).copyWith(
                                        cardColor: const Color(0xFF15102A),
                                      ),
                                      child: PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_horiz,
                                            size: 26, color: Colors.white70),
                                        tooltip: 'Fler åtgärder',
                                        onSelected: (value) async {
                                          if (value == 'playlist') {
                                            _showPlaylistDialog();
                                          } else if (value == 'watch') {
                                            _toggleWatchStatus();
                                          } else if (value == 'refresh') {
                                            try {
                                              setState(() => _isLoading = true);
                                              await widget.apiService
                                                  .refreshMediaMetadata(
                                                      widget.mediaId);
                                              _fetchDetails();
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'Metadata har uppdaterats online!'),
                                                    backgroundColor:
                                                        Color(0xFF8A5BFF)),
                                              );
                                            } catch (e) {
                                              setState(
                                                  () => _isLoading = false);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'Misslyckades uppdatera: $e'),
                                                    backgroundColor:
                                                        Colors.redAccent),
                                              );
                                            }
                                          } else if (value == 'analyze') {
                                            try {
                                              setState(() => _isLoading = true);
                                              await widget.apiService
                                                  .analyzeMediaItem(
                                                      widget.mediaId);
                                              _fetchDetails();
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'Mediefilen har analyserats om!'),
                                                    backgroundColor:
                                                        Color(0xFF8A5BFF)),
                                              );
                                            } catch (e) {
                                              setState(
                                                  () => _isLoading = false);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'Misslyckades analysera: $e'),
                                                    backgroundColor:
                                                        Colors.redAccent),
                                              );
                                            }
                                          } else if (value == 'match') {
                                            _showFixMatchDialog();
                                          } else if (value == 'unmatch') {
                                            try {
                                              setState(() => _isLoading = true);
                                              await widget.apiService
                                                  .unmatchMediaItem(
                                                      widget.mediaId);
                                              _fetchDetails();
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'Matchning borttagen!'),
                                                    backgroundColor:
                                                        Color(0xFF8A5BFF)),
                                              );
                                            } catch (e) {
                                              setState(
                                                  () => _isLoading = false);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'Misslyckades ta bort matchning: $e'),
                                                    backgroundColor:
                                                        Colors.redAccent),
                                              );
                                            }
                                          } else if (value == 'delete') {
                                            // Confirm dialog
                                            final confirm =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                backgroundColor:
                                                    const Color(0xFF15102A),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                                                ),
                                                title: const Row(
                                                  children: [
                                                    Icon(Icons.delete_outline, color: Colors.redAccent, size: 24),
                                                    SizedBox(width: 10),
                                                    Text('Flytta till papperskorg?',
                                                        style: TextStyle(color: Colors.white, fontSize: 18)),
                                                  ],
                                                ),
                                                content: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Filmen tas bort från biblioteket och filen på hårddisken flyttas till en .trash-mapp.',
                                                      style: const TextStyle(color: Colors.white70, height: 1.4),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Container(
                                                      padding: const EdgeInsets.all(10),
                                                      decoration: BoxDecoration(
                                                        color: Colors.redAccent.withValues(alpha: 0.08),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                                                      ),
                                                      child: const Row(
                                                        children: [
                                                          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                                                          SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              'Filen raderas från hårddisken om du tömmer papperskorgen i Inställningar.',
                                                              style: TextStyle(color: Colors.orange, fontSize: 12, height: 1.4),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                actions: [
                                                  OutlinedButton(
                                                    onPressed: () => Navigator.pop(ctx, false),
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Colors.white70,
                                                      side: const BorderSide(color: Colors.white24),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    child: const Text('Avbryt'),
                                                  ),
                                                  ElevatedButton.icon(
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    icon: const Icon(Icons.delete_outline, size: 18),
                                                    label: const Text('Flytta till papperskorg'),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.redAccent,
                                                      foregroundColor: Colors.white,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              try {
                                                await widget.apiService
                                                    .deleteMediaItem(
                                                        widget.mediaId);
                                                if (widget.onBack != null) {
                                                  widget.onBack!();
                                                } else {
                                                  Navigator.pop(context);
                                                }
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'Media raderad från biblioteket.'),
                                                      backgroundColor:
                                                          Color(0xFF8A5BFF)),
                                                );
                                              } catch (e) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content: Text(
                                                          'Misslyckades ta bort: $e'),
                                                      backgroundColor:
                                                          Colors.redAccent),
                                                );
                                              }
                                            }
                                          } else if (value == 'scan_chapters') {
                                            try {
                                              await widget.apiService.scanChapters(widget.mediaId);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Kapitelskanning startad i bakgrunden. Intro/outro-knappar visas när det är klart!'),
                                                  backgroundColor: Color(0xFF8A5BFF),
                                                  duration: Duration(seconds: 4),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Skanning misslyckades: $e'), backgroundColor: Colors.redAccent),
                                              );
                                            }
                                          } else if (value == 'edit') {
                                            widget.onEdit?.call();
                                          } else if (value == 'info') {
                                            showDialog(
                                              context: context,
                                              barrierDismissible: true,
                                              builder: (_) => MediaInfoDialog(
                                                mediaId: widget.mediaId,
                                                title: _mediaData?['title']?.toString() ?? 'Media',
                                                apiService: widget.apiService,
                                              ),
                                            );
                                          } else if (value == 'statistics') {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Statistik kommer snart!'),
                                                backgroundColor:
                                                    Color(0xFF8A5BFF),
                                              ),
                                            );
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'playlist',
                                            child: Text(
                                                'Lägg till på spellista',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          PopupMenuItem(
                                            value: 'watch',
                                            child: Text(
                                                _isWatched
                                                    ? 'Markera som osedd'
                                                    : 'Markera som visad',
                                                style: const TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'refresh',
                                            child: Text('Uppdatera metadata',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'analyze',
                                            child: Text('Analysera',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          if (!widget.mediaId.startsWith('external_'))
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Redigera', style: TextStyle(color: Colors.white)),
                                            ),
                                          const PopupMenuItem(
                                            value: 'match',
                                            child: Text('Fixa matchning',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'unmatch',
                                            child: Text('Ta bort matchning',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'scan_chapters',
                                            child: Text('Skanna kapitel/intro',
                                                style: TextStyle(
                                                    color: Colors.white70)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Ta bort',
                                                style: TextStyle(
                                                    color: Colors.redAccent)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'info',
                                            child: Text('Info',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'statistics',
                                            child: Text('Visa statistik',
                                                style: TextStyle(
                                                    color: Colors.white30)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Content & Ratings
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overview & Streams info (2/3 width)
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Raw Tagline italicized right above Plot (Handling) without 'Tagline:' prefix text
                        if (tagline != null && tagline.trim().isNotEmpty) ...[
                          Text(
                            tagline,
                            style: const TextStyle(
                              color: Color(0xFFB593FF),
                              fontSize: 19,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          plot,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 17, height: 1.6),
                        ),
                        const SizedBox(height: 20),

                        // Streaming Watch Providers
                        if (providers.isNotEmpty) ...[
                          const Text('Finns att strömma på',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: providers.map((prov) {
                              final logoPath = prov['logo_path'];
                              final name = prov['provider_name'];
                              if (logoPath == null) return const SizedBox();
                              return Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white12),
                                  image: DecorationImage(
                                    image: NetworkImage(
                                        'https://image.tmdb.org/t/p/w500$logoPath'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: Tooltip(message: name ?? ''),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ── Playback settings dropdowns ──────────────
                        _buildPlaybackSelectors(Map<String, dynamic>.from(metadata)),
                        const SizedBox(height: 16),

                        // Keywords section placed within left column
                        if (keywords.isNotEmpty) ...[
                          _KeywordsExpandableContainer(
                            keywords: keywords,
                            onKeywordSelected: (label) {
                              if (widget.onKeywordSelected != null) {
                                widget.onKeywordSelected!(label);
                              } else if (widget.onGenreSelected != null) {
                                widget.onGenreSelected!(label);
                              } else {
                                Navigator.pop(context, label);
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                        ],

                      ],
                    ),
                  ),
                  const SizedBox(width: 60),

                  // Ratings Panel (1/3 width) - Shifted upwards and gap minimized
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.04)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Betyg',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 20),
                          _buildMyRatingControl(),
                          const SizedBox(height: 8),

                          // Order: IMDb, Simkl, Trakt, TMDB
                          _buildRatingRow(
                            'IMDb',
                            '${_formatRating(metadata['imdb_rating'])} / 10',
                            const Color(0xFFF5C518),
                            url: media['imdb_id'] != null
                                ? 'https://www.imdb.com/title/${media['imdb_id']}'
                                : 'https://www.imdb.com/find/?q=${Uri.encodeComponent(media['title']?.toString() ?? '')}',
                            votes: _formatVotes(metadata['imdb_votes']),
                          ),
                          _buildRatingRow(
                            'TMDB',
                            '${_formatRating(ratings['tmdb'])} / 10',
                            const Color(0xFF03B6E1),
                            url: media['tmdb_id'] != null
                                ? (media['type']?.toString().toLowerCase() == 'show' ||
                                        media['type']?.toString().toLowerCase() == 'tv'
                                    ? 'https://www.themoviedb.org/tv/${media['tmdb_id']}'
                                    : 'https://www.themoviedb.org/movie/${media['tmdb_id']}')
                                : 'https://www.themoviedb.org/search?query=${Uri.encodeComponent(media['title']?.toString() ?? '')}',
                            votes: _formatVotes(ratings['tmdb_votes']),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Seasons & Episodes for TV shows — shown ABOVE cast
            if (media['type'] == 'Show' && media['episodes'] is List && (media['episodes'] as List).isNotEmpty)
              _buildSeasonsSection(media['episodes'] as List<dynamic>),

            // Cast Carousel
            if (cast.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text('Skådespelare',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 230,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  scrollDirection: Axis.horizontal,
                  itemCount: cast.length,
                  itemBuilder: (context, index) {
                    final actor = cast[index];
                    final actorId = actor['id']?.toString();

                    return HoverableBuilder(
                      builder: (context, isHovered) {
                        return GestureDetector(
                          onTap: () {
                              if (actorId != null) {
                                if (widget.onPersonSelected != null) {
                                  widget.onPersonSelected!(actorId);
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PersonDetailsScreen(
                                        personId: actorId,
                                        apiService: widget.apiService,
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Container(
                              width: 140,
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 160,
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color:
                                              Colors.white.withValues(alpha: isHovered ? 0.3 : 0.04)),
                                      image: actor['profile_path'] != null
                                          ? DecorationImage(
                                              image: NetworkImage(
                                                  actor['profile_path']),
                                              fit: BoxFit.cover)
                                          : null,
                                    ),
                                    foregroundDecoration: isHovered
                                        ? BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          )
                                        : null,
                                child: actor['profile_path'] == null
                                    ? const Center(
                                        child: Icon(Icons.person,
                                            size: 50, color: Colors.white24))
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              Text(actor['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(actor['character'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      );
                    }
                  );
                  },
                ),
              ),
              const SizedBox(height: 30),
            ],

            // Collection Chronology horizontal scroll under Cast
            if (collectionId != null && collectionId.toString().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text('$collectionName',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: _collectionItemsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                      child: Text('Laddar samling...',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 14)),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return const SizedBox.shrink();
                  }
                  final collectionData = snapshot.data!;
                  final parts = collectionData['items'] as List<dynamic>? ?? [];
                  if (parts.isEmpty) return const SizedBox.shrink();

                  return SizedBox(
                    height: 260,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      scrollDirection: Axis.horizontal,
                      itemCount: parts.length,
                      itemBuilder: (context, index) {
                        final item = parts[index] as Map<String, dynamic>;
                        final poster = item['poster_path'];
                        final title = item['title'] ?? 'Okänd';
                        final year =
                            item['year'] != null ? ' (${item['year']})' : '';
                        final localId = item['id']?.toString() ?? '';
                        final tmdbId = item['tmdb_id']?.toString();
                        final inLibrary = localId.isNotEmpty;
                        final isCurrent = localId == widget.mediaId;

                        return HoverableBuilder(
                          builder: (context, isHovered) {
                            return Opacity(
                              opacity: inLibrary ? 1.0 : 0.45,
                              child: GestureDetector(
                                onTap: () {
                                  if (localId.isNotEmpty) {
                                    widget.onMediaSelected?.call(localId);
                                  } else if (tmdbId != null) {
                                    widget.onMediaSelected?.call('external_movie_$tmdbId');
                                  }
                                },
                                child: Container(
                                  width: 140,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        height: 210,
                                        clipBehavior: Clip.antiAlias,
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: isHovered ? 0.3 : 0.06),
                                            width: 1.0,
                                          ),
                                        ),
                                        foregroundDecoration: isHovered
                                            ? BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(12),
                                              )
                                            : null,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (poster != null)
                                              Image.network(
                                            poster.toString(),
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              return const Center(
                                                  child: Icon(Icons.movie,
                                                      size: 50,
                                                      color: Colors.white24));
                                            },
                                          )
                                        else
                                          const Center(
                                              child: Icon(Icons.movie,
                                                  size: 50,
                                                  color: Colors.white24)),

                                        // Top-left watched checkmark badge
                                        Positioned(
                                          top: 8,
                                          left: 8,
                                          child: Builder(builder: (context) {
                                            final itemMeta =
                                                item['metadata'] ?? {};
                                            if (itemMeta['watch_status'] ==
                                                'watched') {
                                              return Container(
                                                padding:
                                                    const EdgeInsets.all(3),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                      color: const Color(
                                                          0xFF00E676),
                                                      width: 1.5),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(
                                                              0xFF00E676)
                                                          .withValues(
                                                              alpha: 0.3),
                                                      blurRadius: 4,
                                                    )
                                                  ],
                                                ),
                                                child: const Icon(Icons.check,
                                                    color: Color(0xFF00E676),
                                                    size: 10),
                                              );
                                            }
                                            return const SizedBox.shrink();
                                          }),
                                        ),

                                        // Thumbnail progress bar for in-progress items
                                        Builder(builder: (context) {
                                          final itemMeta =
                                              item['metadata'] ?? {};
                                          final progress = int.tryParse(
                                                  (itemMeta['playback_progress']
                                                          ?.toString() ??
                                                      '0')) ??
                                              0;
                                          if (progress > 0) {
                                            int duration = int.tryParse(
                                                    (itemMeta['duration']
                                                            ?.toString() ??
                                                        '0')) ??
                                                0;
                                            if (duration == 0) {
                                              final runtimeMinutes =
                                                  int.tryParse((itemMeta[
                                                                  'runtime']
                                                              ?.toString() ??
                                                          '0')) ??
                                                      0;
                                              duration = runtimeMinutes * 60;
                                            }
                                            if (duration == 0) {
                                              duration =
                                                  7200; // 120 min default fallback
                                            }
                                            final ratio = (progress / duration)
                                                .clamp(0.0, 1.0);
                                            return Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                height: 4,
                                                color: Colors.white12,
                                                child: LinearProgressIndicator(
                                                  value: ratio,
                                                  color:
                                                      const Color(0xFF8A5BFF),
                                                  backgroundColor:
                                                      Colors.transparent,
                                                ),
                                              ),
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        }),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text('$title$year',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                    );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
            ],

            // Similar media should appear below cast and remain library-only via backend filter
            _buildSimilarCarousel(),
          ],
        ),
      ),
    );
  }

  String _formatVotes(dynamic votes) {
    if (votes == null) return '';
    final raw = votes.toString().replaceAll(RegExp(r'[^0-9]'), '');
    final count = int.tryParse(raw) ?? 0;
    if (count == 0) return '';
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M röster';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K röster';
    }
    return '$count röster';
  }

  String _formatRating(dynamic rating) {
    if (rating == null) return '—';
    final parsed = double.tryParse(rating.toString().replaceAll(',', '.'));
    if (parsed == null) return rating.toString();
    return parsed.toStringAsFixed(1);
  }

  String _formatSimklRating(dynamic rating) {
    if (rating == null) return '—%';
    final parsed = double.tryParse(rating.toString().replaceAll(',', '.'));
    if (parsed == null) return '${rating.toString()}%';

    if (parsed <= 10) {
      return '${(parsed * 10).toStringAsFixed(0)}%';
    }
    if (parsed <= 100) {
      return '${parsed.toStringAsFixed(0)}%';
    }
    return '—%';
  }

  Widget _buildRatingRow(String source, String value, Color color,
      {String? url, String? votes}) {
    Widget badge;
    if (source.toLowerCase() == 'imdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF5C518),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'IMDb',
          style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: -0.5),
        ),
      );
    } else if (source.toLowerCase() == 'simkl') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF21C65E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'SIMKL',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.5),
        ),
      );
    } else if (source.toLowerCase() == 'trakt') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFED2224),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'TRAKT',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 0.5),
        ),
      );
    } else if (source.toLowerCase() == 'tmdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF03B6E1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'TMDB',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      );
    } else {
      badge = Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
    }

    return MouseRegion(
      cursor: url != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: url != null ? () async {
          try {
            await Process.run('cmd', ['/c', 'start', '', url]);
          } catch (_) {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          }
        } : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: url != null
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: url != null
                ? Border.all(color: Colors.white.withValues(alpha: 0.04))
                : null,
          ),
          child: Row(
            children: [
              badge,
              const SizedBox(width: 12),
              if (url != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new, color: Colors.white24, size: 12),
              ],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  if (votes != null && votes.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(votes,
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 11)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityBadgesRow(String? filePath, String? resolution,
      {Map<dynamic, dynamic>? metadata}) {
    final badges = <Widget>[];

    Widget qualityBadge(String label,
        {Color color = const Color(0xFFB593FF), IconData? icon}) {
      return Container(
        margin: const EdgeInsets.only(right: 8, top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
          ],
        ),
      );
    }

    // Resolution badge
    final res = resolution?.toUpperCase() ?? '';
    if (res.contains('4K') || res.contains('2160')) {
      badges.add(
          qualityBadge('4K', color: const Color(0xFF00C9FF), icon: Icons.hd));
    } else if (res.contains('1080')) {
      badges.add(qualityBadge('1080p', color: const Color(0xFF7AB8F5)));
    } else if (res.contains('720')) {
      badges.add(qualityBadge('720p', color: Colors.white70));
    } else {
      badges.add(qualityBadge('HD', color: const Color(0xFF7AB8F5)));
    }

    // Audio format badges based on filename patterns and real DB probed audio tracks
    final path = (filePath ?? '').toLowerCase();

    // Check real db tracks first
    final List<dynamic> audioTracks =
        (metadata != null && metadata['audio_tracks'] is List)
            ? metadata['audio_tracks'] as List<dynamic>
            : [];
    final List<dynamic> subtitleTracks =
        (metadata != null && metadata['subtitle_tracks'] is List)
            ? metadata['subtitle_tracks'] as List<dynamic>
            : [];

    if (audioTracks.isNotEmpty) {
      for (final track in audioTracks) {
        final String codec = track['codec']?.toString().toUpperCase() ?? '';
        final String lang = track['language']?.toString().toUpperCase() ?? '';
        final int channels =
            int.tryParse(track['channels']?.toString() ?? '') ?? 2;
        final String chLabel = channels >= 8
            ? '7.1'
            : channels >= 6
                ? '5.1'
                : 'Stereo';

        if (codec.isNotEmpty) {
          badges.add(qualityBadge('$lang $codec $chLabel',
              color: const Color(0xFFB593FF)));
        }
      }
    } else {
      // Resilient Filename-based quality fallbacks when ffprobe results are empty
      bool hasAudioFallback = false;
      if (path.contains('dts-hd') ||
          path.contains('dtshd') ||
          path.contains('dts.hd')) {
        badges.add(qualityBadge('DTS-HD', color: const Color(0xFFFFD700)));
        hasAudioFallback = true;
      } else if (path.contains('dts')) {
        badges.add(qualityBadge('DTS', color: const Color(0xFFFFD700)));
        hasAudioFallback = true;
      } else if (path.contains('atmos') || path.contains('truehd')) {
        badges.add(qualityBadge('Atmos', color: const Color(0xFF00E5FF)));
        hasAudioFallback = true;
      } else if (path.contains('aac')) {
        badges.add(qualityBadge('AAC', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      } else if (path.contains('ac3') ||
          path.contains('dd5.1') ||
          path.contains('ddp') ||
          path.contains('dolby')) {
        badges
            .add(qualityBadge('Dolby Digital', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      }

      if (path.contains('5.1') ||
          path.contains('6ch') ||
          path.contains('5-1')) {
        badges.add(qualityBadge('5.1 Audio', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      } else if (path.contains('7.1') ||
          path.contains('8ch') ||
          path.contains('7-1')) {
        badges.add(qualityBadge('7.1 Audio', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      } else if (path.contains('stereo') ||
          path.contains('2.0') ||
          path.contains('2ch')) {
        badges.add(qualityBadge('Stereo', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      }

      // Premium defaults if all scans returned nothing
      if (!hasAudioFallback) {
        badges.add(qualityBadge('5.1 Audio', color: const Color(0xFFB593FF)));
        badges
            .add(qualityBadge('Dolby Digital', color: const Color(0xFFB593FF)));
      }
    }

    if (subtitleTracks.isNotEmpty) {
      final langs = subtitleTracks
          .map((t) => t['language']?.toString().toUpperCase() ?? '')
          .toSet()
          .toList();
      badges.add(qualityBadge('TEXT: ${langs.join(", ")}',
          color: const Color(0xFF00FFCC)));
    } else {
      // Filename subtitle fallback scanning
      final List<String> textLangs = [];
      if (path.contains('swe') ||
          path.contains('swedish') ||
          path.contains('.se.')) textLangs.add('SWE');
      if (path.contains('eng') || path.contains('english'))
        textLangs.add('ENG');
      if (textLangs.isNotEmpty) {
        badges.add(qualityBadge('TEXT: ${textLangs.join(", ")}',
            color: const Color(0xFF00FFCC)));
      }
    }

    if (path.contains('hdr') || path.contains('hdr10')) {
      badges.add(qualityBadge('HDR', color: const Color(0xFFFF9800)));
    }

    if (badges.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(children: badges),
    );
  }

  Widget _buildSimilarCarousel() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _similarItemsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Liknande media laddas...',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Liknande media kunde inte laddas.',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Liknande media saknas.',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        final similarItems = (snapshot.data!['items'] as List<dynamic>?) ?? [];
        if (similarItems.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Inga liknande titlar finns i biblioteket.',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text('Liknande Media',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 240,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                scrollDirection: Axis.horizontal,
                itemCount: similarItems.length,
                itemBuilder: (context, index) {
                  final item = similarItems[index];
                  final itemId = item['id']?.toString();
                  final tmdbId = item['tmdb_id']?.toString();
                  final title = item['title'] ?? 'Unknown';
                  final year = item['year'] != null ? ' (${item['year']})' : '';
                  final poster = item['poster_path'] as String?;
                  final inLibrary = item['in_library'] as bool? ?? true;
                  final type = (item['type'] as String?)?.toLowerCase() == 'show' ? 'show' : 'movie';
                  final targetId = itemId ?? 'external_${type}_$tmdbId';

                  return HoverableBuilder(
                    builder: (context, isHovered) {
                      return GestureDetector(
                        onTap: () {
                          if (widget.onMediaSelected != null) {
                            widget.onMediaSelected!(targetId);
                          } else {
                            if (targetId.startsWith('external_')) {
                               Navigator.push(
                                 context,
                                 MaterialPageRoute(
                                   builder: (context) => MediaDetailsScreen(
                                     mediaId: targetId,
                                     apiService: widget.apiService,
                                   ),
                                 ),
                               );
                            } else {
                              setState(() {
                                _mediaData = null;
                                _isLoading = true;
                              });
                              _fetchDetails();
                            }
                          }
                        },
                        onSecondaryTapDown: (details) async {
                          final position = details.globalPosition;
                          final value = await showMenu(
                            context: context,
                              position: RelativeRect.fromLTRB(
                                position.dx, position.dy, position.dx + 1, position.dy + 1,
                              ),
                              items: [
                                const PopupMenuItem(
                                  value: 'watchlist',
                                  child: Text('Lägg till i bevakningslista'),
                                ),
                              ],
                            );
                            if (value == 'watchlist' && tmdbId != null) {
                              try {
                                await widget.apiService.addToWatchlist(
                                  tmdbId: tmdbId,
                                  title: title,
                                  type: type,
                                  year: item['year'] != null ? int.tryParse(item['year'].toString()) : null,
                                  posterPath: poster,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$title lades till i bevakningslistan!')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Kunde inte lägga till: $e')),
                                  );
                                }
                              }
                            }
                          },
                          child: Container(
                            width: 140,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Opacity(
                                  opacity: inLibrary ? 1.0 : 0.4,
                                  child: Stack(
                                    children: [
                                      Container(
                                        height: 180,
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                              color:
                                                  Colors.white.withValues(alpha: isHovered ? 0.3 : 0.04)),
                                          image: poster != null
                                              ? DecorationImage(
                                                  image: NetworkImage(poster),
                                                  fit: BoxFit.cover)
                                              : null,
                                        ),
                                        foregroundDecoration: isHovered
                                            ? BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(12),
                                              )
                                            : null,
                                        child: poster == null
                                            ? const Center(
                                                child: Icon(Icons.movie,
                                                    size: 50, color: Colors.white24))
                                            : null,
                                      ),
                                      if (!inLibrary)
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Center(
                                              child: Icon(Icons.cloud_off, color: Colors.white70, size: 36),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Opacity(
                                  opacity: inLibrary ? 1.0 : 0.6,
                                  child: Text('$title$year',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    );
                  },
              ),
            ),
            const SizedBox(height: 60),
          ],
        );
      },
    );
  }

  bool get _isAdmin =>
      widget.apiService.currentUserPayload?['role'] == 'Admin';

  Future<void> _showSeasonContextMenu(
      BuildContext ctx, Offset globalPos, int seasonNum, List<Map<String, dynamic>> eps) async {
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    final rel = RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    );
    final label = seasonNum == 0 ? 'Specials' : 'Säsong $seasonNum';
    final allWatched = eps.isNotEmpty && eps.every((e) => e['is_watched'] == 1 || e['is_watched'] == true);
    final selected = await showMenu<String>(
      context: ctx,
      color: const Color(0xFF11151D),
      position: rel,
      items: [
        PopupMenuItem(
          value: 'favorite',
          child: Row(children: [
            const Icon(Icons.star_border, size: 16, color: Color(0xFFFFD700)),
            const SizedBox(width: 8),
            const Text('Lägg till i favoriter'),
          ]),
        ),
        PopupMenuItem(
          value: 'playlist',
          child: Row(children: [
            const Icon(Icons.playlist_add, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Lägg till på spellista'),
          ]),
        ),
        PopupMenuItem(
          value: allWatched ? 'mark_unwatched' : 'mark_watched',
          child: Row(children: [
            Icon(allWatched ? Icons.visibility_off : Icons.visibility, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Text(allWatched ? 'Markera som osedd' : 'Markera som sedd'),
          ]),
        ),
        PopupMenuItem(
          value: 'refresh',
          child: Row(children: [
            const Icon(Icons.refresh, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Uppdatera metadata'),
          ]),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            const Icon(Icons.edit_outlined, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Redigera'),
          ]),
        ),
        PopupMenuItem(
          value: 'fix_match',
          child: Row(children: [
            const Icon(Icons.search, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Fixa matchning'),
          ]),
        ),
        PopupMenuItem(
          value: 'unmatch',
          child: Row(children: [
            const Icon(Icons.link_off, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Ta bort matchning'),
          ]),
        ),
        if (_isAdmin)
          const PopupMenuItem(
            value: 'delete_season',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Ta bort', style: TextStyle(color: Colors.redAccent)),
            ]),
          ),
        PopupMenuItem(
          value: 'info',
          child: Row(children: [
            const Icon(Icons.info_outline, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Info'),
          ]),
        ),
        PopupMenuItem(
          value: 'stats',
          child: Row(children: [
            const Icon(Icons.bar_chart, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Visa statistik'),
          ]),
        ),
      ],
    );

    if (!mounted) return;

    if (selected == 'mark_watched' || selected == 'mark_unwatched') {
      try {
        final newWatched = selected == 'mark_watched';
        await widget.apiService.markSeasonSeen(widget.mediaId, seasonNum, newWatched);
        if (mounted && _mediaData != null) {
          setState(() {
            final allEps = _mediaData!['episodes'];
            if (allEps is List) {
              for (final e in allEps) {
                if (e is Map && int.tryParse(e['season_number']?.toString() ?? '') == seasonNum) {
                  e['is_watched'] = newWatched ? 1 : 0;
                }
              }
            }
          });
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e')));
      }
      return;
    }

    if (selected == 'info') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Info-vy för säsonger är inte implementerad.')));
      }
      return;
    }
    if (selected == 'edit') {
      if (mounted) {
        widget.onEdit?.call();
      }
      return;
    }
    if (selected == 'favorite' || selected == 'playlist' || selected == 'refresh' || selected == 'fix_match' || selected == 'unmatch' || selected == 'stats') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Funktionen stöds ej för enskilda säsonger.')));
      }
      return;
    }

    if (selected == 'delete_season' && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Flytta till papperskorgen?'),
          content: Text('Ska $label (${eps.length} avsnitt) flyttas till papperskorgen?'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(d, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Avbryt'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Radera'),
            ),
          ],
        ),
      );
      if (ok == true) {
        try {
          await widget.apiService.deleteSeason(widget.mediaId, seasonNum);
          if (mounted) setState(() => _mediaData = null);
          _fetchDetails();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Kunde inte radera: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _showEpisodeContextMenu(
      BuildContext ctx, Offset globalPos, String epId, String label, {bool isWatched = false, int progress = 0}) async {
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    final rel = RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<String>(
      context: ctx,
      color: const Color(0xFF11151D),
      position: rel,
      items: [
        if (progress > 0)
          const PopupMenuItem(value: 'clear_continue', child: Text('Ta bort från fortsätt titta')),
        PopupMenuItem(
          value: 'play',
          child: Row(children: [
            Icon(progress > 60 ? Icons.play_circle_outline : Icons.play_arrow, size: 16, color: const Color(0xFF8A5BFF)),
            const SizedBox(width: 8),
            Text(progress > 60 ? 'Fortsätt' : 'Spela'),
          ]),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: Row(children: [
            const Icon(Icons.star_border, size: 16, color: Color(0xFFFFD700)),
            const SizedBox(width: 8),
            const Text('Lägg till i favoriter'),
          ]),
        ),
        PopupMenuItem(
          value: 'playlist',
          child: Row(children: [
            const Icon(Icons.playlist_add, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Lägg till på spellista'),
          ]),
        ),
        PopupMenuItem(
          value: isWatched ? 'mark_unwatched' : 'mark_watched',
          child: Row(children: [
            Icon(isWatched ? Icons.visibility_off : Icons.visibility, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Text(isWatched ? 'Markera som osedd' : 'Markera som sedd'),
          ]),
        ),
        PopupMenuItem(
          value: 'refresh',
          child: Row(children: [
            const Icon(Icons.refresh, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Uppdatera metadata'),
          ]),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            const Icon(Icons.edit_outlined, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Redigera'),
          ]),
        ),
        PopupMenuItem(
          value: 'fix_match',
          child: Row(children: [
            const Icon(Icons.search, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Fixa matchning'),
          ]),
        ),
        PopupMenuItem(
          value: 'unmatch',
          child: Row(children: [
            const Icon(Icons.link_off, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Ta bort matchning'),
          ]),
        ),
        if (_isAdmin)
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              const SizedBox(width: 8),
              const Text('Ta bort', style: TextStyle(color: Colors.redAccent)),
            ]),
          ),
        PopupMenuItem(
          value: 'info',
          child: Row(children: [
            const Icon(Icons.info_outline, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Info'),
          ]),
        ),
        PopupMenuItem(
          value: 'stats',
          child: Row(children: [
            const Icon(Icons.bar_chart, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            const Text('Visa statistik'),
          ]),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == 'play') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          mediaId: epId,
          apiService: widget.apiService,
          startFromSeconds: 0,
        ),
      ));
    } else if (selected == 'resume') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          mediaId: epId,
          apiService: widget.apiService,
          startFromSeconds: progress,
        ),
      ));
    } else if (selected == 'mark_watched' || selected == 'mark_unwatched') {
      try {
        final newWatched = selected == 'mark_watched';
        await widget.apiService.toggleEpisodeSeenStatus(epId, newWatched);
        if (mounted && _mediaData != null) {
          setState(() {
            final allEps = _mediaData!['episodes'];
            if (allEps is List) {
              for (final e in allEps) {
                if (e is Map && e['id']?.toString() == epId) {
                  e['is_watched'] = newWatched ? 1 : 0;
                  break;
                }
              }
            }
          });
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e')));
      }
    } else if (selected == 'info') {
      if (_mediaData != null) {
        final allEps = _mediaData!['episodes'];
        Map<String, dynamic>? ep;
        if (allEps is List) {
          for (final e in allEps) {
            if (e is Map && e['id']?.toString() == epId) {
              ep = Map<String, dynamic>.from(e);
              break;
            }
          }
        }
        if (ep != null && widget.onEpisodeSelected != null) {
          widget.onEpisodeSelected!(ep, _mediaData!);
        }
      }
    } else if (selected == 'edit') {
      if (_mediaData != null) {
        final allEps = _mediaData!['episodes'];
        Map<String, dynamic>? ep;
        if (allEps is List) {
          for (final e in allEps) {
            if (e is Map && e['id']?.toString() == epId) {
              ep = Map<String, dynamic>.from(e);
              break;
            }
          }
        }
        if (ep != null) widget.onEditEpisode?.call(epId, ep);
      }
    } else if (selected == 'favorite' || selected == 'playlist' || selected == 'refresh' || selected == 'fix_match' || selected == 'unmatch' || selected == 'stats' || selected == 'clear_continue') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Funktionen stöds ej för enskilda avsnitt.')));
    } else if (selected == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Flytta till papperskorgen?'),
          content: Text('Ska $label flyttas till papperskorgen?'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(d, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Avbryt'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Radera'),
            ),
          ],
        ),
      );
      if (ok == true) {
        try {
          await widget.apiService.deleteEpisode(epId);
          if (mounted) setState(() => _mediaData = null);
          _fetchDetails();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Kunde inte radera: $e')),
            );
          }
        }
      }
    }
  }

  Widget _buildSeasonsSection(List<dynamic> episodes) {
    // Build local seasons map
    final Map<int, List<Map<String, dynamic>>> localSeasons = {};
    for (final ep in episodes) {
      final episode = Map<String, dynamic>.from(ep as Map);
      final season = int.tryParse(episode['season_number']?.toString() ?? '0') ?? 0;
      localSeasons.putIfAbsent(season, () => []).add(episode);
    }
    if (localSeasons.isEmpty) return const SizedBox.shrink();

    // Parse TMDB seasons metadata
    final metadata = _mediaData?['metadata'];
    List<Map<String, dynamic>> tmdbSeasons = [];
    if (metadata is Map) {
      final seasonsRaw = metadata['seasons_json'];
      if (seasonsRaw is List) {
        for (final e in seasonsRaw) {
          if (e is Map) tmdbSeasons.add(Map<String, dynamic>.from(e));
        }
      } else if (seasonsRaw is String && seasonsRaw.isNotEmpty) {
        for (final e in _parseJsonList(seasonsRaw)) {
          if (e is Map) tmdbSeasons.add(Map<String, dynamic>.from(e));
        }
      }
    }

    // Build merged season list: TMDB seasons (sorted) + any local-only seasons not in TMDB
    final Set<int> tmdbSeasonNums = tmdbSeasons.map((s) => (s['season_number'] as num?)?.toInt() ?? 0).toSet();
    final List<int> localOnly = localSeasons.keys.where((n) => !tmdbSeasonNums.contains(n)).toList()..sort();

    // Compose display list: TMDB seasons first (in order), then local-only ones
    final List<Map<String, dynamic>> displaySeasons = [
      ...tmdbSeasons.where((s) {
        final n = (s['season_number'] as num?)?.toInt() ?? 0;
        return n >= 0; // include specials (0)
      }),
      ...localOnly.map<Map<String, dynamic>>((n) => <String, dynamic>{
        'season_number': n,
        'name': n == 0 ? 'Specials' : 'Säsong $n',
        'episode_count': localSeasons[n]!.length,
        'poster_path': null,
      }),
    ];

    if (displaySeasons.isEmpty) {
      for (final n in localSeasons.keys.toList()..sort()) {
        displaySeasons.add(<String, dynamic>{
          'season_number': n,
          'name': n == 0 ? 'Specials' : 'Säsong $n',
          'episode_count': localSeasons[n]!.length,
          'poster_path': null,
        });
      }
    }

    // Auto-select season for episode view
    if (_selectedSeasonNumber == -1) {
      final lastEpId = metadata is Map ? metadata['last_watched_episode_id']?.toString() : null;
      int autoSeason = (displaySeasons.firstWhere(
        (s) => localSeasons.containsKey((s['season_number'] as num?)?.toInt() ?? -1),
        orElse: () => displaySeasons.first,
      )['season_number'] as num?)?.toInt() ?? 1;
      if (lastEpId != null) {
        for (final ep in episodes) {
          if (ep['id']?.toString() == lastEpId) {
            autoSeason = int.tryParse(ep['season_number']?.toString() ?? '') ?? autoSeason;
            break;
          }
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedSeasonNumber == -1) {
          setState(() => _selectedSeasonNumber = autoSeason);
        }
      });
    }

    if (_seasonOverviewMode) {
      return _buildSeasonOverview(displaySeasons, localSeasons);
    } else {
      return _buildSeasonEpisodeView(localSeasons, displaySeasons);
    }
  }

  // ── Season overview ──────────────────────────────────────────────────────

  Widget _buildSeasonOverview(
    List<Map<String, dynamic>> displaySeasons,
    Map<int, List<Map<String, dynamic>>> localSeasons,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Säsonger', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            itemCount: displaySeasons.length,
            itemBuilder: (context, index) {
              final s = displaySeasons[index];
              final sNum = (s['season_number'] as num?)?.toInt() ?? 0;
              final hasLocal = localSeasons.containsKey(sNum);
              final sEps = localSeasons[sNum] ?? [];
              final watched = sEps.where((e) => e['is_watched'] == 1 || e['is_watched'] == true).length;
              final total = sEps.length;
              final tmdbTotal = (s['episode_count'] as num?)?.toInt() ?? total;
              final allWatched = total > 0 && watched == total;
              final posterRaw = s['poster_path']?.toString();
              final poster = posterRaw != null && posterRaw.isNotEmpty
                  ? (posterRaw.startsWith('http') ? posterRaw : 'https://image.tmdb.org/t/p/w300$posterRaw')
                  : null;
              final sName = s['name']?.toString() ?? (sNum == 0 ? 'Specials' : 'Säsong $sNum');
              final airDate = s['air_date']?.toString() ?? '';
              final year = airDate.length >= 4 ? airDate.substring(0, 4) : '';

              // Find next to watch in this season
              Map<String, dynamic>? nextEp;
              if (hasLocal) {
                for (final ep in sEps) {
                  if (ep['is_watched'] != 1 && ep['is_watched'] != true) {
                    nextEp = ep;
                    break;
                  }
                }
              }

              return MouseRegion(
                cursor: hasLocal ? SystemMouseCursors.click : SystemMouseCursors.basic,
                child: GestureDetector(
                onTap: hasLocal
                    ? () => setState(() {
                          _selectedSeasonNumber = sNum;
                          _seasonOverviewMode = false;
                        })
                    : null,
                onSecondaryTapUp: hasLocal
                    ? (d) => _showSeasonContextMenu(context, d.globalPosition, sNum, sEps)
                    : null,
                child: AnimatedOpacity(
                  opacity: hasLocal ? 1.0 : 0.38,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Poster
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (poster != null && poster.isNotEmpty)
                                  Image.network(poster, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          child: const Icon(Icons.tv, color: Colors.white24, size: 32)))
                                else
                                  Container(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    child: const Icon(Icons.tv, color: Colors.white24, size: 32),
                                  ),
                                // Not-local overlay
                                if (!hasLocal)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: const Center(
                                      child: Icon(Icons.lock_outline, color: Colors.white38, size: 28),
                                    ),
                                  ),
                                // Watched overlay
                                if (allWatched)
                                  Container(color: Colors.black.withValues(alpha: 0.35)),
                                // "Next" banner
                                if (nextEp != null && !allWatched)
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF8A5BFF),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'E${(nextEp['episode_number'] as num?)?.toInt() ?? 1}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                // Watched check
                                if (allWatched)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                                      child: const Icon(Icons.check, color: Colors.white, size: 10),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Info
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(sName,
                                        style: TextStyle(
                                            color: hasLocal ? Colors.white : Colors.white54,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hasLocal ? '$total av $tmdbTotal avsnitt' : '$tmdbTotal avsnitt${year.isNotEmpty ? ' · $year' : ''}',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.40), fontSize: 10),
                              ),
                              if (hasLocal && total > 0) ...[
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: watched / total,
                                    minHeight: 3,
                                    color: allWatched ? const Color(0xFF4CAF50) : const Color(0xFF8A5BFF),
                                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                              ],
                              if (!hasLocal)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('Ej tillgänglig',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.30), fontSize: 10)),
                                ),
                              // "..." button row
                              if (hasLocal)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    InkWell(
                                      mouseCursor: SystemMouseCursors.click,
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        final RenderBox box = context.findRenderObject() as RenderBox;
                                        final pos = box.localToGlobal(Offset.zero);
                                        _showSeasonContextMenu(context, Offset(pos.dx + box.size.width / 2, pos.dy + box.size.height / 2), sNum, sEps);
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Icon(Icons.more_horiz, color: Colors.white38, size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),  // GestureDetector (child of MouseRegion)
              );  // MouseRegion
            },
          ),
        ],
      ),
    );
  }

  // ── Episode view (after selecting a season) ──────────────────────────────

  Widget _buildSeasonEpisodeView(
    Map<int, List<Map<String, dynamic>>> localSeasons,
    List<Map<String, dynamic>> displaySeasons,
  ) {
    final sortedLocal = localSeasons.keys.toList()..sort();
    final activeSeason = _selectedSeasonNumber == -1 ? sortedLocal.first : _selectedSeasonNumber;
    final localActiveEps = List<Map<String, dynamic>>.from(localSeasons[activeSeason] ?? localSeasons[sortedLocal.first]!);

    // Build combined list with upcoming placeholder episodes if enabled
    List<Map<String, dynamic>> activeEps = localActiveEps;
    if (_showUpcomingEpisodes) {
      final tmdbSeason = displaySeasons.firstWhere(
        (s) => (s['season_number'] as num?)?.toInt() == activeSeason,
        orElse: () => {},
      );
      final tmdbCount = (tmdbSeason['episode_count'] as num?)?.toInt() ?? 0;
      if (tmdbCount > localActiveEps.length) {
        final localEpNums = localActiveEps.map((e) => int.tryParse(e['episode_number']?.toString() ?? '0') ?? 0).toSet();
        final placeholders = <Map<String, dynamic>>[];
        for (int n = 1; n <= tmdbCount; n++) {
          if (!localEpNums.contains(n)) {
            placeholders.add({
              'episode_number': n,
              'season_number': activeSeason,
              'title': 'Avsnitt $n',
              'file_path': null,
              'id': null,
              '_is_upcoming': true,
            });
          }
        }
        activeEps = [...localActiveEps, ...placeholders]
          ..sort((a, b) => (int.tryParse(a['episode_number']?.toString() ?? '0') ?? 0)
              .compareTo(int.tryParse(b['episode_number']?.toString() ?? '0') ?? 0));
      }
    }

    // Find next unwatched episode (from local only)
    Map<String, dynamic>? nextEp;
    for (final ep in localActiveEps) {
      if (ep['is_watched'] != 1 && ep['is_watched'] != true) { nextEp = ep; break; }
    }

    final watchedCount = localActiveEps.where((e) => e['is_watched'] == 1 || e['is_watched'] == true).length;
    final totalCount = localActiveEps.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ───────────────────────────────────────────────────
          Row(
            children: [
              // Back to season overview
              InkWell(
                onTap: () => setState(() => _seasonOverviewMode = true),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF8A5BFF), size: 14),
                      const SizedBox(width: 4),
                      Text('Säsonger', style: TextStyle(color: const Color(0xFF8A5BFF), fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  activeSeason == 0 ? 'Specials' : 'Säsong $activeSeason',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Grid / List toggle
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildViewToggleBtn(Icons.view_list_rounded, !_episodeViewIsGrid, () { setState(() => _episodeViewIsGrid = false); _saveEpisodeViewPref(false); }, tooltip: 'Lista'),
                    _buildViewToggleBtn(Icons.grid_view_rounded, _episodeViewIsGrid, () { setState(() => _episodeViewIsGrid = true); _saveEpisodeViewPref(true); }, tooltip: 'Rutnät'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Season chips (quick jump) ────────────────────────────────────
          if (sortedLocal.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: sortedLocal.map((sNum) {
                    final isActive = sNum == activeSeason;
                    final sLabel = sNum == 0 ? 'Specials' : 'S$sNum';
                    final sEps = localSeasons[sNum]!;
                    final sWatched = sEps.where((e) => e['is_watched'] == 1 || e['is_watched'] == true).length;
                    final allWatched = sWatched == sEps.length && sEps.isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                        onTap: () => setState(() => _selectedSeasonNumber = sNum),
                        onSecondaryTapUp: (d) => _showSeasonContextMenu(context, d.globalPosition, sNum, sEps),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive ? const Color(0xFF8A5BFF).withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive ? const Color(0xFF8A5BFF) : Colors.white.withValues(alpha: 0.12),
                              width: isActive ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (allWatched) ...[
                                const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 12),
                                const SizedBox(width: 4),
                              ],
                              Text(sLabel,
                                  style: TextStyle(
                                      color: isActive ? Colors.white : Colors.white60,
                                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12)),
                              const SizedBox(width: 4),
                              Text('$sWatched/${sEps.length}',
                                  style: TextStyle(
                                      color: isActive ? const Color(0xFFB593FF) : Colors.white30,
                                      fontSize: 10)),
                            ],
                          ),
                        ),
                      ),  // GestureDetector
                    ),    // MouseRegion
                  );
                }).toList(),
                ),
              ),
            ),

          // ── Season progress bar ──────────────────────────────────────────
          if (totalCount > 0) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: watchedCount / totalCount,
                      minHeight: 5,
                      color: const Color(0xFF8A5BFF),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$watchedCount av $totalCount sedda',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── Nästa att titta ──────────────────────────────────────────────
          if (nextEp != null) ...[
            _buildNextEpisodeBanner(nextEp, activeSeason),
            const SizedBox(height: 12),
          ],

          // ── Episode list / grid ──────────────────────────────────────────
          _episodeViewIsGrid
              ? _buildEpisodeGrid(activeEps, activeSeason)
              : _buildEpisodeList(activeEps, activeSeason),
        ],
      ),
    );
  }

  // JSON helper (avoids importing dart:convert separately)
  List<dynamic> _parseJsonList(String raw) {
    try {
      // ignore: avoid_dynamic_calls
      return (raw.isEmpty || raw == '[]') ? [] : (jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  Widget _buildViewToggleBtn(IconData icon, bool active, VoidCallback onTap, {String tooltip = ''}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF8A5BFF).withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, color: active ? const Color(0xFF8A5BFF) : Colors.white38, size: 18),
        ),
      ),
    );
  }

  Widget _buildNextEpisodeBanner(Map<String, dynamic> ep, int seasonNum) {
    final epNum = int.tryParse(ep['episode_number']?.toString() ?? '0') ?? 0;
    final epTitle = ep['title']?.toString() ?? 'Avsnitt $epNum';
    final epId = ep['id']?.toString();
    final label = 'S${seasonNum.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}';
    final progress = int.tryParse(ep['playback_progress']?.toString() ?? '0') ?? 0;

    return GestureDetector(
      onTap: epId != null
          ? () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(
                mediaId: epId,
                apiService: widget.apiService,
                startFromSeconds: progress > 60 ? progress : 0,
              )))
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF8A5BFF).withValues(alpha: 0.15), const Color(0xFF8A5BFF).withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF8A5BFF).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF8A5BFF), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nästa att titta', style: TextStyle(color: Color(0xFFB593FF), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Text('$label  ·  $epTitle', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (progress > 60) ...[
                    const SizedBox(height: 4),
                    Text('${(progress ~/ 60)} min in', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeList(List<Map<String, dynamic>> eps, int seasonNum) {
    return Column(
      children: eps.map((ep) {
        final epNum = int.tryParse(ep['episode_number']?.toString() ?? '0') ?? 0;
        final epTitle = ep['title']?.toString() ?? 'Avsnitt $epNum';
        final epId = ep['id']?.toString();
        final label = 'S${seasonNum.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}';
        final isWatched = ep['is_watched'] == 1 || ep['is_watched'] == true;
        final progress = int.tryParse(ep['playback_progress']?.toString() ?? '0') ?? 0;
        final duration = int.tryParse(ep['duration']?.toString() ?? '0') ?? 0;
        final hasProgress = progress > 60 && !isWatched;
        final airDate = ep['air_date']?.toString() ?? '';
        final overview = ep['overview']?.toString() ?? '';
        final isUpcoming = ep['_is_upcoming'] == true;
        final stillPathRaw = ep['still_path']?.toString();
        final stillPath = stillPathRaw != null && stillPathRaw.isNotEmpty
            ? (stillPathRaw.startsWith('http') ? stillPathRaw : 'https://image.tmdb.org/t/p/w300$stillPathRaw')
            : null;

        Widget leadingWidget;
        if (stillPath != null && stillPath.isNotEmpty) {
          leadingWidget = ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 96,
              height: 54,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    stillPath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withValues(alpha: 0.06),
                      child: const Icon(Icons.tv, color: Colors.white24, size: 20),
                    ),
                  ),
                  if (isWatched)
                    Container(color: Colors.black.withValues(alpha: 0.45)),
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              color: isWatched ? Colors.white38 : const Color(0xFF8A5BFF),
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          leadingWidget = Container(
            width: 56,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: isWatched ? Colors.white30 : const Color(0xFF8A5BFF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          );
        }

        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onSecondaryTapUp: (epId != null)
                ? (d) => _showEpisodeContextMenu(context, d.globalPosition, epId, label,
                    isWatched: isWatched, progress: progress)
                : null,
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () {
                if (widget.onEpisodeSelected != null && _mediaData != null) {
                  widget.onEpisodeSelected!(ep, _mediaData!);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EpisodeDetailsScreen(
                        episode: ep,
                        showData: _mediaData ?? {},
                        apiService: widget.apiService,
                        onStatusChanged: () {
                          if (mounted) _fetchDetails();
                        },
                      ),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Opacity(
                opacity: isUpcoming ? 0.40 : 1.0,
                child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isWatched ? 0.01 : 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.fromLTRB(
                          12, stillPath != null && stillPath.isNotEmpty ? 8 : 6, 8,
                          stillPath != null && stillPath.isNotEmpty ? 8 : 6),
                      leading: leadingWidget,
                      title: Text(
                        epTitle,
                        style: TextStyle(color: isWatched ? Colors.white38 : Colors.white, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: airDate.isNotEmpty
                          ? Text(airDate,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 11))
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Watched toggle
                          Tooltip(
                            message: isWatched ? 'Markera som osedd' : 'Markera som sedd',
                            child: InkWell(
                              mouseCursor: SystemMouseCursors.click,
                              onTap: epId != null
                                  ? () async {
                                      try {
                                        await widget.apiService.toggleEpisodeSeenStatus(epId, !isWatched);
                                        if (mounted && _mediaData != null) {
                                          setState(() {
                                            final eps = _mediaData!['episodes'];
                                            if (eps is List) {
                                              for (final e in eps) {
                                                if (e is Map && e['id']?.toString() == epId) {
                                                  e['is_watched'] = !isWatched ? 1 : 0;
                                                  break;
                                                }
                                              }
                                            }
                                          });
                                        }
                                      } catch (_) {}
                                    }
                                  : null,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  isWatched ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: isWatched ? const Color(0xFF4CAF50) : Colors.white24,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          // "..." button
                          if (epId != null)
                            GestureDetector(
                              onTapUp: (details) async {
                                await _showEpisodeContextMenu(context, details.globalPosition, epId, label, isWatched: isWatched, progress: progress);
                              },
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.more_vert, color: Colors.white60, size: 20),
                                ),
                              ),
                            ),
                          // Play button
                          if (epId != null)
                            IconButton(
                              icon: Icon(
                                hasProgress ? Icons.play_circle_outline : Icons.play_arrow_rounded,
                                color: hasProgress ? const Color(0xFFB593FF) : const Color(0xFF8A5BFF),
                                size: 28,
                              ),
                              tooltip: hasProgress ? 'Fortsätt' : 'Spela',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => VideoPlayerScreen(
                                          mediaId: epId,
                                          apiService: widget.apiService,
                                          startFromSeconds: hasProgress ? progress : 0,
                                        )),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Progress bar for in-progress episodes
                    if (hasProgress && duration > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (progress / duration).clamp(0.0, 1.0),
                            minHeight: 3,
                            color: const Color(0xFF8A5BFF),
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ),  // Opacity
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showEpisodeDetailDialog(
    BuildContext context, {
    String? epId,
    required String label,
    required String title,
    required String airDate,
    required String overview,
    String? stillPath,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0E1219),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.45,
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Still image
              if (stillPath != null && stillPath.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      stillPath,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.white.withValues(alpha: 0.05),
                        child: const Icon(Icons.tv, color: Colors.white24, size: 40),
                      ),
                    ),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.04),
                      child: const Icon(Icons.tv, color: Colors.white12, size: 48),
                    ),
                  ),
                ),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Label chip + close
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8A5BFF).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.4)),
                            ),
                            child: Text(label,
                                style: const TextStyle(
                                    color: Color(0xFF8A5BFF), fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Title
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),

                      // Air date
                      if (airDate.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(airDate,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.40), fontSize: 12)),
                      ],

                      // Overview
                      if (overview.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(overview,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 13,
                                height: 1.5)),
                      ] else ...[
                        const SizedBox(height: 14),
                        Text('Ingen beskrivning tillgänglig.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.30), fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeGrid(List<Map<String, dynamic>> eps, int seasonNum) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: eps.length,
      itemBuilder: (context, index) {
        final ep = eps[index];
        final epNum = int.tryParse(ep['episode_number']?.toString() ?? '0') ?? 0;
        final epTitle = ep['title']?.toString() ?? 'Avsnitt $epNum';
        final epId = ep['id']?.toString();
        final label = 'S${seasonNum.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}';
        final isWatched = ep['is_watched'] == 1 || ep['is_watched'] == true;
        final progress = int.tryParse(ep['playback_progress']?.toString() ?? '0') ?? 0;
        final duration = int.tryParse(ep['duration']?.toString() ?? '0') ?? 0;
        final hasProgress = progress > 60 && !isWatched;
        final stillRaw2 = ep['still_path']?.toString();
        final stillPath = stillRaw2 != null && stillRaw2.isNotEmpty
            ? (stillRaw2.startsWith('http') ? stillRaw2 : 'https://image.tmdb.org/t/p/w300$stillRaw2')
            : null;
        final overview = ep['overview']?.toString() ?? '';
        final airDate = ep['air_date']?.toString() ?? '';
        final isUpcoming = ep['_is_upcoming'] == true;

        return Opacity(
          opacity: isUpcoming ? 0.40 : 1.0,
          child: Stack(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    if (widget.onEpisodeSelected != null && _mediaData != null) {
                      widget.onEpisodeSelected!(ep, _mediaData!);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EpisodeDetailsScreen(
                            episode: ep,
                            showData: _mediaData ?? {},
                            apiService: widget.apiService,
                            onStatusChanged: () {
                              if (mounted) setState(() => _mediaData = null);
                              _fetchDetails();
                            },
                          ),
                        ),
                      );
                    }
                  },
                  onDoubleTap: epId != null
                      ? () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            mediaId: epId,
                            apiService: widget.apiService,
                            startFromSeconds: hasProgress ? progress : 0,
                          )))
                      : null,
                  onSecondaryTapUp: epId != null
                      ? (d) => _showEpisodeContextMenu(context, d.globalPosition, epId, label, isWatched: isWatched, progress: progress)
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: isWatched ? 0.02 : 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (stillPath != null && stillPath.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              stillPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        if (isWatched)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 22, 8, 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black.withValues(alpha: 0.88), Colors.transparent],
                              ),
                              borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasProgress && duration > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: (progress / duration).clamp(0.0, 1.0),
                                        minHeight: 3,
                                        color: const Color(0xFF8A5BFF),
                                        backgroundColor: Colors.white12,
                                      ),
                                    ),
                                  ),
                                Text(label,
                                    style: const TextStyle(
                                        color: Color(0xFFB593FF), fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(epTitle,
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                        if (isWatched)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                              child: const Icon(Icons.check, color: Colors.white, size: 10),
                            ),
                          ),
                        Center(
                          child: Icon(
                            isWatched ? Icons.replay_rounded : Icons.play_circle_outline_rounded,
                            color: Colors.white.withValues(alpha: stillPath != null && stillPath.isNotEmpty ? 0.0 : 0.30),
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // "..." button outside the card GestureDetector — no gesture conflict
              if (epId != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTapUp: (details) async {
                        await _showEpisodeContextMenu(context, details.globalPosition, epId, label, isWatched: isWatched, progress: progress);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.more_vert, color: Colors.white70, size: 16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPlaylistDialog() {
    showDialog(
      context: context,
      builder: (context) => _PlaylistDialog(
        mediaId: widget.mediaId,
        mediaTitle: _mediaData?['title'] ?? '',
        apiService: widget.apiService,
      ),
    );
  }

  Future<void> _showCollectionDialog(
      String collectionName, String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: widget.apiService.fetchCollectionItems(collectionId),
          builder: (_, snapshot) {
            final items = (snapshot.data?['items'] as List<dynamic>?) ?? [];
            final name = snapshot.data?['collectionName'] as String? ?? collectionName;

            return AlertDialog(
              backgroundColor: const Color(0xFF15102A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 600,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: Color(0xFF8A5BFF))))
                    : items.isEmpty
                        ? const Text('Inga titlar hittades.', style: TextStyle(color: Colors.white70))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (ctx2, index) {
                              final item = items[index] as Map<String, dynamic>;
                              final inLibrary = item['in_library'] as bool? ?? false;
                              final libId = item['id']?.toString();
                              final tmdbId = item['tmdb_id']?.toString();
                              final poster = item['poster_path']?.toString();
                              final title = item['title']?.toString() ?? 'Okänd titel';
                              final year = item['year']?.toString() ?? '';

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    // Poster
                                    MouseRegion(
                                      cursor: tmdbId != null ? SystemMouseCursors.click : MouseCursor.defer,
                                      child: GestureDetector(
                                        onTap: () {
                                          if (inLibrary && libId != null) {
                                            Navigator.pop(dialogCtx);
                                            widget.onMediaSelected?.call(libId);
                                          } else if (tmdbId != null) {
                                            Navigator.pop(dialogCtx);
                                            widget.onMediaSelected?.call('external_movie_$tmdbId');
                                          }
                                        },
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: poster != null
                                              ? Image.network(poster, width: 48, height: 72, fit: BoxFit.cover)
                                              : Container(width: 48, height: 72, color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    // Title + year
                                    Expanded(
                                      child: MouseRegion(
                                        cursor: tmdbId != null ? SystemMouseCursors.click : MouseCursor.defer,
                                        child: GestureDetector(
                                        onTap: () {
                                          if (inLibrary && libId != null) {
                                            Navigator.pop(dialogCtx);
                                            widget.onMediaSelected?.call(libId);
                                          } else if (tmdbId != null) {
                                            Navigator.pop(dialogCtx);
                                            widget.onMediaSelected?.call('external_movie_$tmdbId');
                                          }
                                        },
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(title,
                                                style: TextStyle(
                                                    color: inLibrary ? Colors.white : Colors.white54,
                                                    fontWeight: inLibrary ? FontWeight.w600 : FontWeight.normal)),
                                            if (year.isNotEmpty)
                                              Text(year, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Badge or button
                                    if (inLibrary)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2ECC71).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: const Color(0xFF2ECC71).withValues(alpha: 0.5)),
                                        ),
                                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.check_circle_outline, color: Color(0xFF2ECC71), size: 13),
                                          SizedBox(width: 4),
                                          Text('I samling', style: TextStyle(color: Color(0xFF2ECC71), fontSize: 12, fontWeight: FontWeight.w600)),
                                        ]),
                                      )
                                    else
                                      TextButton(
                                        onPressed: tmdbId == null ? null : () async {
                                          Navigator.pop(dialogCtx);
                                          await widget.apiService.addToWatchlist(
                                            tmdbId: tmdbId,
                                            title: title,
                                            type: 'Movie',
                                            year: year.isNotEmpty ? int.tryParse(year) : null,
                                            posterPath: poster,
                                          );
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('"$title" lagd i bevakningslistan!'), backgroundColor: const Color(0xFF8A5BFF)),
                                            );
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(0xFF8A5BFF),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          side: const BorderSide(color: Color(0xFF8A5BFF), width: 0.5),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        ),
                                        child: const Text('+ Bevakningslista', style: TextStyle(fontSize: 12)),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text('Stäng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAwardsRow(String? awardsString) {
    if (awardsString == null ||
        awardsString.trim().isEmpty ||
        awardsString.toLowerCase().contains('inga prisuppgifter') ||
        awardsString.toLowerCase() == 'n/a') {
      return const SizedBox();
    }

    // Parse using regex
    int oscarsWins = 0;
    int oscarsNoms = 0;
    int globesWins = 0;
    int globesNoms = 0;
    int baftaWins = 0;
    int baftaNoms = 0;
    int totalWins = 0;
    int totalNoms = 0;

    // RegEx patterns
    final oscarWinPattern =
        RegExp(r'Won\s+(\d+)\s+Oscars?', caseSensitive: false);
    final oscarNomPattern =
        RegExp(r'Nominated\s+for\s+(\d+)\s+Oscars?', caseSensitive: false);
    final globeWinPattern =
        RegExp(r'Won\s+(\d+)\s+Golden\s+Globes?', caseSensitive: false);
    final globeNomPattern = RegExp(
        r'Nominated\s+for\s+(\d+)\s+Golden\s+Globes?',
        caseSensitive: false);
    final baftaWinPattern =
        RegExp(r'Won\s+(\d+)\s+BAFTAs?', caseSensitive: false);
    final baftaNomPattern =
        RegExp(r'Nominated\s+for\s+(\d+)\s+BAFTAs?', caseSensitive: false);
    final winPattern = RegExp(r'(\d+)\s+win', caseSensitive: false);
    final nomPattern = RegExp(r'(\d+)\s+nomination', caseSensitive: false);

    // Matching
    var match = oscarWinPattern.firstMatch(awardsString);
    if (match != null) oscarsWins = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = oscarNomPattern.firstMatch(awardsString);
    if (match != null) oscarsNoms = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = globeWinPattern.firstMatch(awardsString);
    if (match != null) globesWins = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = globeNomPattern.firstMatch(awardsString);
    if (match != null) globesNoms = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = baftaWinPattern.firstMatch(awardsString);
    if (match != null) baftaWins = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = baftaNomPattern.firstMatch(awardsString);
    if (match != null) baftaNoms = int.tryParse(match.group(1) ?? '0') ?? 0;

    for (final m in winPattern.allMatches(awardsString)) {
      final val = int.tryParse(m.group(1) ?? '0') ?? 0;
      if (val > totalWins) totalWins = val;
    }
    for (final m in nomPattern.allMatches(awardsString)) {
      final val = int.tryParse(m.group(1) ?? '0') ?? 0;
      if (val > totalNoms) totalNoms = val;
    }

    final List<Widget> badges = [];

    final rawAwardsText = awardsString.trim();

    Widget buildBadge({
      required IconData icon,
      required Color color,
      required String label,
      required String tooltip,
    }) {
      return Container(
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Tooltip(
          message: tooltip,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color.withAlpha(240),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (oscarsWins > 0) {
      badges.add(buildBadge(
        icon: Icons.emoji_events,
        color: const Color(0xFFFFD700), // Gold
        label: '$oscarsWins Oscar${oscarsWins > 1 ? "s" : ""}',
        tooltip: '$oscarsWins Oscars-vinster',
      ));
    } else if (oscarsNoms > 0) {
      badges.add(buildBadge(
        icon: Icons.emoji_events_outlined,
        color: const Color(0xFFC0C0C0), // Silver
        label: '$oscarsNoms Oscar-nom',
        tooltip: '$oscarsNoms Oscars-nomineringar',
      ));
    }

    if (globesWins > 0) {
      badges.add(buildBadge(
        icon: Icons.public,
        color: const Color(0xFFFF8C00),
        label: '$globesWins Globe${globesWins > 1 ? "s" : ""}',
        tooltip: '$globesWins Golden Globe-vinster',
      ));
    } else if (globesNoms > 0) {
      badges.add(buildBadge(
        icon: Icons.public,
        color: const Color(0xFFFFB300),
        label: '$globesNoms Globe-nom',
        tooltip: '$globesNoms Golden Globe-nomineringar',
      ));
    }

    if (baftaWins > 0) {
      badges.add(buildBadge(
        icon: Icons.military_tech,
        color: const Color(0xFFCE93D8),
        label: '$baftaWins BAFTA${baftaWins > 1 ? "s" : ""}',
        tooltip: '$baftaWins BAFTA-vinster',
      ));
    } else if (baftaNoms > 0) {
      badges.add(buildBadge(
        icon: Icons.military_tech_outlined,
        color: const Color(0xFFE1BEE7),
        label: '$baftaNoms BAFTA-nom',
        tooltip: '$baftaNoms BAFTA-nomineringar',
      ));
    }

    if (totalWins > 0) {
      badges.add(buildBadge(
        icon: Icons.workspace_premium,
        color: const Color(0xFF00FFCC),
        label: '$totalWins vinst${totalWins > 1 ? "er" : ""}',
        tooltip: '$totalWins vinster totalt',
      ));
    }

    if (totalNoms > 0) {
      badges.add(buildBadge(
        icon: Icons.stars,
        color: const Color(0xFF64B5F6),
        label: '$totalNoms nom',
        tooltip: '$totalNoms nomineringar totalt',
      ));
    }

    if (badges.isEmpty) {
      badges.add(buildBadge(
        icon: Icons.emoji_events,
        color: const Color(0xFFB593FF),
        label: rawAwardsText,
        tooltip: rawAwardsText,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          children: badges,
        ),
      ],
    );
  }
}

extension FilterList<T> on List<T> {
  List<T> filter(bool Function(T) test) {
    return where(test).toList();
  }
}

// ─────────────────────────────────────────────────────────────────
// Playlist Dialog
// ─────────────────────────────────────────────────────────────────
class _PlaylistDialog extends StatefulWidget {
  final String mediaId;
  final String mediaTitle;
  final ApiService apiService;

  const _PlaylistDialog({
    required this.mediaId,
    required this.mediaTitle,
    required this.apiService,
  });

  @override
  State<_PlaylistDialog> createState() => _PlaylistDialogState();
}

class _PlaylistDialogState extends State<_PlaylistDialog> {
  final TextEditingController _newPlaylistController = TextEditingController();
  bool _isCreating = false;
  String? _feedback;

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  Future<void> _createAndAdd() async {
    final name = _newPlaylistController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _isCreating = true;
      _feedback = null;
    });
    try {
      await widget.apiService.createPlaylistAndAddItem(name, widget.mediaId);
      setState(() {
        _isCreating = false;
        _feedback = '✓ "$name" skapad och "${widget.mediaTitle}" lades till!';
      });
    } catch (e) {
      setState(() {
        _isCreating = false;
        _feedback = 'Fel: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0B1E).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Spellistor',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              Text(
                'Lägger till: ${widget.mediaTitle}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
              ),
              const SizedBox(height: 20),
              const Text('Skapa ny spellista',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPlaylistController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Spellista-namn...',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF8A5BFF)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isCreating ? null : _createAndAdd,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A5BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add, size: 18),
                    label: const Text('Skapa & Lägg till',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _feedback!.startsWith('✓')
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _feedback!.startsWith('✓')
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _feedback!,
                    style: TextStyle(
                      color: _feedback!.startsWith('✓')
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Expandable slate/purple keywords/tags container
// ─────────────────────────────────────────────────────────────────
class _KeywordsExpandableContainer extends StatefulWidget {
  final List<dynamic> keywords;
  final ValueChanged<String> onKeywordSelected;

  const _KeywordsExpandableContainer({
    required this.keywords,
    required this.onKeywordSelected,
  });

  @override
  State<_KeywordsExpandableContainer> createState() =>
      _KeywordsExpandableContainerState();
}

class _KeywordsExpandableContainerState
    extends State<_KeywordsExpandableContainer> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final displayList =
        _expanded ? widget.keywords : widget.keywords.take(6).toList();
    final hasMore = widget.keywords.length > 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (hasMore) ...[
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedRotation(
                        turns: _expanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        child: const Icon(
                          Icons.keyboard_arrow_right,
                          color: Color(0xFF8A5BFF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${widget.keywords.length})',
                        style: const TextStyle(
                          color: Color(0xFFB593FF),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ],
            const Text(
              'Keywords',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: displayList.map((keyword) {
              final keywordLabel = keyword is Map
                  ? (keyword['name']?.toString() ?? '')
                  : keyword.toString();
              if (keywordLabel.isEmpty) return const SizedBox.shrink();
              return ActionChip(
                backgroundColor: const Color(0xFF281E46).withValues(alpha: 0.6),
                side: BorderSide(
                    color: const Color(0xFF8A5BFF).withValues(alpha: 0.25)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                label: Text(keywordLabel,
                    style: const TextStyle(
                        color: Color(0xFFD4C7FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                onPressed: () => widget.onKeywordSelected(keywordLabel),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _PlaybackSimulatorDialog extends StatefulWidget {
  final String mediaId;
  final ApiService apiService;
  final String title;
  final int durationSeconds;
  final int startFromSeconds;
  final Function(int finalPosition, bool wasCompleted) onPlaybackFinished;

  const _PlaybackSimulatorDialog({
    required this.mediaId,
    required this.apiService,
    required this.title,
    required this.durationSeconds,
    required this.startFromSeconds,
    required this.onPlaybackFinished,
  });

  @override
  State<_PlaybackSimulatorDialog> createState() =>
      _PlaybackSimulatorDialogState();
}

class _PlaybackSimulatorDialogState extends State<_PlaybackSimulatorDialog> {
  late int _currentPosition;
  Timer? _timer;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.startFromSeconds;

    // Increment position every second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        _currentPosition++;
      });

      final ratio = _currentPosition / widget.durationSeconds;

      // Heartbeat / Report progress to API every 5 seconds (or if completed)
      if (_currentPosition % 5 == 0 || ratio >= 0.90) {
        _reportProgress();
      }

      // Check auto-watch status threshold (90%)
      if (ratio >= 0.90) {
        _timer?.cancel();
        _timer = null;
        _finishPlayback(true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reportProgress() async {
    try {
      await widget.apiService.reportPlaybackProgress(
        widget.mediaId,
        _currentPosition,
        widget.durationSeconds,
      );
    } catch (e) {
      debugPrint('Playback simulator scrobble failed: $e');
    }
  }

  Future<void> _finishPlayback(bool wasCompleted) async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });

    _timer?.cancel();
    _timer = null;

    // Send final progress update
    await _reportProgress();

    if (mounted) {
      Navigator.pop(context);
      widget.onPlaybackFinished(_currentPosition, wasCompleted);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasCompleted
              ? 'Filmen klar! Automatisk scrobbling till Trakt & Simkl lyckades!'
              : 'Uppspelning pausad. Position sparad!'),
          backgroundColor: const Color(0xFF8A5BFF),
        ),
      );
    }
  }

  String _formatDuration(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (_currentPosition / widget.durationSeconds).clamp(0.0, 1.0);
    final remainingSec = widget.durationSeconds - _currentPosition;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0B1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: const Color(0xFF8A5BFF).withValues(alpha: 0.2),
                width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Custom top bar with pulsing neon dot
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE2537A),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Color(0xFFE2537A), blurRadius: 8),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'LOOM SPELARE (SIMULERING)',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const Icon(Icons.movie, color: Color(0xFF8A5BFF), size: 18),
                ],
              ),
              const SizedBox(height: 30),

              // Title
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),

              // Pulsing soundwaves / status
              const SizedBox(
                height: 60,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.graphic_eq,
                          color: Color(0xFF8A5BFF), size: 36),
                      SizedBox(width: 8),
                      Text(
                        'Spelar upp media...',
                        style: TextStyle(
                          color: Colors.white70,
                          fontStyle: FontStyle.italic,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 12,
                  color: const Color(0xFF8A5BFF),
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 12),

              // Time labels
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_currentPosition),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  Text(
                    '-${_formatDuration(remainingSec)}',
                    style: const TextStyle(
                        color: Colors.white54,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 35),

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildControlButton(
                    icon: Icons.replay_10_rounded,
                    tooltip: 'Spola bakåt 10s',
                    color: const Color(0xFFB593FF),
                    onPressed: () {
                      setState(() {
                        _currentPosition = (_currentPosition - 10)
                            .clamp(0, widget.durationSeconds);
                      });
                      _reportProgress();
                    },
                  ),
                  const SizedBox(width: 24),

                  // Save & Stop Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE2537A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      elevation: 8,
                      shadowColor:
                          const Color(0xFFE2537A).withValues(alpha: 0.4),
                    ),
                    onPressed: _isSaving ? null : () => _finishPlayback(false),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.stop, size: 20),
                    label: Text(
                      _isSaving ? 'Sparar...' : 'Spara & Avsluta',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(width: 24),

                  _buildControlButton(
                    icon: Icons.forward_30_rounded,
                    tooltip: 'Spola framåt 30s',
                    color: const Color(0xFF00E5FF),
                    onPressed: () {
                      setState(() {
                        _currentPosition = (_currentPosition + 30)
                            .clamp(0, widget.durationSeconds);
                      });
                      _reportProgress();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              shape: BoxShape.circle,
              border:
                  Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
