const fs = require('fs');

let content = fs.readFileSync('lib/screens/episode_details_screen.dart', 'utf8');
content = content.replace(
  'List<Map<String, dynamic>> get _subtitleTracks {\n    final raw = widget.episode[\'subtitle_tracks\'] ?? _showMeta[\'subtitle_tracks\'];\n    return _parseTrackList(raw);\n  }',
  'List<Map<String, dynamic>> get _subtitleTracks {\n    final raw = widget.episode[\'subtitle_tracks\'] ?? _showMeta[\'subtitle_tracks\'];\n    final parsed = _parseTrackList(raw);\n    print("EPISODE_SUBTITLES RAW: $raw => PARSED: $parsed");\n    return parsed;\n  }'
);

fs.writeFileSync('lib/screens/episode_details_screen.dart', content, 'utf8');
console.log('Added print to _subtitleTracks');
