const { spawn } = require('child_process');
const path = require('path');
const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg');

const cp = spawn(path.join(process.cwd(), 'yt-dlp.exe'), [
  '-q', // quiet
  '--no-warnings',
  '--ffmpeg-location', ffmpegInstaller.path,
  '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best',
  '--merge-output-format', 'mp4',
  '--postprocessor-args', 'ffmpeg:-movflags frag_keyframe+empty_moov',
  '-o', '-',
  'https://www.youtube.com/watch?v=8r9-oeONQ8U'
]);

cp.stdout.on('data', d => console.log('STDOUT chunk size:', d.length));
cp.stderr.on('data', d => console.log('STDERR:', d.toString()));
