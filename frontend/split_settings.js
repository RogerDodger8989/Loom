const fs = require('fs');
const path = require('path');

const srcFile = path.join(__dirname, 'lib/screens/settings_screen.dart');
const destDir = path.join(__dirname, 'lib/screens/settings');

const content = fs.readFileSync(srcFile, 'utf8');
const lines = content.split('\n');

const markers = [
  { name: 'bibliotek', marker: 'Category: Bibliotek' },
  { name: 'papperskorg', marker: 'Category: Papperskorg' },
  { name: 'uppspelning', marker: 'Category: Uppspelning' },
  { name: 'kallor', marker: 'Category: Källor & Integrationer' },
  { name: 'notifieringar', marker: 'Category: Notifieringar' },
  { name: 'loggning', marker: 'Category: Loggning' },
  { name: 'server', marker: 'Category: Server' },
  { name: 'statistik', marker: 'Category: Statistik' },
  { name: 'konto', marker: 'Category: Konto' },
  { name: 'anvandare', marker: 'Category: Användare' },
  { name: 'diskutrymme', marker: 'Category: Diskutrymme' },
];

// Find the line index for each marker
let markerLines = [];
for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  for (const m of markers) {
    if (line.includes(m.marker)) {
      markerLines.push({ name: m.name, lineIndex: i });
      break;
    }
  }
}

// Sort by line index
markerLines.sort((a, b) => a.lineIndex - b.lineIndex);

if (markerLines.length === 0) {
  console.log("No markers found!");
  process.exit(1);
}

// Ensure dir exists
if (!fs.existsSync(destDir)) {
  fs.mkdirSync(destDir, { recursive: true });
}

let newMainLines = lines.slice(0, markerLines[0].lineIndex - 1);
// Remove the trailing `}` that closed the class, because it was at the end of the file.
// We'll add it back later.

// Wait, the first chunk might include the `}` of the last method before the categories start.
// Let's just find the last `}` in the file.
let lastBraceIndex = -1;
for (let i = lines.length - 1; i >= 0; i--) {
  if (lines[i].trim() === '}') {
    lastBraceIndex = i;
    break;
  }
}

for (let i = 0; i < markerLines.length; i++) {
  const start = markerLines[i].lineIndex - 1; // Include the `// ───` line before it
  let end = i < markerLines.length - 1 ? markerLines[i + 1].lineIndex - 1 : lastBraceIndex;
  
  const chunkLines = lines.slice(start, end);
  
  const extName = markerLines[i].name.charAt(0).toUpperCase() + markerLines[i].name.slice(1) + 'TabExtension';
  
  const fileContent = `part of '../settings_screen.dart';\n\nextension ${extName} on SettingsScreenState {\n${chunkLines.join('\n')}\n}\n`;
  
  const destFile = path.join(destDir, `${markerLines[i].name}_tab.dart`);
  fs.writeFileSync(destFile, fileContent, 'utf8');
  console.log(`Wrote ${destFile}`);
}

// Now add parts to main lines
let partDirectives = markers.map(m => `part 'settings/${m.name}_tab.dart';`).join('\n');

// Find the imports to add parts after
let importEndIndex = -1;
for (let i = 0; i < newMainLines.length; i++) {
  if (newMainLines[i].startsWith('import ')) {
    importEndIndex = i;
  }
}

newMainLines.splice(importEndIndex + 1, 0, '\n' + partDirectives + '\n');

// Add the closing brace back
newMainLines.push('}\n');

fs.writeFileSync(srcFile, newMainLines.join('\n'), 'utf8');
console.log('Main file updated!');
