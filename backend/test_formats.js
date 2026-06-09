const YTDlpWrap = require('yt-dlp-wrap').default;
const path = require('path');
async function test() {
  const ytdlp = new YTDlpWrap(path.join(process.cwd(), 'yt-dlp.exe'));
  const info = await ytdlp.getVideoInfo('ytsearch1:Batman Begins 2005 Official Trailer');
  const videoData = info.entries ? info.entries[0] : info;
  console.log('Manifest:', videoData.manifest_url);
  const m3u8 = videoData.formats?.find(f => f.protocol === 'm3u8_native' || f.format_id === '136' || f.url?.includes('.m3u8'));
  console.log('m3u8 formats:', m3u8 ? true : false);
  videoData.formats.forEach(f => {
    if (f.protocol.includes('m3u8') || f.ext === 'mp4') {
        if (!f.vcodec || f.vcodec === 'none') return;
        console.log(`${f.format_id}: ext=${f.ext} proto=${f.protocol} res=${f.resolution} vcodec=${f.vcodec} acodec=${f.acodec}`);
    }
  });
}
test().catch(console.error);
