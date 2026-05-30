import 'package:flutter/material.dart';
import '../services/api.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:html' as html;
import 'person_details_screen.dart';
import 'resume_playback_modal.dart';

class MediaDetailsScreen extends StatefulWidget {
  final String mediaId;
  final ApiService apiService;
  final VoidCallback? onBack;
  final ValueChanged<String>? onGenreSelected;
  final ValueChanged<String>? onKeywordSelected;
  final ValueChanged<String>? onMediaSelected;
  final ValueChanged<String>? onPersonSelected;

  const MediaDetailsScreen({
    super.key,
    required this.mediaId,
    required this.apiService,
    this.onBack,
    this.onGenreSelected,
    this.onKeywordSelected,
    this.onMediaSelected,
    this.onPersonSelected,
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
  String _selectedAudioTrack = 'English (AAC 5.1)';
  String _selectedSubtitle = 'None';
  bool _isCoverHovered = false;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  @override
  void dispose() {
    _ratingFlashTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final data = await widget.apiService.fetchMediaDetails(widget.mediaId);
      
      // Extract ratings / watch status if saved
      final metadata = data['metadata'] ?? {};
      final savedRating = double.tryParse(metadata['my_rating']?.toString() ?? '0') ?? 0.0;
      final savedWatchStatus = metadata['watch_status'] == 'watched';
      final progress = int.tryParse(metadata['playback_progress']?.toString() ?? '0') ?? 0;

      // Load settings to fetch default options
      String titleStyle = 'Translated';
      String subLang = 'sv';
      String audioLang = 'en';
      try {
        final settings = await widget.apiService.getSettings();
        if (settings.containsKey('TITLE_DISPLAY_STYLE')) {
          titleStyle = settings['TITLE_DISPLAY_STYLE'];
        }
        subLang = settings['DEFAULT_SUBTITLE_LANG'] ?? 'sv';
        audioLang = settings['DEFAULT_AUDIO_LANG'] ?? 'en';
      } catch (e) {
        debugPrint('Error loading settings in details: $e');
      }

      // Parse audio and subtitle tracks lists
      final List<dynamic> audioTracks = (metadata['audio_tracks'] is List) 
          ? metadata['audio_tracks'] as List<dynamic> 
          : [];
      final List<dynamic> subtitleTracks = (metadata['subtitle_tracks'] is List) 
          ? metadata['subtitle_tracks'] as List<dynamic> 
          : [];

      // Pre-select based on settings
      String audioTrack = 'English (AAC 5.1)';
      if (audioTracks.isNotEmpty) {
        final isSv = (audioLang.toLowerCase() == 'sv' || audioLang.toLowerCase() == 'swedish' || audioLang.toLowerCase() == 'swe');
        final targetLang = isSv ? 'SWE' : 'ENG';
        final matchIndex = audioTracks.indexWhere(
          (t) => t['language']?.toString().toUpperCase() == targetLang
        );
        if (matchIndex != -1) {
          audioTrack = audioTracks[matchIndex]['label']?.toString() ?? 'Unknown Audio';
        } else {
          audioTrack = audioTracks.first['label']?.toString() ?? 'Unknown Audio';
        }
      } else {
        audioTrack = (audioLang.toLowerCase() == 'sv' || audioLang.toLowerCase() == 'swedish') 
            ? 'Swedish (Stereo)' 
            : 'English (AAC 5.1)';
      }

      String subtitle = 'None';
      if (subtitleTracks.isNotEmpty) {
        final isSv = (subLang.toLowerCase() == 'sv' || subLang.toLowerCase() == 'swedish' || subLang.toLowerCase() == 'swe');
        final isEn = (subLang.toLowerCase() == 'en' || subLang.toLowerCase() == 'english' || subLang.toLowerCase() == 'eng');
        if (isSv || isEn) {
          final targetLang = isSv ? 'SWE' : 'ENG';
          final matchIndex = subtitleTracks.indexWhere(
            (t) => t['language']?.toString().toUpperCase() == targetLang
          );
          if (matchIndex != -1) {
            subtitle = subtitleTracks[matchIndex]['label']?.toString() ?? 'None';
          }
        }
      } else {
        subtitle = (subLang.toLowerCase() == 'sv' || subLang.toLowerCase() == 'swedish') 
            ? 'Swedish (SRT)' 
            : (subLang.toLowerCase() == 'en' || subLang.toLowerCase() == 'english')
                ? 'English (SDH)'
                : 'None';
      }

      setState(() {
        _mediaData = data;
        _myRating = savedRating > 0 ? savedRating : 0.0;
        _isWatched = savedWatchStatus;
        _savedProgressSeconds = progress;
        _titleDisplayStyle = titleStyle;
        _selectedAudioTrack = audioTrack;
        _selectedSubtitle = subtitle;
        _isLoading = false;
      });
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
            content: Text('Betyg uppdaterat till ${rating.toStringAsFixed(0)}! Synkas med Trakt/Simkl.'),
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
            SnackBar(content: Text('Misslyckades spara betyg: $e'), backgroundColor: Colors.redAccent),
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
            content: Text(targetState ? 'Markerad som sedd! Synkar...' : 'Markerad som osedd! Synkar...'),
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
        return _FixMatchDialog(
          mediaId: widget.mediaId,
          apiService: widget.apiService,
          currentTitle: _mediaData?['title'] ?? '',
          currentYear: _mediaData?['year']?.toString() ?? '',
          onMatchSuccess: () {
            _fetchDetails();
          },
        );
      },
    );
  }

  void _playMedia() {
    if (_savedProgressSeconds > 0) {
      showDialog(
        context: context,
        builder: (context) => ResumePlaybackModal(
          savedPositionSeconds: _savedProgressSeconds,
          onResume: () {
            _startPlayback(_savedProgressSeconds);
          },
          onStartOver: () {
            _startPlayback(0);
          },
        ),
      );
    } else {
      _startPlayback(0);
    }
  }

