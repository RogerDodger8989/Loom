const { execSync, spawn } = require('child_process');
const path = require('path');
const ytdlpPath = path.join(process.cwd(), 'yt-dlp.exe');

async function test() {
  const query = 'Monsters, Inc. 2001 Official Trailer';
  
  // 1. Get IDs
  console.log('Searching for IDs...');
  const idsOutput = execSync(`"${ytdlpPath}" "ytsearch10:${query}" --get-id --ignore-errors --no-warnings`).toString();
  const ids = idsOutput.split('\n').map(s => s.trim()).filter(Boolean);
  
  console.log('Found IDs:', ids);
  
  let workingId = null;
  // 2. Find first working ID
  for (const id of ids) {
     try {
       console.log('Testing ID', id);
       execSync(`"${ytdlpPath}" -j "https://www.youtube.com/watch?v=${id}"`, { stdio: 'ignore' });
       workingId = id;
       break;
     } catch(e) {
       console.log('ID', id, 'is unavailable');
     }
  }
  
  if (!workingId) {
    console.error('No working ID found!');
    return;
  }
  
  console.log('Working ID is', workingId);
  
  // 3. Stream it with merging
  const cp = spawn(ytdlpPath, [
    '--no-warnings',
    '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best',
    '--merge-output-format', 'mp4',
    '--postprocessor-args', 'ffmpeg:-movflags frag_keyframe+empty_moov',
    '-o', '-',
    `https://www.youtube.com/watch?v=${workingId}`
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
