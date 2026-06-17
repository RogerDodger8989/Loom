import 'package:flutter/material.dart';
import '../services/api.dart';
import 'music_player_screen.dart';

class SoundtrackScreen extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> soundtrackData;
  final String movieTitle;
  final String movieId;

  const SoundtrackScreen({
    super.key,
    required this.apiService,
    required this.soundtrackData,
    required this.movieTitle,
    required this.movieId,
  });

  @override
  State<SoundtrackScreen> createState() => _SoundtrackScreenState();
}

class _SoundtrackScreenState extends State<SoundtrackScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPlayer());
  }

  void _openPlayer() {
    final raw = widget.soundtrackData['tracks'] as List? ?? [];
    final tracks = raw.map((t) {
      final m = Map<String, dynamic>.from(t as Map);
      m['stream_url'] = '/api/music/stream/${m['id']}';
      final secs = (m['duration_seconds'] as num?)?.toInt() ?? 0;
      final mm = secs ~/ 60;
      final ss = secs % 60;
      m['duration_formatted'] = '$mm:${ss.toString().padLeft(2, '0')}';
      return m;
    }).toList();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MusicPlayerScreen(
          apiService: widget.apiService,
          albumId: widget.soundtrackData['album_id']?.toString() ?? '',
          coverUrl: (widget.soundtrackData['cover_url'] ?? widget.soundtrackData['cover_path'])?.toString() ?? '',
          albumTitle: widget.soundtrackData['album']?.toString() ?? widget.movieTitle,
          albumArtist: widget.soundtrackData['artist']?.toString() ?? '',
          tracks: tracks,
          initialIndex: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0714),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF))),
    );
  }
}
