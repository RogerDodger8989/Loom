import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import '../services/api.dart';

// ─── Data models ─────────────────────────────────────────────────────────────

class MusicAlbum {
  final String id;
  final String title;
  final String albumArtist;
  final int? year;
  final String? genre;
  final String? coverUrl;
  final String? discartPath;
  final int trackCount;
  final int discCount;
  final bool isHiRes;
  final String? linkedMediaId;
  final String? linkedMediaTitle;
  final String? linkedMediaPosterUrl;
  final String totalDuration;
  final int? maxBitDepth;
  final int? maxSampleRate;

  const MusicAlbum({
    required this.id,
    required this.title,
    required this.albumArtist,
    this.year,
    this.genre,
    this.coverUrl,
    this.discartPath,
    this.trackCount = 0,
    this.discCount = 1,
    this.isHiRes = false,
    this.linkedMediaId,
    this.linkedMediaTitle,
    this.linkedMediaPosterUrl,
    this.totalDuration = '0:00',
    this.maxBitDepth,
    this.maxSampleRate,
  });

  factory MusicAlbum.fromJson(Map<String, dynamic> j) {
    final linked = j['linked_media'] as Map<String, dynamic>?;
    return MusicAlbum(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? 'Unknown Album',
      albumArtist: j['album_artist']?.toString() ?? 'Unknown Artist',
      year: j['year'] is int ? j['year'] as int : int.tryParse(j['year']?.toString() ?? ''),
      genre: j['genre']?.toString(),
      coverUrl: j['cover_url']?.toString(),
      discartPath: j['discart_path']?.toString(),
      trackCount: (j['track_count'] as num?)?.toInt() ?? 0,
      discCount: (j['disc_count'] as num?)?.toInt() ?? 1,
      isHiRes: j['is_hires'] == true,
      linkedMediaId: linked?['id']?.toString(),
      linkedMediaTitle: linked?['title']?.toString(),
      linkedMediaPosterUrl: linked?['poster_url']?.toString(),
      totalDuration: j['total_duration_formatted']?.toString() ?? '0:00',
      maxBitDepth: j['max_bit_depth'] is num ? (j['max_bit_depth'] as num).toInt() : null,
      maxSampleRate: j['max_sample_rate'] is num ? (j['max_sample_rate'] as num).toInt() : null,
    );
  }

  String get hiResLabel {
    if (!isHiRes) return '';
    if (maxBitDepth != null && maxSampleRate != null) {
      return '${maxBitDepth}bit / ${(maxSampleRate! / 1000).toStringAsFixed(0)}kHz';
    }
    return 'Hi-Res';
  }
}

class MusicArtist {
  final String id;
  final String name;
  final String? imagePath;
  final int albumCount;
  final int trackCount;
  const MusicArtist({required this.id, required this.name, this.imagePath, this.albumCount = 0, this.trackCount = 0});
  factory MusicArtist.fromJson(Map<String, dynamic> j) => MusicArtist(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? 'Unknown',
    imagePath: j['image_path']?.toString(),
    albumCount: (j['album_count'] as num?)?.toInt() ?? 0,
    trackCount: (j['track_count'] as num?)?.toInt() ?? 0,
  );
}

// ─── Layout & Column config ────────────────────────────────────────────────

enum MusicNavMode { artists, albumArtists, genres, album, years }
enum MusicLayoutMode { grid, cards, list }

const _kDefaultColumns = ['album', 'tracks', 'artist', 'year', 'genre'];
const _kColumnLabels = {
  'album': 'Album', 'tracks': 'Spår', 'artist': 'Artist', 'year': 'År',
  'genre': 'Genre', 'duration': 'Längd', 'codec': 'Codec',
};

// ─── Main Screen ────────────────────────────────────────────────────────────

class MusicLibraryScreen extends StatefulWidget {
  final ApiService apiService;
  const MusicLibraryScreen({super.key, required this.apiService});

  @override
  State<MusicLibraryScreen> createState() => _MusicLibraryScreenState();
}

class _MusicLibraryScreenState extends State<MusicLibraryScreen> with SingleTickerProviderStateMixin {
  MusicNavMode _navMode = MusicNavMode.album;
  MusicLayoutMode _layoutMode = MusicLayoutMode.grid;

  List<MusicAlbum> _albums = [];
  List<MusicArtist> _artists = [];
  List<Map<String, dynamic>> _genres = [];
  List<Map<String, dynamic>> _years = [];

