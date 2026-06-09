const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');

async function test() {
  const ytdlpPath = path.join(process.cwd(), 'yt-dlp.exe');
  const finalUrl = 'ytsearch10:Batman Begins 2005 Official Trailer';
  const hash = crypto.createHash('md5').update(finalUrl).digest('hex');
  const outputPath = path.join(os.tmpdir(), `trailer_${hash}.mp4`);
  
  if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath); // clean

  console.log('Downloading to', outputPath);
  
  const cp = spawn(ytdlpPath, [
    '--no-warnings',
    '-i', '--max-downloads', '1',
    '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best',
    '--merge-output-format', 'mp4',
    '-o', outputPath,
    finalUrl
  ]);

  cp.stderr.on('data', d => process.stdout.write(d.toString()));
  cp.stdout.on('data', d => process.stdout.write(d.toString()));

  await new Promise((resolve) => {
     cp.on('close', code => {
       console.log('Exited', code);
       resolve();
     });
  });

  if (fs.existsSync(outputPath)) {
     console.log('File size:', fs.statSync(outputPath).size);
  } else {
     console.log('File not found!');
  }
}
test().catch(console.error);
