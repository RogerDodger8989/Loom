const { spawn } = require('child_process');
const path = require('path');
const ytdlpPath = path.join(process.cwd(), 'yt-dlp.exe');
const cp = spawn(ytdlpPath, [
  '--no-warnings',
  '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best',
  '--merge-output-format', 'mkv',
  '-o', '-',
  'ytsearch1:Monsters, Inc. 2001 Official Trailer'
]);

let bytes = 0;
cp.stdout.on('data', chunk => {
  bytes += chunk.length;
  if (bytes > 1024 * 1024) { // Got 1MB
     console.log('Successfully streaming mkv! bytes:', bytes);
     cp.kill();
     process.exit(0);
  }
});
cp.stderr.on('data', chunk => console.error(chunk.toString()));
cp.on('close', code => console.log('Exited with code', code));