  bool _isLoading = false;
  String? _error;
  bool _isScanning = false;

  // List view column config
  List<String> _columns = List.from(_kDefaultColumns);

  // Audio player state
  AudioPlayer? _player;
  String? _playingTrackId;
  bool _isPlaying = false;
  late AnimationController _vinylController;

  // Selected album for detail overlay
  MusicAlbum? _selectedAlbum;
  List<Map<String, dynamic>> _albumTracks = [];
  bool _isLoadingAlbum = false;

  @override
  void initState() {
    super.initState();
    _vinylController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _vinylController.stop();
    _loadColumnConfig();
    _loadData();
    _initAudio();
  }

  @override
  void dispose() {
    _player?.dispose();
    _vinylController.dispose();
    super.dispose();
  }

  Future<void> _initAudio() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _player = AudioPlayer();
    _player!.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.playing) {
          _vinylController.repeat();
        } else {
          _vinylController.stop();
        }
      });
    });
  }

  Future<void> _loadColumnConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('music_list_columns');
    if (saved != null && saved.isNotEmpty) {
      setState(() => _columns = saved);
    }
  }

  Future<void> _saveColumnConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('music_list_columns', _columns);
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final navParam = _navMode.name == 'albumArtists' ? 'albumartists' : _navMode.name;
      final data = await widget.apiService.fetchMusicAlbums(nav: navParam);

      setState(() {
        _isLoading = false;
        if (_navMode == MusicNavMode.album) {
          _albums = ((data['albums'] as List?) ?? []).map((j) => MusicAlbum.fromJson(j as Map<String, dynamic>)).toList();
        } else if (_navMode == MusicNavMode.artists) {
          _artists = ((data['artists'] as List?) ?? []).map((j) => MusicArtist.fromJson(j as Map<String, dynamic>)).toList();
        } else if (_navMode == MusicNavMode.albumArtists) {
          _artists = ((data['albumArtists'] as List?) ?? []).map((j) => MusicArtist(
            id: j['album_artist']?.toString() ?? '',
            name: j['album_artist']?.toString() ?? '',
            albumCount: (j['album_count'] as num?)?.toInt() ?? 0,
          )).toList();
        } else if (_navMode == MusicNavMode.genres) {
          _genres = ((data['genres'] as List?) ?? []).cast<Map<String, dynamic>>();
        } else if (_navMode == MusicNavMode.years) {
          _years = ((data['years'] as List?) ?? []).cast<Map<String, dynamic>>();
        }
      });
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  Future<void> _openAlbum(MusicAlbum album) async {
    setState(() { _selectedAlbum = album; _isLoadingAlbum = true; _albumTracks = []; });
    try {
      final data = await widget.apiService.fetchMusicAlbum(album.id);
      setState(() {
        _albumTracks = ((data['tracks'] as List?) ?? []).cast<Map<String, dynamic>>();
        _isLoadingAlbum = false;
      });
    } catch (e) {
      setState(() { _isLoadingAlbum = false; });
    }
  }

  Future<void> _playTrack(String trackId, String streamUrl) async {
    if (_player == null) return;
    try {
      if (_playingTrackId == trackId && _isPlaying) {
        await _player!.pause();
        return;
      }
      setState(() => _playingTrackId = trackId);
      final url = '${widget.apiService.baseUrl}$streamUrl';
      await _player!.setUrl(url);
      await _player!.play();
    } catch (e) {
      debugPrint('[Music] Play error: $e');
    }
  }

  Future<void> _triggerScan() async {
    setState(() => _isScanning = true);
    try {
      await widget.apiService.triggerMusicScan();
      await Future.delayed(const Duration(seconds: 2));
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Skanning misslyckades: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      body: _selectedAlbum != null ? _buildAlbumDetail() : _buildLibrary(),
    );
  }

  Widget _buildLibrary() {
    return Column(
      children: [
        _buildHeader(),
        _buildSubNav(),
        Expanded(child: _buildContent()),
      ],
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 20, 12),
      child: Row(
        children: [
          const Text('Musik', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const Spacer(),
          // Layout switcher
          _layoutButton(Icons.grid_view_rounded, MusicLayoutMode.grid, 'Rutnät'),
          const SizedBox(width: 4),
          _layoutButton(Icons.view_agenda_outlined, MusicLayoutMode.cards, 'Kort'),
          const SizedBox(width: 4),
          _layoutButton(Icons.format_list_bulleted, MusicLayoutMode.list, 'Lista'),
          const SizedBox(width: 12),
          if (_layoutMode == MusicLayoutMode.list)
            IconButton(
              tooltip: 'Konfigurera kolumner',
              onPressed: _showColumnConfig,
              icon: const Icon(Icons.tune, color: Colors.white54, size: 20),
            ),
          const SizedBox(width: 4),
          _isScanning
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8A5BFF)))
              : IconButton(
                  tooltip: 'Skanna musikbiblioteket',
                  onPressed: _triggerScan,
                  icon: const Icon(Icons.sync, color: Colors.white54, size: 20),
                ),
        ],
      ),
    );
  }

  Widget _layoutButton(IconData icon, MusicLayoutMode mode, String tooltip) {
    final active = _layoutMode == mode;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => setState(() => _layoutMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF8A5BFF).withValues(alpha: 0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? const Color(0xFF8A5BFF) : Colors.transparent),
          ),
          child: Icon(icon, color: active ? const Color(0xFF8A5BFF) : Colors.white38, size: 18),
        ),
      ),
    );
  }

  // ─── Sub-Nav ─────────────────────────────────────────────────────────────

  Widget _buildSubNav() {
    final items = [
      (MusicNavMode.album, 'Album'),
      (MusicNavMode.artists, 'Artister'),
      (MusicNavMode.albumArtists, 'Albumartister'),
      (MusicNavMode.genres, 'Genrer'),
      (MusicNavMode.years, 'År'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final (mode, label) = items[i];
          final active = _navMode == mode;
          return GestureDetector(
            onTap: () {
              if (_navMode == mode) return;
              setState(() { _navMode = mode; _albums = []; _artists = []; _genres = []; _years = []; });
              _loadData();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? const Color(0xFF8A5BFF).withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? const Color(0xFF8A5BFF) : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Text(label,
                style: TextStyle(
                  color: active ? const Color(0xFF8A5BFF) : Colors.white54,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                )),
            ),
          );
        },
      ),
    );
  }

  // ─── Content dispatch ────────────────────────────────────────────────────

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF)));
    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
          const SizedBox(height: 12),
          Text('Fel: $_error', style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadData, child: const Text('Försök igen')),
        ],
      ));
    }

    if (_navMode == MusicNavMode.genres) return _buildGenreGrid();
    if (_navMode == MusicNavMode.years) return _buildYearList();
    if (_navMode == MusicNavMode.artists || _navMode == MusicNavMode.albumArtists) return _buildArtistList();

    if (_albums.isEmpty) return _buildEmptyState();

    return switch (_layoutMode) {
      MusicLayoutMode.grid  => _buildAlbumGrid(),
      MusicLayoutMode.cards => _buildAlbumCards(),
      MusicLayoutMode.list  => _buildAlbumList(),
    };
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.music_off, color: Colors.white12, size: 64),
        const SizedBox(height: 16),
        const Text('Inga album hittades', style: TextStyle(color: Colors.white38, fontSize: 18)),
        const SizedBox(height: 8),
        const Text('Lägg till en musikmapp i Inställningar → Bibliotek → Musik och skanna sedan.',
            style: TextStyle(color: Colors.white24, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8A5BFF), foregroundColor: Colors.white),
          onPressed: _isScanning ? null : _triggerScan,
          icon: const Icon(Icons.sync),
          label: const Text('Skanna nu'),
        ),
      ]),
    );
  }

  // ─── Grid layout ─────────────────────────────────────────────────────────

  Widget _buildAlbumGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: _albums.length,
      itemBuilder: (context, i) => _buildAlbumGridCard(_albums[i]),
    );
  }

  Widget _buildAlbumGridCard(MusicAlbum album) {
    return GestureDetector(
      onTap: () => _openAlbum(album),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: album.coverUrl != null
                        ? Image.network(album.coverUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _albumPlaceholder())
                        : _albumPlaceholder(),
                  ),
                  if (album.isHiRes)
                    Positioned(top: 6, right: 6, child: _hiResBadge(album)),
                  if (album.linkedMediaId != null)
                    Positioned(bottom: 6, left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.movie_outlined, size: 10, color: Color(0xFF8A5BFF)),
                          SizedBox(width: 3),
                          Text('Soundtrack', style: TextStyle(color: Color(0xFF8A5BFF), fontSize: 9)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(album.title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(album.albumArtist,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ─── Cards layout ────────────────────────────────────────────────────────

  Widget _buildAlbumCards() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _albums.length,
      itemBuilder: (context, i) => _buildAlbumCard(_albums[i]),
    );
  }

  Widget _buildAlbumCard(MusicAlbum album) {
    return GestureDetector(
      onTap: () => _openAlbum(album),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              // Cover
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72, height: 72,
                  child: album.coverUrl != null
                      ? Image.network(album.coverUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _albumPlaceholder(size: 72))
                      : _albumPlaceholder(size: 72),
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(album.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      if (album.isHiRes) _hiResBadge(album),
                    ]),
                    const SizedBox(height: 3),
                    Text(album.albumArtist,
                      style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, children: [
                      if (album.year != null)
                        _infoBadge(album.year.toString()),
                      if (album.genre != null && album.genre!.isNotEmpty)
                        _infoBadge(album.genre!),
                      _infoBadge('${album.trackCount} spår'),
                      _infoBadge(album.totalDuration),
                    ]),
                  ],
                ),
              ),
              // Linked movie
              if (album.linkedMediaPosterUrl != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Tooltip(
                    message: 'Soundtrack: ${album.linkedMediaTitle ?? ""}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(album.linkedMediaPosterUrl!, width: 36, height: 54, fit: BoxFit.cover),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── List layout ─────────────────────────────────────────────────────────

  Widget _buildAlbumList() {
    return Column(
      children: [
        _buildListHeader(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            itemCount: _albums.length,
            itemBuilder: (context, i) => _buildListRow(_albums[i], i),
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: _columns.map((col) => _listCell(
          _kColumnLabels[col] ?? col,
          flex: col == 'album' || col == 'artist' ? 3 : 1,
          isHeader: true,
        )).toList(),
      ),
    );
  }

  Widget _buildListRow(MusicAlbum album, int index) {
    final cells = _columns.map((col) {
      String value = '';
      switch (col) {
        case 'album':  value = album.title; break;
        case 'artist': value = album.albumArtist; break;
        case 'tracks': value = album.trackCount.toString(); break;
        case 'year':   value = album.year?.toString() ?? '—'; break;
        case 'genre':  value = album.genre ?? '—'; break;
        case 'duration': value = album.totalDuration; break;
        case 'codec':  value = album.isHiRes ? 'Hi-Res' : 'CD'; break;
      }
      return _listCell(value, flex: col == 'album' || col == 'artist' ? 3 : 1);
    }).toList();

    return GestureDetector(
      onTap: () => _openAlbum(album),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: index.isOdd ? Colors.white.withValues(alpha: 0.015) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            // Mini cover
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 32, height: 32,
                child: album.coverUrl != null
                    ? Image.network(album.coverUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _albumPlaceholder(size: 32))
                    : _albumPlaceholder(size: 32),
              ),
            ),
            const SizedBox(width: 10),
            ...cells,
            if (album.isHiRes) _hiResBadge(album, small: true),
          ]),
        ),
      ),
    );
  }

  Widget _listCell(String text, {int flex = 1, bool isHeader = false}) {
    return Expanded(
      flex: flex,
      child: Text(text,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isHeader ? Colors.white38 : Colors.white70,
          fontSize: isHeader ? 11 : 13,
          fontWeight: isHeader ? FontWeight.w600 : FontWeight.w400,
          letterSpacing: isHeader ? 0.8 : 0,
        )),
    );
  }

  // ─── Artists / AlbumArtists ────────────────────────────────────────────

  Widget _buildArtistList() {
    if (_artists.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _artists.length,
      itemBuilder: (context, i) {
        final ar = _artists[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF281E46),
                backgroundImage: ar.imagePath != null ? NetworkImage(ar.imagePath!) : null,
                child: ar.imagePath == null ? const Icon(Icons.person, color: Color(0xFF8A5BFF)) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ar.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${ar.albumCount} album • ${ar.trackCount} spår',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Colors.white24),
            ],
          ),
        );
      },
    );
  }

  // ─── Genres ────────────────────────────────────────────────────────────

  Widget _buildGenreGrid() {
    if (_genres.isEmpty) return _buildEmptyState();
    final colors = [const Color(0xFF8A5BFF), const Color(0xFFE2537A), const Color(0xFF00BCD4), const Color(0xFF4CAF50), const Color(0xFFFF9800)];
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 2,
      ),
      itemCount: _genres.length,
      itemBuilder: (context, i) {
        final g = _genres[i];
        final color = colors[i % colors.length];
        return GestureDetector(
          onTap: () {
            setState(() { _navMode = MusicNavMode.album; });
            _loadData();
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.6), color.withValues(alpha: 0.2)]),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(g['genre']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              Text('${g['album_count']} album', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ]),
          ),
        );
      },
    );
  }

  // ─── Years ──────────────────────────────────────────────────────────────

  Widget _buildYearList() {
    if (_years.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _years.length,
      itemBuilder: (context, i) {
        final y = _years[i];
        return ListTile(
          leading: Text(y['year'].toString(), style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 22, fontWeight: FontWeight.bold)),
          title: Text('${y['album_count']} album', style: const TextStyle(color: Colors.white70)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white24),
          onTap: () {},
        );
      },
    );
  }

  // ─── Album detail overlay ────────────────────────────────────────────────

  Widget _buildAlbumDetail() {
    final album = _selectedAlbum!;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() { _selectedAlbum = null; _albumTracks = []; }),
        ),
        title: Text(album.title, style: const TextStyle(color: Colors.white)),
        actions: [
          if (album.linkedMediaTitle != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                avatar: const Icon(Icons.movie, size: 14, color: Color(0xFF8A5BFF)),
                label: Text(album.linkedMediaTitle!, style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 11)),
                backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3)),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero section
            _buildAlbumHero(album),
            const SizedBox(height: 24),
            // Track list
            if (_isLoadingAlbum)
              const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: Color(0xFF8A5BFF)),
              )
            else
              _buildTrackList(album),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumHero(MusicAlbum album) {
    return Stack(
      children: [
        // Background blur from cover
        if (album.coverUrl != null)
          Positioned.fill(
            child: Opacity(opacity: 0.15, child: Image.network(album.coverUrl!, fit: BoxFit.cover)),
          ),
        Container(
          height: 300,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xFF0A0714)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Vinyl + Cover
              SizedBox(
                width: 200, height: 200,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Vinyl disc
                    AnimatedBuilder(
                      animation: _vinylController,
                      builder: (_, child) => Transform.rotate(
                        angle: _vinylController.value * 2 * math.pi,
                        child: child,
                      ),
                      child: Positioned(
                        left: 80,
                        child: _buildVinylDisc(size: 160),
                      ),
                    ),
                    // Album cover on top
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 160, height: 160,
                        child: album.coverUrl != null
                            ? Image.network(album.coverUrl!, fit: BoxFit.cover)
                            : _albumPlaceholder(size: 160),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (album.isHiRes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _hiResBadge(album),
                      ),
                    Text(album.title,
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, height: 1.1)),
                    const SizedBox(height: 6),
                    Text(album.albumArtist,
                      style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 10, runSpacing: 6, children: [
                      if (album.year != null) _infoBadge(album.year.toString()),
                      if (album.genre != null && album.genre!.isNotEmpty) _infoBadge(album.genre!),
                      _infoBadge('${album.trackCount} spår'),
                      if (album.discCount > 1) _infoBadge('${album.discCount} skivor'),
                      _infoBadge(album.totalDuration),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrackList(MusicAlbum album) {
    if (_albumTracks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Text('Inga spår hittades.', style: TextStyle(color: Colors.white38)),
      );
    }

    int? currentDisc;
    final widgets = <Widget>[];

    for (int i = 0; i < _albumTracks.length; i++) {
      final track = _albumTracks[i];
      final disc = (track['disc_number'] as num?)?.toInt() ?? 1;
      final trackId = track['id']?.toString() ?? '';
      final isPlayingThis = _playingTrackId == trackId && _isPlaying;

      if (album.discCount > 1 && disc != currentDisc) {
        currentDisc = disc;
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 6),
          child: Text('Skiva $disc',
            style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ));
      }

      widgets.add(_buildTrackRow(track, i, isPlayingThis));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 0, 28, 10),
          child: Text('Spårlista', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        ...widgets,
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildTrackRow(Map<String, dynamic> track, int index, bool isPlayingThis) {
    final trackId = track['id']?.toString() ?? '';
    final title = track['title']?.toString() ?? 'Unknown';
    final artist = track['artist']?.toString() ?? '';
    final duration = track['duration_formatted']?.toString() ?? '';
    final codec = track['codec']?.toString() ?? '';
    final bitDepth = track['bit_depth'] as num?;
    final sampleRate = track['sample_rate'] as num?;
    final trackNum = track['track_number'] as num?;
    final streamUrl = track['stream_url']?.toString() ?? '';
    final isHiRes = track['is_hires'] == true;

    return GestureDetector(
      onTap: () => _playTrack(trackId, streamUrl),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isPlayingThis
                ? const Color(0xFF8A5BFF).withValues(alpha: 0.12)
                : index.isOdd ? Colors.white.withValues(alpha: 0.015) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isPlayingThis ? Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3)) : null,
          ),
          child: Row(
            children: [
              // Track number or play icon
              SizedBox(
                width: 32,
                child: isPlayingThis
                    ? const Icon(Icons.equalizer, color: Color(0xFF8A5BFF), size: 16)
                    : Text(
                        trackNum?.toString() ?? (index + 1).toString(),
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 10),
              // Title + artist
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isPlayingThis ? const Color(0xFF8A5BFF) : Colors.white,
                      fontWeight: FontWeight.w500, fontSize: 13,
                    )),
                  if (artist.isNotEmpty)
                    Text(artist,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              ),
              // Codec / Hi-Res badge
              if (isHiRes)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _hiResBadge(null, small: true, bitDepth: bitDepth?.toInt(), sampleRate: sampleRate?.toInt()),
                )
              else if (codec.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _infoBadge(codec.toUpperCase()),
                ),
              // Duration
              Text(duration, style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Column config dialog ────────────────────────────────────────────────

  void _showColumnConfig() {
    final allColumns = _kColumnLabels.keys.toList();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            backgroundColor: const Color(0xFF15102A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      children: [
                        const Text('Kolumner', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text('Dra för att ändra ordning. Markera/avmarkera för att visa/dölja.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                  SizedBox(
                    height: 320,
                    child: ReorderableListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onReorderItem: (oldIndex, newIndex) {
                        setDialogState(() {
                          final item = _columns.removeAt(oldIndex);
                          _columns.insert(newIndex, item);
                        });
                        setState(() {});
                        _saveColumnConfig();
                      },
                      children: _columns.map((col) => ListTile(
                        key: ValueKey(col),
                        leading: const Icon(Icons.drag_handle, color: Colors.white24),
                        title: Text(_kColumnLabels[col] ?? col, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                          onPressed: _columns.length <= 1 ? null : () {
                            setDialogState(() => _columns.remove(col));
                            setState(() {});
                            _saveColumnConfig();
                          },
                        ),
                      )).toList(),
                    ),
                  ),
                  // Add columns
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    child: Wrap(
                      spacing: 6,
                      children: allColumns.where((c) => !_columns.contains(c)).map((col) => ActionChip(
                        label: Text('+ ${_kColumnLabels[col] ?? col}', style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 11)),
                        backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.08),
                        side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3)),
                        onPressed: () {
                          setDialogState(() => _columns.add(col));
                          setState(() {});
                          _saveColumnConfig();
                        },
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Shared widgets ──────────────────────────────────────────────────────

  Widget _albumPlaceholder({double size = double.infinity}) {
    return Container(
      width: size == double.infinity ? null : size,
      height: size == double.infinity ? null : size,
      color: const Color(0xFF1C1530),
      child: const Icon(Icons.album, color: Color(0xFF3A2E5A), size: 36),
    );
  }

  Widget _buildVinylDisc({double size = 160}) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF2A2A2A), Colors.black87],
          stops: [0.15, 0.5, 1.0],
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 20, offset: const Offset(4, 4))],
      ),
      child: Center(
        child: Container(
          width: size * 0.15, height: size * 0.15,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF8A5BFF)),
        ),
      ),
    );
  }

  Widget _hiResBadge(MusicAlbum? album, {bool small = false, int? bitDepth, int? sampleRate}) {
    final bd = bitDepth ?? album?.maxBitDepth;
    final sr = sampleRate ?? album?.maxSampleRate;
    final label = (bd != null && bd > 16) ? '${bd}bit' : 'Hi-Res';
    final subLabel = sr != null ? '${(sr / 1000).toStringAsFixed(0)}kHz' : null;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6B21A8), Color(0xFF1D4ED8)]),
        borderRadius: BorderRadius.circular(small ? 4 : 6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
            style: TextStyle(color: Colors.white, fontSize: small ? 9 : 11, fontWeight: FontWeight.w800)),
          if (subLabel != null) ...[
            const SizedBox(width: 3),
            Text(subLabel, style: TextStyle(color: Colors.white70, fontSize: small ? 8 : 10)),
          ],
        ],
      ),
    );
  }

  Widget _infoBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11)),
    );
  }
}
