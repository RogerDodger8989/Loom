const fs = require('fs');

let content = fs.readFileSync('lib/screens/media_details/media_layout_tab.dart', 'utf8');

if (!content.includes('if (!isTv) ...[')) {
  content = content.replace(
    '                        _buildPlaybackSelectors(Map<String, dynamic>.from(metadata)),\n                        const SizedBox(height: 16),',
    '                        if (!isTv) ...[\n                          _buildPlaybackSelectors(Map<String, dynamic>.from(metadata)),\n                          const SizedBox(height: 16),\n                        ],'
  );
  fs.writeFileSync('lib/screens/media_details/media_layout_tab.dart', content, 'utf8');
  console.log('Fixed media_layout_tab.dart');
} else {
  console.log('Already fixed.');
}
