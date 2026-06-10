const fs = require('fs');
const path = require('path');

const srcFile = path.join(__dirname, 'lib/screens/media_details_screen.dart');
const destDir = path.join(__dirname, 'lib/screens/media_details');

const content = fs.readFileSync(srcFile, 'utf8');

const filesToCreate = [
  {
    fileName: 'media_seasons_tab.dart',
    extName: 'MediaSeasonsTabExtension',
    methods: [
      '_buildSeasonsSection',
      '_buildSeasonOverview',
      '_buildSeasonEpisodeView',
      '_buildNextEpisodeBanner',
      '_buildEpisodeList',
      '_buildEpisodeGrid',
      '_buildViewToggleBtn'
    ]
  },
  {
    fileName: 'media_playback_tab.dart',
    extName: 'MediaPlaybackTabExtension',
    methods: [
      '_buildPlaybackSelectors',
      '_buildControlButton'
    ]
  },
  {
    fileName: 'media_info_tab.dart',
    extName: 'MediaInfoTabExtension',
    methods: [
      '_buildSimilarCarousel',
      '_buildCrewRow',
      '_buildRatingRow',
      '_buildMyRatingControl'
    ]
  },
  {
    fileName: 'media_badges_tab.dart',
    extName: 'MediaBadgesTabExtension',
    methods: [
      '_buildShowStatusBadge',
      '_buildQualityBadgesRow',
      '_buildAwardsRow'
    ]
  },
  {
    fileName: 'media_layout_tab.dart',
    extName: 'MediaLayoutTabExtension',
    methods: [
      '_buildContent'
    ]
  }
];

let remainingContent = content;
let methodBodies = {};

// We need to carefully extract the methods from the file string.
for (const fileDef of filesToCreate) {
  for (const method of fileDef.methods) {
    const startRegex = new RegExp(`  Widget ${method}\\([^{]*\\{`);
    const match = remainingContent.match(startRegex);
    if (!match) {
      console.error(`Could not find ${method}`);
      continue;
    }
    
    let startIndex = match.index;
    
    // We should also try to grab any immediately preceding dart doc comments or metadata
    // like `//  build something` or `@override`. Since this is just helper methods, they probably don't have `@override`, but let's grab preceding lines if they start with `//`.
    let lines = remainingContent.substring(0, startIndex).split('\n');
    let preIdx = startIndex;
    for (let i = lines.length - 1; i >= 0; i--) {
      let l = lines[i].trim();
      if (l.startsWith('//') || l === '') {
        // Go backwards
        preIdx -= (lines[i].length + 1);
      } else {
        break;
      }
    }
    // Don't grab too much whitespace
    
    // Balance braces
    let braceCount = 0;
    let endIndex = -1;
    let started = false;
    
    for (let i = startIndex; i < remainingContent.length; i++) {
      if (remainingContent[i] === '{') {
        braceCount++;
        started = true;
      } else if (remainingContent[i] === '}') {
        braceCount--;
        if (started && braceCount === 0) {
          endIndex = i + 1;
          break;
        }
      }
    }
    
    if (endIndex === -1) {
      console.error(`Could not balance braces for ${method}`);
      continue;
    }
    
    const body = remainingContent.substring(startIndex, endIndex);
    methodBodies[method] = body;
    
    // Remove from remaining content
    remainingContent = remainingContent.substring(0, startIndex) + remainingContent.substring(endIndex);
  }
}

// Write the parts
for (const fileDef of filesToCreate) {
  const destFile = path.join(destDir, fileDef.fileName);
  let fileContent = `part of '../media_details_screen.dart';\n\nextension ${fileDef.extName} on _MediaDetailsScreenState {\n`;
  for (const method of fileDef.methods) {
    if (methodBodies[method]) {
      fileContent += methodBodies[method] + '\n\n';
    }
  }
  fileContent += '}\n';
  fs.writeFileSync(destFile, fileContent, 'utf8');
  console.log(`Wrote ${destFile}`);
}

// Add part directives to the main file
const partDirectives = filesToCreate.map(f => `part 'media_details/${f.fileName}';`).join('\n');
let importEndIndex = -1;
const lines = remainingContent.split('\n');
for (let i = 0; i < lines.length; i++) {
  if (lines[i].startsWith('import ')) {
    importEndIndex = i;
  }
}

lines.splice(importEndIndex + 1, 0, '\n' + partDirectives + '\n');
fs.writeFileSync(srcFile, lines.join('\n'), 'utf8');
console.log('Main file updated!');
