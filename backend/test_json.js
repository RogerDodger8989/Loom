const YTDlpWrap = require('yt-dlp-wrap').default;
const path = require('path');
async function test() {
  const ytdlp = new YTDlpWrap(path.join(process.cwd(), 'yt-dlp.exe'));
  const info = await ytdlp.getVideoInfo('ytsearch1:Batman Begins 2005 Official Trailer');
  const videoData = info.entries ? info.entries[0] : info;
  
  if (videoData.requested_formats) {
     console.log('Video URL:', videoData.requested_formats[0].url);
     console.log('Audio URL:', videoData.requested_formats[1].url);
  } else {
     console.log('Single URL:', videoData.url);
  }
}
test().catch(console.error);
