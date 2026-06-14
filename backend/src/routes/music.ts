import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import fs from 'fs';
import path from 'path';
import db from '../config/database';
import { scanMusicLibrary } from '../services/soundtrack_scanner';

// ─── Types ───────────────────────────────────────────────────────────────────

interface TrackRow {
  id: string; title: string; artist: string; album: string; file_path: string;
  track_number: number; disc_number: number; duration_seconds: number;
  codec: string; bit_depth: number; sample_rate: number; replay_gain: number;
  album_id: string; soundtrack_movie_id: string;
}

interface AlbumRow {
  id: string; album_artist: string; title: string; year: number; genre: string;
  cover_path: string; discart_path: string; disc_count: number; local_path: string;
  linked_media_id: string; artist_id: string; musicbrainz_album_id: string;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatDuration(secs: number): string {
  if (!secs) return '0:00';
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function isHiRes(bitDepth: number | null, sampleRate: number | null): boolean {
  return (bitDepth != null && bitDepth > 16) || (sampleRate != null && sampleRate > 44100);
}

function albumCoverUrl(album: AlbumRow): string | null {
  if (album.cover_path) return album.cover_path;
  if (album.linked_media_id) {
    const media = db.prepare('SELECT poster_path FROM media_items WHERE id = ?').get(album.linked_media_id) as { poster_path: string } | undefined;
    if (media?.poster_path) return `https://image.tmdb.org/t/p/w500${media.poster_path}`;
  }
  return null;
}

// ─── Routes ──────────────────────────────────────────────────────────────────

export default async function musicRoutes(fastify: FastifyInstance) {

  // ── GET /api/music/albums ──────────────────────────────────────────────────
  fastify.get('/api/music/albums', async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      const { nav = 'albums', genre, year, artist_id } = request.query as Record<string, string>;

      let albums: AlbumRow[] = [];

      if (nav === 'years') {
        // return distinct years with album counts
        const rows = db.prepare(`
          SELECT year, COUNT(*) as album_count FROM music_albums WHERE year IS NOT NULL GROUP BY year ORDER BY year DESC
        `).all() as { year: number; album_count: number }[];
        return reply.send({ nav, years: rows });
      }

      if (nav === 'genres') {
        const rows = db.prepare(`
          SELECT genre, COUNT(*) as album_count FROM music_albums WHERE genre IS NOT NULL AND genre != '' GROUP BY genre ORDER BY genre ASC
        `).all() as { genre: string; album_count: number }[];
        return reply.send({ nav, genres: rows });
      }

      // Build WHERE clause
      const where: string[] = [];
      const params: (string | number)[] = [];

      if (genre) { where.push("LOWER(a.genre) = LOWER(?)"); params.push(genre); }
      if (year)  { where.push("a.year = ?");                params.push(parseInt(year)); }
      if (artist_id) { where.push("a.artist_id = ?");       params.push(artist_id); }

      if (nav === 'artists') {
        const rows = db.prepare(`
          SELECT ar.id, ar.name, ar.image_path,
            COUNT(DISTINCT al.id) as album_count,
            COUNT(DISTINCT t.id) as track_count
          FROM music_artists ar
          LEFT JOIN music_albums al ON al.artist_id = ar.id
          LEFT JOIN music_tracks t ON t.album_id = al.id
          GROUP BY ar.id ORDER BY ar.name ASC
        `).all() as any[];
        return reply.send({ nav, artists: rows });
      }

      if (nav === 'albumartists') {
        const rows = db.prepare(`
          SELECT album_artist, COUNT(*) as album_count, MIN(year) as first_year
          FROM music_albums GROUP BY LOWER(album_artist) ORDER BY album_artist ASC
        `).all() as any[];
        return reply.send({ nav, albumArtists: rows });
      }

      // Default: albums (with optional filters)
      const whereStr = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';
      albums = db.prepare(`
        SELECT a.*,
          COUNT(t.id) as track_count,
          SUM(t.duration_seconds) as total_duration,
          MAX(t.bit_depth) as max_bit_depth,
          MAX(t.sample_rate) as max_sample_rate
        FROM music_albums a
        LEFT JOIN music_tracks t ON t.album_id = a.id
        ${whereStr}
        GROUP BY a.id
        ORDER BY a.album_artist ASC, a.year DESC NULLS LAST, a.title ASC
      `).all(...params) as any[];

      const result = albums.map((album: any) => ({
        ...album,
        cover_url: albumCoverUrl(album as AlbumRow),
        is_hires: isHiRes(album.max_bit_depth, album.max_sample_rate),
        total_duration_formatted: formatDuration(album.total_duration || 0),
        linked_media: album.linked_media_id ? (() => {
          const m = db.prepare('SELECT id, title, poster_path FROM media_items WHERE id = ?').get(album.linked_media_id) as any;
          return m ? { id: m.id, title: m.title, poster_url: m.poster_path ? `https://image.tmdb.org/t/p/w500${m.poster_path}` : null } : null;
        })() : null,
      }));

      return reply.send({ nav, albums: result, total: result.length });
    } catch (err) {
      console.error('[Music] albums error:', err);
      return reply.code(500).send({ error: 'Failed to fetch music albums' });
    }
  });


