import 'dart:math' as math;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/api.dart';

class MusicPlayerScreen extends StatefulWidget {
  final ApiService apiService;
  final String albumId;
  final String coverUrl;
  final String albumTitle;
  final String albumArtist;
  final List<Map<String, dynamic>> tracks;
  final int initialIndex;

  const MusicPlayerScreen({
    super.key,
    required this.apiService,
    required this.albumId,
    required this.coverUrl,
    required this.albumTitle,
    required this.albumArtist,
    required this.tracks,
    this.initialIndex = 0,
  });

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with SingleTickerProviderStateMixin {

  late AudioPlayer _player;
  late AnimationController _vinylController;

  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  bool _seeking = false;
  double _seekValue = 0;

  List<Map<String, dynamic>> _queue = [];
  Map<String, dynamic>? _albumData;
  List<Map<String, dynamic>> _coverImages = [];
  bool _loadingCovers = false;

  // For tracking stream subscriptions
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _queue = List.from(widget.tracks);
    _currentIndex = widget.initialIndex.clamp(0, _queue.length - 1);

    _vinylController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    _initAudio();
    _loadAlbumData();
  }

  Future<void> _initAudio() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player = AudioPlayer();

    _player.positionStream.listen((pos) {
      if (!mounted || _seeking) return;
      setState(() => _position = pos);
    });

