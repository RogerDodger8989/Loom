import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Process;
import 'package:url_launcher/url_launcher.dart';
import '../services/api.dart';
import 'person_details_screen.dart';
import 'video_player_screen.dart';

class EpisodeDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> episode;
  final Map<String, dynamic> showData;
  final ApiService apiService;
  final VoidCallback? onStatusChanged;
  final ValueChanged<String>? onPersonSelected;
  final VoidCallback? onNavigateToShow;
  final ValueChanged<int>? onNavigateToSeason;
  final ValueChanged<Map<String, dynamic>>? onNavigateToEpisode;

  const EpisodeDetailsScreen({
    super.key,
    required this.episode,
    required this.showData,
    required this.apiService,
    this.onStatusChanged,
    this.onPersonSelected,
    this.onNavigateToShow,
    this.onNavigateToSeason,
    this.onNavigateToEpisode,
  });

  @override
  State<EpisodeDetailsScreen> createState() => _EpisodeDetailsScreenState();
}

class _EpisodeDetailsScreenState extends State<EpisodeDetailsScreen> {
  late bool _isWatched;
  late int _progress;

  // Playback selectors
  String _selectedQuality = 'direct';
  String _selectedSubtitleIndex = 'none';
  String? _selectedAudioIndex;

  // Rating state (for show rating)
  double _showMyRating = 0.0;
  double? _ratingPreview;
  bool _isRatingHovering = false;
  bool _isResetHovering = false;
  bool _isRatingFlashing = false;
  int _ratingFlashNonce = 0;
  Timer? _ratingFlashTimer;
  bool _isPrevPressed = false;
  bool _isNextPressed = false;

  @override
  void initState() {
    super.initState();
    _loadPlaybackSettings();
    final ep = widget.episode;
    _isWatched = ep['is_watched'] == 1 || ep['is_watched'] == true;
    _progress  = int.tryParse(ep['playback_progress']?.toString() ?? '0') ?? 0;
    final meta = widget.showData['metadata'];
    if (meta is Map) {
      _showMyRating = double.tryParse(meta['my_rating']?.toString() ?? '0') ?? 0.0;
    }
  }


  bool _langMatch(String? trackLang, String prefLang) {
    if (trackLang == null) return false;
    final t = trackLang.toLowerCase();
    final p = prefLang.toLowerCase();
    if (t == p) return true;
    if (t.startsWith(p)) return true;
    if (p.startsWith(t)) return true;
    return false;
  }

  String _pendingSubtitleLang = '';
  String _pendingFallbackSubtitleLang = '';
  String _pendingAudioLang = '';

  void _applyLanguageDefaults(Map<String, dynamic> metadata) {
    final subtitleTracks = _parseTrackList(metadata['subtitle_tracks'] ?? _showMeta['subtitle_tracks']);
    final audioTracks = _parseTrackList(metadata['audio_tracks'] ?? _showMeta['audio_tracks']);

    String resolvedSub = 'none';
    String resolvedAudio = 'auto';

    // Rule: if exactly 1 subtitle track exists, always select it!
    if (subtitleTracks.length == 1) {
      resolvedSub = subtitleTracks.first['index']?.toString() ?? 'none';
    } else if (_pendingSubtitleLang.isNotEmpty) {
      try {
        final match = subtitleTracks.firstWhere(
          (t) => _langMatch(t['language'], _pendingSubtitleLang),
        );
        resolvedSub = match['index'].toString();
      } catch (_) {
        if (_pendingFallbackSubtitleLang.isNotEmpty) {
          try {
            final fallbackMatch = subtitleTracks.firstWhere(
              (t) => _langMatch(t['language'], _pendingFallbackSubtitleLang),
            );
            resolvedSub = fallbackMatch['index'].toString();
          } catch (_) {}
        }
      }
    }

    if (_pendingAudioLang.isNotEmpty) {
      try {
        final match = audioTracks.firstWhere(
          (t) => _langMatch(t['language'], _pendingAudioLang),
        );
        resolvedAudio = match['index'].toString();
      } catch (_) {}
    }

    setState(() {
      _selectedSubtitleIndex = resolvedSub;
      _selectedAudioIndex = resolvedAudio;
    });
  }

