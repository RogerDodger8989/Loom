const fs = require('fs');

let content = fs.readFileSync('lib/screens/episode_details_screen.dart', 'utf8');

// Normalize line endings to avoid matching issues
content = content.replace(/\r\n/g, '\n');

// 1. Add _loadPlaybackSettings() into initState()
if (!content.includes('_loadPlaybackSettings();')) {
  content = content.replace(
    'super.initState();',
    'super.initState();\n    _loadPlaybackSettings();'
  );
}

// 2. Add the missing functions right before `void dispose() {`
const funcs = `
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
    final subtitleTracks = (metadata['subtitle_tracks'] is List)
        ? (metadata['subtitle_tracks'] as List).cast<Map>()
        : <Map>[];
    final audioTracks = (metadata['audio_tracks'] is List)
        ? (metadata['audio_tracks'] as List).cast<Map>()
        : <Map>[];

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
      _selectedSubtitleTrack = resolvedSub;
      _selectedAudioTrack = resolvedAudio;
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
  }
`;

if (!content.includes('bool _langMatch(')) {
  content = content.replace('  @override\n  void dispose() {', funcs + '\n  @override\n  void dispose() {');
}

// 3. Make _playVideo use _applyLanguageDefaults logic
// In episode_details_screen.dart, _playVideo currently has:
/*
  void _playVideo(Map<String, dynamic> mediaData) {
    if (mediaData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunde inte ladda media-data för avsnittet.')),
      );
      return;
    }

    // Default subtitle logic
    final subtitleTracks = (mediaData['subtitle_tracks'] is List)
        ? (mediaData['subtitle_tracks'] as List).cast<Map>()
        : <Map>[];

    String resolvedSub = 'none';
    if (subtitleTracks.isNotEmpty) {
      resolvedSub = subtitleTracks.first['index']?.toString() ?? 'none';
    }

    Navigator.push(...
*/

if (content.includes("String resolvedSub = 'none';\n    if (subtitleTracks.isNotEmpty) {\n      resolvedSub = subtitleTracks.first['index']?.toString() ?? 'none';\n    }")) {
  content = content.replace(
    `    // Default subtitle logic
    final subtitleTracks = (mediaData['subtitle_tracks'] is List)
        ? (mediaData['subtitle_tracks'] as List).cast<Map>()
        : <Map>[];

    String resolvedSub = 'none';
    if (subtitleTracks.isNotEmpty) {
      resolvedSub = subtitleTracks.first['index']?.toString() ?? 'none';
    }`,
    `    _applyLanguageDefaults(mediaData);
    final resolvedSub = _selectedSubtitleTrack;
    final resolvedAudio = _selectedAudioTrack;`
  );
}

fs.writeFileSync('lib/screens/episode_details_screen.dart', content, 'utf8');
console.log('Fixed episode_details_screen.dart!');
