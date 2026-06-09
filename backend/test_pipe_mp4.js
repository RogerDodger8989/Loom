const { spawn } = require('child_process');
const path = require('path');
const ytdlpPath = path.join(process.cwd(), 'yt-dlp.exe');
const cp = spawn(ytdlpPath, [
  '--no-warnings',
  '-i',
  '--max-downloads', '1',
  '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best',
  '--merge-output-format', 'mp4',
  '--postprocessor-args', 'ffmpeg:-movflags frag_keyframe+empty_moov',
  '-o', '-',
  'ytsearch10:Monsters Inc trailer'
]);

let bytes = 0;
cp.stdout.on('data', chunk => {
  bytes += chunk.length;
  if (bytes > 1024 * 1024) { // Got 1MB
     console.log('Successfully streaming mp4! bytes:', bytes);
     cp.kill();
     process.exit(0);
  }
});
cp.stderr.on('data', chunk => console.error(chunk.toString()));
cp.on('close', code => console.log('Exited with code', code));