  // ── GET /api/music/albums/:id ──────────────────────────────────────────────
  fastify.get('/api/music/albums/:id', async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      const { id } = request.params as { id: string };
      const album = db.prepare('SELECT * FROM music_albums WHERE id = ?').get(id) as AlbumRow | undefined;
      if (!album) return reply.code(404).send({ error: 'Album not found' });

      const tracks = db.prepare(`
        SELECT id, title, artist, track_number, disc_number, duration_seconds,
               codec, bit_depth, sample_rate, replay_gain, file_path
        FROM music_tracks WHERE album_id = ?
        ORDER BY disc_number ASC, track_number ASC, title ASC
      `).all(id) as TrackRow[];

      const artist = album.artist_id
        ? db.prepare('SELECT id, name, image_path FROM music_artists WHERE id = ?').get(album.artist_id) as any
        : null;

      let linkedMedia = null;
      if (album.linked_media_id) {
        linkedMedia = db.prepare('SELECT id, title, poster_path, fanart_path, year FROM media_items WHERE id = ?').get(album.linked_media_id) as any;
        if (linkedMedia?.poster_path) linkedMedia.poster_url = `https://image.tmdb.org/t/p/w500${linkedMedia.poster_path}`;
        if (linkedMedia?.fanart_path) linkedMedia.fanart_url = linkedMedia.fanart_path;
      }

      const tracksWithMeta = tracks.map(t => ({
        ...t,
        duration_formatted: formatDuration(t.duration_seconds || 0),
        is_hires: isHiRes(t.bit_depth, t.sample_rate),
        stream_url: `/api/music/stream/${t.id}`,
      }));

      const isHiResAlbum = tracks.some(t => isHiRes(t.bit_depth, t.sample_rate));

      return reply.send({
        ...album,
        cover_url: albumCoverUrl(album),
        is_hires: isHiResAlbum,
        artist,
        linked_media: linkedMedia,
        tracks: tracksWithMeta,
        track_count: tracks.length,
        total_duration: formatDuration(tracks.reduce((s, t) => s + (t.duration_seconds || 0), 0)),
      });
    } catch (err) {
      console.error('[Music] album/:id error:', err);
      return reply.code(500).send({ error: 'Failed to fetch album' });
    }
  });


  // ── GET /api/music/tracks ─────────────────────────────────────────────────
  fastify.get('/api/music/tracks', async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      const { album_id } = request.query as { album_id?: string };
      let tracks: any[];
      if (album_id) {
        tracks = db.prepare(`
          SELECT t.*, al.title as album_title, al.album_artist, al.cover_path,
                 al.linked_media_id, al.year as album_year
          FROM music_tracks t
          LEFT JOIN music_albums al ON al.id = t.album_id
          WHERE t.album_id = ?
          ORDER BY t.disc_number ASC, t.track_number ASC
        `).all(album_id) as any[];
      } else {
        tracks = db.prepare(`
          SELECT t.*, al.title as album_title, al.album_artist, al.cover_path,
                 al.linked_media_id, al.year as album_year
          FROM music_tracks t
          LEFT JOIN music_albums al ON al.id = t.album_id
          ORDER BY al.album_artist ASC, al.title ASC, t.disc_number ASC, t.track_number ASC
        `).all() as any[];
      }

      return reply.send({
        tracks: tracks.map(t => ({
          ...t,
          duration_formatted: formatDuration(t.duration_seconds || 0),
          is_hires: isHiRes(t.bit_depth, t.sample_rate),
          stream_url: `/api/music/stream/${t.id}`,
        })),
        total: tracks.length,
      });
    } catch (err) {
      console.error('[Music] tracks error:', err);
      return reply.code(500).send({ error: 'Failed to fetch tracks' });
    }
  });


  // ── GET /api/music/stream/:id ─────────────────────────────────────────────
  fastify.get('/api/music/stream/:id', async (request: FastifyRequest, reply: FastifyReply) => {
    try {
      const { id } = request.params as { id: string };
      const track = db.prepare('SELECT file_path FROM music_tracks WHERE id = ?').get(id) as { file_path: string } | undefined;
      if (!track) return reply.code(404).send({ error: 'Track not found' });

      const filePath = track.file_path;
      if (!fs.existsSync(filePath)) return reply.code(404).send({ error: 'File not found on disk' });

      const stat = fs.statSync(filePath);
      const ext = path.extname(filePath).toLowerCase();
      const mimeMap: Record<string, string> = {
        '.flac': 'audio/flac', '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4',
        '.aac': 'audio/aac',   '.ogg': 'audio/ogg',  '.wav': 'audio/wav',
        '.opus': 'audio/opus', '.wma': 'audio/x-ms-wma',
      };
      const mime = mimeMap[ext] || 'application/octet-stream';

      const rangeHeader = (request.headers as any)['range'] as string | undefined;
      if (rangeHeader) {
        const [startStr, endStr] = rangeHeader.replace('bytes=', '').split('-');
        const start = parseInt(startStr, 10);
        const end = endStr ? parseInt(endStr, 10) : stat.size - 1;
        const chunkSize = end - start + 1;
        reply.code(206).headers({
          'Content-Range': `bytes ${start}-${end}/${stat.size}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': chunkSize,
          'Content-Type': mime,
        });
        return reply.send(fs.createReadStream(filePath, { start, end }));
      }

      reply.headers({ 'Content-Length': stat.size, 'Content-Type': mime, 'Accept-Ranges': 'bytes' });
      return reply.send(fs.createReadStream(filePath));
    } catch (err) {
      console.error('[Music] stream error:', err);
      return reply.code(500).send({ error: 'Stream failed' });
    }
  });


  // ── POST /api/music/scan ─────────────────────────────────────────────────
  fastify.post('/api/music/scan', async (request: FastifyRequest, reply: FastifyReply) => {
    const { path: scanPath } = (request.body as any) || {};
    reply.send({ status: 'scanning', message: 'Music scan started in background' });
    scanMusicLibrary(scanPath || undefined).catch(e => console.error('[Music] scan error:', e));
  });


  // ── GET /api/music (overview / legacy) ───────────────────────────────────
  fastify.get('/api/music', async (_request: FastifyRequest, reply: FastifyReply) => {
    try {
      const albumCount  = (db.prepare('SELECT COUNT(*) as c FROM music_albums').get() as any).c;
      const artistCount = (db.prepare('SELECT COUNT(*) as c FROM music_artists').get() as any).c;
      const trackCount  = (db.prepare('SELECT COUNT(*) as c FROM music_tracks').get() as any).c;

      const recentAlbums = db.prepare(`
        SELECT a.id, a.title, a.album_artist, a.year, a.cover_path, a.linked_media_id,
               COUNT(t.id) as track_count
        FROM music_albums a
        LEFT JOIN music_tracks t ON t.album_id = a.id
        GROUP BY a.id ORDER BY a.added_at DESC LIMIT 12
      `).all() as any[];

      return reply.send({
        stats: { albumCount, artistCount, trackCount },
        recentAlbums: recentAlbums.map(a => ({ ...a, cover_url: albumCoverUrl(a as AlbumRow) })),
      });
    } catch (err) {
      console.error('[Music] overview error:', err);
      return reply.code(500).send({ error: 'Failed to fetch music overview' });
    }
  });
}
