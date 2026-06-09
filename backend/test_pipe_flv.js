const { spawn } = require('child_process');
const path = require('path');
const ytdlpPath = path.join(process.cwd(), 'yt-dlp.exe');
const cp = spawn(ytdlpPath, [
  '--no-warnings',
  '-i', '--max-downloads', '1',
  '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best',
  '--merge-output-format', 'flv',
  '-o', '-',
  'ytsearch1:Batman Begins 2005 Official Trailer'
]);

cp.stdout.on('data', chunk => process.stdout.write('.'));
cp.stderr.on('data', chunk => console.error(chunk.toString()));
cp.on('close', code => console.log('Exited with code', code));
