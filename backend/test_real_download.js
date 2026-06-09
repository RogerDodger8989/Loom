const { spawn } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');

async function test() {
  const ytdlpPath = path.join(process.cwd(), 'yt-dlp.exe');
  const videoId = 'xWKo2fvCvJY';
  const outputPath = path.join(os.tmpdir(), `loom_trailer_${videoId}.mp4`);

  if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath);

  const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg');

  const cp = spawn(ytdlpPath, [
    '--no-warnings',
    '--ffmpeg-location', ffmpegInstaller.path,
    '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best',
    '--merge-output-format', 'mp4',
    '-o', outputPath,
    `https://www.youtube.com/watch?v=${videoId}`
  ]);

  cp.stdout.on('data', d => process.stdout.write(d));
  cp.stderr.on('data', d => process.stdout.write(d));

  await new Promise((resolve) => cp.on('close', resolve));

  if (fs.existsSync(outputPath)) console.log('Size:', fs.statSync(outputPath).size);
  else console.log('File not found!');
}
test().catch(console.error);