  Future<void> _loadPlaybackSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedQuality = prefs.getString('loom_player_quality_pref') ?? 'direct';
    final savedSubLang = prefs.getString('loom_player_subtitle_lang') ?? '';
    final savedFallbackSub = prefs.getString('loom_player_fallback_subtitle_lang') ?? '';
    final savedAudioLang = prefs.getString('loom_player_audio_lang') ?? '';

    setState(() {
      _selectedQuality = savedQuality;
      _pendingSubtitleLang = savedSubLang;
      _pendingFallbackSubtitleLang = savedFallbackSub;
      _pendingAudioLang = savedAudioLang;
    });
    _applyLanguageDefaults(widget.episode);
  }

  @override
  void dispose() {
    _ratingFlashTimer?.cancel();
    super.dispose();
  }

  // ── Episode helpers ──────────────────────────────────────────────────────

  String get _epId    => widget.episode['id']?.toString() ?? '';
  int    get _seasonN => int.tryParse(widget.episode['season_number']?.toString() ?? '1') ?? 1;
  int    get _epN     => int.tryParse(widget.episode['episode_number']?.toString() ?? '1') ?? 1;
  String get _label   => 'S${_seasonN.toString().padLeft(2,'0')}E${_epN.toString().padLeft(2,'0')}';
  String get _epTitle => widget.episode['title']?.toString() ?? 'Avsnitt $_epN';
  String get _airDate => widget.episode['air_date']?.toString() ?? '';
  String get _overview => widget.episode['overview']?.toString() ?? '';
  String? get _stillPath {
    final raw = widget.episode['still_path']?.toString();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return 'https://image.tmdb.org/t/p/w780$raw';
  }
  bool   get _hasFile => _epId.isNotEmpty && (widget.episode['file_path'] != null);
  bool   get _hasProgress => _progress > 60 && !_isWatched;

  // ── Show helpers ─────────────────────────────────────────────────────────

  Map<String, dynamic> get _showMeta {
    final m = widget.showData['metadata'];
    return (m is Map) ? Map<String, dynamic>.from(m as Map) : {};
  }

  String get _showTitle => widget.showData['title']?.toString() ?? '';
  String? get _fanartPath => widget.showData['fanart_path']?.toString();
  String? get _posterPath => widget.showData['poster_path']?.toString();
  String? get _logoPath => _showMeta['logo_path']?.toString();

  List<dynamic> get _allEpisodes {
    final eps = widget.showData['episodes'];
    return eps is List ? eps : [];
  }

  String _episodeLabel(Map<String, dynamic> ep) {
    final s = int.tryParse(ep['season_number']?.toString() ?? '1') ?? 1;
    final e = int.tryParse(ep['episode_number']?.toString() ?? '1') ?? 1;
    return 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? get _prevEpisode {
    Map<String, dynamic>? best;
    for (final raw in _allEpisodes) {
      final e = raw as Map<String, dynamic>;
      final s = int.tryParse(e['season_number']?.toString() ?? '0') ?? 0;
      final n = int.tryParse(e['episode_number']?.toString() ?? '0') ?? 0;
      if (s == 0 || n == 0) continue;
      if (s > _seasonN || (s == _seasonN && n >= _epN)) continue;
      if (best == null) { best = e; continue; }
      final bs = int.tryParse(best['season_number']?.toString() ?? '0') ?? 0;
      final bn = int.tryParse(best['episode_number']?.toString() ?? '0') ?? 0;
      if (s > bs || (s == bs && n > bn)) best = e;
    }
    return best;
  }

  Map<String, dynamic>? get _nextEpisode {
    Map<String, dynamic>? best;
    for (final raw in _allEpisodes) {
      final e = raw as Map<String, dynamic>;
      final s = int.tryParse(e['season_number']?.toString() ?? '0') ?? 0;
      final n = int.tryParse(e['episode_number']?.toString() ?? '0') ?? 0;
      if (s == 0 || n == 0) continue;
      if (s < _seasonN || (s == _seasonN && n <= _epN)) continue;
      if (best == null) { best = e; continue; }
      final bs = int.tryParse(best['season_number']?.toString() ?? '0') ?? 0;
      final bn = int.tryParse(best['episode_number']?.toString() ?? '0') ?? 0;
      if (s < bs || (s == bs && n < bn)) best = e;
    }
    return best;
  }

  void _showSeasonPickerForNav() {
    final eps = _allEpisodes;
    if (eps.isEmpty) return;
    final seasons = <int>{};
    for (final raw in eps) {
      final s = int.tryParse((raw as Map)['season_number']?.toString() ?? '0') ?? 0;
      if (s > 0) seasons.add(s);
    }
    final sortedSeasons = seasons.toList()..sort();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Välj säsong', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 220,
          child: ListView(
            shrinkWrap: true,
            children: sortedSeasons.map((s) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ListTile(
                title: Text('Säsong $s', style: TextStyle(
                  color: s == _seasonN ? const Color(0xFF8A5BFF) : Colors.white,
                  fontWeight: s == _seasonN ? FontWeight.bold : FontWeight.normal,
                )),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onNavigateToSeason?.call(s);
                },
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }

  void _showSeasonPicker() {
    final eps = _allEpisodes;
    if (eps.isEmpty) return;
    final seasons = <int>{};
    for (final raw in eps) {
      final s = int.tryParse((raw as Map)['season_number']?.toString() ?? '0') ?? 0;
      if (s > 0) seasons.add(s);
    }
    final sortedSeasons = seasons.toList()..sort();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Välj säsong', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 220,
          child: ListView(
            shrinkWrap: true,
            children: sortedSeasons.map((s) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ListTile(
                title: Text('Säsong $s', style: TextStyle(
                  color: s == _seasonN ? const Color(0xFF8A5BFF) : Colors.white,
                  fontWeight: s == _seasonN ? FontWeight.bold : FontWeight.normal,
                )),
                onTap: () { Navigator.pop(ctx); _showEpisodePicker(s); },
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }

  void _showEpisodePicker(int seasonN) {
    final eps = _allEpisodes;
    final seasonEps = eps
        .where((e) => (int.tryParse((e as Map)['season_number']?.toString() ?? '0') ?? 0) == seasonN)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    seasonEps.sort((a, b) {
      final an = int.tryParse(a['episode_number']?.toString() ?? '0') ?? 0;
      final bn = int.tryParse(b['episode_number']?.toString() ?? '0') ?? 0;
      return an.compareTo(bn);
    });
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Säsong $seasonN — välj avsnitt', style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: seasonEps.map((ep) {
              final label = _episodeLabel(ep);
              final title = ep['title']?.toString() ?? label;
              final isCurrent = ep['id']?.toString() == _epId;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ListTile(
                  leading: Text(label, style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 12, fontWeight: FontWeight.bold)),
                  title: Text(title, style: TextStyle(
                    color: isCurrent ? const Color(0xFF8A5BFF) : Colors.white,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onNavigateToEpisode?.call(ep);
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _parseCrewList(dynamic raw) {
    if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (raw is String && raw.isNotEmpty) {
      try { return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(); } catch (_) {}
    }
    return [];
  }

  List<Map<String, dynamic>> get _cast => _parseCrewList(_showMeta['cast']);

  List<dynamic> get _providers {
    final wp = _showMeta['watch_providers'];
    if (wp is Map && wp['SE'] is Map) {
      return (wp['SE']['flatrate'] as List<dynamic>? ?? []);
    }
    return [];
  }

  List<String> get _genres {
    return (widget.showData['genre'] as String? ?? '')
        .split(', ')
        .where((g) => g.isNotEmpty)
        .toList();
  }

  // ── Subtitle / audio tracks from episode file or show fallback ───────────

  List<Map<String, dynamic>> _parseTrackList(dynamic raw) {
    if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }
    return [];
  }

  List<Map<String, dynamic>> get _subtitleTracks {
    final raw = widget.episode['subtitle_tracks'] ?? _showMeta['subtitle_tracks'];
    final parsed = _parseTrackList(raw);
    print("EPISODE_SUBTITLES RAW: $raw => PARSED: $parsed");
    return parsed;
  }

  List<Map<String, dynamic>> get _audioTracks {
    final raw = widget.episode['audio_tracks'] ?? _showMeta['audio_tracks'];
    return _parseTrackList(raw);
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  void _play([int startFrom = 0]) {
    if (_epId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          mediaId: _epId,
          apiService: widget.apiService,
          startFromSeconds: startFrom,
          useTranscode: _selectedQuality != 'direct',
          bitrate: _selectedQuality != 'direct' ? _selectedQuality : '4000k',
          initialSubtitleIndex: _selectedSubtitleIndex,
          initialAudioIndex: _selectedAudioIndex,
        ),
      ),
    ).then((_) {
      _reload();
      widget.onStatusChanged?.call();
    });
  }

  Future<void> _reload() async {
    if (_epId.isEmpty) return;
    try {
      final data = await widget.apiService.fetchEpisodeStatus(_epId);
      if (!mounted) return;
      setState(() {
        _isWatched = data['is_watched'] == true || data['is_watched'] == 1;
        _progress  = int.tryParse(data['playback_progress']?.toString() ?? '0') ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _toggleWatched() async {
    final target = !_isWatched;
    setState(() => _isWatched = target);
    try {
      await widget.apiService.toggleEpisodeSeenStatus(_epId, target);
      widget.onStatusChanged?.call();
    } catch (_) {
      if (mounted) setState(() => _isWatched = !target);
    }
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildCrewRow(String label, List<Map<String, dynamic>> people) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: people.map((p) {
          final name = p['name'] as String? ?? '';
          final id = p['id']?.toString();
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
                  builder: (_) => PersonDetailsScreen(personId: id, apiService: widget.apiService),
                ));
              }
            } : null,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPlaybackSelectors() {
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
            Text('$label: ', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
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

    final qualityItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'direct', child: Text('Direct play')),
      const DropdownMenuItem(value: '2000k', child: Text('Transcode 2 Mb')),
      const DropdownMenuItem(value: '5000k', child: Text('Transcode 5 Mb')),
      const DropdownMenuItem(value: '8000k', child: Text('Transcode 8 Mb')),
    ];

    final subtitleItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'none', child: Text('Av')),
      ..._subtitleTracks.map((t) {
        final idx = t['index']?.toString() ?? '';
        final label = t['label']?.toString() ?? t['codec']?.toString() ?? idx;
        final lang = t['language']?.toString() ?? '';
        return DropdownMenuItem(value: idx, child: Text(lang.isEmpty ? label : '$label · $lang', overflow: TextOverflow.ellipsis));
      }),
    ];

    final audioItems = <DropdownMenuItem<String?>>[
      ..._audioTracks.map((t) {
        final idx = t['index']?.toString() ?? '';
        final codec = t['codec']?.toString() ?? 'Audio';
        final lang = t['language']?.toString() ?? '';
        final ch = t['channels']?.toString() ?? '';
        final label = [codec, if (ch.isNotEmpty) '${ch}ch', if (lang.isNotEmpty) lang].join(' · ');
        return DropdownMenuItem(value: idx, child: Text(label, overflow: TextOverflow.ellipsis));
      }),
    ];

    final effSub = subtitleItems.any((i) => i.value == _selectedSubtitleIndex)
        ? _selectedSubtitleIndex : 'none';

    String? effAudio;
    if (_audioTracks.isNotEmpty) {
      final firstIdx = _audioTracks.first['index']?.toString();
      effAudio = audioItems.any((i) => i.value == _selectedAudioIndex)
          ? _selectedAudioIndex : firstIdx;
      if (effAudio != _selectedAudioIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedAudioIndex = effAudio);
        });
      }
    }

    return Row(
      children: [
        Expanded(child: dropdown<String>(
          icon: Icons.hd_outlined,
          label: 'Kvalitet',
          value: _selectedQuality,
          items: qualityItems,
          onChanged: (v) { if (v != null) setState(() => _selectedQuality = v); },
        )),
        const SizedBox(width: 8),
        Expanded(child: dropdown<String>(
          icon: Icons.subtitles_outlined,
          label: 'Undertext',
          value: effSub,
          items: subtitleItems,
          onChanged: (v) { if (v != null) setState(() => _selectedSubtitleIndex = v); },
        )),
        if (_audioTracks.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(child: dropdown<String?>(
            icon: Icons.audio_file_outlined,
            label: 'Ljud',
            value: effAudio,
            items: audioItems,
            onChanged: (v) => setState(() => _selectedAudioIndex = v),
          )),
        ],
      ],
    );
  }

  double _normalizeRating(double value) => value.clamp(0.0, 10.0).roundToDouble();

  Future<void> _onShowRatingChangeEnd(double val) async {
    final rating = _normalizeRating(val);
    _ratingFlashTimer?.cancel();
    setState(() {
      _showMyRating = rating;
      _ratingPreview = rating;
      _isRatingHovering = false;
      _isRatingFlashing = true;
      _ratingFlashNonce++;
    });
    _ratingFlashTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      setState(() => _isRatingFlashing = false);
    });
    final showId = widget.showData['id']?.toString() ?? '';
    if (showId.isNotEmpty) {
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Betyg uppdaterat till ${rating.toStringAsFixed(0)}! Synkas med Trakt/Simkl.'),
            backgroundColor: const Color(0xFF8A5BFF),
            duration: const Duration(seconds: 2),
          ));
        }
        await widget.apiService.saveRating(showId, rating);
      } catch (_) {}
    }
  }

  String _formatRating(dynamic rating) {
    if (rating == null) return '—';
    final parsed = double.tryParse(rating.toString().replaceAll(',', '.'));
    if (parsed == null) return rating.toString();
    return parsed.toStringAsFixed(1);
  }

  String _formatVotes(dynamic votes) {
    if (votes == null) return '';
    final raw = votes.toString().replaceAll(RegExp(r'[^0-9]'), '');
    final count = int.tryParse(raw) ?? 0;
    if (count == 0) return '';
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M röster';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K röster';
    return '$count röster';
  }

  String _formatSimklRating(dynamic rating) {
    if (rating == null) return '—%';
    final parsed = double.tryParse(rating.toString().replaceAll(',', '.'));
    if (parsed == null) return '${rating.toString()}%';
    if (parsed <= 10) return '${(parsed * 10).toStringAsFixed(0)}%';
    if (parsed <= 100) return '${parsed.toStringAsFixed(0)}%';
    return '—%';
  }

  Widget _buildRatingRow(String source, String value, Color color, {String? url, String? votes}) {
    Widget badge;
    if (source.toLowerCase() == 'imdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFF5C518), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black, width: 1.5)),
        child: const Text('IMDb', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: -0.5)),
      );
    } else if (source.toLowerCase() == 'simkl') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFF21C65E), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black, width: 1.5)),
        child: const Text('SIMKL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
      );
    } else if (source.toLowerCase() == 'trakt') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFED2224), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black, width: 1.5)),
        child: const Text('TRAKT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5)),
      );
    } else if (source.toLowerCase() == 'tmdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFF03B6E1), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black, width: 1.5)),
        child: const Text('TMDB', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
      );
    } else {
      badge = Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
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
            color: url != null ? Colors.white.withValues(alpha: 0.02) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: url != null ? Border.all(color: Colors.white.withValues(alpha: 0.04)) : null,
          ),
          child: Row(
            children: [
              badge,
              const SizedBox(width: 12),
              if (url != null) ...[const SizedBox(width: 4), const Icon(Icons.open_in_new, color: Colors.white24, size: 12)],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  if (votes != null && votes.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(votes, style: const TextStyle(color: Colors.white30, fontSize: 11)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyRatingControl() {
    final displayRating = _isRatingHovering && _ratingPreview != null ? _ratingPreview! : _showMyRating;
    final displayText = displayRating.toStringAsFixed(0);
    final glowColor = _isRatingFlashing
        ? const Color(0xFFFFD65C)
        : (_isRatingHovering ? const Color(0xFFB593FF) : const Color(0xFF8A5BFF));

    Widget buildChip(int rating) {
      final isSelected = rating == displayRating.round();
      final isHovered = _isRatingHovering && _ratingPreview?.round() == rating;
      final chipGlow = _isRatingFlashing && isSelected
          ? const Color(0xFFFFD65C)
          : (isHovered ? const Color(0xFFB593FF) : const Color(0xFF8A5BFF));
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() { _isRatingHovering = true; _ratingPreview = rating.toDouble(); }),
        child: GestureDetector(
          onTap: () => _onShowRatingChangeEnd(rating.toDouble()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 24, height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? chipGlow.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: chipGlow.withValues(alpha: isSelected || isHovered ? 0.9 : 0.22), width: isSelected ? 1.3 : 1.0),
              boxShadow: [BoxShadow(color: chipGlow.withValues(alpha: isHovered || isSelected ? 0.36 : 0.08), blurRadius: isHovered || isSelected ? 10 : 4, offset: const Offset(0, 2))],
            ),
            child: Text('$rating', style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 10, fontWeight: FontWeight.w900)),
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onExit: (_) => setState(() { _isRatingHovering = false; _ratingPreview = null; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: _isRatingHovering || _isRatingFlashing ? 0.12 : 0.04)),
        ),
        child: Row(
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isResetHovering = true),
              onExit: (_) => setState(() => _isResetHovering = false),
              child: GestureDetector(
                onTap: () => _onShowRatingChangeEnd(0.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isResetHovering ? const Color(0xFFB9536F) : const Color(0xFF8A5BFF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Text(_isResetHovering ? 'NOLLSTÄLL BETYG' : 'MITT BETYG',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5)),
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
                    if (index != 0) return Padding(padding: const EdgeInsets.only(left: 4), child: buildChip(rating));
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
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: Tween<double>(begin: 1.3, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)), child: child),
                ),
                child: Text(displayText,
                  key: ValueKey('eprating-$_ratingFlashNonce-$displayText'),
                  style: TextStyle(
                    color: _isRatingFlashing ? const Color(0xFFFFF4B0) : const Color(0xFFE7D7FF),
                    fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.6,
                    shadows: [Shadow(color: glowColor.withValues(alpha: 0.8), blurRadius: _isRatingFlashing ? 12 : 8)],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('/ 10', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingsPanel() {
    final meta = _showMeta;
    final ratings = (meta['ratings'] is Map) ? meta['ratings'] as Map<String, dynamic> : <String, dynamic>{};
    final imdbId = widget.showData['imdb_id']?.toString();
    final tmdbId = widget.showData['tmdb_id']?.toString();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Betyg', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildMyRatingControl(),
          const SizedBox(height: 8),
          _buildRatingRow('IMDb', '${_formatRating(meta['imdb_rating'])} / 10', const Color(0xFFF5C518),
              url: imdbId != null
                  ? 'https://www.imdb.com/title/$imdbId'
                  : 'https://www.imdb.com/find/?q=${Uri.encodeComponent(widget.showData['title']?.toString() ?? '')}',
              votes: _formatVotes(meta['imdb_votes'])),
          _buildRatingRow('TMDB', '${_formatRating(ratings['tmdb'])} / 10', const Color(0xFF03B6E1),
              url: tmdbId != null
                  ? 'https://www.themoviedb.org/tv/$tmdbId'
                  : 'https://www.themoviedb.org/search?query=${Uri.encodeComponent(widget.showData['title']?.toString() ?? '')}',
              votes: _formatVotes(ratings['tmdb_votes'])),
        ],
      ),
    );
  }

  Widget _buildNavArrow({required bool isNext, required Map<String, dynamic>? episode}) {
    if (episode == null) return const SizedBox(width: 72);
    final label = _episodeLabel(episode);
    final isPressed = isNext ? _isNextPressed : _isPrevPressed;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => isNext ? _isNextPressed = true : _isPrevPressed = true),
        onTapUp: (_) {
          setState(() => isNext ? _isNextPressed = false : _isPrevPressed = false);
          widget.onNavigateToEpisode?.call(episode);
        },
        onTapCancel: () => setState(() => isNext ? _isNextPressed = false : _isPrevPressed = false),
        child: AnimatedScale(
          scale: isPressed ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isNext ? Icons.arrow_forward_ios_rounded : Icons.arrow_back_ios_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backdropUrl = _stillPath ?? _fanartPath;
    final showMeta = _showMeta;

    final createdBy  = _parseCrewList(showMeta['created_by']);
    final producers  = _parseCrewList(showMeta['producers']);
    final writers    = _parseCrewList(showMeta['writers']);
    final composers  = _parseCrewList(showMeta['composers']);
    final awardsVal  = showMeta['awards']?.toString();

    final productionCompanies = (showMeta['production_companies'] is List)
        ? showMeta['production_companies'] as List<dynamic> : [];
    final productionCountries = (showMeta['production_countries'] is List)
        ? showMeta['production_countries'] as List<dynamic> : [];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          _buildNavArrow(isNext: false, episode: _prevEpisode),
          _buildNavArrow(isNext: true, episode: _nextEpisode),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero / backdrop ──────────────────────────────────────────────
            Stack(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  width: double.infinity,
                  child: backdropUrl != null
                      ? ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black, Colors.black, Colors.transparent],
                            stops: [0.0, 0.45, 1.0],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: Image.network(backdropUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF15102A))),
                        )
                      : Container(color: const Color(0xFF15102A)),
                ),

                // Overlay content in hero
                Positioned(
                  bottom: 0,
                  left: 40,
                  right: 40,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Poster column: show series poster only when no episode still available
                      if (_posterPath != null && _stillPath == null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (_logoPath != null) ...[
                              SizedBox(
                                width: 180,
                                height: 65,
                                child: Image.network(_logoPath!, fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Container(
                              width: 180,
                              height: 270,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, 12))],
                                image: DecorationImage(image: NetworkImage(_posterPath!), fit: BoxFit.cover),
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(width: 36),

                      // Title / info column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Breadcrumb: ShowTitle — Säsong X — SxxExx
                            if (_showTitle.isNotEmpty) ...[
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () => widget.onNavigateToShow?.call(),
                                      child: Text(
                                        _showTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor: Colors.white54,
                                          shadows: [Shadow(blurRadius: 6, color: Colors.black), Shadow(blurRadius: 12, color: Colors.black)],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Text('  —  ', style: TextStyle(color: Colors.white70, fontSize: 14, shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: _showSeasonPickerForNav,
                                      child: Text(
                                        'Säsong $_seasonN',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor: Colors.white54,
                                          shadows: [Shadow(blurRadius: 6, color: Colors.black), Shadow(blurRadius: 12, color: Colors.black)],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Text('  —  ', style: TextStyle(color: Colors.white70, fontSize: 14, shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () => _showEpisodePicker(_seasonN),
                                      child: Text(
                                        _label,
                                        style: const TextStyle(
                                          color: Color(0xFFB593FF),
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                          decorationColor: Color(0xFF8A5BFF),
                                          shadows: [Shadow(blurRadius: 6, color: Colors.black), Shadow(blurRadius: 12, color: Colors.black)],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],

                            // Episode title
                            Text(_epTitle, style: const TextStyle(
                              color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold,
                              height: 1.1, letterSpacing: -0.4,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 6, offset: Offset(1.5, 1.5)),
                                Shadow(color: Colors.black, blurRadius: 6, offset: Offset(-1.5, 1.5)),
                                Shadow(color: Colors.black, blurRadius: 6, offset: Offset(1.5, -1.5)),
                                Shadow(color: Colors.black, blurRadius: 6, offset: Offset(-1.5, -1.5)),
                              ],
                            )),

                            // Air date
                            if (_airDate.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(_airDate, style: TextStyle(color: Colors.white.withValues(alpha: 0.40), fontSize: 13)),
                            ],

                            const SizedBox(height: 20),

                            // Crew (from show)
                            _buildCrewRow('Skapare', createdBy),
                            _buildCrewRow('Producent', producers),
                            _buildCrewRow('Manus', writers),
                            _buildCrewRow('Musik', composers),

                            const SizedBox(height: 12),

                            // PG + companies + countries
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    border: Border.all(color: Colors.black, width: 2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('PG-13', style: TextStyle(
                                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold,
                                  )),
                                ),
                                ...productionCompanies.take(2).map((c) {
                                  final name = c is Map ? (c['name']?.toString() ?? '') : c.toString();
                                  if (name.isEmpty) return const SizedBox.shrink();
                                  return Chip(
                                    avatar: const Icon(Icons.business, size: 14, color: Color(0xFF8A5BFF)),
                                    label: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                                    side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                  );
                                }),
                                ...productionCountries.map((c) {
                                  final name = c is Map ? (c['name']?.toString() ?? '') : c.toString();
                                  final iso = c is Map ? (c['iso_3166_1']?.toString().toUpperCase() ?? '') : '';
                                  if (name.isEmpty) return const SizedBox.shrink();
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (iso.length == 2) ...[
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(2),
                                            child: Image.network(
                                              'https://flagcdn.com/w20/${iso.toLowerCase()}.png',
                                              width: 18, height: 12, fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Text(iso, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                        Text(name, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Genres
                            if (_genres.isNotEmpty)
                              Wrap(
                                spacing: 6,
                                children: _genres.map((g) => Chip(
                                  label: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                )).toList(),
                              ),

                            // Awards
                            if (awardsVal != null && awardsVal.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: awardsVal.split(RegExp(r'[•|]')).map((s) => s.trim()).where((s) => s.isNotEmpty).take(3).map((award) {
                                  final isWin = award.toLowerCase().contains('win') || award.contains('vinner') || award.contains('vinst');
                                  final isNom = award.toLowerCase().contains('nom');
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isWin
                                          ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                                          : const Color(0xFFB593FF).withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: isWin
                                          ? const Color(0xFFFFD700).withValues(alpha: 0.40)
                                          : const Color(0xFFB593FF).withValues(alpha: 0.30)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(isWin ? Icons.emoji_events : (isNom ? Icons.star_border : Icons.military_tech_outlined),
                                            size: 13, color: isWin ? const Color(0xFFFFD700) : const Color(0xFFB593FF)),
                                        const SizedBox(width: 5),
                                        Text(award, style: TextStyle(
                                          color: isWin ? const Color(0xFFFFD700) : const Color(0xFFB593FF),
                                          fontSize: 11, fontWeight: FontWeight.w600,
                                        )),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],

                            const SizedBox(height: 20),

                            // Action buttons
                            Row(
                              children: [
                                if (_hasFile) ...[
                                  ElevatedButton.icon(
                                    onPressed: () => _play(_hasProgress ? _progress : 0),
                                    icon: Icon(_hasProgress ? Icons.play_circle_outline : Icons.play_arrow, size: 26),
                                    label: Text(_hasProgress ? 'Återuppta' : 'Spela',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF8A5BFF),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                      elevation: 8,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: _toggleWatched,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: _isWatched
                                              ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                                              : Colors.white.withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(30),
                                          border: Border.all(color: _isWatched ? const Color(0xFF4CAF50) : Colors.white24),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _isWatched ? Icons.check_circle : Icons.radio_button_unchecked,
                                              color: _isWatched ? const Color(0xFF4CAF50) : Colors.white54,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _isWatched ? 'Sedd' : 'Markera som sedd',
                                              style: TextStyle(
                                                color: _isWatched ? const Color(0xFF4CAF50) : Colors.white70,
                                                fontSize: 14, fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.schedule, color: Colors.white38, size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          _airDate.isNotEmpty ? 'Sänds $_airDate' : 'Ej tillgänglig ännu',
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.40), fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            // Progress bar
                            if (_hasProgress) ...[
                              const SizedBox(height: 14),
                              Builder(builder: (context) {
                                final dur = int.tryParse(widget.episode['duration']?.toString() ?? '0') ?? 0;
                                if (dur == 0) return const SizedBox.shrink();
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (_progress / dur).clamp(0.0, 1.0),
                                    minHeight: 4,
                                    color: const Color(0xFF8A5BFF),
                                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Content section ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: overview + playback selectors
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Episode overview
                        if (_overview.isNotEmpty) ...[
                          Text(_overview, style: const TextStyle(
                            color: Colors.white70, fontSize: 16, height: 1.6,
                          )),
                          const SizedBox(height: 24),
                        ],

                        // Streaming providers
                        if (_providers.isNotEmpty) ...[
                          const Text('Finns att strömma på', style: TextStyle(
                            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700,
                          )),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _providers.map((prov) {
                              final logoPath = prov['logo_path'];
                              final name = prov['provider_name'];
                              if (logoPath == null) return const SizedBox.shrink();
                              return Tooltip(
                                message: name ?? '',
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white12),
                                    image: DecorationImage(
                                      image: NetworkImage('https://image.tmdb.org/t/p/w500$logoPath'),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Playback selectors
                        _buildPlaybackSelectors(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 60),

                  // Right: ratings panel
                  Expanded(
                    flex: 1,
                    child: _buildRatingsPanel(),
                  ),
                ],
              ),
            ),

            // ── Cast carousel ────────────────────────────────────────────────
            if (_cast.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text('Skådespelare', style: TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
                )),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  scrollDirection: Axis.horizontal,
                  itemCount: _cast.length,
                  itemBuilder: (context, index) {
                    final actor = _cast[index];
                    final actorId = actor['id']?.toString();
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          if (actorId == null) return;
                          if (widget.onPersonSelected != null) {
                            widget.onPersonSelected!(actorId);
                          } else {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => PersonDetailsScreen(personId: actorId, apiService: widget.apiService),
                            ));
                          }
                        },
                        child: Container(
                          width: 130,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 150,
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                                  image: actor['profile_path'] != null
                                      ? DecorationImage(image: NetworkImage(actor['profile_path']), fit: BoxFit.cover)
                                      : null,
                                ),
                                child: actor['profile_path'] == null
                                    ? const Center(child: Icon(Icons.person, size: 44, color: Colors.white24))
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(actor['name'] ?? '', style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13,
                              ), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(actor['character'] ?? '', style: const TextStyle(
                                color: Colors.white38, fontSize: 11,
                              ), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }

}
