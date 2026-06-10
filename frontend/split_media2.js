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
      'Widget _buildSeasonsSection',
      'Widget _buildSeasonOverview',
      'Widget _buildSeasonEpisodeView',
      'Widget _buildNextEpisodeBanner',
      'Widget _buildEpisodeList',
      'Widget _buildEpisodeGrid',
      'Widget _buildViewToggleBtn'
    ]
  },
  {
    fileName: 'media_playback_tab.dart',
    extName: 'MediaPlaybackTabExtension',
    methods: [
      'Widget _buildPlaybackSelectors'
    ]
  },
  {
    fileName: 'media_info_tab.dart',
    extName: 'MediaInfoTabExtension',
    methods: [
      'Widget _buildSimilarCarousel',
      'Widget _buildCrewRow',
      'Widget _buildRatingRow',
      'Widget _buildMyRatingControl'
    ]
  },
  {
    fileName: 'media_badges_tab.dart',
    extName: 'MediaBadgesTabExtension',
    methods: [
      'Widget _buildShowStatusBadge',
      'Widget _buildQualityBadgesRow',
      'Widget _buildAwardsRow'
    ]
  },
  {
    fileName: 'media_layout_tab.dart',
    extName: 'MediaLayoutTabExtension',
    methods: [
      'Widget _buildContent'
    ]
  }
];

let remainingContent = content;
let methodBodies = {};

for (const fileDef of filesToCreate) {
  for (const methodPrefix of fileDef.methods) {
    let searchStr = `  ${methodPrefix}(`;
    let startIndex = remainingContent.indexOf(searchStr);
    
    if (startIndex === -1) {
      searchStr = `  ${methodPrefix} (`;
      startIndex = remainingContent.indexOf(searchStr);
    }
    if (startIndex === -1) {
        searchStr = `  ${methodPrefix}\n`;
        startIndex = remainingContent.indexOf(searchStr);
    }

    if (startIndex === -1) {
      console.error(`Could not find ${methodPrefix}`);
      continue;
    }

    // go forward to find the first `{` that starts the body, being careful about `{` in params
    let firstBraceIdx = startIndex;
    let inString = false;
    let stringChar = '';
    
    let paramsOpen = 0;
    while (firstBraceIdx < remainingContent.length) {
      let char = remainingContent[firstBraceIdx];
      if (!inString && (char === "'" || char === '"')) {
        inString = true;
        stringChar = char;
      } else if (inString && char === stringChar && remainingContent[firstBraceIdx-1] !== '\\') {
        inString = false;
      } else if (!inString) {
        if (char === '(') paramsOpen++;
        else if (char === ')') paramsOpen--;
        else if (char === '{' && paramsOpen === 0) {
          break;
        }
      }
      firstBraceIdx++;
    }

    let braceCount = 0;
    let endIndex = -1;
    let started = false;
    
    for (let i = firstBraceIdx; i < remainingContent.length; i++) {
      let char = remainingContent[i];
      if (char === '{') {
        braceCount++;
        started = true;
      } else if (char === '}') {
        braceCount--;
        if (started && braceCount === 0) {
          endIndex = i + 1;
          break;
        }
      }
    }
    
    if (endIndex === -1) {
      console.error(`Could not balance braces for ${methodPrefix}`);
      continue;
    }
    
    // Check for comments above the method
    let lines = remainingContent.substring(0, startIndex).split('\n');
    let preIdx = startIndex;
    for (let i = lines.length - 1; i >= 0; i--) {
      let l = lines[i].trim();
      if (l.startsWith('//') || l === '') {
        preIdx -= (lines[i].length + 1);
      } else if (l === '') {
        preIdx -= 1;
      } else {
        break;
      }
    }

    const body = remainingContent.substring(preIdx, endIndex).trim();
    methodBodies[methodPrefix] = body;
    
    remainingContent = remainingContent.substring(0, preIdx) + '\n' + remainingContent.substring(endIndex);
  }
}

for (const fileDef of filesToCreate) {
  const destFile = path.join(destDir, fileDef.fileName);
  let fileContent = `part of '../media_details_screen.dart';\n\nextension ${fileDef.extName} on _MediaDetailsScreenState {\n`;
  for (const method of fileDef.methods) {
    if (methodBodies[method]) {
      let body = methodBodies[method];
      if (fileDef.fileName === 'media_playback_tab.dart') {
        body = body.replace(/_buildVersionLabel\(v\)/g, '_MediaDetailsScreenState._buildVersionLabel(v)');
      }
      fileContent += body + '\n\n';
    }
  }
  fileContent += '}\n';
  fs.writeFileSync(destFile, fileContent, 'utf8');
  console.log(`Wrote ${destFile}`);
}

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
