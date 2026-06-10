const fs = require('fs');
const path = require('path');

const applyLanguageLogic = `
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
`;

// Update media_details_screen.dart
const mediaPath = path.join(__dirname, 'lib/screens/media_details_screen.dart');
let mediaContent = fs.readFileSync(mediaPath, 'utf8');

// 1. Update _loadPlaybackSettings to include fallback
mediaContent = mediaContent.replace(
  /final savedAudioLang = prefs\.getString\('loom_player_audio_lang'\) \?\? '';/,
  `final savedAudioLang = prefs.getString('loom_player_audio_lang') ?? '';
      final savedFallbackSubLang = prefs.getString('loom_player_fallback_subtitle_lang') ?? '';`
);
mediaContent = mediaContent.replace(
  /_pendingAudioLang = savedAudioLang;/,
  `_pendingAudioLang = savedAudioLang;
        _pendingFallbackSubtitleLang = savedFallbackSubLang;`
);

// 2. Replace the old _applyLanguageDefaults block entirely
const applyDefaultsStart = mediaContent.indexOf('  // Resolved once tracks are known');
const savePlaybackSettingsStart = mediaContent.indexOf('  Future<void> _savePlaybackSettings() async {');
if (applyDefaultsStart !== -1 && savePlaybackSettingsStart !== -1) {
  mediaContent = mediaContent.substring(0, applyDefaultsStart) + applyLanguageLogic + '\n' + mediaContent.substring(savePlaybackSettingsStart);
}
fs.writeFileSync(mediaPath, mediaContent, 'utf8');
console.log('Updated media_details_screen.dart');


// Update episode_details_screen.dart
const episodePath = path.join(__dirname, 'lib/screens/episode_details_screen.dart');
let epContent = fs.readFileSync(episodePath, 'utf8');

const epSettingsImport = "import 'package:shared_preferences/shared_preferences.dart';";
if (!epContent.includes(epSettingsImport)) {
  epContent = epContent.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:shared_preferences/shared_preferences.dart';");
}

const epLoadSettings = `
  Future<void> _loadPlaybackSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedQuality = prefs.getString('loom_player_quality_pref') ?? 'direct';
    final savedSubLang = prefs.getString('loom_player_subtitle_lang') ?? '';
    final savedFallbackSubLang = prefs.getString('loom_player_fallback_subtitle_lang') ?? '';
    final savedAudioLang = prefs.getString('loom_player_audio_lang') ?? '';
    if (!mounted) return;
    setState(() {
      _selectedQuality = savedQuality;
      _pendingSubtitleLang = savedSubLang;
      _pendingFallbackSubtitleLang = savedFallbackSubLang;
      _pendingAudioLang = savedAudioLang;
    });
    
    // Apply defaults to current tracks
    final tracks = {
      'subtitle_tracks': _subtitleTracks,
      'audio_tracks': _audioTracks,
    };
    _applyLanguageDefaults(tracks);
  }
`;

// Insert _loadPlaybackSettings into initState
if (epContent.includes('super.initState();')) {
  epContent = epContent.replace(
    'super.initState();',
    'super.initState();\n    _loadPlaybackSettings();'
  );
}

// Insert the functions right before dispose
const epDisposeStart = epContent.indexOf('  @override\n  void dispose() {');
if (epDisposeStart !== -1) {
  epContent = epContent.substring(0, epDisposeStart) + applyLanguageLogic + '\n' + epLoadSettings + '\n' + epContent.substring(epDisposeStart);
}

// Also hook up onChanged for the quality dropdown
epContent = epContent.replace(
  `onChanged: (v) { if (v != null) setState(() => _selectedQuality = v); },`,
  `onChanged: (v) async { 
              if (v != null) {
                setState(() => _selectedQuality = v);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('loom_player_quality_pref', v);
              }
            },`
);

fs.writeFileSync(episodePath, epContent, 'utf8');
console.log('Updated episode_details_screen.dart');

