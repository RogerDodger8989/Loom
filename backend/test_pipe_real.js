const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

async function test() {
  const ytdlpPath = path.join(process.cwd(), 'yt-dlp.exe');
  const videoId = 'xWKo2fvCvJY';
  const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg');

  const cp = spawn(ytdlpPath, [
    '--no-warnings',
    '--ffmpeg-location', ffmpegInstaller.path,
    '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best',
    '--merge-output-format', 'mp4',
    '--postprocessor-args', 'ffmpeg:-movflags frag_keyframe+empty_moov',
    '-o', '-',
    `https://www.youtube.com/watch?v=${videoId}`
  ]);

  let bytes = 0;
  cp.stdout.on('data', chunk => {
    bytes += chunk.length;
    if (bytes > 1024 * 1024) {
       console.log('Successfully streaming mp4! bytes:', bytes);
       cp.kill();
       process.exit(0);
    }
  });
  cp.stderr.on('data', chunk => process.stdout.write(chunk.toString()));
}

test().catch(console.error);