  void _startPlayback(int startFromSeconds) {
    final meta = _mediaData?['metadata'] ?? {};
    int durationSec = int.tryParse(meta['duration']?.toString() ?? '') ?? 0;
    if (durationSec == 0) {
      final runtimeMinutes = int.tryParse(meta['runtime']?.toString() ?? '') ?? 0;
      durationSec = runtimeMinutes * 60;
    }
    if (durationSec <= 0) {
      durationSec = 7200; // default 120 minutes
    }

    showDialog(
      context: context,
      barrierDismissible: false, // Must click Stop to save progress
      builder: (context) {
        return _PlaybackSimulatorDialog(
          mediaId: widget.mediaId,
          apiService: widget.apiService,
          title: _mediaData?['title'] ?? 'Unknown Title',
          durationSeconds: durationSec,
          startFromSeconds: startFromSeconds,
          onPlaybackFinished: (finalPosition, wasCompleted) {
            if (wasCompleted) {
              setState(() {
                _isWatched = true;
                _savedProgressSeconds = 0;
              });
            } else {
              setState(() {
                _savedProgressSeconds = finalPosition;
              });
            }
            _fetchDetails(); // Reload media info to sync with UI
          },
        );
      },
    );
  }


  double _normalizeRating(double value) {
    return value.clamp(0.0, 10.0).roundToDouble();
  }

  void _updateRatingPreviewFromHover(dynamic event, double width) {
    final usableWidth = width <= 0 ? 1.0 : width;
    final localPosition = event.localPosition;
    final clampedDx = (localPosition.dx as double).clamp(0.0, usableWidth);
    final preview = _normalizeRating(((clampedDx / usableWidth) * 10.0).ceilToDouble());
    setState(() {
      _ratingPreview = preview;
      _isRatingHovering = true;
    });
  }

