import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';
import { spawn, execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import ffmpegInstaller from '@ffmpeg-installer/ffmpeg';
const ffprobeInstaller = require('@ffprobe-installer/ffprobe');

const HLS_CACHE_DIR = path.join(process.cwd(), 'hls_cache');

if (!fs.existsSync(HLS_CACHE_DIR)) {
  fs.mkdirSync(HLS_CACHE_DIR, { recursive: true });
}

function getSetting(key: string): string {
  const row = db.prepare('SELECT value FROM system_settings WHERE key = ?').get(key) as { value: string } | undefined;
  return row?.value ?? '';
}

// ── Semaphore: max simultana transkodningsströmmar ─────────────────────────
let _activeStreams = 0;

function getMaxStreams(): number {
  const v = parseInt(getSetting('MAX_STREAMS') || '3', 10);
  return isNaN(v) || v < 1 ? 3 : v;
}


export default async function playbackRoutes(fastify: FastifyInstance) {
  fastify.register(require('@fastify/static'), {
    root: HLS_CACHE_DIR,
    prefix: '/hls/',
    decorateReply: false
  });

  fastify.get(
    '/api/playback/markers/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        // Legacy episode_markers
        const legacy = db.prepare(
          `SELECT marker_type, start_time_seconds, end_time_seconds, NULL as title, 'manual' as source
           FROM episode_markers WHERE episode_id = ?`
        ).all(id);

        // New media_markers (supports both episodes and movies)
        const modern = db.prepare(
          `SELECT marker_type, start_time_seconds, end_time_seconds, title, source
           FROM media_markers WHERE episode_id = ? OR media_item_id = ?
           ORDER BY start_time_seconds ASC`
        ).all(id, id);

        // Merge, deduplicate by marker_type+start
        const seen = new Set<string>();
        const merged: any[] = [];
        for (const m of [...modern, ...legacy]) {
          const key = `${m.marker_type}:${Math.round(m.start_time_seconds)}`;
          if (!seen.has(key)) { seen.add(key); merged.push(m); }
        }

        return reply.send({ markers: merged });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed', details: err.message });
      }
    }
  );

  fastify.get(
    '/api/playback/subtitles/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      return reply.send({ message: 'Subtitle extraction endpoint initialized.' });
    }
  );

  fastify.get(
    '/api/playback/file-path/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      let item = db.prepare('SELECT file_path FROM media_items WHERE id = ? AND deleted_at IS NULL').get(id) as any;
      if (!item) item = db.prepare('SELECT file_path, show_id FROM episodes WHERE id = ?').get(id) as any;
      if (!item || !item.file_path || !fs.existsSync(item.file_path)) {
        return reply.code(404).send({ error: 'File missing' });
      }
      reply.header('Access-Control-Allow-Origin', '*');
      const fileUrl = 'file:///' + item.file_path.replace(/\\/g, '/');
      return reply.send({ filePath: item.file_path, fileUrl });
    }
  );

  fastify.get(
    '/api/playback/stream/:id',
    async (request: FastifyRequest<{ Params: { id: string }, Querystring: { transcode?: string, bitrate?: string, subtitleIndex?: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      let item = db.prepare('SELECT file_path FROM media_items WHERE id = ? AND deleted_at IS NULL').get(id) as any;
      if (!item) item = db.prepare('SELECT file_path, show_id FROM episodes WHERE id = ?').get(id) as any;
      if (!item || !item.file_path || !fs.existsSync(item.file_path)) {
        return reply.code(404).send({ error: 'File missing' });
      }

      const stat = fs.statSync(item.file_path);
      const range = request.headers.range;
      const contentType = item.file_path.toLowerCase().endsWith('.mkv')
        ? 'video/x-matroska'
        : item.file_path.toLowerCase().endsWith('.webm')
          ? 'video/webm'
          : 'video/mp4';

      reply.header('Accept-Ranges', 'bytes');
      reply.header('Content-Type', contentType);
      reply.header('Access-Control-Allow-Origin', '*');

      if (range) {
        const parts = range.replace(/bytes=/, '').split('-');
        const start = parseInt(parts[0], 10);
        const end = parts[1] ? parseInt(parts[1], 10) : stat.size - 1;
        const chunksize = (end - start) + 1;
        reply.raw.writeHead(206, {
          'Content-Range': `bytes ${start}-${end}/${stat.size}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': chunksize,
          'Content-Type': contentType,
        });
        fs.createReadStream(item.file_path, { start, end }).pipe(reply.raw);
        return;
      }

      reply.raw.writeHead(200, {
        'Content-Length': stat.size,
        'Content-Type': contentType,
        'Accept-Ranges': 'bytes',
      });
      fs.createReadStream(item.file_path).pipe(reply.raw);
      return;
    }
  );

  fastify.get(
    '/api/playback/web-stream/:id',
    async (request: FastifyRequest<{ Params: { id: string }, Querystring: { bitrate?: string, subtitleIndex?: string, start?: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const bitrate = request.query.bitrate || '4000k';
      const subtitleIndex = request.query.subtitleIndex || 'none';
      const startSec = Math.max(0, parseInt(request.query.start || '0', 10));

      let item = db.prepare('SELECT file_path FROM media_items WHERE id = ? AND deleted_at IS NULL').get(id) as any;
      if (!item) item = db.prepare('SELECT file_path, show_id FROM episodes WHERE id = ?').get(id) as any;
      if (!item || !fs.existsSync(item.file_path)) return reply.code(404).send('Not found');

      reply.header('Content-Type', 'video/mp4');
      reply.header('Access-Control-Allow-Origin', '*');

      const bitrateKbps = parseInt(bitrate);
      const bufsizeStr = `${bitrateKbps * 2}k`;
      // -ss BEFORE -i = fast keyframe seek (input seeking, much faster than output seeking)
      let ffmpegArgs: string[] = [];
      if (startSec > 0) ffmpegArgs.push('-ss', startSec.toString());
      ffmpegArgs.push(
        '-i', item.file_path,
        '-sn',
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-b:v', bitrate,
        '-maxrate', bitrate,
        '-bufsize', bufsizeStr,
        '-c:a', 'aac',
        '-f', 'mp4',
        '-movflags', 'frag_keyframe+empty_moov',
        'pipe:1'
      );

      let isPgsSub = false;
      let relativeIndex = 0;  // hoisted so the two-input PGS rebuild can reference it
      if (subtitleIndex !== 'none') {
        const subIndexNum = parseInt(subtitleIndex, 10);
        let isText = true;
        try {
          const subMeta = item.show_id
            ? db.prepare(`SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?`).get(item.show_id, `ep_${id}_subtitle_tracks`) as any
            : db.prepare('SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?').get(id, 'subtitle_tracks') as any;
          if (subMeta && subMeta.metadata_value) {
            const tracks = JSON.parse(subMeta.metadata_value);
            relativeIndex = tracks.findIndex((t: any) => t.index === subIndexNum);
            if (relativeIndex === -1) relativeIndex = 0;
            const track = tracks.find((t: any) => t.index === subIndexNum);
            const codecUp = (track?.codec || '').toUpperCase();
            if (track && (codecUp.includes('PGS') || codecUp.includes('HDMV') || codecUp.includes('DVD_SUBTITLE') || codecUp.includes('VOBSUB'))) {
              isText = false;
              isPgsSub = true;
            }
            console.log(`[Sub] codec="${codecUp}" relativeIndex=${relativeIndex} isText=${isText}`);
          }
        } catch (e) { console.error('[Sub] metadata parse error:', e); }

        // Remove -sn AND the output placeholder (pipe:1) — output must come last
        ffmpegArgs = ffmpegArgs.filter(a => a !== '-sn' && a !== 'pipe:1');
        if (isText) {
           const escapedPath = item.file_path.replace(/\\/g, '\\\\').replace(/:/g, '\\:');
           ffmpegArgs.push('-vf', `subtitles='${escapedPath}':si=${relativeIndex}`);
        } else {
           // PGS/VOBSUB bitmap overlay.
           // For startSec=0 we use a single input — subtitle state is correct from start.
           // For startSec>0 the two-input rebuild below replaces these args.
           ffmpegArgs.push(
             '-filter_complex',
             `[0:v]scale=1920:-2[vid];[0:s:${relativeIndex}]scale=1920:-2[sub];[vid][sub]overlay=format=auto[v]`,
             '-map', '[v]', '-map', '0:a'
           );
        }
        // Output must be last
        ffmpegArgs.push('pipe:1');
      }

      // PGS two-input seek fix:
      // PGS bitmaps have no random-access state — input-seeking past a subtitle event
      // loses its bitmap, causing sub2video to stall with no frame for the overlay.
      // Solution: open the file twice. Input 0 is input-seeked (fast video start).
      // Input 1 has NO seek; sub2video reads all PGS packets from the beginning so
      // it has the correct bitmap at any position. The subtitle-only demux from start
      // is fast (PGS packets are sparse; no HEVC decoding needed for input 1).
      if (isPgsSub && startSec > 0) {
        ffmpegArgs = [
          '-ss', startSec.toString(),        // input 0: fast keyframe seek for video
          '-i', item.file_path,
          '-i', item.file_path,              // input 1: subtitle from beginning (no seek)
          '-c:v', 'libx264',
          '-preset', 'veryfast',
          '-b:v', bitrate,
          '-maxrate', bitrate,
          '-bufsize', bufsizeStr,
          '-c:a', 'aac',
          '-f', 'mp4',
          '-movflags', 'frag_keyframe+empty_moov',
          '-filter_complex',
          `[0:v]scale=1920:-2[vid];[1:s:${relativeIndex}]scale=1920:-2[sub];[vid][sub]overlay=format=auto[v]`,
          '-map', '[v]',
          '-map', '0:a',
          'pipe:1',
        ];
      }

      // Log the full FFmpeg command for PGS debugging
      if (isPgsSub) {
        console.log('[PGS] FFmpeg args:', ffmpegInstaller.path, ffmpegArgs.join(' '));
      }

      const ff = spawn(ffmpegInstaller.path, ffmpegArgs, { stdio: ['ignore', 'pipe', 'pipe'] });
      if (isPgsSub) {
        ff.stderr!.on('data', (d: Buffer) => process.stderr.write(`[PGS] ${d}`));
      } else {
        ff.stderr!.resume(); // drain stderr to prevent buffer blocking
      }
      
      request.raw.on('close', () => {
        ff.kill('SIGKILL');
      });

      return reply.send(ff.stdout);
    }
  );

  fastify.get(
    '/api/playback/dynamic/:id/playlist.m3u8',
    async (request: FastifyRequest<{ Params: { id: string }, Querystring: { bitrate?: string, subtitleIndex?: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const bitrate = request.query.bitrate || '4000k';
      const subtitleIndex = request.query.subtitleIndex || 'none';

      let item = db.prepare('SELECT file_path FROM media_items WHERE id = ? AND deleted_at IS NULL').get(id) as any;
      if (!item) item = db.prepare('SELECT file_path, show_id FROM episodes WHERE id = ?').get(id) as any;
      if (!item || !fs.existsSync(item.file_path)) return reply.code(404).send('Not found');

      try {
        const probeOutput = execSync(`"${ffprobeInstaller.path}" -v quiet -print_format json -show_format "${item.file_path.replace(/"/g, '\\"')}"`).toString();
        const duration = parseFloat(JSON.parse(probeOutput).format.duration);
        
        const segmentLength = 10;
        const numSegments = Math.ceil(duration / segmentLength);

        // Use request.headers.host which includes the port (e.g. localhost:8080)
        const host = (request.headers['host'] as string) || request.hostname;
        let m3u8 = `#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:${segmentLength}\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n`;
        for (let i = 0; i < numSegments; i++) {
          const isLast = i === numSegments - 1;
          const dur = isLast ? (duration - i * segmentLength) : segmentLength;
          m3u8 += `#EXTINF:${dur.toFixed(6)},\n`;
          m3u8 += `http://${host}/api/playback/dynamic/${id}/segment/${i}.ts?bitrate=${bitrate}&subtitleIndex=${subtitleIndex}\n`;
        }
        m3u8 += `#EXT-X-ENDLIST\n`;

        reply.header('Content-Type', 'application/vnd.apple.mpegurl');
        reply.header('Access-Control-Allow-Origin', '*');
        return reply.send(m3u8);
      } catch (err) {
        return reply.code(500).send('Error generating playlist');
      }
    }
  );

  fastify.get(
    '/api/playback/dynamic/:id/segment/:segmentFile',
    async (request: FastifyRequest<{ Params: { id: string, segmentFile: string }, Querystring: { bitrate?: string, subtitleIndex?: string } }>, reply: FastifyReply) => {
      const { id, segmentFile } = request.params;
      const index = parseInt(segmentFile.replace('.ts', ''), 10);
      const bitrate = request.query.bitrate || '4000k';
      const subtitleIndex = request.query.subtitleIndex || 'none';

      let item = db.prepare('SELECT file_path FROM media_items WHERE id = ? AND deleted_at IS NULL').get(id) as any;
      if (!item) item = db.prepare('SELECT file_path, show_id FROM episodes WHERE id = ?').get(id) as any;
      if (!item || !fs.existsSync(item.file_path)) return reply.code(404).send('Not found');

      const sessionId = `hls_dynamic_${id}_${bitrate}_${subtitleIndex}`;
      const sessionDir = path.join(HLS_CACHE_DIR, sessionId);
      if (!fs.existsSync(sessionDir)) fs.mkdirSync(sessionDir, { recursive: true });

      const segmentPath = path.join(sessionDir, `segment_${index}.ts`);
      const segmentPathTmp = segmentPath + '.tmp';

      if (fs.existsSync(segmentPath) && fs.statSync(segmentPath).size > 0) {
        reply.header('Content-Type', 'video/mp2t');
        reply.header('Access-Control-Allow-Origin', '*');
        const stream = fs.createReadStream(segmentPath);
        return reply.send(stream);
      }

      // Semaphore check
      if (_activeStreams >= getMaxStreams()) {
        return reply.code(503).send({ error: 'Max antal simultana strömmar nådd. Försök igen om en stund.' });
      }
      _activeStreams++;

      const startTime = index * 10;
      const segBitrateKbps = parseInt(bitrate);
      const segBufsizeStr = `${segBitrateKbps * 2}k`;
      let ffmpegArgs = [
        '-y',
        '-ss', startTime.toString(),
        '-t', '10',
        '-i', item.file_path,
        '-sn',
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-b:v', bitrate,
        '-maxrate', bitrate,
        '-bufsize', segBufsizeStr,
        '-c:a', 'copy',
        '-f', 'mpegts'
      ];

      let isPgsSegment = false;
      if (subtitleIndex !== 'none') {
        const subIndexNum = parseInt(subtitleIndex, 10);
        let isText = true;
        let relativeIndex = 0;
        try {
          const subMeta = item.show_id
            ? db.prepare(`SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?`).get(item.show_id, `ep_${id}_subtitle_tracks`) as any
            : db.prepare('SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?').get(id, 'subtitle_tracks') as any;
          if (subMeta && subMeta.metadata_value) {
            const tracks = JSON.parse(subMeta.metadata_value);
            relativeIndex = tracks.findIndex((t: any) => t.index === subIndexNum);
            if (relativeIndex === -1) relativeIndex = 0;
            const track = tracks.find((t: any) => t.index === subIndexNum);
            const codecUp = (track?.codec || '').toUpperCase();
            if (track && (codecUp.includes('PGS') || codecUp.includes('HDMV') || codecUp.includes('DVD_SUBTITLE') || codecUp.includes('VOBSUB'))) {
              isText = false;
              isPgsSegment = true;
            }
          }
        } catch (e) {}

        ffmpegArgs = ffmpegArgs.filter(a => a !== '-sn');
        if (isText) {
           const escapedPath = item.file_path.replace(/\\/g, '\\\\').replace(/:/g, '\\:');
           ffmpegArgs.push('-vf', `subtitles='${escapedPath}':si=${relativeIndex}`);
        } else {
           // PGS: output-seek so subtitle timestamps align with the segment window
           const ssIdx = ffmpegArgs.indexOf('-ss');
           if (ssIdx >= 0) {
             const ssVal = ffmpegArgs[ssIdx + 1];
             ffmpegArgs.splice(ssIdx, 2);
             const iIdx = ffmpegArgs.indexOf('-i');
             if (iIdx >= 0) ffmpegArgs.splice(iIdx + 2, 0, '-ss', ssVal);
           }
           // Scale video and PGS bitmap to ≤1080p, overlay with format conversion
           ffmpegArgs.push(
             '-filter_complex',
             `[0:v]scale=1920:-2[vid];[0:s:${relativeIndex}]scale=1920:-2[sub];[vid][sub]overlay=format=auto[v]`,
             '-map', '[v]', '-map', '0:a'
           );
        }
      }

      ffmpegArgs.push(segmentPathTmp);

      reply.header('Content-Type', 'video/mp2t');
      reply.header('Access-Control-Allow-Origin', '*');

      const spawnStdio: any = isPgsSegment ? ['ignore', 'ignore', 'pipe'] : 'ignore';
      const ff = spawn(ffmpegInstaller.path, ffmpegArgs, { stdio: spawnStdio });
      if (isPgsSegment && ff.stderr) {
        ff.stderr.on('data', (d: Buffer) => process.stderr.write(`[PGS-seg] ${d}`));
      }
      
      return new Promise((resolve) => {
        ff.on('close', (code) => {
          _activeStreams = Math.max(0, _activeStreams - 1);
          if (fs.existsSync(segmentPathTmp) && fs.statSync(segmentPathTmp).size > 0) {
            fs.renameSync(segmentPathTmp, segmentPath);
            const stream = fs.createReadStream(segmentPath);
            resolve(stream);
          } else if (fs.existsSync(segmentPath)) {
            const stream = fs.createReadStream(segmentPath);
            resolve(stream);
          } else {
            reply.code(500);
            resolve('Segment failed');
          }
        });
        ff.on('error', () => { _activeStreams = Math.max(0, _activeStreams - 1); });
      });
    }
  );

  // GET /api/stream/warmup/:id — pre-generate first 2 HLS segments so playback starts instantly
  fastify.get(
    '/api/stream/warmup/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      let item = db.prepare('SELECT file_path FROM media_items WHERE id = ? AND deleted_at IS NULL').get(id) as any;
      if (!item) item = db.prepare('SELECT file_path, show_id FROM episodes WHERE id = ?').get(id) as any;
      if (!item || !fs.existsSync(item.file_path)) {
        return reply.code(404).send({ error: 'Not found' });
      }

      const sessionId = `hls_dynamic_${id}_4000k_none`;
      const sessionDir = path.join(HLS_CACHE_DIR, sessionId);

      reply.send({ ok: true, preloading: true });

      // Fire-and-forget: generate segments 0 and 1 in the background
      setImmediate(async () => {
        for (const segIndex of [0, 1]) {
          const segPath = path.join(sessionDir, `segment_${segIndex}.ts`);
          if (fs.existsSync(segPath) && fs.statSync(segPath).size > 0) continue;

          if (!fs.existsSync(sessionDir)) fs.mkdirSync(sessionDir, { recursive: true });
          const segPathTmp = segPath + '.tmp';
          const startTime = segIndex * 10;

          const ffArgs = [
            '-y', '-ss', startTime.toString(), '-t', '10',
            '-i', item.file_path,
            '-sn', '-c:v', 'libx264', '-preset', 'veryfast',
            '-b:v', '4000k', '-maxrate', '4000k', '-bufsize', '8000k',
            '-c:a', 'copy', '-f', 'mpegts', segPathTmp
          ];

          await new Promise<void>((res) => {
            const ff = spawn(ffmpegInstaller.path, ffArgs, { stdio: 'ignore' });
            ff.on('close', () => {
              if (fs.existsSync(segPathTmp) && fs.statSync(segPathTmp).size > 0) {
                try { fs.renameSync(segPathTmp, segPath); } catch (e) {}
              }
              res();
            });
          });
        }
      });
    }
  );
}
