import fs from 'fs';
import path from 'path';
import db from '../config/database';
import { v4 as uuidv4 } from 'uuid';

const AUDIO_EXTENSIONS = new Set(['.flac', '.mp3', '.m4a', '.aac', '.ogg', '.wav', '.alac', '.ape', '.opus', '.wma']);

interface TrackMeta {
  title: string;
  artist: string;
  albumArtist: string;
  album: string;
  trackNumber: number;
  discNumber: number;
  year: number | null;
  genre: string;
  durationSeconds: number;
  codec: string;
  bitDepth: number | null;
  sampleRate: number | null;
  replayGain: number | null;
  filePath: string;
}

async function parseAudioFile(filePath: string): Promise<TrackMeta> {
  const { parseFile } = await import('music-metadata');
  const metadata = await parseFile(filePath, { duration: true, skipCovers: true });
  const c = metadata.common;
  const f = metadata.format;

  return {
    title:        c.title                        || path.basename(filePath, path.extname(filePath)),
    artist:       (c.artist ?? c.artists?.[0]   ?? 'Unknown Artist').toString(),
    albumArtist:  (c.albumartist ?? c.artist    ?? 'Unknown Artist').toString(),
    album:        c.album                        || path.basename(path.dirname(filePath)),
    trackNumber:  c.track?.no                   ?? 0,
    discNumber:   c.disk?.no                    ?? 1,
    year:         c.year                        ?? null,
    genre:        c.genre?.[0]                  ?? '',
    durationSeconds: Math.round(f.duration      ?? 0),
    codec:        f.codec                        || path.extname(filePath).slice(1).toUpperCase(),
    bitDepth:     f.bitsPerSample               ?? null,
    sampleRate:   f.sampleRate                  ?? null,
    replayGain:   (f as any).trackGain          ?? null,
    filePath,
  };
}

function walkDirectory(dir: string): string[] {
  const files: string[] = [];
  try {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        files.push(...walkDirectory(full));
      } else if (AUDIO_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) {
        files.push(full);
      }
    }
  } catch (e) {
    console.error(`[Music Scanner] Cannot read dir ${dir}:`, e);
  }
  return files;
}

function tryLinkToMedia(albumDir: string, albumTitle: string): string | null {
  const dirName = path.basename(albumDir);
  // 1. IMDb ID in folder name: "Interstellar (2014) [tt0816692]"
  const imdbMatch = dirName.match(/(tt\d{7,8})/i);
  if (imdbMatch) {
    const row = db.prepare('SELECT id FROM media_items WHERE imdb_id = ? AND deleted_at IS NULL').get(imdbMatch[1]) as { id: string } | undefined;
    if (row) return row.id;
  }
  // 2. Fuzzy title match on album name (strip year/parentheses)
  const cleanTitle = albumTitle.replace(/\s*\(.*?\)\s*/g, '').trim();
  if (cleanTitle.length > 3) {
    const row = db.prepare(`SELECT id FROM media_items WHERE type='Movie' AND deleted_at IS NULL AND LOWER(title) LIKE LOWER(?) LIMIT 1`).get(`%${cleanTitle}%`) as { id: string } | undefined;
    if (row) return row.id;
  }
  return null;
}

function upsertArtist(name: string): string {
  const existing = db.prepare('SELECT id FROM music_artists WHERE LOWER(name) = LOWER(?)').get(name) as { id: string } | undefined;
  if (existing) return existing.id;
  const id = uuidv4();
  db.prepare('INSERT INTO music_artists (id, name) VALUES (?, ?)').run(id, name);
  return id;
}

