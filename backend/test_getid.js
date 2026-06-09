const { execSync } = require('child_process');
const path = require('path');
const ytdlpPath = path.join(process.cwd(), 'yt-dlp.exe');
try {
  const out = execSync(`"${ytdlpPath}" "ytsearch10:Monsters Inc trailer" --get-id -i --max-downloads 1 --no-warnings`).toString();
  console.log('ID:', out.trim().split('\n')[0].trim());
} catch (e) {
  const out = e.stdout?.toString();
  console.log('Error, but stdout is:', out);
  if (out) console.log('ID:', out.trim().split('\n')[0].trim());
}