    _player.durationStream.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur ?? Duration.zero);
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing;
      setState(() => _isPlaying = playing);
      if (playing) {
        _vinylController.repeat();
      } else {
        _vinylController.stop();
      }
      if (state.processingState == ProcessingState.completed) {
        _playNext();
      }
    });

    if (_queue.isNotEmpty) {
      await _playIndex(_currentIndex, autoPlay: true);
    }
  }

  Future<void> _loadAlbumData() async {
    if (widget.albumId.isEmpty) return;
    try {
      final data = await widget.apiService.fetchMusicAlbum(widget.albumId);
      if (!mounted) return;
      setState(() => _albumData = data);
    } catch (_) {}
  }

  Future<void> _loadCovers() async {
    if (widget.albumId.isEmpty || _loadingCovers) return;
    setState(() => _loadingCovers = true);
    try {
      final covers = await widget.apiService.fetchMusicAlbumCovers(widget.albumId);
      if (!mounted) return;
      setState(() { _coverImages = covers.cast<Map<String, dynamic>>(); _loadingCovers = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingCovers = false);
    }
  }

  Future<void> _playIndex(int i, {bool autoPlay = true}) async {
    if (_queue.isEmpty) return;
    final index = i.clamp(0, _queue.length - 1);
    final track = _queue[index];
    final streamUrl = track['stream_url']?.toString() ?? '/api/music/stream/${track['id']}';
    final url = '${widget.apiService.baseUrl}$streamUrl';
    setState(() {
      _currentIndex = index;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    try {
      await _player.setUrl(url);
      if (autoPlay) await _player.play();
    } catch (e) {
      debugPrint('[Player] setUrl error: $e');
    }
  }

  void _playNext() {
    if (_loopMode == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    if (_currentIndex < _queue.length - 1) {
      _playIndex(_currentIndex + 1);
    } else if (_loopMode == LoopMode.all) {
      _playIndex(0);
    }
  }

  void _playPrev() {
    if (_position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }
    if (_currentIndex > 0) _playIndex(_currentIndex - 1);
  }

  void _toggleShuffle() {
    setState(() {
      _shuffle = !_shuffle;
      if (_shuffle) {
        final current = _queue[_currentIndex];
        final rest = List<Map<String, dynamic>>.from(_queue)..removeAt(_currentIndex);
        rest.shuffle();
        _queue = [current, ...rest];
        _currentIndex = 0;
      } else {
        _queue = List.from(widget.tracks);
        final currentId = _queue.isNotEmpty ? _queue[_currentIndex]['id'] : null;
        if (currentId != null) {
          final idx = widget.tracks.indexWhere((t) => t['id'] == currentId);
          _currentIndex = idx < 0 ? 0 : idx;
        }
      }
    });
  }

  void _toggleLoop() {
    setState(() {
      _loopMode = switch (_loopMode) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        _ => LoopMode.off,
      };
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> get _currentTrack =>
      _queue.isNotEmpty ? _queue[_currentIndex] : {};

  String get _currentTrackTitle => _currentTrack['title']?.toString() ?? '';

  @override
  void dispose() {
    _player.dispose();
    _vinylController.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0714),
        appBar: _buildAppBar(),
        body: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                _buildHero(),
                _buildTrackInfo(),
                _buildSeekBar(),
                _buildControls(),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          _buildTabBar(),
          SizedBox(
            height: 260,
            child: TabBarView(children: [
              _buildQueueTab(),
              _buildTagsTab(),
              _buildCoversTab(),
            ]),
          ),
        ]),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(children: [
        const Text('Nu Spelas', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
        Text(widget.albumTitle, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
      centerTitle: true,
    );
  }

  Widget _buildHero() {
    final coverUrl = widget.coverUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 16),
      child: SizedBox(
        height: 240,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Vinyl disc (peeks to the right)
            AnimatedBuilder(
              animation: _vinylController,
              builder: (_, child) => Positioned(
                right: 0,
                child: Transform.rotate(
                  angle: _vinylController.value * 2 * math.pi,
                  child: child,
                ),
              ),
              child: _buildVinylDisc(200),
            ),
            // Album cover
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 220, height: 220,
                child: coverUrl.isNotEmpty
                    ? Image.network(coverUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder())
                    : _placeholder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVinylDisc(double size) {
    return SizedBox(
      width: size, height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A1A1A),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 16)],
            ),
          ),
          // Grooves
          ...List.generate(6, (i) => Container(
            width: size * (0.85 - i * 0.08),
            height: size * (0.85 - i * 0.08),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.04), width: 0.5),
            ),
          )),
          // Label
          Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF8A5BFF),
            ),
            child: const Center(child: Icon(Icons.fiber_manual_record, color: Colors.white, size: 10)),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: const Color(0xFF1C1530),
    child: const Center(child: Icon(Icons.album, color: Color(0xFF8A5BFF), size: 64)),
  );

  Widget _buildTrackInfo() {
    final album = _albumData;
    final label = album?['label']?.toString() ?? '';
    final year = album?['year']?.toString() ?? (album?['release_date']?.toString() ?? '');
    final packaging = album?['packaging']?.toString() ?? '';
    final catalogNumber = album?['catalog_number']?.toString() ?? '';
    final rating = album?['rating'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              _currentTrackTitle,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rating != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _buildRatingStars((rating as num).toDouble()),
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          [widget.albumArtist, if (year.isNotEmpty) year].join(' • '),
          style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 14, fontWeight: FontWeight.w600),
        ),
        if (label.isNotEmpty || packaging.isNotEmpty || catalogNumber.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            [if (label.isNotEmpty) label, if (packaging.isNotEmpty) packaging, if (catalogNumber.isNotEmpty) catalogNumber].join(' • '),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _buildRatingStars(double rating) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) {
      final v = rating - i;
      if (v >= 1) return const Icon(Icons.star, color: Color(0xFF8A5BFF), size: 14);
      if (v >= 0.5) return const Icon(Icons.star_half, color: Color(0xFF8A5BFF), size: 14);
      return const Icon(Icons.star_border, color: Colors.white24, size: 14);
    }));
  }

  Widget _buildSeekBar() {
    final total = _duration.inSeconds.toDouble();
    final pos = _seeking ? _seekValue : _position.inSeconds.toDouble().clamp(0.0, total > 0 ? total : 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: const Color(0xFF8A5BFF),
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayColor: const Color(0xFF8A5BFF).withValues(alpha: 0.25),
          ),
          child: Slider(
            value: pos,
            min: 0,
            max: total > 0 ? total : 1,
            onChangeStart: (_) => setState(() => _seeking = true),
            onChanged: (v) => setState(() => _seekValue = v),
            onChangeEnd: (v) {
              setState(() => _seeking = false);
              _player.seek(Duration(seconds: v.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(Duration(seconds: pos.toInt())), style: const TextStyle(color: Colors.white38, fontSize: 11)),
              Text(_fmt(_duration), style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        // Main controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded),
              color: Colors.white70,
              iconSize: 36,
              onPressed: _playPrev,
            ),
            IconButton(
              icon: const Icon(Icons.replay_10_rounded),
              color: Colors.white54,
              iconSize: 30,
              onPressed: () => _player.seek(Duration(seconds: (_position.inSeconds - 10).clamp(0, _duration.inSeconds))),
            ),
            GestureDetector(
              onTap: () => _isPlaying ? _player.pause() : _player.play(),
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF8A5BFF),
                  boxShadow: [BoxShadow(color: Color(0x558A5BFF), blurRadius: 20, spreadRadius: 4)],
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.forward_10_rounded),
              color: Colors.white54,
              iconSize: 30,
              onPressed: () => _player.seek(Duration(seconds: (_position.inSeconds + 10).clamp(0, _duration.inSeconds))),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded),
              color: Colors.white70,
              iconSize: 36,
              onPressed: _playNext,
            ),
          ],
        ),
        // Shuffle / Loop
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(Icons.shuffle_rounded,
                color: _shuffle ? const Color(0xFF8A5BFF) : Colors.white38, size: 22),
              onPressed: _toggleShuffle,
            ),
            const SizedBox(width: 60),
            IconButton(
              icon: Icon(
                _loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                color: _loopMode != LoopMode.off ? const Color(0xFF8A5BFF) : Colors.white38,
                size: 22,
              ),
              onPressed: _toggleLoop,
            ),
          ],
        ),
      ]),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        color: const Color(0xFF0A0714),
      ),
      child: const TabBar(
        tabs: [
          Tab(icon: Icon(Icons.queue_music_rounded, size: 18), text: 'Kö'),
          Tab(icon: Icon(Icons.label_outline_rounded, size: 18), text: 'Taggar'),
          Tab(icon: Icon(Icons.photo_library_outlined, size: 18), text: 'Omslag'),
        ],
        labelColor: Color(0xFF8A5BFF),
        unselectedLabelColor: Colors.white38,
        indicatorColor: Color(0xFF8A5BFF),
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontSize: 11),
      ),
    );
  }

  // ── Queue tab ────────────────────────────────────────────────────────────

  Widget _buildQueueTab() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _queue.length,
      itemBuilder: (context, i) {
        final track = _queue[i];
        final isActive = i == _currentIndex;
        final trackNum = track['track_number']?.toString() ?? (i + 1).toString();
        final title = track['title']?.toString() ?? '';
        final dur = track['duration_formatted']?.toString() ?? '';

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          tileColor: isActive ? const Color(0xFF8A5BFF).withValues(alpha: 0.1) : Colors.transparent,
          leading: SizedBox(
            width: 28,
            child: isActive
                ? const Icon(Icons.equalizer, color: Color(0xFF8A5BFF), size: 18)
                : Text(trackNum, style: const TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
          ),
          title: Text(title,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isActive ? const Color(0xFF8A5BFF) : Colors.white,
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            )),
          trailing: Text(dur, style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
          onTap: () => _playIndex(i),
        );
      },
    );
  }

  // ── Tags tab ─────────────────────────────────────────────────────────────

  Widget _buildTagsTab() {
    final track = _currentTrack;
    final album = _albumData;

    Widget row(String key, dynamic value) {
      if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 140, child: Text(key, style: const TextStyle(color: Colors.white38, fontSize: 11))),
          Expanded(child: Text(value.toString(), style: const TextStyle(color: Colors.white70, fontSize: 11))),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (track.isNotEmpty) ...[
          const Text('Spår', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          row('Titel', track['title']),
          row('Artist', track['artist']),
          row('ISRC', track['isrc']),
          row('Recording MBID', track['recording_mbid']),
          row('Work MBID', track['work_mbid']),
          row('ISWC', track['iswc']),
          row('Work-typ', track['work_type']),
          if ((track['composers'] as List?)?.isNotEmpty == true)
            row('Kompositör', (track['composers'] as List).map((c) => c is Map ? c['name'] : c.toString()).join(', ')),
          if ((track['lyricists'] as List?)?.isNotEmpty == true)
            row('Textförfattare', (track['lyricists'] as List).map((c) => c is Map ? c['name'] : c.toString()).join(', ')),
          if ((track['arrangers'] as List?)?.isNotEmpty == true)
            row('Arrangör', (track['arrangers'] as List).map((c) => c is Map ? c['name'] : c.toString()).join(', ')),
          row('Codec', track['codec']),
          row('Bit-djup', track['bit_depth'] != null ? '${track['bit_depth']} bit' : null),
          row('Samplingsfrekvens', track['sample_rate'] != null ? '${(track['sample_rate'] as num) / 1000} kHz' : null),
          const SizedBox(height: 12),
        ],
        if (album != null) ...[
          const Text('Album', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          row('Label', album['label']),
          row('Katalognummer', album['catalog_number']),
          row('Utgivningsdatum', album['release_date']),
          row('Land', album['release_country']),
          row('Status', album['release_status']),
          row('Förpackning', album['packaging']),
          row('Typ', album['release_type']),
          row('Streckkod', album['barcode']),
          row('Skript', album['script']),
          row('MusicBrainz ID', album['musicbrainz_album_id']),
        ],
      ]),
    );
  }

  // ── Covers tab ───────────────────────────────────────────────────────────

  Widget _buildCoversTab() {
    if (_coverImages.isEmpty && !_loadingCovers) {
      return Center(
        child: TextButton.icon(
          onPressed: _loadCovers,
          icon: const Icon(Icons.photo_library_outlined, color: Color(0xFF8A5BFF)),
          label: const Text('Ladda omslag från Cover Art Archive', style: TextStyle(color: Color(0xFF8A5BFF))),
        ),
      );
    }

    if (_loadingCovers) return const Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF)));

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _coverImages.length,
      itemBuilder: (context, i) {
        final img = _coverImages[i];
        final type = img['type']?.toString() ?? 'other';
        final url = img['url']?.toString() ?? '';

        return GestureDetector(
          onTap: () => _showFullscreenCover(url, type),
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            width: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF1C1530),
            ),
            child: Column(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  child: url.isNotEmpty
                      ? Image.network(url, fit: BoxFit.cover, width: 160,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white24, size: 36))
                      : const Icon(Icons.image_not_supported, color: Colors.white24, size: 36),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  _coverTypeLabel(type),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  String _coverTypeLabel(String type) => switch (type) {
    'front'   => 'Framsida',
    'back'    => 'Baksida',
    'booklet' => 'Häfte',
    'medium'  => 'Skivkonst',
    'obi'     => 'Obi-band',
    'spine'   => 'Rygg',
    'tray'    => 'Fodral',
    'liner'   => 'Infoblad',
    _         => type,
  };

  void _showFullscreenCover(String url, String type) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(children: [
          InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
          Positioned(
            top: 8, right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            bottom: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: Text(_coverTypeLabel(type), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ),
        ]),
      ),
    );
  }
}