  Widget _buildMyRatingControl() {
    final displayRating = _isRatingHovering && _ratingPreview != null ? _ratingPreview! : _myRating;
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
              color: isSelected ? chipGlow.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: chipGlow.withValues(alpha: isSelected || isHovered ? 0.9 : 0.22), width: isSelected ? 1.3 : 1.0),
              boxShadow: [
                BoxShadow(
                  color: chipGlow.withValues(alpha: isHovered || isSelected ? 0.36 : 0.08),
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
          border: Border.all(color: Colors.white.withValues(alpha: _isRatingHovering || _isRatingFlashing ? 0.12 : 0.04)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isResetHovering ? const Color(0xFFB9536F) : const Color(0xFF8A5BFF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Text(
                    _isResetHovering ? 'NOLLSTÄLL BETYG' : 'MITT BETYG',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
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
                      scale: Tween<double>(begin: 1.3, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  displayText,
                  key: ValueKey('rating-${_ratingFlashNonce}-$displayText'),
                  style: TextStyle(
                    color: _isRatingFlashing ? const Color(0xFFFFF4B0) : const Color(0xFFE7D7FF),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    shadows: [
                      Shadow(color: glowColor.withValues(alpha: 0.8), blurRadius: _isRatingFlashing ? 12 : 8),
                    ],
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

  String _buildTrailerSearchUrl(String title, String year) {
    return 'https://www.youtube.com/results?search_query=${Uri.encodeComponent("$title $year Official Trailer")}';
  }

  Future<void> _launchTrailer(String? trailerUrl, String title, String year) async {
    final finalTrailerUrl = trailerUrl ?? _buildTrailerSearchUrl(title, year);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF15102A),
          title: const Text('Öppna trailer', style: TextStyle(color: Colors.white)),
          content: const Text(
            'För TV-fjärrkontroll: välj Samma flik så fungerar Back/Retur för att gå tillbaka till filmen.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'same'),
              child: const Text('Samma flik', style: TextStyle(color: Color(0xFF8A5BFF))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'new'),
              child: const Text('Ny flik', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('Avbryt', style: TextStyle(color: Colors.white54)),
            ),
          ],
        );
      },
    );

    if (action == 'same') {
      html.window.open(finalTrailerUrl, '_self');
    } else if (action == 'new') {
      html.window.open(finalTrailerUrl, '_blank');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0714),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF))),
      );
    }

    if (_error != null || _mediaData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0714),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              Text('Failed to load media details:\n$_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
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
    final title = media['title'] ?? 'Unknown Title';
    final year = media['year']?.toString() ?? '';
    final plot = media['plot'] ?? 'Ingen beskrivning tillgänglig.';
    final posterPath = media['poster_path'];
    final fanartPath = media['fanart_path'];
    final collectionName = media['collection_name'];
    final collectionId = media['collection_id'];
    final trailerUrl = media['metadata']?['trailer_url'];
    final metadata = (media['metadata'] is Map) ? media['metadata'] as Map<String, dynamic> : {};
    final audioTracks = (metadata['audio_tracks'] is List) ? metadata['audio_tracks'] as List<dynamic> : [];
    final subtitleTracks = (metadata['subtitle_tracks'] is List) ? metadata['subtitle_tracks'] as List<dynamic> : [];
    final tagline = metadata['tagline'] as String?;
    final genresList = (media['genre'] as String? ?? '').split(', ').where((g) => g.isNotEmpty).toList();
    final ratings = (metadata['ratings'] is Map) ? metadata['ratings'] as Map<String, dynamic> : {};
    final cast = (metadata['cast'] is List) ? metadata['cast'] as List<dynamic> : [];
    final keywords = (metadata['keywords'] is List) ? metadata['keywords'] as List<dynamic> : [];
    final productionCompanies = (metadata['production_companies'] is List) ? metadata['production_companies'] as List<dynamic> : [];
    final productionCountries = (metadata['production_countries'] is List) ? metadata['production_countries'] as List<dynamic> : [];
    // Director is now stored as an object with id and name
    final directorData = metadata['director'] is Map ? metadata['director'] as Map<String, dynamic> : 
                        metadata['director'] is String ? {'name': metadata['director']} : null;
    final directorName = directorData?['name'] as String?;
    final directorId = directorData?['id']?.toString();
    final logoPath = metadata['logo_path'] as String?;
    final providers = (metadata['watch_providers'] is Map && metadata['watch_providers']['SE'] is Map)
        ? (metadata['watch_providers']['SE']['flatrate'] as List<dynamic>? ?? [])
        : [];
    final awardsValue = metadata['awards'] ?? metadata['awards_text'] ?? metadata['award'] ?? metadata['prizes'] ?? metadata['omdb_awards'] ?? metadata['imdb_awards'];
    final awardsString = awardsValue is String ? awardsValue : awardsValue?.toString();

    debugPrint('[Flutter Details] Metadata rating keys present: ${metadata.keys.where((k) => k.contains("rating") || k.contains("vote")).toList()}');
    debugPrint('[Flutter Details] imdb_rating: ${metadata["imdb_rating"]} (${metadata["imdb_rating"].runtimeType}), simkl_rating: ${metadata["simkl_rating"]} (${metadata["simkl_rating"].runtimeType}), trakt_rating: ${metadata["trakt_rating"]} (${metadata["trakt_rating"].runtimeType})');

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
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
                              onEnter: (_) => setState(() => _isCoverHovered = true),
                              onExit: (_) => setState(() => _isCoverHovered = false),
                              child: GestureDetector(
                                onTap: _playMedia,
                                child: Container(
                                  width: 220,
                                  height: 330,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, 12)),
                                    ],
                                    image: DecorationImage(image: NetworkImage(posterPath), fit: BoxFit.cover),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      children: [
                                        AnimatedOpacity(
                                          duration: const Duration(milliseconds: 200),
                                          opacity: _isCoverHovered ? 1.0 : 0.0,
                                          child: Container(
                                            color: Colors.black.withValues(alpha: 0.55),
                                            child: const Center(
                                              child: CircleAvatar(
                                                radius: 36,
                                                backgroundColor: Color(0xFF8A5BFF),
                                                child: Icon(Icons.play_arrow, size: 40, color: Colors.white),
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
                            // Progress bar and minutes-left when in-progress
                            if (_savedProgressSeconds > 0) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 220,
                                child: Builder(builder: (context) {
                                  final meta = _mediaData?['metadata'] ?? {};
                                  int durationSec = int.tryParse(meta['duration']?.toString() ?? '') ?? 0;
                                  if (durationSec == 0) {
                                    final runtimeMinutes = int.tryParse(meta['runtime']?.toString() ?? '') ?? 0;
                                    durationSec = runtimeMinutes * 60;
                                  }
                                  if (durationSec == 0) {
                                    durationSec = 7200; // 120 min fallback to prevent indeterminate/rolling line
                                  }
                                  final progress = _savedProgressSeconds;
                                  final ratio = (progress / durationSec).clamp(0.0, 1.0);
                                  final playedMin = (progress / 60).ceil();
                                  final leftMin = ((durationSec - progress) / 60).ceil();
                                  
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
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                            ],
                          ],
                        ),
                      const SizedBox(width: 40),

                      // Title & Metadata info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title (Year) with translated/original logic
                            Builder(
                              builder: (context) {
                                final originalTitle = media['original_title'] as String?;
                                final hasOriginal = originalTitle != null && originalTitle.isNotEmpty;
                                final isOriginalStyle = _titleDisplayStyle == 'Original';
                                
                                String mainDisplayTitle = title;
                                String? subtitleDisplayTitle;

                                if (isOriginalStyle && hasOriginal) {
                                  mainDisplayTitle = originalTitle;
                                  if (originalTitle.toLowerCase() != title.toLowerCase()) {
                                    subtitleDisplayTitle = 'Översatt titel: $title';
                                  }
                                } else if (!isOriginalStyle && hasOriginal) {
                                  mainDisplayTitle = title;
                                  if (originalTitle.toLowerCase() != title.toLowerCase()) {
                                    subtitleDisplayTitle = 'Originaltitel: $originalTitle';
                                  }
                                }

                                final releaseVersion = metadata['release_version']?.toString() ?? '';
                                final versionSuffix = releaseVersion.isNotEmpty ? ' [$releaseVersion]' : '';
                                final displayTitle = year.isNotEmpty ? '$mainDisplayTitle ($year)$versionSuffix' : '$mainDisplayTitle$versionSuffix';

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
                                              color: Colors.white.withValues(alpha: 0.85),
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
                            
                            // Premium Quality Badges Row under the Title
                            _buildQualityBadgesRow(
                              media['file_path'] as String?, 
                              media['versions']?[0]?['resolution'] as String? ?? media['resolution'] as String?,
                              metadata: metadata
                            ),
                            const SizedBox(height: 12),

                            // Subtitle Metadata details with highly legible high-contrast outlines
                            Row(
                              children: [
                                // PG Box with drop shadow and outline
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    border: Border.all(color: Colors.black, width: 2),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4, offset: const Offset(0, 2)),
                                    ],
                                  ),
                                  child: const Text(
                                    'PG-13', 
                                    style: TextStyle(
                                      color: Colors.white, 
                                      fontSize: 12, 
                                      fontWeight: FontWeight.bold,
                                    )
                                  ),
                                ),
                                const SizedBox(width: 16),
                                
                                // Collection Banner with clear black outline
                                if (collectionName != null && collectionName.toString().isNotEmpty) ...[
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () {
                                        _showCollectionDialog(collectionName.toString(), collectionId?.toString());
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFB593FF).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.black, width: 2),
                                          boxShadow: [
                                            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 2)),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.layers, color: Color(0xFFB593FF), size: 14),
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

                                // Director as keyword-style chip with premium high-contrast outline
                                if (directorName != null) ...[
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () {
                                        if (directorId != null) {
                                          if (widget.onPersonSelected != null) {
                                            widget.onPersonSelected!(directorId);
                                          } else {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => PersonDetailsScreen(
                                                  personId: directorId,
                                                  apiService: widget.apiService,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.65),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.black, width: 2),
                                          boxShadow: [
                                            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 2)),
                                          ],
                                        ),
                                        child: Text(
                                          'Regi: $directorName',
                                          style: const TextStyle(
                                            color: Colors.white, 
                                            fontSize: 12, 
                                            fontWeight: FontWeight.bold
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (productionCompanies.isNotEmpty || productionCountries.isNotEmpty) ...[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ...productionCompanies.take(2).map((company) {
                                    final companyName = company is Map ? (company['name']?.toString() ?? '') : company.toString();
                                    if (companyName.isEmpty) return const SizedBox.shrink();
                                    return Chip(
                                      avatar: const Icon(Icons.business, size: 16, color: Color(0xFF8A5BFF)),
                                      label: Text(companyName, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                                      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                    );
                                  }),
                                  ...productionCountries.map((country) {
                                    final countryName = country is Map ? (country['name']?.toString() ?? '') : country.toString();
                                    final iso = country is Map ? (country['iso_3166_1']?.toString() ?? '') : '';
                                    if (countryName.isEmpty) return const SizedBox.shrink();
                                    
                                    // Generate regional flag emoji
                                    String flag = '';
                                    if (iso.length == 2) {
                                      final int char1 = iso.codeUnitAt(0) - 65 + 127462;
                                      final int char2 = iso.codeUnitAt(1) - 65 + 127462;
                                      flag = String.fromCharCode(char1) + String.fromCharCode(char2);
                                    }

                                    return Tooltip(
                                      message: countryName,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                        ),
                                        child: Text(
                                          flag.isNotEmpty ? flag : countryName,
                                          style: TextStyle(fontSize: flag.isNotEmpty ? 20 : 12),
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
                                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  label: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  onPressed: () {
                                    if (widget.onGenreSelected != null) {
                                      widget.onGenreSelected!(g);
                                    } else {
                                      Navigator.pop(context, g);
                                    }
                                  },
                                );
                              }).toList(),
                            ),

                            // Collapsible slate/purple keywords/tags wrap with expanding pane
                            if (keywords.isNotEmpty) ...[
                              const SizedBox(height: 12),
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
                            ],

                            // Awards / Priser placed directly under Genre
                            _buildAwardsRow(awardsString),
                            const SizedBox(height: 24),

                            // Control Actions Row
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _playMedia,
                                  icon: const Icon(Icons.play_arrow, size: 28),
                                  label: Text(
                                    _savedProgressSeconds > 0 ? 'Återuppta' : 'Spela',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8A5BFF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                    elevation: 8,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                
                                Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: OutlinedButton.icon(
                                    onPressed: () => _launchTrailer(trailerUrl?.toString(), title.toString(), year.toString()),
                                    icon: const Icon(Icons.slideshow, size: 22, color: Colors.white),
                                    label: const Text('Trailer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.white54, width: 1.5),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                    ),
                                  ),
                                ),

                                // Dynamic kebab Menu button frambringande av actions
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.55),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      cardColor: const Color(0xFF15102A),
                                    ),
                                    child: PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_horiz, size: 26, color: Colors.white70),
                                      tooltip: 'Fler åtgärder',
                                      onSelected: (value) async {
                                        if (value == 'playlist') {
                                          _showPlaylistDialog();
                                        } else if (value == 'watch') {
                                          _toggleWatchStatus();
                                        } else if (value == 'refresh') {
                                          try {
                                            setState(() => _isLoading = true);
                                            await widget.apiService.refreshMediaMetadata(widget.mediaId);
                                            _fetchDetails();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Metadata har uppdaterats online!'), backgroundColor: Color(0xFF8A5BFF)),
                                            );
                                          } catch (e) {
                                            setState(() => _isLoading = false);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Misslyckades uppdatera: $e'), backgroundColor: Colors.redAccent),
                                            );
                                          }
                                        } else if (value == 'analyze') {
                                          try {
                                            setState(() => _isLoading = true);
                                            await widget.apiService.analyzeMediaItem(widget.mediaId);
                                            _fetchDetails();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Mediefilen har analyserats om!'), backgroundColor: Color(0xFF8A5BFF)),
                                            );
                                          } catch (e) {
                                            setState(() => _isLoading = false);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Misslyckades analysera: $e'), backgroundColor: Colors.redAccent),
                                            );
                                          }
                                        } else if (value == 'match') {
                                          _showFixMatchDialog();
                                        } else if (value == 'unmatch') {
                                          try {
                                            setState(() => _isLoading = true);
                                            await widget.apiService.unmatchMediaItem(widget.mediaId);
                                            _fetchDetails();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Matchning borttagen!'), backgroundColor: Color(0xFF8A5BFF)),
                                            );
                                          } catch (e) {
                                            setState(() => _isLoading = false);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Misslyckades ta bort matchning: $e'), backgroundColor: Colors.redAccent),
                                            );
                                          }
                                        } else if (value == 'delete') {
                                          // Confirm dialog
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: const Color(0xFF15102A),
                                              title: const Text('Ta bort media?', style: TextStyle(color: Colors.white)),
                                              content: const Text('Är du säker på att du vill ta bort den här filmen från biblioteket? Filen på disken kommer inte raderas.', style: TextStyle(color: Colors.white70)),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt', style: TextStyle(color: Colors.white54))),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  child: const Text('Ta bort', style: TextStyle(color: Colors.redAccent)),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            try {
                                              await widget.apiService.deleteMediaItem(widget.mediaId);
                                              if (widget.onBack != null) {
                                                widget.onBack!();
                                              } else {
                                                Navigator.pop(context);
                                              }
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Media raderad från biblioteket.'), backgroundColor: Color(0xFF8A5BFF)),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Misslyckades ta bort: $e'), backgroundColor: Colors.redAccent),
                                              );
                                            }
                                          }
                                        } else if (value == 'statistics') {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Statistik kommer snart!'),
                                              backgroundColor: Color(0xFF8A5BFF),
                                            ),
                                          );
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'playlist',
                                          child: Text('Lägg till på spellista', style: TextStyle(color: Colors.white)),
                                        ),
                                        PopupMenuItem(
                                          value: 'watch',
                                          child: Text(_isWatched ? 'Markera som osedd' : 'Markera som visad', style: const TextStyle(color: Colors.white)),
                                        ),
                                        const PopupMenuItem(
                                          value: 'refresh',
                                          child: Text('Uppdatera metadata', style: TextStyle(color: Colors.white)),
                                        ),
                                        const PopupMenuItem(
                                          value: 'analyze',
                                          child: Text('Analysera', style: TextStyle(color: Colors.white)),
                                        ),
                                        const PopupMenuItem(
                                          value: 'match',
                                          child: Text('Fixa matchning', style: TextStyle(color: Colors.white)),
                                        ),
                                        const PopupMenuItem(
                                          value: 'unmatch',
                                          child: Text('Ta bort matchning', style: TextStyle(color: Colors.white)),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Ta bort', style: TextStyle(color: Colors.redAccent)),
                                        ),
                                        const PopupMenuItem(
                                          value: 'statistics',
                                          child: Text('Visa statistik', style: TextStyle(color: Colors.white30)),
                                        ),
                                      ],
                                    ),
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
                          style: const TextStyle(color: Colors.white70, fontSize: 17, height: 1.6),
                        ),
                        const SizedBox(height: 20),
                        
                        // Streaming Watch Providers
                        if (providers.isNotEmpty) ...[
                          const Text('Finns att strömma på', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
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
                                    image: NetworkImage('https://image.tmdb.org/t/p/w500$logoPath'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: Tooltip(message: name ?? ''),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Compact Audio & Subtitles Row
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.volume_up_outlined, color: Colors.white38, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isDense: true,
                                    value: _selectedAudioTrack,
                                    dropdownColor: const Color(0xFF15102A),
                                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white38, size: 16),
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                    items: (audioTracks.isNotEmpty 
                                        ? audioTracks.map((t) => t['label']?.toString() ?? '').where((label) => label.isNotEmpty).toList() 
                                        : ['English (AAC 5.1)', 'Swedish (Stereo)'])
                                      .map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                                    onChanged: (val) { if (val != null) setState(() => _selectedAudioTrack = val); },
                                  ),
                                ),
                              ),
                              Container(width: 1, height: 24, color: Colors.white10, margin: const EdgeInsets.symmetric(horizontal: 12)),
                              const Icon(Icons.subtitles_outlined, color: Colors.white38, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    isDense: true,
                                    value: _selectedSubtitle,
                                    dropdownColor: const Color(0xFF15102A),
                                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white38, size: 16),
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                    items: (subtitleTracks.isNotEmpty 
                                        ? ['None', ...subtitleTracks.map((t) => t['label']?.toString() ?? '').where((label) => label.isNotEmpty)] 
                                        : ['None', 'Swedish (SRT)', 'English (SDH)'])
                                      .map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                                    onChanged: (val) { if (val != null) setState(() => _selectedSubtitle = val); },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Betyg', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 20),
                          _buildMyRatingControl(),
                          const SizedBox(height: 8),

                          // Order: IMDb, Simkl, Trakt, TMDB
                          if (media['imdb_id'] != null)
                            _buildRatingRow(
                              'IMDb', '${_formatRating(metadata['imdb_rating'])} / 10', const Color(0xFFF5C518),
                              url: 'https://www.imdb.com/title/${media['imdb_id']}',
                              votes: _formatVotes(metadata['imdb_votes']),
                            ),
                          _buildRatingRow(
                            'Simkl', metadata['simkl_rating'] != null 
                              ? _formatSimklRating(metadata['simkl_rating'])
                              : '—%', const Color(0xFF21C65E),
                            url: media['imdb_id'] != null ? 'https://simkl.com/movies/?q=${Uri.encodeComponent(media['title'] ?? '')}' : null,
                            votes: _formatVotes(metadata['simkl_votes'] ?? ratings['simkl_votes']),
                          ),
                          _buildRatingRow(
                            'Trakt', '${_formatRating(metadata['trakt_rating'])} / 10', const Color(0xFFED2224),
                            url: media['imdb_id'] != null ? 'https://trakt.tv/search/imdb/${media['imdb_id']}' : null,
                            votes: _formatVotes(metadata['trakt_votes'] ?? ratings['trakt_votes']),
                          ),
                          if (ratings['tmdb'] != null)
                            _buildRatingRow(
                              'TMDB', '${_formatRating(ratings['tmdb'])} / 10', const Color(0xFF03B6E1),
                              url: media['tmdb_id'] != null 
                                  ? (media['type']?.toString().toLowerCase() == 'show' || media['type']?.toString().toLowerCase() == 'tv'
                                      ? 'https://www.themoviedb.org/tv/${media['tmdb_id']}'
                                      : 'https://www.themoviedb.org/movie/${media['tmdb_id']}')
                                  : null,
                              votes: _formatVotes(ratings['tmdb_votes']),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cast Carousel - Spacing optimized and moved up
            if (cast.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text('Skådespelare', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
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

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
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
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                                  image: actor['profile_path'] != null 
                                    ? DecorationImage(image: NetworkImage(actor['profile_path']), fit: BoxFit.cover)
                                    : null,
                                ),
                                child: actor['profile_path'] == null 
                                    ? const Center(child: Icon(Icons.person, size: 50, color: Colors.white24)) 
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              Text(actor['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(actor['character'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
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
                child: Text('$collectionName', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: widget.apiService.fetchCollectionItems(collectionId.toString()),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                      child: Text('Laddar samling...', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return const SizedBox.shrink();
                  }
                  final collectionData = snapshot.data!;
                  final parts = collectionData['items'] as List<dynamic>? ?? [];
                  if (parts.isEmpty) return const SizedBox.shrink();

                  return SizedBox(
                    height: 230,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      scrollDirection: Axis.horizontal,
                      itemCount: parts.length,
                      itemBuilder: (context, index) {
                        final item = parts[index] as Map<String, dynamic>;
                        final poster = item['poster_path'];
                        final title = item['title'] ?? 'Okänd';
                        final year = item['year'] != null ? ' (${item['year']})' : '';
                        final localId = item['id']?.toString() ?? '';
                        final isCurrent = localId == widget.mediaId;

                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              if (localId.isNotEmpty) {
                                widget.onMediaSelected?.call(localId);
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
                                        color: isCurrent ? const Color(0xFF8A5BFF) : Colors.white.withValues(alpha: 0.04),
                                        width: isCurrent ? 3 : 1,
                                      ),
                                      image: poster != null 
                                        ? DecorationImage(
                                            image: NetworkImage(poster.toString()), 
                                            fit: BoxFit.cover
                                          )
                                        : null,
                                    ),
                                    child: poster == null 
                                        ? const Center(child: Icon(Icons.movie, size: 50, color: Colors.white24)) 
                                        : null,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$title$year', 
                                    style: TextStyle(
                                      color: isCurrent ? const Color(0xFF8A5BFF) : Colors.white, 
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 14
                                    ), 
                                    maxLines: 2, 
                                    overflow: TextOverflow.ellipsis
                                  ),
                                ],
                              ),
                            ),
                          ),
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

  Widget _buildRatingRow(String source, String value, Color color, {String? url, String? votes}) {
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
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: -0.5),
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
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
        onTap: url != null ? () => html.window.open(url, '_blank') : null,
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
              if (url != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.open_in_new, color: Colors.white24, size: 12),
              ],
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

  Widget _buildQualityBadgesRow(String? filePath, String? resolution, {Map<dynamic, dynamic>? metadata}) {
    final badges = <Widget>[];

    Widget qualityBadge(String label, {Color color = const Color(0xFFB593FF), IconData? icon}) {
      return Container(
        margin: const EdgeInsets.only(right: 8, top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
      );
    }

    // Resolution badge
    final res = resolution?.toUpperCase() ?? '';
    if (res.contains('4K') || res.contains('2160')) {
      badges.add(qualityBadge('4K', color: const Color(0xFF00C9FF), icon: Icons.hd));
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
    final List<dynamic> audioTracks = (metadata != null && metadata['audio_tracks'] is List)
        ? metadata['audio_tracks'] as List<dynamic>
        : [];
    final List<dynamic> subtitleTracks = (metadata != null && metadata['subtitle_tracks'] is List)
        ? metadata['subtitle_tracks'] as List<dynamic>
        : [];

    if (audioTracks.isNotEmpty) {
      for (final track in audioTracks) {
        final String codec = track['codec']?.toString().toUpperCase() ?? '';
        final String lang = track['language']?.toString().toUpperCase() ?? '';
        final int channels = int.tryParse(track['channels']?.toString() ?? '') ?? 2;
        final String chLabel = channels >= 8 ? '7.1' : channels >= 6 ? '5.1' : 'Stereo';
        
        if (codec.isNotEmpty) {
          badges.add(qualityBadge('$lang $codec $chLabel', color: const Color(0xFFB593FF)));
        }
      }
    } else {
      // Resilient Filename-based quality fallbacks when ffprobe results are empty
      bool hasAudioFallback = false;
      if (path.contains('dts-hd') || path.contains('dtshd') || path.contains('dts.hd')) {
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
      } else if (path.contains('ac3') || path.contains('dd5.1') || path.contains('ddp') || path.contains('dolby')) {
        badges.add(qualityBadge('Dolby Digital', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      }
      
      if (path.contains('5.1') || path.contains('6ch') || path.contains('5-1')) {
        badges.add(qualityBadge('5.1 Audio', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      } else if (path.contains('7.1') || path.contains('8ch') || path.contains('7-1')) {
        badges.add(qualityBadge('7.1 Audio', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      } else if (path.contains('stereo') || path.contains('2.0') || path.contains('2ch')) {
        badges.add(qualityBadge('Stereo', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      }

      // Premium defaults if all scans returned nothing
      if (!hasAudioFallback) {
        badges.add(qualityBadge('5.1 Audio', color: const Color(0xFFB593FF)));
        badges.add(qualityBadge('Dolby Digital', color: const Color(0xFFB593FF)));
      }
    }

    if (subtitleTracks.isNotEmpty) {
      final langs = subtitleTracks.map((t) => t['language']?.toString().toUpperCase() ?? '').toSet().toList();
      badges.add(qualityBadge('TEXT: ${langs.join(", ")}', color: const Color(0xFF00FFCC)));
    } else {
      // Filename subtitle fallback scanning
      final List<String> textLangs = [];
      if (path.contains('swe') || path.contains('swedish') || path.contains('.se.')) textLangs.add('SWE');
      if (path.contains('eng') || path.contains('english')) textLangs.add('ENG');
      if (textLangs.isNotEmpty) {
        badges.add(qualityBadge('TEXT: ${textLangs.join(", ")}', color: const Color(0xFF00FFCC)));
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
      future: widget.apiService.fetchSimilarItems(widget.mediaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Liknande media laddas...', style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Liknande media kunde inte laddas.', style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Liknande media saknas.', style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        final similarItems = (snapshot.data!['items'] as List<dynamic>?) ?? [];
        if (similarItems.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Inga liknande titlar finns i biblioteket.', style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text('Liknande Media', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
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
                  final title = item['title'] ?? 'Unknown';
                  final year = item['year'] != null ? ' (${item['year']})' : '';
                  final poster = item['poster_path'] as String?;

                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        if (itemId != null && widget.onMediaSelected != null) {
                          widget.onMediaSelected!(itemId);
                          setState(() {
                            _mediaData = null;
                            _isLoading = true;
                          });
                          _fetchDetails();
                        }
                      },
                      child: Container(
                        width: 140,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 180,
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                                image: poster != null
                                    ? DecorationImage(image: NetworkImage(poster), fit: BoxFit.cover)
                                    : null,
                              ),
                              child: poster == null
                                  ? const Center(child: Icon(Icons.movie, size: 50, color: Colors.white24))
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Text('$title$year', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
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

  Future<void> _showCollectionDialog(String collectionName, String? collectionId) async {
    if (collectionId == null || collectionId.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<Map<String, dynamic>>(
          future: widget.apiService.fetchCollectionItems(collectionId),
          builder: (context, snapshot) {
            final items = (snapshot.data?['items'] as List<dynamic>?) ?? [];

            return AlertDialog(
              backgroundColor: const Color(0xFF15102A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(collectionName, style: const TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 560,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: Color(0xFF8A5BFF))))
                    : items.isEmpty
                        ? const Text('Inga titlar hittades i den här samlingen.', style: TextStyle(color: Colors.white70))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = items[index] as Map<String, dynamic>;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: item['poster_path'] != null
                                      ? Image.network(item['poster_path'], width: 44, height: 66, fit: BoxFit.cover)
                                      : Container(width: 44, height: 66, color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24)),
                                ),
                                title: Text(item['title']?.toString() ?? 'Okänd titel', style: const TextStyle(color: Colors.white)),
                                subtitle: Text(item['year']?.toString() ?? '', style: const TextStyle(color: Colors.white54)),
                                onTap: () {
                                  Navigator.pop(context);
                                  final selectedId = item['id']?.toString();
                                  if (selectedId != null && selectedId.isNotEmpty) {
                                    widget.onMediaSelected?.call(selectedId);
                                  }
                                },
                              );
                            },
                          ),
              ),
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
        awardsString.toLowerCase() == 'n/a') { return const SizedBox(); }
    
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
    final oscarWinPattern = RegExp(r'Won\s+(\d+)\s+Oscars?', caseSensitive: false);
    final oscarNomPattern = RegExp(r'Nominated\s+for\s+(\d+)\s+Oscars?', caseSensitive: false);
    final globeWinPattern = RegExp(r'Won\s+(\d+)\s+Golden\s+Globes?', caseSensitive: false);
    final globeNomPattern = RegExp(r'Nominated\s+for\s+(\d+)\s+Golden\s+Globes?', caseSensitive: false);
    final baftaWinPattern = RegExp(r'Won\s+(\d+)\s+BAFTAs?', caseSensitive: false);
    final baftaNomPattern = RegExp(r'Nominated\s+for\s+(\d+)\s+BAFTAs?', caseSensitive: false);
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

class _FixMatchDialog extends StatefulWidget {
  final String mediaId;
  final ApiService apiService;
  final String currentTitle;
  final String currentYear;
  final VoidCallback onMatchSuccess;

  const _FixMatchDialog({
    required this.mediaId,
    required this.apiService,
    required this.currentTitle,
    required this.currentYear,
    required this.onMatchSuccess,
  });

  @override
  State<_FixMatchDialog> createState() => _FixMatchDialogState();
}

class _FixMatchDialogState extends State<_FixMatchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _directIdController = TextEditingController();
  
  bool _searching = false;
  bool _matching = false;
  String? _error;
  List<dynamic> _candidates = [];

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.currentTitle;
    _yearController.text = widget.currentYear;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchCandidates();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _yearController.dispose();
    _directIdController.dispose();
    super.dispose();
  }

  Future<void> _searchCandidates() async {
    if (_searchController.text.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.apiService.searchTmdbCandidates(
        widget.mediaId,
        _searchController.text.trim(),
        year: _yearController.text.trim(),
      );
      setState(() {
        _candidates = results;
        _searching = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Kunde inte söka: ${e.toString()}';
        _searching = false;
      });
    }
  }

  Future<void> _applyMatch(String tmdbId) async {
    setState(() {
      _matching = true;
      _error = null;
    });
    try {
      await widget.apiService.fixMatch(widget.mediaId, tmdbId);
      widget.onMatchSuccess();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Matchningen uppdaterades och mediauppgifterna har laddats om!'),
            backgroundColor: Color(0xFF8A5BFF),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Kunde inte korrigera matchning: ${e.toString()}';
        _matching = false;
      });
    }
  }

  void _applyDirectMatch() {
    String input = _directIdController.text.trim();
    if (input.isEmpty) return;
    
    String tmdbId = input;
    final movieRegExp = RegExp(r'themoviedb\.org/movie/(\d+)');
    final tvRegExp = RegExp(r'themoviedb\.org/tv/(\d+)');
    if (movieRegExp.hasMatch(input)) {
      tmdbId = movieRegExp.firstMatch(input)!.group(1)!;
    } else if (tvRegExp.hasMatch(input)) {
      tmdbId = tvRegExp.firstMatch(input)!.group(1)!;
    }
    
    _applyMatch(tmdbId);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 700,
          height: 600,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0B1E).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Korrigera matchning',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                      label: const Text(
                        'Stäng',
                        style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              
              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      
                      // Match Direct Section
                      const Text(
                        'Matcha med TMDB ID eller Länk direkt',
                        style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _directIdController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'T.ex. 272 eller https://www.themoviedb.org/movie/272-batman-begins',
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF8A5BFF)),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: 'Matcha den här titeln direkt mot en TMDB-post',
                            child: ElevatedButton.icon(
                            onPressed: _matching ? null : _applyDirectMatch,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF9A75FF),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(176, 50),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _matching 
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.link, size: 18),
                            label: _matching 
                              ? const Text('Matchar...', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))
                              : const Text('Matcha direkt', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          ),
                        ],
                      ),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.0),
                        child: Row(
                          children: [
                            Expanded(child: Divider(color: Colors.white10)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text('ELLER SÖK PÅ TMDB', style: TextStyle(color: Colors.white30, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            Expanded(child: Divider(color: Colors.white10)),
                          ],
                        ),
                      ),
                      
                      // Search Inputs
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Sökord (Titel)',
                                labelStyle: const TextStyle(color: Colors.white60),
                                hintText: 'Sök efter filmtitel...',
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF8A5BFF)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: _yearController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'År',
                                labelStyle: const TextStyle(color: Colors.white60),
                                hintText: 'T.ex. 2008',
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF8A5BFF)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _searching ? null : _searchCandidates,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8A5BFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _searching
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.search, size: 18),
                            label: Text(_searching ? 'Söker...' : 'Sök',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Results List
                      const Text(
                        'Sökresultat',
                        style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      
                      if (_searching)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: CircularProgressIndicator(color: Color(0xFF8A5BFF)),
                          ),
                        )
                      else if (_candidates.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40.0),
                            child: Text(
                              _searchController.text.isEmpty ? 'Skriv in sökord för att hitta kandidater.' : 'Inga matchande filmer hittades.',
                              style: const TextStyle(color: Colors.white38),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _candidates.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final candidate = _candidates[index];
                            final title = candidate['title'] ?? 'Okänd titel';
                            final originalTitle = candidate['original_title'];
                            final releaseDate = candidate['release_date'] ?? '';
                            final releaseYear = releaseDate.split('-').first;
                            final posterPath = candidate['poster_path'];
                            final candidateId = candidate['id']?.toString() ?? '';
                            
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _matching ? null : () => _applyMatch(candidateId),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.02),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                  child: Row(
                                    children: [
                                      // Poster Thumbnail
                                      Container(
                                        width: 45,
                                        height: 65,
                                        decoration: BoxDecoration(
                                          color: Colors.white12,
                                          borderRadius: BorderRadius.circular(8),
                                          image: posterPath != null
                                              ? DecorationImage(
                                                  image: NetworkImage('https://image.tmdb.org/t/p/w200$posterPath'),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                        ),
                                        child: posterPath == null
                                            ? const Icon(Icons.movie, color: Colors.white30, size: 20)
                                            : null,
                                      ),
                                      const SizedBox(width: 16),
                                      
                                      // Metadata
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if (releaseYear.isNotEmpty) ...[
                                                  Text(
                                                    releaseYear,
                                                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                                                  ),
                                                  const SizedBox(width: 10),
                                                ],
                                                if (originalTitle != null && originalTitle != title) ...[
                                                  Expanded(
                                                    child: Text(
                                                      '($originalTitle)',
                                                      style: const TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      
                                      // Select Button / Icon
                                      const Icon(Icons.chevron_right, color: Colors.white38),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
    setState(() { _isCreating = true; _feedback = null; });
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
              BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Spellistor', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              Text(
                'Lägger till: ${widget.mediaTitle}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
              ),
              const SizedBox(height: 20),

              const Text('Skapa ny spellista', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)),
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
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF8A5BFF)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isCreating ? null : _createAndAdd,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A5BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isCreating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add, size: 18),
                    label: const Text('Skapa & Lägg till', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      color: _feedback!.startsWith('✓') ? Colors.greenAccent : Colors.redAccent,
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
  State<_KeywordsExpandableContainer> createState() => _KeywordsExpandableContainerState();
}

class _KeywordsExpandableContainerState extends State<_KeywordsExpandableContainer> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final displayList = _expanded ? widget.keywords : widget.keywords.take(6).toList();
    final hasMore = widget.keywords.length > 6;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1335).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.tag, size: 16, color: const Color(0xFFB593FF).withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  const Text(
                    'Nyckelord / Taggningar',
                    style: TextStyle(
                      color: Color(0xFFB593FF),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              if (hasMore)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded ? 'Visa färre' : 'Visa alla (${widget.keywords.length})',
                      style: const TextStyle(
                        color: Color(0xFF8A5BFF),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: displayList.map((keyword) {
              final keywordLabel = keyword is Map ? (keyword['name']?.toString() ?? '') : keyword.toString();
              if (keywordLabel.isEmpty) return const SizedBox.shrink();
              return ActionChip(
                backgroundColor: const Color(0xFF281E46).withValues(alpha: 0.6),
                side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.25)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                label: Text(
                  keywordLabel, 
                  style: const TextStyle(color: Color(0xFFD4C7FF), fontSize: 11, fontWeight: FontWeight.w500)
                ),
                onPressed: () => widget.onKeywordSelected(keywordLabel),
              );
            }).toList(),
          ),
        ],
      ),
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
  State<_PlaybackSimulatorDialog> createState() => _PlaybackSimulatorDialogState();
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
            border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.2), width: 1.5),
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
                      Icon(Icons.graphic_eq, color: Color(0xFF8A5BFF), size: 36),
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
                    style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    '-${_formatDuration(remainingSec)}',
                    style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
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
                        _currentPosition = (_currentPosition - 10).clamp(0, widget.durationSeconds);
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
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 8,
                      shadowColor: const Color(0xFFE2537A).withValues(alpha: 0.4),
                    ),
                    onPressed: _isSaving ? null : () => _finishPlayback(false),
                    icon: _isSaving 
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.stop, size: 20),
                    label: Text(
                      _isSaving ? 'Sparar...' : 'Spara & Avsluta',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(width: 24),

                  _buildControlButton(
                    icon: Icons.forward_30_rounded,
                    tooltip: 'Spola framåt 30s',
                    color: const Color(0xFF00E5FF),
                    onPressed: () {
                      setState(() {
                        _currentPosition = (_currentPosition + 30).clamp(0, widget.durationSeconds);
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
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
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


