const fs = require('fs');
let content = fs.readFileSync('lib/screens/episode_details_screen.dart', 'utf8');

// Add _parseTrackList if it doesn't exist
if (!content.includes('List<Map<String, dynamic>> _parseTrackList(dynamic raw)')) {
  content = content.replace(
    '// ── Subtitle / audio tracks from episode file or show fallback ───────────',
    `// ── Subtitle / audio tracks from episode file or show fallback ───────────

  List<Map<String, dynamic>> _parseTrackList(dynamic raw) {
    if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }
    return [];
  }`
  );
}

// Update _subtitleTracks
content = content.replace(
  /List<Map<String, dynamic>> get _subtitleTracks \{\s*final raw = widget\.episode\['subtitle_tracks'\] \?\? _showMeta\['subtitle_tracks'\];\s*if \(raw is List\) return raw\.cast<Map<String, dynamic>>\(\);\s*return \[\];\s*\}/,
  `List<Map<String, dynamic>> get _subtitleTracks {
    final raw = widget.episode['subtitle_tracks'] ?? _showMeta['subtitle_tracks'];
    return _parseTrackList(raw);
  }`
);

// Update _audioTracks
content = content.replace(
  /List<Map<String, dynamic>> get _audioTracks \{\s*final raw = widget\.episode\['audio_tracks'\] \?\? _showMeta\['audio_tracks'\];\s*if \(raw is List\) return raw\.cast<Map<String, dynamic>>\(\);\s*return \[\];\s*\}/,
  `List<Map<String, dynamic>> get _audioTracks {
    final raw = widget.episode['audio_tracks'] ?? _showMeta['audio_tracks'];
    return _parseTrackList(raw);
  }`
);

// Update _applyLanguageDefaults
content = content.replace(
  /final subtitleTracks = \(metadata\['subtitle_tracks'\] is List\)\s*\?\s*\(metadata\['subtitle_tracks'\] as List\)\.cast<Map>\(\)\s*:\s*<Map>\[\];/,
  `final subtitleTracks = _parseTrackList(metadata['subtitle_tracks'] ?? _showMeta['subtitle_tracks']);`
);

content = content.replace(
  /final audioTracks = \(metadata\['audio_tracks'\] is List\)\s*\?\s*\(metadata\['audio_tracks'\] as List\)\.cast<Map>\(\)\s*:\s*<Map>\[\];/,
  `final audioTracks = _parseTrackList(metadata['audio_tracks'] ?? _showMeta['audio_tracks']);`
);

fs.writeFileSync('lib/screens/episode_details_screen.dart', content, 'utf8');
console.log('Fixed episode parsing');
