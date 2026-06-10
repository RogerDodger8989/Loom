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
import '../widgets/unified_poster_card.dart';
import '../utils/media_actions_helper.dart';

part 'media_details/media_seasons_tab.dart';
part 'media_details/media_playback_tab.dart';
part 'media_details/media_info_tab.dart';
part 'media_details/media_badges_tab.dart';
part 'media_details/media_layout_tab.dart';


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
  late final MediaActionsHelper _mediaActionsHelper;
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
    _mediaActionsHelper = MediaActionsHelper(
      context: context,
      apiService: widget.apiService,
      onRefresh: _fetchDetails,
      onNavigate: (type, id) {
        Navigator.pushNamed(context, '/media_details', arguments: {'id': id});
      },
      onDelete: (item) {}, // No specific delete handling in details yet
    );
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
      final savedFallbackSubLang = prefs.getString('loom_player_fallback_subtitle_lang') ?? '';
    final savedEpGrid = prefs.getBool('loom_episode_view_is_grid') ?? false;
    if (!mounted) return;
    setState(() {
      _selectedQuality = savedQuality;
      _selectedSubtitleIndex = 'none';
      _selectedAudioIndex = null;
      _pendingSubtitleLang = savedSubLang;
      _pendingAudioLang = savedAudioLang;
        _pendingFallbackSubtitleLang = savedFallbackSubLang;
      _episodeViewIsGrid = savedEpGrid;
    });
  }

  Future<void> _saveEpisodeViewPref(bool isGrid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loom_episode_view_is_grid', isGrid);
  }


  bool _langMatch(String? trackLang, String prefLang) {
    if (trackLang == null) return false;
    final t = trackLang.toLowerCase();
    final p = prefLang.toLowerCase();
    if (t == p) return true;
    if (p == 'sv' && (t == 'swe' || t == 'swedish')) return true;
    if (p == 'en' && (t == 'eng' || t == 'english')) return true;
    if (p == 'no' && (t == 'nor' || t == 'norwegian')) return true;
    if (p == 'da' && (t == 'dan' || t == 'danish')) return true;
    if (p == 'fi' && (t == 'fin' || t == 'finnish')) return true;
    return false;
  }

  // Resolved once tracks are known
  String _pendingSubtitleLang = '';
  String _pendingFallbackSubtitleLang = '';
  String _pendingAudioLang = '';

  void _applyLanguageDefaults(Map<String, dynamic> metadata) {
    final subtitleTracks = (metadata['subtitle_tracks'] is List)
        ? (metadata['subtitle_tracks'] as List).cast<Map>()
        : <Map>[];
    final audioTracks = (metadata['audio_tracks'] is List)
        ? (metadata['audio_tracks'] as List).cast<Map>()
        : <Map>[];

    String resolvedSub = 'none';

    // Rule: if exactly 1 subtitle track exists, always select it!
    if (subtitleTracks.length == 1) {
      resolvedSub = subtitleTracks.first['index']?.toString() ?? 'none';
    } else if (_pendingSubtitleLang.isNotEmpty) {
      final match = subtitleTracks.firstWhere(
        (t) => _langMatch(t['language']?.toString(), _pendingSubtitleLang),
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        resolvedSub = match['index']?.toString() ?? 'none';
      } else if (_pendingSubtitleLang.toLowerCase() != 'none' && _pendingFallbackSubtitleLang.isNotEmpty && _pendingFallbackSubtitleLang.toLowerCase() != 'none') {
        final fallbackMatch = subtitleTracks.firstWhere(
          (t) => _langMatch(t['language']?.toString(), _pendingFallbackSubtitleLang),
          orElse: () => {},
        );
        if (fallbackMatch.isNotEmpty) {
          resolvedSub = fallbackMatch['index']?.toString() ?? 'none';
        }
      }
    }
    _selectedSubtitleIndex = resolvedSub;

    String? resolvedAudio;
    if (_pendingAudioLang.isNotEmpty) {
      final match = audioTracks.firstWhere(
        (t) => _langMatch(t['language']?.toString(), _pendingAudioLang),
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


  // JSON helper (avoids importing dart:convert separately)
  List<dynamic> _parseJsonList(String raw) {
    try {
      // ignore: avoid_dynamic_calls
      return (raw.isEmpty || raw == '[]') ? [] : (jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
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
                          : GridView.builder(
                              shrinkWrap: true,
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 160,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 0.65,
                              ),
                              itemCount: items.length,
                              itemBuilder: (ctx2, index) {
                                final item = items[index] as Map<String, dynamic>;
                                final inLibrary = item['in_library'] as bool? ?? false;
                                final localId = item['id']?.toString();
                                final tmdbId = item['tmdb_id']?.toString();

                                return UnifiedPosterCard(
                                  item: item,
                                  isHomeCard: false,
                                  index: index,
                                  inLibrary: inLibrary,
                                  posterPrefix: 'col_dialog',
                                  titleDisplayStyle: _titleDisplayStyle,
                                  posterScale: 1.0,

                                  selectedItems: const {},
                                  selectionMode: false,
                                  onPlayTap: inLibrary && localId != null ? (i) {
                                    Navigator.pop(dialogCtx);
                                    widget.onMediaSelected?.call(localId);
                                  } : null,
                                  onContextMenu: (i, isHome, pos) => _mediaActionsHelper.openPosterActionsMenu(i, isHomeCard: isHome, globalPos: pos),
                                onEdit: inLibrary ? _mediaActionsHelper.openMediaEditor : null,
                                  onPosterTap: (i, isHome) {
                                    Navigator.pop(dialogCtx);
                                    if (inLibrary && localId != null) {
                                      widget.onMediaSelected?.call(localId);
                                    } else if (tmdbId != null) {
                                      widget.onMediaSelected?.call('external_movie_$tmdbId');
                                    }
                                  },
                                );
                              },
                            )
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