function upsertAlbum(
  artistId: string,
  albumArtist: string,
  albumTitle: string,
  year: number | null,
  genre: string,
  localPath: string,
  discCount: number,
  linkedMediaId: string | null,
): string {
  const existing = db.prepare(
    'SELECT id FROM music_albums WHERE LOWER(album_artist) = LOWER(?) AND LOWER(title) = LOWER(?)'
  ).get(albumArtist, albumTitle) as { id: string } | undefined;

  if (existing) {
    db.prepare(`
      UPDATE music_albums SET year=?, genre=?, local_path=?, disc_count=?, linked_media_id=?, artist_id=? WHERE id=?
    `).run(year, genre, localPath, discCount, linkedMediaId, artistId, existing.id);
    return existing.id;
  }

  const id = uuidv4();
  db.prepare(`
    INSERT INTO music_albums (id, artist_id, album_artist, title, year, genre, local_path, disc_count, linked_media_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, artistId, albumArtist, albumTitle, year, genre, localPath, discCount, linkedMediaId);
  return id;
}

function upsertTrack(meta: TrackMeta, albumId: string, linkedMediaId: string | null) {
  const existing = db.prepare('SELECT id FROM music_tracks WHERE file_path = ?').get(meta.filePath) as { id: string } | undefined;
  if (existing) {
    db.prepare(`
      UPDATE music_tracks SET title=?, artist=?, album=?, track_number=?, disc_number=?,
        duration_seconds=?, codec=?, bit_depth=?, sample_rate=?, replay_gain=?, album_id=?,
        soundtrack_movie_id=? WHERE id=?
    `).run(meta.title, meta.artist, meta.album, meta.trackNumber, meta.discNumber,
          meta.durationSeconds, meta.codec, meta.bitDepth, meta.sampleRate, meta.replayGain,
          albumId, linkedMediaId, existing.id);
  } else {
    db.prepare(`
      INSERT INTO music_tracks (id, album_id, title, artist, album, file_path, track_number, disc_number,
        duration_seconds, codec, bit_depth, sample_rate, replay_gain, soundtrack_movie_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(uuidv4(), albumId, meta.title, meta.artist, meta.album, meta.filePath,
          meta.trackNumber, meta.discNumber, meta.durationSeconds, meta.codec,
          meta.bitDepth, meta.sampleRate, meta.replayGain, linkedMediaId);
  }
}

export async function scanMusicLibrary(rootPath?: string) {
  let scanPaths: string[];

  if (rootPath) {
    scanPaths = [rootPath];
  } else {
    const rows = db.prepare("SELECT path FROM library_paths WHERE type='Music'").all() as { path: string }[];
    scanPaths = rows.map(r => r.path);
  }

  if (scanPaths.length === 0) {
    console.log('[Music Scanner] No music library paths configured. Add a path in Settings → Bibliotek → Musik.');
    return { scanned: 0, albums: 0, artists: 0 };
  }

  let totalFiles = 0, totalAlbums = 0, totalArtists = new Set<string>();

  for (const scanPath of scanPaths) {
    if (!fs.existsSync(scanPath)) {
      console.warn(`[Music Scanner] Path not found: ${scanPath}`);
      continue;
    }

    console.log(`[Music Scanner] Scanning: ${scanPath}`);
    const audioFiles = walkDirectory(scanPath);
    console.log(`[Music Scanner] Found ${audioFiles.length} audio files`);

    // ── Group by albumArtist + album (primary key of an album) ──
    const albumGroups = new Map<string, TrackMeta[]>();

    for (const filePath of audioFiles) {
      try {
        const meta = await parseAudioFile(filePath);
        const key = `${meta.albumArtist.toLowerCase()}||${meta.album.toLowerCase()}`;
        if (!albumGroups.has(key)) albumGroups.set(key, []);
        albumGroups.get(key)!.push(meta);
        totalFiles++;
      } catch (e) {
        console.error(`[Music Scanner] Failed to parse ${filePath}:`, e);
      }
    }

    // ── Persist each album group ──
    for (const tracks of albumGroups.values()) {
      tracks.sort((a, b) => {
        if (a.discNumber !== b.discNumber) return a.discNumber - b.discNumber;
        return a.trackNumber - b.trackNumber;
      });

      const first = tracks[0];
      const discCount = Math.max(...tracks.map(t => t.discNumber || 1));
      const albumDir = path.dirname(first.filePath);
      const linkedMediaId = tryLinkToMedia(albumDir, first.album);

      const artistId = upsertArtist(first.albumArtist);
      totalArtists.add(first.albumArtist);

      const albumId = upsertAlbum(artistId, first.albumArtist, first.album, first.year, first.genre, albumDir, discCount, linkedMediaId);
      totalAlbums++;

      for (const track of tracks) {
        upsertTrack(track, albumId, linkedMediaId);
      }

      const hires = first.bitDepth && first.bitDepth > 16 ? ` [Hi-Res ${first.bitDepth}bit/${(first.sampleRate ?? 0) / 1000}kHz]` : '';
      console.log(`[Music Scanner] ✓ ${first.albumArtist} – ${first.album} (${tracks.length} tracks)${hires}`);
    }
  }

  console.log(`[Music Scanner] Complete. ${totalFiles} files → ${totalAlbums} albums, ${totalArtists.size} artists`);
  return { scanned: totalFiles, albums: totalAlbums, artists: totalArtists.size };
}

// Backward compatibility alias
export const scanSoundtracks = scanMusicLibrary;
