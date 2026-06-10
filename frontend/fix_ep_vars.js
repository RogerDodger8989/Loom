const fs = require('fs');
let content = fs.readFileSync('lib/screens/episode_details_screen.dart', 'utf8');

// 1. Add SharedPreferences import
if (!content.includes("import 'package:shared_preferences/shared_preferences.dart';")) {
  content = content.replace(
    "import 'package:flutter/material.dart';",
    "import 'package:flutter/material.dart';\nimport 'package:shared_preferences/shared_preferences.dart';"
  );
}

// 2. Add the missing state variables
if (!content.includes('String _selectedSubtitleTrack')) {
  content = content.replace(
    "  String _pendingAudioLang = '';",
    "  String _pendingAudioLang = '';\n  String _selectedSubtitleTrack = 'none';\n  String _selectedAudioTrack = 'auto';\n  String _selectedQuality = 'direct';"
  );
}

fs.writeFileSync('lib/screens/episode_details_screen.dart', content, 'utf8');
console.log('Variables and imports fixed!');
