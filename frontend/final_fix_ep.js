const fs = require('fs');

let content = fs.readFileSync('lib/screens/episode_details_screen.dart', 'utf8');

if (!content.includes('_applyLanguageDefaults(widget.episode);')) {
  content = content.replace(
    '      _pendingAudioLang = savedAudioLang;\n    });',
    '      _pendingAudioLang = savedAudioLang;\n    });\n    _applyLanguageDefaults(widget.episode);'
  );
  fs.writeFileSync('lib/screens/episode_details_screen.dart', content, 'utf8');
  console.log('Added _applyLanguageDefaults call to _loadPlaybackSettings');
} else {
  console.log('Already added.');
}
