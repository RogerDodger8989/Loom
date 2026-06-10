import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';
import axios from 'axios';
import { tmdbService } from '../services/tmdb';
import { v4 as uuidv4 } from 'uuid';
import path from 'path';
import fs from 'fs';
import { exec } from 'child_process';
import ffprobeInstaller from '@ffprobe-installer/ffprobe';
import YTDlpWrap from 'yt-dlp-wrap';
import { syncExternalRatings, syncExternalWatchStatus } from '../services/rating_sync';

function computeTrashPath(filePath: string): string {
  const libraryPaths = db.prepare('SELECT path FROM library_paths').all() as Array<{ path: string }>;
  let libraryBase = '';
  for (const lp of libraryPaths) {
    const normalizedLp = lp.path.replace(/[/\\]+$/, '');
    if (filePath.startsWith(normalizedLp + path.sep) || filePath.startsWith(normalizedLp + '/')) {
      libraryBase = normalizedLp;
      break;
    }
  }
  if (!libraryBase) {
    libraryBase = path.dirname(path.dirname(filePath));
  }
  const relative = filePath.substring(libraryBase.length).replace(/^[/\\]/, '');
  return path.join(libraryBase, '.trash', relative);
}


interface MediaQueryParams {
  mergeVersions?: string; // 'true' or 'false'
}

function normalizeRatingValue(value: any): string | null {
  if (value === undefined || value === null) return null;
  const cleaned = value.toString().trim().replace(',', '.').replace(/[^0-9.]/g, '');
  if (!cleaned) return null;
  const parsed = Number.parseFloat(cleaned);
  return Number.isFinite(parsed) ? parsed.toString() : null;
}

function normalizeVotesValue(value: any): string | null {
  if (value === undefined || value === null) return null;
  const cleaned = value.toString().replace(/[^0-9]/g, '');
  if (!cleaned) return null;
  const parsed = Number.parseInt(cleaned, 10);
  return Number.isFinite(parsed) ? parsed.toString() : null;
}

function extractSimklId(payload: any): string | null {
  const candidates = [
    payload,
    payload?.movie,
    payload?.show,
    payload?.anime,
    payload?.item,
    payload?.data,
    payload?.result,
  ].filter(Boolean);

  for (const candidate of candidates) {
    const rawId = candidate?.ids?.simkl ?? candidate?.simkl ?? candidate?.simkl_id ?? candidate?.id;
    if (rawId === undefined || rawId === null) {
      continue;
    }

    const cleaned = rawId.toString().trim();
    if (!cleaned) {
      continue;
    }

    return cleaned;
  }

  return null;
}

function extractSimklRatings(payload: any): {
  simklRating: string | null;
  simklVotes: string | null;
} {
  const candidates = [
    payload,
    payload?.movie,
    payload?.show,
    payload?.anime,
    payload?.item,
    payload?.data,
    payload?.result,
  ].filter(Boolean);

  let simklRating: string | null = null;
  let simklVotes: string | null = null;

  for (const candidate of candidates) {
    const ratings = candidate?.ratings || {};

    simklRating = simklRating
      || normalizeRatingValue(ratings?.simkl?.rating)
      || normalizeRatingValue(ratings?.simkl_rating)
      || normalizeRatingValue(candidate?.simkl?.rating)
      || normalizeRatingValue(candidate?.simkl_rating)
      || normalizeRatingValue(candidate?.simklRating)
      || normalizeRatingValue(candidate?.rating);

    simklVotes = simklVotes
      || normalizeVotesValue(ratings?.simkl?.votes)
      || normalizeVotesValue(ratings?.simkl_votes)
      || normalizeVotesValue(candidate?.simkl?.votes)
      || normalizeVotesValue(candidate?.simkl_votes)
      || normalizeVotesValue(candidate?.simklVotes)
      || normalizeVotesValue(candidate?.votes);

    if (simklRating && simklVotes) {
      break;
    }
  }

  return {
    simklRating,
    simklVotes,
  };
}

function extractTraktRatings(payload: any): {
  traktRating: string | null;
  traktVotes: string | null;
} {
  const candidates = [
    payload,
    payload?.movie,
    payload?.show,
    payload?.anime,
    payload?.item,
    payload?.data,
    payload?.result,
  ].filter(Boolean);

  let simklRating: string | null = null;
  let simklVotes: string | null = null;
  let traktRating: string | null = null;
  let traktVotes: string | null = null;

  for (const candidate of candidates) {
    const ratings = candidate?.ratings || {};
    const nestedMovie = candidate?.movie || {};
    const nestedShow = candidate?.show || {};

    traktRating = traktRating
      || normalizeRatingValue(ratings?.trakt?.rating)
      || normalizeRatingValue(ratings?.trakt_rating)
      || normalizeRatingValue(candidate?.rating)
      || normalizeRatingValue(nestedMovie?.rating)
      || normalizeRatingValue(nestedShow?.rating)
      || normalizeRatingValue(candidate?.trakt?.rating)
      || normalizeRatingValue(candidate?.trakt_rating)
      || normalizeRatingValue(candidate?.traktRating);

    traktVotes = traktVotes
      || normalizeVotesValue(ratings?.trakt?.votes)
      || normalizeVotesValue(ratings?.trakt_votes)
      || normalizeVotesValue(candidate?.votes)
      || normalizeVotesValue(nestedMovie?.votes)
      || normalizeVotesValue(nestedShow?.votes)
      || normalizeVotesValue(candidate?.trakt?.votes)
      || normalizeVotesValue(candidate?.trakt_votes)
      || normalizeVotesValue(candidate?.traktVotes);

    if (traktRating && traktVotes) {
      break;
    }
  }

  return {
    traktRating,
    traktVotes,
  };
}

async function fetchTraktRatingsByImdb(imdbId: string, traktApiKey: string, mediaType: 'movie' | 'show'): Promise<{
  traktRating: string | null;
  traktVotes: string | null;
}> {
  const traktRes = await axios.get(`https://api.trakt.tv/search/imdb/${imdbId}`, {
    params: {
      type: mediaType,
      extended: 'full',
    },
    headers: {
      'trakt-api-key': traktApiKey,
      'trakt-api-version': '2',
      'User-Agent': 'Loom/1.0',
    },
  });

  const traktData = Array.isArray(traktRes.data) ? traktRes.data[0] : traktRes.data;
  return extractTraktRatings(traktData);
}

export default async function mediaRoutes(fastify: FastifyInstance) {
  const anonymousUser = { id: 'public', username: 'guest', role: 'user' };

  // GET /api/media/movies
  // Retrieves movies with automatic SQL-level content filtering based on user restrictions
  fastify.get(
    '/api/media/movies',
    async (request: FastifyRequest<{ Querystring: MediaQueryParams }>, reply: FastifyReply) => {
      const user = (request.user as { id: string; username: string; role: string } | undefined) ?? anonymousUser;
      const mergeVersions = request.query.mergeVersions !== 'false'; // Default to true (merged mode)

      try {
        // Query to get all movies that are NOT restricted for this user
        // Excludes matches on GENRE, RATING, or KEYWORD restriction patterns completely at the DB layer
        const moviesQuery = `
          SELECT mi.*, (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'last_watched_at') as last_watched_at FROM media_items mi
          WHERE mi.type = 'Movie'
          AND mi.deleted_at IS NULL
          AND mi.id NOT IN (
            SELECT mm.media_item_id 
            FROM media_metadata mm
            JOIN user_restrictions ur ON ur.user_id = ?
            WHERE 
              (ur.restriction_type = 'GENRE' AND mm.metadata_key = 'genre' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'RATING' AND mm.metadata_key = 'rating' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'KEYWORD' AND mm.metadata_key = 'keyword' AND mm.metadata_value LIKE '%' || ur.restriction_value || '%')
          )
        `;

        const rawMovies = db.prepare(moviesQuery).all(user.id) as Array<{
          id: string;
          title: string;
          type: string;
          tmdb_id: string | null;
          imdb_id: string | null;
          file_path: string;
          added_at: string;
          last_watched_at: string | null;
          poster_path: string | null;
          fanart_path: string | null;
          plot: string | null;
          year: number | null;
          genre: string | null;
        }>;

        // Fetch metadata for each movie
        const moviesWithMetadata = rawMovies.map(movie => {
          const metadataRows = db.prepare(`
            SELECT metadata_key, metadata_value 
            FROM media_metadata 
            WHERE media_item_id = ?
          `).all(movie.id) as Array<{ metadata_key: string; metadata_value: string }>;

          const metadata: Record<string, string> = {};
          metadataRows.forEach(row => {
            metadata[row.metadata_key] = row.metadata_value;
          });

          return {
            ...movie,
            metadata,
            resolution: metadata.resolution || metadata.video_resolution || null
          };
        });

        if (mergeVersions) {
          // Merged Mode: group movies by their TMDB ID or title if TMDB ID is missing
          const mergedMovies: Record<string, any> = {};

          moviesWithMetadata.forEach(movie => {
            const groupKey = movie.tmdb_id || movie.title;
            
            if (!mergedMovies[groupKey]) {
              mergedMovies[groupKey] = {
                id: movie.id,
                title: movie.title,
                type: movie.type,
                tmdb_id: movie.tmdb_id,
                imdb_id: movie.imdb_id,
                poster_path: movie.poster_path,
                fanart_path: movie.fanart_path,
                plot: movie.plot,
                year: movie.year,
                last_watched_at: movie.last_watched_at,
                genre: movie.genre || movie.metadata.genre || 'Movie',
                added_at: movie.added_at,
                is_favorite: (movie as any).is_favorite === 1,
                metadata: movie.metadata,
                versions: []
              };
            }

            mergedMovies[groupKey].versions.push({
              id: movie.id,
              file_path: movie.file_path,
              resolution: movie.resolution
            });
          });

          return reply.send(Object.values(mergedMovies));
        } else {
          // Separated Mode: Return items individually and add a clear visual badge indicator
          const badgedMovies = moviesWithMetadata.map(movie => ({
            ...movie,
            last_watched_at: movie.last_watched_at,
            resolution_badge: movie.resolution // e.g. "4K" or "1080p"
          }));

          return reply.send(badgedMovies);
        }
      } catch (err) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to retrieve movies' });
      }
    }
  );

  // POST /api/media/items/:id/metadata
  // Upsert a metadata key/value for a given media item (used to save user-specific state like ratings)
  fastify.post(
    '/api/media/items/:id/metadata',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { key: string; value: any } }>, reply: FastifyReply) => {
      const user = (request.user as { id: string; username: string; role: string } | undefined) ?? anonymousUser;
      const { id } = request.params;
      const { key, value } = request.body;

      try {
        const movie = db.prepare(`SELECT * FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!movie) return reply.code(404).send({ error: 'Media item not found' });

        // Upsert into media_metadata (use JSON-stringified value for complex objects)
        const stringVal = typeof value === 'string' ? value : JSON.stringify(value);
        db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, ?, ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run(uuidv4(), movie.id, key, stringVal);

        if (key === 'my_rating') {
          await syncExternalRatings(movie, value);
        }

        return reply.code(200).send({ ok: true });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to save metadata', details: err.message });
      }
    }
  );

  // GET /api/media/items/:id/metadata-state
  // Returns metadata values together with lock flags for editor UIs.
  fastify.get(
    '/api/media/items/:id/metadata-state',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      try {
        const item = db.prepare(`SELECT id FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!item) return reply.code(404).send({ error: 'Media item not found' });

        const rows = db.prepare(`
          SELECT metadata_key, metadata_value, is_locked
          FROM media_metadata
          WHERE media_item_id = ?
        `).all(id) as Array<{ metadata_key: string; metadata_value: string; is_locked: number }>;

        const metadata: Record<string, { value: any; is_locked: boolean }> = {};
        rows.forEach(row => {
          try {
            metadata[row.metadata_key] = { value: JSON.parse(row.metadata_value), is_locked: row.is_locked === 1 };
          } catch {
            metadata[row.metadata_key] = { value: row.metadata_value, is_locked: row.is_locked === 1 };
          }
        });

        return reply.send({ id, metadata });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to fetch metadata state', details: err.message });
      }
    }
  );

  // PUT /api/media/items/:id/metadata-lock
  // Toggle lock state for a single metadata key.
  fastify.put(
    '/api/media/items/:id/metadata-lock',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { key?: string; isLocked?: boolean } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const { key, isLocked } = request.body || {};

      if (!key) {
        return reply.code(400).send({ error: 'metadata key is required' });
      }

      try {
        const item = db.prepare(`SELECT id FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!item) return reply.code(404).send({ error: 'Media item not found' });

        const existing = db.prepare(`
          SELECT id FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?
        `).get(id, key) as { id: string } | undefined;

        if (!existing) {
          db.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value, is_locked)
            VALUES (?, ?, ?, ?, ?)
          `).run(uuidv4(), id, key, '', isLocked ? 1 : 0);
        } else {
          db.prepare(`
            UPDATE media_metadata
            SET is_locked = ?
            WHERE media_item_id = ? AND metadata_key = ?
          `).run(isLocked ? 1 : 0, id, key);
        }

        return reply.send({ ok: true });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to update metadata lock', details: err.message });
      }
    }
  );

  // PATCH /api/media/items/:id
  // Update core media_items fields used by the editor modal.
  fastify.patch(
    '/api/media/items/:id',
    async (request: FastifyRequest<{ Params: { id: string }; Body: Record<string, any> }>, reply: FastifyReply) => {
      const { id } = request.params;
      const body = request.body || {};

      try {
        const item = db.prepare(`SELECT id FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!item) return reply.code(404).send({ error: 'Media item not found' });

        const allowed = ['title', 'original_title', 'plot', 'genre', 'year', 'poster_path', 'fanart_path', 'director', 'collection_name', 'collection_id', 'imdb_id', 'tmdb_id'];
        const updates: string[] = [];
        const params: any[] = [];

        for (const key of allowed) {
          if (body[key] !== undefined) {
            updates.push(`${key} = ?`);
            if (key === 'year') {
              params.push(body[key] === '' || body[key] === null ? null : Number(body[key]));
            } else {
              params.push(body[key]);
            }
          }
        }

        if (updates.length === 0) {
          return reply.send({ ok: true, updated: 0 });
        }

        params.push(id);
        db.prepare(`UPDATE media_items SET ${updates.join(', ')} WHERE id = ?`).run(...params);

        return reply.send({ ok: true, updated: updates.length });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to update media item', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/seen
  // Toggle seen status for a given media item, update DB (media_metadata & watch_history) and sync to Trakt/Simkl
  fastify.post(
    '/api/media/items/:id/seen',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { watched?: boolean; isWatched?: boolean } }>, reply: FastifyReply) => {
      const user = (request.user as { id: string; username: string; role: string } | undefined) ?? anonymousUser;
      const { id } = request.params;
      const { watched, isWatched } = request.body || {};
      const isWatchedBool = watched !== undefined ? watched : (isWatched ?? true);

      try {
        const movie = db.prepare(`SELECT * FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!movie) return reply.code(404).send({ error: 'Media item not found' });

        const statusStr = isWatchedBool ? 'watched' : 'unwatched';

        // 1. Update media_metadata for watch_status
        db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
          VALUES (?, ?, 'watch_status', ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run(uuidv4(), movie.id, statusStr);

        // 2. Update watch_history to prevent duplicate rows for the same user & media item
        const existingHistory = db.prepare(`
          SELECT id FROM watch_history 
          WHERE user_id = ? AND media_item_id = ? AND episode_id IS NULL
        `).get(user.id, movie.id) as { id: string } | undefined;

        if (existingHistory) {
          db.prepare(`
            UPDATE watch_history 
            SET is_watched = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `).run(isWatchedBool ? 1 : 0, existingHistory.id);
        } else {
          db.prepare(`
            INSERT INTO watch_history (id, user_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
            VALUES (?, ?, ?, 0, 0, ?, CURRENT_TIMESTAMP)
          `).run(uuidv4(), user.id, movie.id, isWatchedBool ? 1 : 0);
        }

        // 3. Sync to external APIs in background
        syncExternalWatchStatus(movie, isWatchedBool).catch(err => {
          console.error('[Seen Route] syncExternalWatchStatus failed:', err);
        });

        return reply.code(200).send({ ok: true, watch_status: statusStr });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to update seen status', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/favorite
  // Toggle favorite/protected status. For Shows, all episodes inherit the flag.
  fastify.post(
    '/api/media/items/:id/favorite',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { is_favorite?: boolean } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        const item = db.prepare(`SELECT id, type, is_favorite FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!item) return reply.code(404).send({ error: 'Media item not found' });

        const newVal = request.body?.is_favorite !== undefined
          ? (request.body.is_favorite ? 1 : 0)
          : (item.is_favorite ? 0 : 1);

        db.prepare(`UPDATE media_items SET is_favorite = ? WHERE id = ?`).run(newVal, id);

        return reply.code(200).send({ ok: true, is_favorite: newVal === 1 });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to toggle favorite', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/season/:season/favorite
  // Toggle favorite for a specific season of a TV show (stored as metadata).
  fastify.post(
    '/api/media/items/:id/season/:season/favorite',
    async (request: FastifyRequest<{ Params: { id: string; season: string }; Body: { is_favorite?: boolean } }>, reply: FastifyReply) => {
      const { id, season } = request.params;
      try {
        const item = db.prepare(`SELECT id FROM media_items WHERE id = ? AND type = 'Show' AND deleted_at IS NULL`).get(id) as any;
        if (!item) return reply.code(404).send({ error: 'Show not found' });

        const key = `season_${season}_favorite`;
        const existing = db.prepare(`SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?`).get(id, key) as any;
        const currentVal = existing?.metadata_value === '1';
        const newVal = request.body?.is_favorite !== undefined ? request.body.is_favorite : !currentVal;

        db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run(uuidv4(), id, key, newVal ? '1' : '0');

        return reply.code(200).send({ ok: true, is_favorite: newVal });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to toggle season favorite', details: err.message });
      }
    }
  );

  // POST /api/media/episodes/:episodeId/progress
  // Save episode playback progress; also bubbles up last_watched_at to the parent show
  fastify.post(
    '/api/media/episodes/:episodeId/progress',
    async (request: FastifyRequest<{ Params: { episodeId: string }; Body: { position?: number; duration?: number; positionSeconds?: number; durationSeconds?: number } }>, reply: FastifyReply) => {
      const user = (request.user as { id: string; username: string; role: string } | undefined) ?? anonymousUser;
      const { episodeId } = request.params;
      const { position, duration, positionSeconds, durationSeconds } = request.body || {};

      const posSec = positionSeconds !== undefined ? positionSeconds : (position ?? 0);
      const durSec = durationSeconds !== undefined ? durationSeconds : (duration ?? 0);

      if (durSec <= 0) return reply.code(400).send({ error: 'Duration must be greater than 0' });

      try {
        const episode = db.prepare(`SELECT * FROM episodes WHERE id = ? AND (deleted_at IS NULL OR deleted_at = '')`).get(episodeId) as any;
        if (!episode) return reply.code(404).send({ error: 'Episode not found' });

        const progressPercent = posSec / durSec;
        const autoWatch = progressPercent >= 0.90;

        // Upsert watch_history for this episode
        const existing = db.prepare(`
          SELECT id FROM watch_history WHERE user_id = ? AND episode_id = ?
        `).get(user.id, episodeId) as any;
        if (existing) {
          db.prepare(`
            UPDATE watch_history
            SET last_position_seconds = ?, total_duration_seconds = ?, is_watched = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `).run(posSec, durSec, autoWatch ? 1 : 0, existing.id);
        } else {
          db.prepare(`
            INSERT INTO watch_history (id, user_id, episode_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
          `).run(uuidv4(), user.id, episodeId, episode.show_id, posSec, durSec, autoWatch ? 1 : 0);
        }

        // Bubble up to parent show's media_metadata so continue-watching works
        const upsertMeta = db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `);
        if (posSec >= 60) {
          upsertMeta.run(uuidv4(), episode.show_id, 'last_watched_at', new Date().toISOString());
        }
        upsertMeta.run(uuidv4(), episode.show_id, 'last_watched_episode_id', episodeId);
        upsertMeta.run(uuidv4(), episode.show_id, 'playback_progress', posSec.toString());
        upsertMeta.run(uuidv4(), episode.show_id, 'duration', durSec.toString());

        return reply.code(200).send({ ok: true, position: posSec, duration: durSec, is_watched: autoWatch });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to update episode progress', details: err.message });
      }
    }
  );

  // GET /api/media/episodes/:episodeId/status
  fastify.get(
    '/api/media/episodes/:episodeId/status',
    async (request: FastifyRequest<{ Params: { episodeId: string } }>, reply: FastifyReply) => {
      const user = (request.user as { id: string } | undefined) ?? anonymousUser;
      const { episodeId } = request.params;
      try {
        const ep = db.prepare(`SELECT id FROM episodes WHERE id = ?`).get(episodeId) as any;
        if (!ep) return reply.code(404).send({ error: 'Episode not found' });
        const wh = db.prepare(`SELECT is_watched, last_position_seconds FROM watch_history WHERE user_id = ? AND episode_id = ?`).get(user.id, episodeId) as any;
        return reply.send({
          is_watched:        wh ? wh.is_watched === 1 : false,
          playback_progress: wh ? wh.last_position_seconds : 0,
        });
      } catch (err: any) {
        return reply.code(500).send({ error: err.message });
      }
    }
  );

  // POST /api/media/episodes/:episodeId/seen
  // Toggle watched status for a single episode
  fastify.post(
    '/api/media/episodes/:episodeId/seen',
    async (request: FastifyRequest<{ Params: { episodeId: string }; Body: { watched: boolean } }>, reply: FastifyReply) => {
      const user = (request.user as { id: string; username: string; role: string } | undefined) ?? anonymousUser;
      const { episodeId } = request.params;
      const { watched } = request.body || {};

      try {
        const episode = db.prepare(`SELECT * FROM episodes WHERE id = ?`).get(episodeId) as any;
        if (!episode) return reply.code(404).send({ error: 'Episode not found' });

        const existing = db.prepare(`SELECT id, total_duration_seconds FROM watch_history WHERE user_id = ? AND episode_id = ?`).get(user.id, episodeId) as any;
        if (existing) {
          db.prepare(`
            UPDATE watch_history SET is_watched = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
          `).run(watched ? 1 : 0, existing.id);
        } else {
          db.prepare(`
            INSERT INTO watch_history (id, user_id, episode_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
            VALUES (?, ?, ?, ?, 0, 0, ?, CURRENT_TIMESTAMP)
          `).run(uuidv4(), user.id, episodeId, episode.show_id, watched ? 1 : 0);
        }

        return reply.code(200).send({ ok: true, is_watched: watched });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to toggle episode seen', details: err.message });
      }
    }
  );

  // POST /api/media/items/:showId/season/:season/seen
  // Mark all episodes in a season as watched or unwatched
  fastify.post(
    '/api/media/items/:showId/season/:season/seen',
    async (request: FastifyRequest<{ Params: { showId: string; season: string }; Body: { watched: boolean } }>, reply: FastifyReply) => {
      const user = (request.user as { id: string; username: string; role: string } | undefined) ?? anonymousUser;
      const { showId, season } = request.params;
      const { watched } = request.body || {};
      const seasonNum = parseInt(season, 10);

      try {
        const episodes = db.prepare(`SELECT id FROM episodes WHERE show_id = ? AND season_number = ?`).all(showId, seasonNum) as Array<{ id: string }>;
        for (const ep of episodes) {
          const existingEp = db.prepare(`SELECT id FROM watch_history WHERE user_id = ? AND episode_id = ?`).get(user.id, ep.id) as any;
          if (existingEp) {
            db.prepare(`UPDATE watch_history SET is_watched = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`).run(watched ? 1 : 0, existingEp.id);
          } else {
            db.prepare(`
              INSERT INTO watch_history (id, user_id, episode_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
              VALUES (?, ?, ?, ?, 0, 0, ?, CURRENT_TIMESTAMP)
            `).run(uuidv4(), user.id, ep.id, showId, watched ? 1 : 0);
          }
        }
        return reply.code(200).send({ ok: true, count: episodes.length });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to mark season', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/progress
  // Save play progress (heartbeat/scrobbling) and toggle watched state if progress is >= 90%
  fastify.post(
    '/api/media/items/:id/progress',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { position?: number; duration?: number; positionSeconds?: number; durationSeconds?: number } }>, reply: FastifyReply) => {
      const user = (request.user as { id: string; username: string; role: string } | undefined) ?? anonymousUser;
      const { id } = request.params;
      const { position, duration, positionSeconds, durationSeconds } = request.body || {};

      const posSec = positionSeconds !== undefined ? positionSeconds : (position ?? 0);
      const durSec = durationSeconds !== undefined ? durationSeconds : (duration ?? 0);

      if (durSec <= 0) {
        return reply.code(400).send({ error: 'Duration must be greater than 0' });
      }

      try {
        // Auto-detect: if the ID belongs to an episode, delegate to episode logic
        const movieCheck = db.prepare(`SELECT * FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!movieCheck) {
          const ep = db.prepare(`SELECT * FROM episodes WHERE id = ?`).get(id) as any;
          if (ep) {
            const pct = posSec / durSec;
            const aw = pct >= 0.90;
            const exEp = db.prepare(`SELECT id FROM watch_history WHERE user_id = ? AND episode_id = ?`).get(user.id, id) as any;
            if (exEp) {
              db.prepare(`UPDATE watch_history SET last_position_seconds=?,total_duration_seconds=?,is_watched=?,updated_at=CURRENT_TIMESTAMP WHERE id=?`).run(posSec, durSec, aw ? 1 : 0, exEp.id);
            } else {
              db.prepare(`INSERT INTO watch_history(id,user_id,episode_id,media_item_id,last_position_seconds,total_duration_seconds,is_watched,updated_at)VALUES(?,?,?,?,?,?,?,CURRENT_TIMESTAMP)`).run(uuidv4(), user.id, id, ep.show_id, posSec, durSec, aw ? 1 : 0);
            }
            const um = db.prepare(`INSERT INTO media_metadata(id,media_item_id,metadata_key,metadata_value)VALUES(?,?,?,?)ON CONFLICT(media_item_id,metadata_key)DO UPDATE SET metadata_value=excluded.metadata_value`);
            if (posSec >= 60) um.run(uuidv4(), ep.show_id, 'last_watched_at', new Date().toISOString());
            um.run(uuidv4(), ep.show_id, 'last_watched_episode_id', id);
            um.run(uuidv4(), ep.show_id, 'playback_progress', posSec.toString());
            um.run(uuidv4(), ep.show_id, 'duration', durSec.toString());
            return reply.code(200).send({ ok: true, position: posSec, duration: durSec, watch_status: aw ? 'watched' : 'in_progress' });
          }
          return reply.code(404).send({ error: 'Media item not found' });
        }
        const movie = movieCheck;

        const progressPercent = posSec / durSec;
        const autoWatch = progressPercent >= 0.90;

        // 1. Update playback_progress and duration in media_metadata
        db.prepare(`
          INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
          VALUES (?, ?, 'playback_progress', ?)
          ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
        `).run(uuidv4(), movie.id, posSec.toString());

        // Track last_watched_at only once user has watched ≥ 60 seconds
        if (posSec >= 60) {
          db.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
            VALUES (?, ?, 'last_watched_at', datetime('now'))
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run(uuidv4(), movie.id);
        }

        if (durSec > 0) {
          db.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
            VALUES (?, ?, 'duration', ?)
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run(uuidv4(), movie.id, durSec.toString());
        }

        // 2. If >= 90%, update watch_status and record exact completion time
        let currentStatus = 'unwatched';
        if (autoWatch) {
          currentStatus = 'watched';
          db.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
            VALUES (?, ?, 'watch_status', 'watched')
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run(uuidv4(), movie.id);
          // watch_completed_at = when the film was finished; used to sort "Nyligen sedda"
          db.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
            VALUES (?, ?, 'watch_completed_at', datetime('now'))
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run(uuidv4(), movie.id);
        }

        // 3. Update watch_history (best-effort — may fail for anonymous users lacking a users row)
        try {
          const existingHistory = db.prepare(`
            SELECT id FROM watch_history
            WHERE user_id = ? AND media_item_id = ? AND episode_id IS NULL
          `).get(user.id, movie.id) as { id: string } | undefined;

          if (existingHistory) {
            db.prepare(`
              UPDATE watch_history
              SET last_position_seconds = ?, total_duration_seconds = ?, is_watched = ?, updated_at = CURRENT_TIMESTAMP
              WHERE id = ?
            `).run(posSec, durSec, autoWatch ? 1 : 0, existingHistory.id);
          } else {
            db.prepare(`
              INSERT INTO watch_history (id, user_id, media_item_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            `).run(uuidv4(), user.id, movie.id, posSec, durSec, autoWatch ? 1 : 0);
          }
        } catch (histErr: any) {
          request.log.warn(`[Progress] watch_history skipped: ${histErr.message}`);
        }

        // 4. Sync to Trakt/Simkl if threshold met
        if (autoWatch) {
          syncExternalWatchStatus(movie, true).catch(err => {
            console.error('[Progress Route] syncExternalWatchStatus failed:', err);
          });
        }

        return reply.code(200).send({ ok: true, position: posSec, duration: durSec, watch_status: currentStatus });
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to update progress', details: err.message });
      }
    }
  );


  // GET /api/media/items/:id
  // Retrieves full details for a specific media item (Loom Media Details page)
  fastify.get(
    '/api/media/items/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const user = (request.user as { id: string; username: string; role: string } | undefined) ?? anonymousUser;
      const { id } = request.params;

      try {
        if (id.startsWith('external_')) {
          const parts = id.split('_');
          const extType = parts[1]; // 'movie' or 'show'
          const tmdbId = parts[2];
          const type = extType.toLowerCase() === 'show' ? 'Show' : 'Movie';

          try {
            let tmdbData: any;
            if (type === 'Show') {
              tmdbData = await tmdbService.fetchShowById(tmdbId);
            } else {
              tmdbData = await tmdbService.fetchMovieById(tmdbId);
            }

            if (!tmdbData) {
              return reply.code(404).send({ error: 'External media not found' });
            }

            // Check if this item is in the local watchlist
            const watchlistRow = db.prepare(`SELECT status FROM watchlist WHERE tmdb_id = ?`).get(tmdbId) as any;
            const isInWatchlist = !!watchlistRow;
            const watchlistStatus = watchlistRow?.status || null;

            // Check if we already have it in the library
            const localItem = db.prepare(`SELECT id FROM media_items WHERE tmdb_id = ? AND deleted_at IS NULL`).get(tmdbId) as any;

            // Local metadata (if movie already exists in library)
            const localMetaRows = localItem
              ? db.prepare(`
                  SELECT metadata_key, metadata_value
                  FROM media_metadata
                  WHERE media_item_id = ?
                    AND metadata_key IN ('my_rating', 'watch_status', 'playback_progress')
                `).all(localItem.id) as Array<{ metadata_key: string; metadata_value: string }>
              : [];
            const localMeta: Record<string, string> = {};
            for (const row of localMetaRows) {
              localMeta[row.metadata_key] = row.metadata_value;
            }

            // Synced external metadata (for movies not in local library)
            const externalState = db.prepare(`
              SELECT my_rating, watch_status
              FROM external_media_state
              WHERE (tmdb_id = ? AND tmdb_id IS NOT NULL)
                 OR (imdb_id = ? AND imdb_id IS NOT NULL)
              ORDER BY updated_at DESC
              LIMIT 1
            `).get(
              tmdbId,
              tmdbData.external_ids?.imdb_id || tmdbData.imdb_id || null,
            ) as { my_rating?: string | null; watch_status?: string | null } | undefined;

            // Map credits
            const castList = (tmdbData.credits?.cast || []).map((c: any) => ({
              ...c,
              profile_path: c.profile_path ? tmdbService.getImageUrl(c.profile_path, 'w500') : null,
            }));
            const crewList = (tmdbData.credits?.crew || []).map((c: any) => ({
              ...c,
              profile_path: c.profile_path ? tmdbService.getImageUrl(c.profile_path, 'w500') : null,
            }));
            const directorItem = crewList.find((c: any) => c.job === 'Director');
            const genresList = (tmdbData.genres || []).map((g: any) => g.name);
            const imdbId = tmdbData.external_ids?.imdb_id || tmdbData.imdb_id || null;

            const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
            const traktApiKey = tmdbService.getSetting('TRAKT_API_KEY');

            let simklRating: string | null = null;
            let simklVotes: string | null = null;
            let traktRating: string | null = null;
            let traktVotes: string | null = null;

            if (simklClientId && imdbId) {
              try {
                const simklLookupRes = await axios.get(`https://api.simkl.com/search/id`, {
                  params: { imdb: imdbId, client_id: simklClientId }
                });
                const simklLookupData = Array.isArray(simklLookupRes.data)
                  ? simklLookupRes.data[0]
                  : simklLookupRes.data;
                const simklId = extractSimklId(simklLookupData);

                if (simklId) {
                  const simklRatingsRes = await axios.get(`https://api.simkl.com/ratings`, {
                    params: {
                      simkl: simklId,
                      fields: 'rank,droprate,simkl,ext,has_trailer,reactions,year',
                      client_id: simklClientId,
                    }
                  });
                  const parsedSimklRatings = extractSimklRatings(simklRatingsRes.data);
                  simklRating = parsedSimklRatings.simklRating;
                  simklVotes = parsedSimklRatings.simklVotes;
                }
              } catch (simklErr) {
                console.error('[External Media Details] Simkl ratings fetch failed:', simklErr);
              }
            }

            if (traktApiKey && imdbId) {
              try {
                const mediaType = type === 'Show' ? 'show' : 'movie';
                const parsedTraktRatings = await fetchTraktRatingsByImdb(imdbId, traktApiKey, mediaType);
                traktRating = parsedTraktRatings.traktRating;
                traktVotes = parsedTraktRatings.traktVotes;
              } catch (traktErr) {
                console.error('[External Media Details] Trakt ratings fetch failed:', traktErr);
              }
            }

            let imdbRating: string | null = null;
            let imdbVotes: string | null = null;
            const omdbKey = tmdbService.getSetting('OMDB_API_KEY');
            if (omdbKey && imdbId) {
              try {
                const omdbRes = await axios.get(`http://www.omdbapi.com/`, {
                  params: { apikey: omdbKey, i: imdbId }
                });
                if (omdbRes.data?.imdbRating && omdbRes.data.imdbRating !== 'N/A') {
                  imdbRating = omdbRes.data.imdbRating;
                }
                if (omdbRes.data?.imdbVotes && omdbRes.data.imdbVotes !== 'N/A') {
                  imdbVotes = omdbRes.data.imdbVotes;
                }
              } catch (omdbErr) {
                console.error('[External Media Details] OMDb ratings fetch failed:', omdbErr);
              }
            }

            const mergedMyRating = localMeta.my_rating ?? externalState?.my_rating ?? '0';
            const mergedWatchStatus = localMeta.watch_status ?? externalState?.watch_status ?? 'unwatched';
            const mergedProgress = localMeta.playback_progress ?? '0';

            const externalProducers = crewList
              .filter((c: any) => c.job === 'Producer' || c.job === 'Executive Producer')
              .slice(0, 3)
              .map((c: any) => ({ id: c.id?.toString() ?? null, name: c.name, job: c.job }));
            const externalWriters = crewList
              .filter((c: any) => c.department === 'Writing')
              .slice(0, 3)
              .map((c: any) => ({ id: c.id?.toString() ?? null, name: c.name, job: c.job }));
            const externalComposers = crewList
              .filter((c: any) => c.job === 'Original Music Composer' || c.department === 'Sound')
              .slice(0, 2)
              .map((c: any) => ({ id: c.id?.toString() ?? null, name: c.name, job: c.job }));

            const metadata: any = {
              tagline: tmdbData.tagline || '',
              keywords: (tmdbData.keywords?.keywords || tmdbData.keywords?.results || []).map((k: any) => k.name),
              production_companies: (tmdbData.production_companies || []).map((c: any) => ({
                id: c.id,
                name: c.name,
                logo_path: c.logo_path ? tmdbService.getImageUrl(c.logo_path, 'w500') : null,
                origin_country: c.origin_country || null
              })),
              production_countries: (tmdbData.production_countries || []),
              director: directorItem ? { name: directorItem.name, id: directorItem.id?.toString() ?? null } : null,
              writer: crewList.find((c: any) => c.department === 'Writing')?.name || '',
              producers: externalProducers,
              writers: externalWriters,
              composers: externalComposers,
              runtime: tmdbData.runtime || tmdbData.episode_run_time?.[0] || 0,
              cast: castList,
              crew: crewList,
              logo_path: tmdbData.logo_path ? tmdbService.getImageUrl(tmdbData.logo_path, 'w500') : null,
              trailer_url: tmdbData.trailer_url || '',
              ratings: {
                tmdb: tmdbData.vote_average ?? null,
                tmdb_votes: tmdbData.vote_count ?? null,
                simkl: simklRating,
                simkl_votes: simklVotes,
                trakt: traktRating,
                trakt_votes: traktVotes,
              },
              imdb_rating: imdbRating,
              imdb_votes: imdbVotes,
              simkl_rating: simklRating ?? 'N/A',
              simkl_votes: simklVotes,
              trakt_rating: traktRating ?? 'N/A',
              trakt_votes: traktVotes,
              my_rating: mergedMyRating,
              watch_status: mergedWatchStatus,
              playback_progress: mergedProgress,
              'watch/providers': tmdbData['watch/providers'] || null,
              status: tmdbData.status,
              next_episode_to_air: tmdbData.next_episode_to_air,
              last_air_date: tmdbData.last_air_date,
              number_of_seasons: tmdbData.number_of_seasons,
              number_of_episodes: tmdbData.number_of_episodes,
            };

            return reply.send({
              id: id,
              title: tmdbData.title || tmdbData.name || 'Unknown',
              type: type,
              plot: tmdbData.overview || '',
              year: tmdbData.release_date
                ? parseInt(tmdbData.release_date.substring(0, 4), 10)
                : (tmdbData.first_air_date ? parseInt(tmdbData.first_air_date.substring(0, 4), 10) : null),
              genre: genresList.join(', ') || type,
              poster_path: tmdbData.poster_path ? tmdbService.getImageUrl(tmdbData.poster_path, 'w500') : null,
              fanart_path: tmdbData.backdrop_path ? tmdbService.getImageUrl(tmdbData.backdrop_path, 'original') : null,
              tmdb_id: tmdbId,
              imdb_id: imdbId,
              collection_name: tmdbData.belongs_to_collection?.name || null,
              collection_id: tmdbData.belongs_to_collection?.id?.toString() || null,
              director: directorItem ? { name: directorItem.name, id: directorItem.id?.toString() ?? null } : null,
              original_title: tmdbData.original_title || tmdbData.original_name || null,
              file_path: null, // Signals not in library
              added_at: new Date().toISOString(),
              is_in_watchlist: isInWatchlist,
              watchlist_status: watchlistStatus,
              local_id: localItem?.id || null,
              metadata: metadata,
              versions: []
            });
          } catch (error: any) {
            request.log.error(error);
            return reply.code(500).send({ error: 'Failed to fetch external media details', details: error.message });
          }
        }

        // Fetch base media item (exclude soft-deleted)
        const movie = db.prepare(`SELECT * FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!movie) {
          return reply.code(404).send({ error: 'Media item not found' });
        }

        // Check user restrictions (if restricted, return 403)
        const restrictions = db.prepare(`
          SELECT ur.restriction_type, ur.restriction_value
          FROM user_restrictions ur
          WHERE ur.user_id = ?
        `).all(user.id) as any[];

        // Fetch metadata
        const metadataRows = db.prepare(`
          SELECT metadata_key, metadata_value 
          FROM media_metadata 
          WHERE media_item_id = ?
        `).all(movie.id) as Array<{ metadata_key: string; metadata_value: string }>;

        const metadata: Record<string, any> = {};
        metadataRows.forEach(row => {
          try {
            // Try to parse JSON for cast/ratings
            metadata[row.metadata_key] = JSON.parse(row.metadata_value);
          } catch (e) {
            metadata[row.metadata_key] = row.metadata_value;
          }
        });

        const upsertMeta = (key: string, value: string) => {
          db.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
            VALUES (?, ?, ?, ?)
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run(uuidv4(), movie.id, key, value);
        };

        const awardsPlaceholder = 'Inga prisuppgifter hittades.';
        const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
        const traktApiKey = tmdbService.getSetting('TRAKT_API_KEY');
        const needsEnrichment = !metadata.tagline || !metadata.keywords || !metadata.production_companies || !metadata.production_countries || !metadata.awards || metadata.awards === awardsPlaceholder || !metadata.director || !metadata.logo_path || !metadata.imdb_rating || !metadata.trailer_url || (simklClientId && (!metadata.simkl_rating || !metadata.trakt_rating));
        
        console.log('[Media Details] Diagnostic check for:', movie.title, {
          needsEnrichment,
          hasImdbRating: Boolean(metadata.imdb_rating),
          hasSimklRating: Boolean(metadata.simkl_rating),
          hasTraktRating: Boolean(metadata.trakt_rating),
          simklClientId: simklClientId ? 'PRESENT' : 'MISSING',
          traktApiKey: traktApiKey ? 'PRESENT' : 'MISSING',
          imdbIdInDb: movie.imdb_id || 'MISSING'
        });

        if (needsEnrichment) {
          const isShowType = movie.type?.toString() === 'Show';
          const tmdbData = movie.tmdb_id
            ? (isShowType
                ? await tmdbService.fetchShowById(movie.tmdb_id.toString())
                : await tmdbService.fetchMovieById(movie.tmdb_id.toString()))
            : await tmdbService.searchMovie(movie.title, movie.year ?? undefined);
          if (tmdbData) {
            if (!movie.original_title && tmdbData.original_title) {
              db.prepare(`UPDATE media_items SET original_title = ? WHERE id = ?`).run(tmdbData.original_title, movie.id);
              movie.original_title = tmdbData.original_title;
            }

            if (!metadata.tagline && tmdbData.tagline) {
              metadata.tagline = tmdbData.tagline;
              upsertMeta('tagline', tmdbData.tagline);
            }

            if (!metadata.keywords) {
              const rawKw = tmdbData.keywords?.keywords || tmdbData.keywords?.results || [];
              if (rawKw.length > 0) {
                const keywords = rawKw.map((keyword: any) => keyword.name);
                metadata.keywords = keywords;
                upsertMeta('keywords', JSON.stringify(keywords));
              }
            }

            if (!metadata.production_companies && tmdbData.production_companies) {
              const companies = tmdbData.production_companies
                .filter((company: any) => company && company.name)
                .slice(0, 2)
                .map((company: any) => ({
                id: company.id,
                name: company.name,
                logo_path: company.logo_path ? tmdbService.getImageUrl(company.logo_path, 'w500') : null,
                origin_country: company.origin_country || null
              }));
              metadata.production_companies = companies;
              upsertMeta('production_companies', JSON.stringify(companies));
            }

            if (!metadata.production_countries && tmdbData.production_countries) {
              const countries = tmdbData.production_countries.map((country: any) => ({
                iso_3166_1: country.iso_3166_1,
                name: country.name
              }));
              metadata.production_countries = countries;
              upsertMeta('production_countries', JSON.stringify(countries));
            }

            if (!metadata.director && tmdbData.credits && tmdbData.credits.crew) {
              const dirObj = tmdbData.credits.crew.find((c: any) => c.job === 'Director');
              if (dirObj) {
                const directorData = { id: dirObj.id, name: dirObj.name };
                metadata.director = directorData;
                upsertMeta('director', JSON.stringify(directorData));
              }
            }

            if (!metadata.producers && tmdbData.credits && tmdbData.credits.crew) {
              const producerList = tmdbData.credits.crew
                .filter((c: any) => c.job === 'Producer' || c.job === 'Executive Producer')
                .slice(0, 3)
                .map((c: any) => ({ id: c.id, name: c.name, job: c.job }));
              if (producerList.length > 0) {
                metadata.producers = producerList;
                upsertMeta('producers', JSON.stringify(producerList));
              }
            }

            if (!metadata.writers && tmdbData.credits && tmdbData.credits.crew) {
              const writerList = tmdbData.credits.crew
                .filter((c: any) => c.department === 'Writing')
                .slice(0, 3)
                .map((c: any) => ({ id: c.id, name: c.name, job: c.job }));
              if (writerList.length > 0) {
                metadata.writers = writerList;
                upsertMeta('writers', JSON.stringify(writerList));
              }
            }

            if (!metadata.composers && tmdbData.credits && tmdbData.credits.crew) {
              const composerList = tmdbData.credits.crew
                .filter((c: any) => c.job === 'Original Music Composer' || c.department === 'Sound')
                .slice(0, 2)
                .map((c: any) => ({ id: c.id, name: c.name, job: c.job }));
              if (composerList.length > 0) {
                metadata.composers = composerList;
                upsertMeta('composers', JSON.stringify(composerList));
              }
            }

            if (!metadata.logo_path && tmdbData.logo_path) {
              const logoUrl = tmdbService.getImageUrl(tmdbData.logo_path, 'w500');
              if (logoUrl) {
                metadata.logo_path = logoUrl;
                upsertMeta('logo_path', logoUrl);
              }
            }

            if (!metadata.trailer_url && tmdbData.trailer_url) {
              metadata.trailer_url = tmdbData.trailer_url;
              upsertMeta('trailer_url', tmdbData.trailer_url);
            }

            if (isShowType) {
              if (tmdbData.next_episode_to_air) {
                metadata.next_episode_to_air = tmdbData.next_episode_to_air;
                upsertMeta('next_episode_to_air', JSON.stringify(tmdbData.next_episode_to_air));
              } else {
                // If it no longer has a next episode, we should remove it or set it to null
                metadata.next_episode_to_air = null;
                db.prepare(`DELETE FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'next_episode_to_air'`).run(movie.id);
              }

              if (tmdbData.last_air_date) {
                metadata.last_air_date = tmdbData.last_air_date;
                upsertMeta('last_air_date', tmdbData.last_air_date);
              }
              
              if (tmdbData.status) {
                metadata.status = tmdbData.status;
                upsertMeta('status', tmdbData.status);
              }
              
              if (tmdbData.number_of_seasons) {
                metadata.number_of_seasons = tmdbData.number_of_seasons;
                upsertMeta('number_of_seasons', tmdbData.number_of_seasons.toString());
              }
              
              if (tmdbData.number_of_episodes) {
                metadata.number_of_episodes = tmdbData.number_of_episodes;
                upsertMeta('number_of_episodes', tmdbData.number_of_episodes.toString());
              }
            }

            const imdbId = movie.imdb_id || tmdbData.external_ids?.imdb_id || null;
            if (imdbId) {
              const omdbKey = tmdbService.getSetting('OMDB_API_KEY');
              if (omdbKey && (!metadata.awards || metadata.awards === awardsPlaceholder || !metadata.imdb_rating)) {
                try {
                  const omdbRes = await axios.get(`http://www.omdbapi.com/`, {
                    params: { apikey: omdbKey, i: imdbId }
                  });
                  if (omdbRes.data) {
                    if (omdbRes.data.Awards) {
                      metadata.awards = omdbRes.data.Awards;
                      upsertMeta('awards', omdbRes.data.Awards);
                    }
                    if (omdbRes.data.imdbRating && omdbRes.data.imdbRating !== 'N/A') {
                      metadata.imdb_rating = omdbRes.data.imdbRating;
                      upsertMeta('imdb_rating', omdbRes.data.imdbRating);
                    }
                    if (omdbRes.data.imdbVotes && omdbRes.data.imdbVotes !== 'N/A') {
                      metadata.imdb_votes = omdbRes.data.imdbVotes;
                      upsertMeta('imdb_votes', omdbRes.data.imdbVotes);
                    }
                    if (omdbRes.data.Metascore && omdbRes.data.Metascore !== 'N/A') {
                      metadata.metascore = omdbRes.data.Metascore;
                      upsertMeta('metascore', omdbRes.data.Metascore);
                    }
                    if (Array.isArray(omdbRes.data.Ratings)) {
                      const rtEntry = omdbRes.data.Ratings.find((r: any) => r.Source === 'Rotten Tomatoes');
                      if (rtEntry) {
                        metadata.rt_rating = rtEntry.Value;
                        upsertMeta('rt_rating', rtEntry.Value);
                      }
                    }
                  }
                } catch (omdbErr) {
                  console.error('[Media Details] OMDb enrichment failed:', omdbErr);
                }
              }


              if (simklClientId && (!metadata.simkl_rating || !metadata.simkl_votes)) {
                try {
                  const simklLookupRes = await axios.get(`https://api.simkl.com/search/id`, {
                    params: { imdb: imdbId, client_id: simklClientId }
                  });
                  const simklLookupData = Array.isArray(simklLookupRes.data)
                    ? simklLookupRes.data[0]
                    : simklLookupRes.data;

                  const simklId = extractSimklId(simklLookupData);

                  if (simklId && (!metadata.simkl_rating || !metadata.simkl_votes)) {
                    const simklRatingsRes = await axios.get(`https://api.simkl.com/ratings`, {
                      params: {
                        simkl: simklId,
                        fields: 'rank,droprate,simkl,ext,has_trailer,reactions,year',
                        client_id: simklClientId,
                      }
                    });
                    const parsedSimklRatings = extractSimklRatings(simklRatingsRes.data);
                    if (parsedSimklRatings.simklRating) {
                      metadata.simkl_rating = parsedSimklRatings.simklRating;
                      upsertMeta('simkl_rating', parsedSimklRatings.simklRating);
                    }
                    if (parsedSimklRatings.simklVotes) {
                      metadata.simkl_votes = parsedSimklRatings.simklVotes;
                      upsertMeta('simkl_votes', parsedSimklRatings.simklVotes);
                    }
                  }
                } catch (simklErr) {
                  console.error('[Media Details] Simkl/Trakt enrichment failed:', simklErr);
                }
              }

              if (traktApiKey && imdbId && (!metadata.trakt_rating || !metadata.trakt_votes)) {
                try {
                  const mediaType = movie.type?.toString().toLowerCase() === 'show' || movie.type?.toString().toLowerCase() === 'tv'
                    ? 'show'
                    : 'movie';
                  const parsedTraktRatings = await fetchTraktRatingsByImdb(imdbId, traktApiKey, mediaType);
                  if (parsedTraktRatings.traktRating) {
                    metadata.trakt_rating = parsedTraktRatings.traktRating;
                    upsertMeta('trakt_rating', parsedTraktRatings.traktRating);
                  }
                  if (parsedTraktRatings.traktVotes) {
                    metadata.trakt_votes = parsedTraktRatings.traktVotes;
                    upsertMeta('trakt_votes', parsedTraktRatings.traktVotes);
                  }
                } catch (traktErr) {
                  console.error('[Media Details] Trakt API enrichment failed:', traktErr);
                }
              }
            }

            if (!metadata.awards || metadata.awards === awardsPlaceholder) {
              const tmdbAwards = await tmdbService.fetchAwardsSummary(tmdbData.id?.toString?.() || movie.tmdb_id?.toString?.() || '');
              if (tmdbAwards) {
                metadata.awards = tmdbAwards;
                upsertMeta('awards', tmdbAwards);
              }
            }
          }
        }

        // Simple restriction check
        if (restrictions.length > 0) {
          const genre = movie.genre || metadata.genre;
          const rating = metadata.rating;
          for (const r of restrictions) {
            if (r.restriction_type === 'GENRE' && genre === r.restriction_value) {
              return reply.code(403).send({ error: 'Access denied due to genre restriction' });
            }
          }
        }

        // Return combined data
        return {
          id: movie.id,
          title: movie.title,
          type: movie.type,
          plot: movie.plot,
          year: movie.year,
          genre: movie.genre || metadata.genre || (movie.type === 'Show' ? 'Show' : 'Movie'),
          poster_path: movie.poster_path,
          fanart_path: movie.fanart_path,
          tmdb_id: movie.tmdb_id,
          imdb_id: movie.imdb_id,
          collection_name: movie.collection_name,
          collection_id: movie.collection_id,
          director: movie.director,
          original_title: movie.original_title,
          file_path: movie.file_path,
          file_size: movie.file_size,
          added_at: movie.added_at,
          is_favorite: movie.is_favorite === 1,
          metadata: metadata, // includes 'cast', 'ratings' etc
          episodes: movie.type === 'Show'
            ? db.prepare(`
                SELECT e.id, e.season_number, e.episode_number, e.title, e.file_path, e.air_date,
                       e.overview, e.still_path,
                       COALESCE(wh.is_watched, 0) as is_watched,
                       COALESCE(wh.last_position_seconds, 0) as playback_progress,
                       COALESCE(wh.total_duration_seconds, 0) as duration,
                       (SELECT metadata_value FROM media_metadata WHERE media_item_id = e.show_id AND metadata_key = 'ep_' || e.id || '_guest_stars') as guest_stars,
                       (SELECT metadata_value FROM media_metadata WHERE media_item_id = e.show_id AND metadata_key = 'ep_' || e.id || '_subtitle_tracks') as subtitle_tracks,
                       (SELECT metadata_value FROM media_metadata WHERE media_item_id = e.show_id AND metadata_key = 'ep_' || e.id || '_audio_tracks') as audio_tracks
                FROM episodes e
                LEFT JOIN watch_history wh ON wh.episode_id = e.id AND wh.user_id = ?
                WHERE e.show_id = ? AND (e.deleted_at IS NULL OR e.deleted_at = '')
                ORDER BY e.season_number ASC, e.episode_number ASC
              `).all(user.id, movie.id).map((ep: any) => ({
                ...ep,
                subtitle_tracks: (() => { try { return ep.subtitle_tracks ? JSON.parse(ep.subtitle_tracks) : []; } catch { return []; } })(),
                audio_tracks: (() => { try { return ep.audio_tracks ? JSON.parse(ep.audio_tracks) : []; } catch { return []; } })()
              }))
            : undefined,
          versions: (() => {
            try {
              const sameItems = movie.tmdb_id
                ? db.prepare(`SELECT id, file_path FROM media_items WHERE tmdb_id = ? AND deleted_at IS NULL`).all(movie.tmdb_id) as any[]
                : db.prepare(`SELECT id, file_path FROM media_items WHERE title = ? AND deleted_at IS NULL`).all(movie.title) as any[];

              return sameItems.map((item: any) => {
                const resRow = db.prepare(`SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'resolution'`).get(item.id) as any;
                const verRow = db.prepare(`SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'release_version'`).get(item.id) as any;
                const subRow = db.prepare(`SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'subtitle_tracks'`).get(item.id) as any;
                const audRow = db.prepare(`SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'audio_tracks'`).get(item.id) as any;
                const parseTracks = (row: any) => { try { return row ? JSON.parse(row.metadata_value) : []; } catch { return []; } };
                return {
                  id: item.id,
                  file_path: item.file_path,
                  resolution: resRow?.metadata_value || '1080p',
                  release_version: verRow?.metadata_value || '',
                  subtitle_tracks: parseTracks(subRow),
                  audio_tracks: parseTracks(audRow),
                };
              });
            } catch (e) {
              return [{
                id: movie.id,
                file_path: movie.file_path,
                resolution: metadata.resolution || metadata.video_resolution || null,
                release_version: metadata.release_version || '',
                subtitle_tracks: metadata.subtitle_tracks || [],
                audio_tracks: metadata.audio_tracks || [],
              }];
            }
          })()
        };

      } catch (error: any) {
        request.log.error(error);
        return reply.code(500).send({ error: 'Failed to fetch media details', details: error.message });
      }
    }
  );

  // GET /api/media/shows
  // Retrieves shows with SQL-level restriction filters applied
  fastify.get(
    '/api/media/shows',
    async (request: FastifyRequest, reply: FastifyReply) => {
      const user = (request.user as { id: string; username: string; role: string } | undefined) ?? anonymousUser;

      try {
        const showsQuery = `
          SELECT mi.* FROM media_items mi
          WHERE mi.type = 'Show'
          AND mi.deleted_at IS NULL
          AND mi.id NOT IN (
            SELECT mm.media_item_id 
            FROM media_metadata mm
            JOIN user_restrictions ur ON ur.user_id = ?
            WHERE 
              (ur.restriction_type = 'GENRE' AND mm.metadata_key = 'genre' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'RATING' AND mm.metadata_key = 'rating' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'KEYWORD' AND mm.metadata_key = 'keyword' AND mm.metadata_value LIKE '%' || ur.restriction_value || '%')
          )
        `;

        const rawShows = db.prepare(showsQuery).all(user.id) as Array<{
          id: string;
          title: string;
          type: string;
          tmdb_id: string | null;
          imdb_id: string | null;
          file_path: string | null;
          added_at: string;
        }>;

        const showsWithEpisodes = rawShows.map(show => {
          // Get metadata
          const metadataRows = db.prepare(`
            SELECT metadata_key, metadata_value 
            FROM media_metadata 
            WHERE media_item_id = ?
          `).all(show.id) as Array<{ metadata_key: string; metadata_value: string }>;

          const metadata: Record<string, string> = {};
          metadataRows.forEach(row => {
            metadata[row.metadata_key] = row.metadata_value;
          });

          // Get episodes with per-user watch status
          const episodes = db.prepare(`
            SELECT e.id, e.season_number, e.episode_number, e.title, e.file_path, e.air_date,
                   e.still_path, e.overview,
                   COALESCE(wh.is_watched, 0) as is_watched,
                   COALESCE(wh.last_position_seconds, 0) as playback_progress,
                   COALESCE(wh.total_duration_seconds, 0) as duration,
                   (SELECT metadata_value FROM media_metadata WHERE media_item_id = e.show_id AND metadata_key = 'ep_' || e.id || '_guest_stars') as guest_stars
            FROM episodes e
            LEFT JOIN watch_history wh ON wh.episode_id = e.id AND wh.user_id = ?
            WHERE e.show_id = ? AND (e.deleted_at IS NULL OR e.deleted_at = '')
            ORDER BY e.season_number ASC, e.episode_number ASC
          `).all(user.id, show.id);

          return {
            ...show,
            is_favorite: (show as any).is_favorite === 1,
            metadata,
            episodes
          };
        });

        return reply.send(showsWithEpisodes);
      } catch (err) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to retrieve shows' });
      }
    }
  );

  // GET /api/people/:id
  // Retrieves bio and local-library matched movie credits for actors/directors
  fastify.get(
    '/api/people/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const apiKeyRow = db.prepare("SELECT value FROM system_settings WHERE key = 'TMDB_API_KEY'").get() as { value: string } | undefined;
      if (!apiKeyRow || !apiKeyRow.value) {
        return reply.code(400).send({ error: 'TMDB API key not configured' });
      }
      const { id } = request.params;
      const prefLang = (db.prepare("SELECT value FROM system_settings WHERE key = 'METADATA_LANGUAGE'").get() as { value: string } | undefined)?.value || 'sv-SE';

      try {
        // 1. Fetch biographical info
        const personRes = await axios.get(`https://api.themoviedb.org/3/person/${id}`, {
          params: { api_key: apiKeyRow.value, language: prefLang }
        });
        const person = personRes.data;

        let biography = person.biography;
        if ((!biography || biography.trim() === '') && prefLang !== 'en-US') {
          try {
            const enPersonRes = await axios.get(`https://api.themoviedb.org/3/person/${id}`, {
              params: { api_key: apiKeyRow.value, language: 'en-US' }
            });
            if (enPersonRes.data && enPersonRes.data.biography) {
              biography = enPersonRes.data.biography;
            }
          } catch (e) {
            console.error('Failed to fetch fallback en-US biography', e);
          }
        }

        // 2. Fetch combined credits (movies + TV shows)
        const creditsRes = await axios.get(`https://api.themoviedb.org/3/person/${id}/combined_credits`, {
          params: { api_key: apiKeyRow.value, language: prefLang }
        });

        // Normalize movie and TV entries to a common shape
        const normalizeCredit = (c: any) => ({
          ...c,
          title: c.title || c.name || '',
          release_date: c.release_date || c.first_air_date || null,
        });

        const castCredits = (creditsRes.data.cast || []).map(normalizeCredit);
        const crewCredits = (creditsRes.data.crew || []).map(normalizeCredit);

        // 3. Match against local library (movies AND shows) and watchlist
        const localMedia = db.prepare(`
          SELECT mi.id, mi.title, mi.year, mi.tmdb_id, mi.type, mi.poster_path,
                 (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'watch_status') as watch_status,
                 (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'playback_progress') as playback_progress,
                 (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'duration') as duration,
                 (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'runtime') as runtime
          FROM media_items mi
          WHERE mi.deleted_at IS NULL
        `).all() as any[];

        const watchlistRows = db.prepare(`SELECT tmdb_id FROM watchlist`).all() as Array<{ tmdb_id: string }>;
        const watchlistTmdbIds = new Set(watchlistRows.map(r => r.tmdb_id.toString()));

        const matchLocal = (tmdbId: any, title: string) => {
          return localMedia.find(m => (m.tmdb_id && tmdbId && m.tmdb_id.toString() === tmdbId.toString()) || m.title.toLowerCase() === title.toLowerCase());
        };

        const mappedCast = castCredits.map((c: any) => {
          const localMatch = matchLocal(c.id, c.title);
          return {
            id: c.id,
            title: c.title,
            character: c.character,
            release_date: c.release_date,
            year: c.release_date ? parseInt(c.release_date.substring(0, 4), 10) : null,
            poster_path: c.poster_path ? `https://image.tmdb.org/t/p/w500${c.poster_path}` : null,
            popularity: c.popularity || 0.0,
            vote_average: c.vote_average || 0.0,
            vote_count: c.vote_count || 0,
            overview: c.overview || '',
            media_type: c.media_type || 'movie',
            local_id: localMatch ? localMatch.id : null,
            watch_status: localMatch ? localMatch.watch_status : null,
            playback_progress: localMatch ? localMatch.playback_progress : null,
            duration: localMatch ? localMatch.duration : null,
            runtime: localMatch ? localMatch.runtime : null,
            is_in_watchlist: watchlistTmdbIds.has(c.id.toString()),
          };
        }).sort((a: any, b: any) => (b.year || 0) - (a.year || 0));

        const mappedCrew = crewCredits.map((c: any) => {
          const localMatch = matchLocal(c.id, c.title);
          return {
            id: c.id,
            title: c.title,
            job: c.job,
            department: c.department || '',
            release_date: c.release_date,
            year: c.release_date ? parseInt(c.release_date.substring(0, 4), 10) : null,
            poster_path: c.poster_path ? `https://image.tmdb.org/t/p/w500${c.poster_path}` : null,
            popularity: c.popularity || 0.0,
            vote_average: c.vote_average || 0.0,
            vote_count: c.vote_count || 0,
            overview: c.overview || '',
            media_type: c.media_type || 'movie',
            local_id: localMatch ? localMatch.id : null,
            watch_status: localMatch ? localMatch.watch_status : null,
            playback_progress: localMatch ? localMatch.playback_progress : null,
            duration: localMatch ? localMatch.duration : null,
            runtime: localMatch ? localMatch.runtime : null,
            is_in_watchlist: watchlistTmdbIds.has(c.id.toString()),
          };
        }).sort((a: any, b: any) => (b.year || 0) - (a.year || 0));

        return reply.send({
          id: person.id,
          name: person.name,
          biography: biography,
          birthday: person.birthday,
          deathday: person.deathday,
          place_of_birth: person.place_of_birth,
          profile_path: person.profile_path ? `https://image.tmdb.org/t/p/w500${person.profile_path}` : null,
          imdb_id: person.imdb_id,
          cast: mappedCast,
          crew: mappedCrew
        });
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to fetch person details', details: err.message });
      }
    }
  );

  // GET /api/media/items/:id/search-tmdb
  fastify.get(
    '/api/media/items/:id/search-tmdb',
    async (request: FastifyRequest<{ Params: { id: string }; Querystring: { query: string; year?: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const { query, year } = request.query;
      const parsedYear = year ? parseInt(year, 10) : undefined;
      try {
        const mediaItem = db.prepare(`SELECT type FROM media_items WHERE id = ?`).get(id) as any;
        const isShow = mediaItem?.type === 'Show';

        let results: any[];
        if (isShow) {
          results = await tmdbService.searchTvCandidates(query, parsedYear);
          return results.map((m: any) => ({
            id: m.id,
            title: m.name,
            original_title: m.original_name,
            release_date: m.first_air_date,
            year: m.first_air_date ? parseInt(m.first_air_date.substring(0, 4), 10) : null,
            poster_path: m.poster_path ? tmdbService.getImageUrl(m.poster_path, 'w500') : null
          }));
        } else {
          results = await tmdbService.searchMovieCandidates(query, parsedYear);
          return results.map((m: any) => ({
            id: m.id,
            title: m.title,
            original_title: m.original_title,
            release_date: m.release_date,
            year: m.release_date ? parseInt(m.release_date.substring(0, 4), 10) : null,
            poster_path: m.poster_path ? tmdbService.getImageUrl(m.poster_path, 'w500') : null
          }));
        }
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to search TMDB', details: err.message });
      }
    }
  );

  // GET /api/media/search-tmdb
  // Generic TMDB movie search used by Home quick search (no local item id required)
  fastify.get(
    '/api/media/search-tmdb',
    async (request: FastifyRequest<{ Querystring: { query: string; year?: string } }>, reply: FastifyReply) => {
      const { query, year } = request.query;
      const parsedYear = year ? parseInt(year, 10) : undefined;

      if (!query || query.trim().length < 1) {
        return reply.send([]);
      }

      try {
        const results = await tmdbService.searchMovieCandidates(query.trim(), parsedYear);
        return results.map((m: any) => ({
          id: m.id,
          title: m.title,
          original_title: m.original_title,
          release_date: m.release_date,
          year: m.release_date ? parseInt(m.release_date.substring(0, 4), 10) : null,
          poster_path: m.poster_path ? tmdbService.getImageUrl(m.poster_path, 'w500') : null
        }));
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to search TMDB', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/match
  fastify.post(
    '/api/media/items/:id/match',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { tmdbId: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const { tmdbId } = request.body;

      try {
        // Clear all non-locked metadata except user state keys
        db.prepare(`
          DELETE FROM media_metadata
          WHERE media_item_id = ?
          AND is_locked = 0
          AND metadata_key NOT IN ('my_rating', 'watch_status', 'playback_progress', 'duration')
        `).run(id);

        const mediaItem = db.prepare(`SELECT file_path, type FROM media_items WHERE id = ?`).get(id) as any;
        const isShow = mediaItem?.type === 'Show';

        if (mediaItem && mediaItem.file_path) {
          const fileName = path.parse(mediaItem.file_path).name.toLowerCase();
          let edition: string | null = null;
          if (/\buncut\b/i.test(fileName)) edition = 'Uncut';
          else if (/\bdirector\'?s\.?cut\b/i.test(fileName)) edition = "Director's Cut";
          else if (/\bextended\b/i.test(fileName)) edition = 'Extended Cut';
          else if (/\btheatrical\b/i.test(fileName)) edition = 'Theatrical Cut';
          else if (/\bultimate\b/i.test(fileName)) edition = 'Ultimate Edition';
          else if (/\bremastered\b/i.test(fileName)) edition = 'Remastered';
          else if (/\bcollector\'?s\.?edition\b/i.test(fileName)) edition = "Collector's Edition";
          else if (/\bspecial\.?edition\b/i.test(fileName)) edition = 'Special Edition';
          else if (/\b3d\b/i.test(fileName)) edition = '3D';
          else if (/\bimax\b/i.test(fileName)) edition = 'IMAX';

          if (edition) {
            db.prepare(`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            `).run(uuidv4(), id, 'release_version', edition);
          }
        }

        const rawData = isShow
          ? await tmdbService.fetchShowById(tmdbId)
          : await tmdbService.fetchMovieById(tmdbId);

        if (!rawData) {
          return reply.code(404).send({ error: 'TMDB details not found' });
        }

        // Normalize show vs movie field names
        const tmdbData = isShow ? {
          ...rawData,
          title: rawData.name,
          original_title: rawData.original_name,
          release_date: rawData.first_air_date,
          imdb_id: rawData.external_ids?.imdb_id || null,
        } : rawData;

        // Get genres
        const genre = tmdbData.genres ? tmdbData.genres.map((g: any) => g.name).join(', ') : (isShow ? 'Show' : 'Movie');

        // Director (store in metadata with ID)
        if (tmdbData.credits && tmdbData.credits.crew) {
          const dirObj = tmdbData.credits.crew.find((c: any) => c.job === 'Director');
          if (dirObj) {
            db.prepare(`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            `).run(
              uuidv4(),
              id,
              'director',
              JSON.stringify({ id: dirObj.id, name: dirObj.name })
            );
          }
        }

        // Logo (store in metadata for ClearLOGO display)
        if (tmdbData.logo_path) {
          const logoUrl = tmdbService.getImageUrl(tmdbData.logo_path, 'w500');
          if (logoUrl) {
            db.prepare(`
              INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value)
              VALUES (?, ?, ?, ?)
              ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
            `).run(
              uuidv4(),
              id,
              'logo_path',
              logoUrl
            );
          }
        }

        // Collection (movies only)
        let collectionName = null;
        let collectionId = null;
        if (!isShow && tmdbData.belongs_to_collection) {
          collectionName = tmdbData.belongs_to_collection.name;
          collectionId = tmdbData.belongs_to_collection.id.toString();
        }

        const poster_path = tmdbService.getImageUrl(tmdbData.poster_path, 'w500');
        const fanart_path = tmdbService.getImageUrl(tmdbData.backdrop_path, 'original');
        const year = tmdbData.release_date ? parseInt(tmdbData.release_date.substring(0, 4), 10) : null;

        // Update database media_item entry (director still stored as string for backward compatibility)
        let directorName = null;
        if (tmdbData.credits && tmdbData.credits.crew) {
          const dirObj = tmdbData.credits.crew.find((c: any) => c.job === 'Director');
          if (dirObj) directorName = dirObj.name;
        }

        db.prepare(`
          UPDATE media_items
          SET title = ?, plot = ?, year = ?, genre = ?, poster_path = ?, fanart_path = ?, tmdb_id = ?, imdb_id = ?, collection_name = ?, collection_id = ?, director = ?, original_title = ?
          WHERE id = ?
        `).run(
          tmdbData.title,
          tmdbData.overview || null,
          year,
          genre,
          poster_path,
          fanart_path,
          tmdbData.id.toString(),
          tmdbData.imdb_id || null,
          collectionName,
          collectionId,
          directorName,
          tmdbData.original_title || null,
          id
        );

        // Sub helper to upsert metadata
        const upsertMeta = (key: string, value: string) => {
          db.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
            VALUES (?, ?, ?, ?)
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run(uuidv4(), id, key, value);
        };

        // Add additional metadata
        if (tmdbData.vote_average) {
          upsertMeta('ratings', JSON.stringify({ tmdb: tmdbData.vote_average, tmdb_votes: tmdbData.vote_count }));
        }

        if (tmdbData.credits && tmdbData.credits.cast) {
          const cast = tmdbData.credits.cast.slice(0, 15).map((c: any) => ({
            id: c.id,
            name: c.name,
            character: c.character,
            profile_path: tmdbService.getImageUrl(c.profile_path, 'w500')
          }));
          upsertMeta('cast', JSON.stringify(cast));
        }

        // Crew: producers, writers, composers
        if (tmdbData.credits && tmdbData.credits.crew) {
          const crewList = tmdbData.credits.crew;
          const producers = crewList
            .filter((c: any) => c.job === 'Producer' || c.job === 'Executive Producer')
            .slice(0, 3)
            .map((c: any) => ({ id: c.id?.toString() ?? null, name: c.name, job: c.job }));
          if (producers.length > 0) upsertMeta('producers', JSON.stringify(producers));

          const writers = crewList
            .filter((c: any) => c.department === 'Writing')
            .slice(0, 3)
            .map((c: any) => ({ id: c.id?.toString() ?? null, name: c.name, job: c.job }));
          if (writers.length > 0) upsertMeta('writers', JSON.stringify(writers));

          const composers = crewList
            .filter((c: any) => c.job === 'Original Music Composer' || c.department === 'Sound')
            .slice(0, 2)
            .map((c: any) => ({ id: c.id?.toString() ?? null, name: c.name, job: c.job }));
          if (composers.length > 0) upsertMeta('composers', JSON.stringify(composers));
        }

        // Tagline
        if (tmdbData.tagline) upsertMeta('tagline', tmdbData.tagline);

        // Keywords
        const matchKeywords = rawData.keywords?.keywords || rawData.keywords?.results || [];
        if (matchKeywords.length > 0) {
          upsertMeta('keywords', JSON.stringify(matchKeywords.map((k: any) => k.name)));
        }

        // Production companies & countries
        const prodCompanies = (rawData.production_companies || []).map((c: any) => ({
          id: c.id,
          name: c.name,
          logo_path: c.logo_path ? tmdbService.getImageUrl(c.logo_path, 'w500') : null,
          origin_country: c.origin_country || null
        }));
        if (prodCompanies.length > 0) upsertMeta('production_companies', JSON.stringify(prodCompanies));
        if (rawData.production_countries?.length) {
          upsertMeta('production_countries', JSON.stringify(rawData.production_countries));
        }

        // Runtime
        const matchRuntime = rawData.runtime || rawData.episode_run_time?.[0] || 0;
        if (matchRuntime) upsertMeta('runtime', String(matchRuntime));

        // Show-specific metadata
        if (isShow) {
          if (rawData.status) upsertMeta('status', rawData.status);
          if (rawData.networks?.length) {
            upsertMeta('networks', JSON.stringify(rawData.networks.map((n: any) => n.name)));
          }
          if (rawData.created_by?.length) {
            upsertMeta('created_by', JSON.stringify(rawData.created_by.map((c: any) => ({
              id: c.id?.toString(),
              name: c.name,
              profile_path: c.profile_path ? tmdbService.getImageUrl(c.profile_path, 'w500') : null
            }))));
          }
          if (rawData.number_of_seasons != null) {
            upsertMeta('number_of_seasons', String(rawData.number_of_seasons));
          }
          if (rawData.seasons?.length) {
            const seasonsData = rawData.seasons.map((s: any) => ({
              season_number: s.season_number,
              name: s.name,
              episode_count: s.episode_count,
              air_date: s.air_date || null,
              poster_path: s.poster_path ? tmdbService.getImageUrl(s.poster_path, 'w342') : null,
              overview: s.overview || null,
            }));
            upsertMeta('seasons_json', JSON.stringify(seasonsData));
          }
        }

        if (tmdbData['watch/providers'] && tmdbData['watch/providers'].results) {
          upsertMeta('watch_providers', JSON.stringify(tmdbData['watch/providers'].results));
        }

        if (tmdbData.trailer_url) {
          upsertMeta('trailer_url', tmdbData.trailer_url);
        } else if (tmdbData.videos && tmdbData.videos.results) {
          const trailerObj = tmdbData.videos.results.find((v: any) => v.site === 'YouTube' && v.type === 'Trailer');
          if (trailerObj) {
            upsertMeta('trailer_url', `https://www.youtube.com/watch?v=${trailerObj.key}`);
          }
        }

        // Fetch OMDb Awards AND Ratings
        const omdbKey = tmdbService.getSetting('OMDB_API_KEY');
        if (omdbKey && tmdbData.imdb_id) {
          try {
            const omdbRes = await axios.get(`http://www.omdbapi.com/`, {
              params: { apikey: omdbKey, i: tmdbData.imdb_id }
            });
            if (omdbRes.data) {
              if (omdbRes.data.Awards) upsertMeta('awards', omdbRes.data.Awards);
              if (omdbRes.data.imdbRating && omdbRes.data.imdbRating !== 'N/A') {
                upsertMeta('imdb_rating', omdbRes.data.imdbRating);
              }
              if (omdbRes.data.imdbVotes && omdbRes.data.imdbVotes !== 'N/A') {
                upsertMeta('imdb_votes', omdbRes.data.imdbVotes);
              }
              if (omdbRes.data.Metascore && omdbRes.data.Metascore !== 'N/A') {
                upsertMeta('metascore', omdbRes.data.Metascore);
              }
              if (Array.isArray(omdbRes.data.Ratings)) {
                const rtEntry = omdbRes.data.Ratings.find((r: any) => r.Source === 'Rotten Tomatoes');
                if (rtEntry) upsertMeta('rt_rating', rtEntry.Value);
              }
            }
          } catch (omdbErr) {
            console.error('[ManualMatch] OMDb API fetch failed:', omdbErr);
          }
        }

        // Fetch Simkl & Trakt Ratings on Manual Match
        const simklClientId = tmdbService.getSetting('SIMKL_CLIENT_ID');
        const traktApiKey = tmdbService.getSetting('TRAKT_API_KEY');
        if (simklClientId && tmdbData.imdb_id) {
          try {
            const simklRes = await axios.get(`https://api.simkl.com/search/id`, {
              params: { imdb: tmdbData.imdb_id, client_id: simklClientId }
            });
            const simklData = Array.isArray(simklRes.data)
              ? simklRes.data[0]
              : simklRes.data;

            if (simklData) {
              const parsedRatings = extractSimklRatings(simklData);
              if (parsedRatings.simklRating) upsertMeta('simkl_rating', parsedRatings.simklRating);
              if (parsedRatings.simklVotes) upsertMeta('simkl_votes', parsedRatings.simklVotes);
            }
          } catch (simklErr) {
            console.error('[ManualMatch] Simkl/Trakt API fetch failed:', simklErr);
          }
        }

        if (traktApiKey && tmdbData.imdb_id) {
          try {
            const mediaType = tmdbData.media_type === 'tv' ? 'show' : 'movie';
            const traktRes = await axios.get(`https://api.trakt.tv/search/imdb/${tmdbData.imdb_id}`, {
              params: {
                type: mediaType,
                extended: 'full',
              },
              headers: {
                'trakt-api-key': traktApiKey,
                'trakt-api-version': '2',
                'User-Agent': 'Loom/1.0',
              },
            });

            const traktData = Array.isArray(traktRes.data) ? traktRes.data[0] : traktRes.data;
            if (traktData) {
              const parsedRatings = extractTraktRatings(traktData);
              if (parsedRatings.traktRating) upsertMeta('trakt_rating', parsedRatings.traktRating);
              if (parsedRatings.traktVotes) upsertMeta('trakt_votes', parsedRatings.traktVotes);
            }
          } catch (traktErr) {
            console.error('[ManualMatch] Trakt API fetch failed:', traktErr);
          }
        }

        // For shows: backfill episode overview + still_path in background
        if (isShow) {
          const tmdbShowId = rawData.id?.toString();
          const apiKey = tmdbService.getSetting('TMDB_API_KEY');
          const prefLang = tmdbService.getSetting('METADATA_LANGUAGE') || 'sv-SE';
          if (tmdbShowId && apiKey) {
            const episodes = db.prepare(`SELECT id, season_number, episode_number FROM episodes WHERE show_id = ? AND deleted_at IS NULL`).all(id) as any[];
            setImmediate(async () => {
              for (const ep of episodes) {
                try {
                  const epResp = await axios.get(
                    `https://api.themoviedb.org/3/tv/${tmdbShowId}/season/${ep.season_number}/episode/${ep.episode_number}`,
                    { params: { api_key: apiKey, language: prefLang } }
                  );
                  const overview = epResp.data?.overview || null;
                  const stillPath = epResp.data?.still_path
                    ? tmdbService.getImageUrl(epResp.data.still_path, 'w500')
                    : null;
                  const title = epResp.data?.name || null;
                  const airDate = epResp.data?.air_date || null;
                  db.prepare(`UPDATE episodes SET title = COALESCE(?, title), air_date = COALESCE(?, air_date), overview = ?, still_path = ? WHERE id = ?`)
                    .run(title, airDate, overview, stillPath, ep.id);
                } catch (_) {}
              }
            });
          }
        }

        return reply.send({ success: true });
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to manual-match media item', details: err.message });
      }
    }
  );

  // DELETE /api/media/items/:id — soft-delete: moves file(s) to .trash, sets deleted_at
  fastify.delete(
    '/api/media/items/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        const item = db.prepare(`SELECT id, type, file_path FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!item) {
          return reply.code(404).send({ error: 'Media item not found' });
        }

        const moveErrors: string[] = [];

        if (item.type === 'Show') {
          const episodes = db.prepare(`SELECT file_path FROM episodes WHERE show_id = ?`).all(id) as Array<{ file_path: string }>;
          for (const ep of episodes) {
            if (ep.file_path && fs.existsSync(ep.file_path)) {
              try {
                const dest = computeTrashPath(ep.file_path);
                fs.mkdirSync(path.dirname(dest), { recursive: true });
                fs.renameSync(ep.file_path, dest);
              } catch (e: any) {
                moveErrors.push(ep.file_path + ': ' + e.message);
              }
            }
          }
        } else if (item.file_path && fs.existsSync(item.file_path)) {
          const dest = computeTrashPath(item.file_path);
          fs.mkdirSync(path.dirname(dest), { recursive: true });
          fs.renameSync(item.file_path, dest);
        }

        db.prepare(`UPDATE media_items SET deleted_at = datetime('now') WHERE id = ?`).run(id);

        return reply.send({ success: true, moveErrors: moveErrors.length ? moveErrors : undefined });
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to delete media item', details: err.message });
      }
    }
  );

  // PATCH /api/media/episodes/:id — update episode metadata fields
  fastify.patch(
    '/api/media/episodes/:id',
    async (request: FastifyRequest<{ Params: { id: string }; Body: Record<string, any> }>, reply: FastifyReply) => {
      const { id } = request.params;
      const body = request.body || {};
      try {
        const ep = db.prepare(`SELECT id FROM episodes WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!ep) return reply.code(404).send({ error: 'Episode not found' });

        const allowed = ['title', 'overview', 'still_path', 'air_date'];
        const updates: string[] = [];
        const params: any[] = [];
        for (const key of allowed) {
          if (body[key] !== undefined) {
            updates.push(`${key} = ?`);
            params.push(body[key]);
          }
        }
        if (updates.length === 0) return reply.send({ ok: true, updated: 0 });
        params.push(id);
        db.prepare(`UPDATE episodes SET ${updates.join(', ')} WHERE id = ?`).run(...params);
        return reply.send({ ok: true, updated: updates.length });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to update episode', details: err.message });
      }
    }
  );

  // DELETE /api/media/episodes/:id — soft-delete a single episode
  fastify.delete(
    '/api/media/episodes/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        const ep = db.prepare(`SELECT id, file_path, show_id FROM episodes WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!ep) return reply.code(404).send({ error: 'Episode not found' });

        if (ep.file_path && fs.existsSync(ep.file_path)) {
          const dest = computeTrashPath(ep.file_path);
          fs.mkdirSync(path.dirname(dest), { recursive: true });
          fs.renameSync(ep.file_path, dest);
        }
        db.prepare(`UPDATE episodes SET deleted_at = datetime('now') WHERE id = ?`).run(id);

        // If show has no remaining episodes soft-delete it too
        const remaining = (db.prepare(`SELECT COUNT(*) as cnt FROM episodes WHERE show_id = ? AND deleted_at IS NULL`).get(ep.show_id) as any)?.cnt ?? 0;
        if (remaining === 0) {
          db.prepare(`UPDATE media_items SET deleted_at = datetime('now') WHERE id = ?`).run(ep.show_id);
        }

        return reply.send({ success: true });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to delete episode', details: err.message });
      }
    }
  );

  // DELETE /api/media/seasons/:showId/:season — soft-delete all episodes in a season
  fastify.delete(
    '/api/media/seasons/:showId/:season',
    async (request: FastifyRequest<{ Params: { showId: string; season: string } }>, reply: FastifyReply) => {
      const { showId, season } = request.params;
      const seasonNum = parseInt(season, 10);
      try {
        const episodes = db.prepare(
          `SELECT id, file_path FROM episodes WHERE show_id = ? AND season_number = ? AND deleted_at IS NULL`
        ).all(showId, seasonNum) as any[];

        if (episodes.length === 0) return reply.code(404).send({ error: 'No episodes found for this season' });

        const moveErrors: string[] = [];
        for (const ep of episodes) {
          if (ep.file_path && fs.existsSync(ep.file_path)) {
            try {
              const dest = computeTrashPath(ep.file_path);
              fs.mkdirSync(path.dirname(dest), { recursive: true });
              fs.renameSync(ep.file_path, dest);
            } catch (e: any) {
              moveErrors.push(ep.file_path + ': ' + e.message);
            }
          }
        }
        db.prepare(
          `UPDATE episodes SET deleted_at = datetime('now') WHERE show_id = ? AND season_number = ?`
        ).run(showId, seasonNum);

        // Soft-delete the show if no active episodes remain
        const remaining = (db.prepare(`SELECT COUNT(*) as cnt FROM episodes WHERE show_id = ? AND deleted_at IS NULL`).get(showId) as any)?.cnt ?? 0;
        if (remaining === 0) {
          db.prepare(`UPDATE media_items SET deleted_at = datetime('now') WHERE id = ?`).run(showId);
        }

        return reply.send({ success: true, deleted: episodes.length, moveErrors: moveErrors.length ? moveErrors : undefined });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to delete season', details: err.message });
      }
    }
  );

  // GET /api/trash — list all soft-deleted items
  fastify.get(
    '/api/trash',
    async (_request: FastifyRequest, reply: FastifyReply) => {
      try {
        const items = db.prepare(`
          SELECT mi.id, mi.title, mi.year, mi.type, mi.file_path, mi.poster_path,
            mi.plot, mi.genre, mi.added_at, mi.deleted_at, mi.file_size,
            mi.delete_source, mi.delete_rule,
            (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'resolution') as resolution
          FROM media_items mi
          WHERE mi.deleted_at IS NOT NULL
          ORDER BY mi.deleted_at DESC
        `).all() as any[];

        const getFileSizeOnDisk = (filePath: string | null): number | null => {
          if (!filePath) return null;
          try {
            const trashPath = computeTrashPath(filePath);
            if (fs.existsSync(trashPath)) return fs.statSync(trashPath).size;
            if (fs.existsSync(filePath)) return fs.statSync(filePath).size;
          } catch { /* ignore */ }
          return null;
        };

        const result = items.map(item => {
          const fileSize = item.file_size ?? getFileSizeOnDisk(item.file_path);
          if (item.type === 'Show') {
            const episodes = db.prepare(`
              SELECT id, season_number, episode_number, title, file_path FROM episodes WHERE show_id = ?
              ORDER BY season_number ASC, episode_number ASC
            `).all(item.id) as any[];
            return { ...item, file_size: fileSize, episodes };
          }
          return { ...item, file_size: fileSize };
        });

        // Also include individually-deleted episodes (not part of a fully-deleted show)
        const deletedEpisodes = db.prepare(`
          SELECT e.id, e.file_path, e.season_number, e.episode_number, e.title as episode_title,
                 e.deleted_at, e.delete_source, e.delete_rule,
                 m.id as show_id, m.title as show_title, m.poster_path
          FROM episodes e
          JOIN media_items m ON e.show_id = m.id
          WHERE e.deleted_at IS NOT NULL AND m.deleted_at IS NULL
          ORDER BY e.deleted_at DESC
        `).all() as any[];

        const episodeItems = deletedEpisodes.map(ep => ({
          id: ep.id,
          type: 'Episode',
          title: ep.show_title,
          episode_title: ep.episode_title,
          season_number: ep.season_number,
          episode_number: ep.episode_number,
          file_path: ep.file_path,
          poster_path: ep.poster_path,
          show_id: ep.show_id,
          deleted_at: ep.deleted_at,
          delete_source: ep.delete_source ?? 'manual',
          delete_rule: ep.delete_rule ?? null,
        }));

        return reply.send([...result, ...episodeItems]);
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to fetch trash', details: err.message });
      }
    }
  );

  // POST /api/trash/:id/restore — move file back and clear deleted_at
  fastify.post(
    '/api/trash/:id/restore',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        // Check if it's an individually-deleted episode first
        const episode = db.prepare(`SELECT id, file_path, show_id FROM episodes WHERE id = ? AND deleted_at IS NOT NULL`).get(id) as any;
        if (episode) {
          if (episode.file_path) {
            const trashPath = computeTrashPath(episode.file_path);
            if (fs.existsSync(trashPath)) {
              fs.mkdirSync(path.dirname(episode.file_path), { recursive: true });
              fs.renameSync(trashPath, episode.file_path);
            }
          }
          db.prepare(`UPDATE episodes SET deleted_at = NULL WHERE id = ?`).run(id);
          db.prepare(`UPDATE media_items SET deleted_at = NULL WHERE id = ? AND deleted_at IS NOT NULL`).run(episode.show_id);
          return reply.send({ success: true });
        }

        const item = db.prepare(`SELECT id, type, file_path FROM media_items WHERE id = ? AND deleted_at IS NOT NULL`).get(id) as any;
        if (!item) return reply.code(404).send({ error: 'Item not found in trash' });

        const restoreErrors: string[] = [];

        if (item.type === 'Show') {
          const episodes = db.prepare(`SELECT file_path FROM episodes WHERE show_id = ?`).all(id) as Array<{ file_path: string }>;
          for (const ep of episodes) {
            if (ep.file_path) {
              const trashPath = computeTrashPath(ep.file_path);
              if (fs.existsSync(trashPath)) {
                try {
                  fs.mkdirSync(path.dirname(ep.file_path), { recursive: true });
                  fs.renameSync(trashPath, ep.file_path);
                } catch (e: any) {
                  restoreErrors.push(trashPath + ': ' + e.message);
                }
              }
            }
          }
        } else if (item.file_path) {
          const trashPath = computeTrashPath(item.file_path);
          if (fs.existsSync(trashPath)) {
            fs.mkdirSync(path.dirname(item.file_path), { recursive: true });
            fs.renameSync(trashPath, item.file_path);
          }
        }

        db.prepare(`UPDATE media_items SET deleted_at = NULL WHERE id = ?`).run(id);

        return reply.send({ success: true, restoreErrors: restoreErrors.length ? restoreErrors : undefined });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to restore item', details: err.message });
      }
    }
  );

  // DELETE /api/trash/:id/permanent — permanently delete from disk + database
  fastify.delete(
    '/api/trash/:id/permanent',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        const item = db.prepare(`SELECT id, type, file_path FROM media_items WHERE id = ? AND deleted_at IS NOT NULL`).get(id) as any;
        if (!item) return reply.code(404).send({ error: 'Item not found in trash' });

        if (item.type === 'Show') {
          const episodes = db.prepare(`SELECT file_path FROM episodes WHERE show_id = ?`).all(id) as Array<{ file_path: string }>;
          for (const ep of episodes) {
            if (ep.file_path) {
              const trashPath = computeTrashPath(ep.file_path);
              if (fs.existsSync(trashPath)) {
                try { fs.unlinkSync(trashPath); } catch (e) {}
              }
            }
          }
        } else if (item.file_path) {
          const trashPath = computeTrashPath(item.file_path);
          if (fs.existsSync(trashPath)) {
            try { fs.unlinkSync(trashPath); } catch (e) {}
          }
        }

        db.prepare(`DELETE FROM media_metadata WHERE media_item_id = ?`).run(id);
        db.prepare(`DELETE FROM watch_history WHERE media_item_id = ?`).run(id);
        if (item.type === 'Show') {
          db.prepare(`DELETE FROM episodes WHERE show_id = ?`).run(id);
        }
        db.prepare(`DELETE FROM media_items WHERE id = ?`).run(id);

        return reply.send({ success: true });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to permanently delete item', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/refresh
  fastify.post(
    '/api/media/items/:id/refresh',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        const item = db.prepare(`SELECT id, file_path, type, tmdb_id FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!item) {
          return reply.code(404).send({ error: 'Media item not found' });
        }

        const { mediaScanner } = await import('../services/scanner');

        if (item.type === 'Show') {
          if (!item.tmdb_id) {
            return reply.code(400).send({ error: 'Show has no TMDB ID — use Fix Match first' });
          }
          await mediaScanner.refreshShowMetadata(item.id, item.tmdb_id);
          return reply.send({ success: true, status: 'updated' });
        }

        // For movies: if we already have a TMDB ID, clear stale metadata first so
        // processMovieFile re-fetches everything fresh via fetchMovieById.
        if (item.tmdb_id) {
          db.prepare(`DELETE FROM media_metadata WHERE media_item_id = ? AND metadata_key IN (
            'production_countries','production_companies','cast','ratings','imdb_rating',
            'imdb_votes','simkl_rating','simkl_votes','trakt_rating','trakt_votes',
            'watch_providers','trailer_url','tagline','keywords','awards'
          )`).run(item.id);
        }
        const res = await mediaScanner.processMovieFile(item.file_path, false);
        return reply.send({ success: true, status: res });
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to refresh metadata', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/unmatch
  fastify.post(
    '/api/media/items/:id/unmatch',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        const item = db.prepare(`SELECT id FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!item) {
          return reply.code(404).send({ error: 'Media item not found' });
        }

        // Clear matches in DB
        db.prepare(`
          UPDATE media_items 
          SET tmdb_id = NULL, imdb_id = NULL, collection_name = NULL, collection_id = NULL, original_title = NULL, poster_path = NULL, fanart_path = NULL
          WHERE id = ?
        `).run(id);

        // Delete metadata keys except custom ratings/watch statuses if desired, or keep simple and delete all non-playback metadata keys
        db.prepare(`
          DELETE FROM media_metadata 
          WHERE media_item_id = ? 
          AND metadata_key NOT IN ('my_rating', 'watch_status', 'playback_progress', 'duration')
        `).run(id);

        return reply.send({ success: true });
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to unmatch media item', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/analyze
  fastify.post(
    '/api/media/items/:id/analyze',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        const item = db.prepare(`SELECT id, file_path FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        if (!item) {
          return reply.code(404).send({ error: 'Media item not found' });
        }

        // Re-analyze using the public processMovieFile or re-probe
        const { mediaScanner } = await import('../services/scanner');
        const res = await mediaScanner.processMovieFile(item.file_path, true);
        return reply.send({ success: true, status: res });
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to analyze media item', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/merge
  fastify.post(
    '/api/media/items/:id/merge',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { targetId: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const { targetId } = request.body;

      if (!targetId || id === targetId) {
        return reply.code(400).send({ error: 'Ogiltigt mål-id' });
      }

      try {
        const sourceShow = db.prepare(`SELECT id, type FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
        const targetShow = db.prepare(`SELECT id, type FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(targetId) as any;

        if (!sourceShow || !targetShow || sourceShow.type !== 'Show' || targetShow.type !== 'Show') {
          return reply.code(404).send({ error: 'En eller båda serierna hittades inte, eller är inte av typen Show' });
        }

        // Get all episodes from source
        const sourceEpisodes = db.prepare(`SELECT id, season_number, episode_number FROM episodes WHERE show_id = ? AND deleted_at IS NULL`).all(sourceShow.id) as any[];

        for (const ep of sourceEpisodes) {
          // Check if target already has this episode
          const conflict = db.prepare(`
            SELECT id FROM episodes WHERE show_id = ? AND season_number = ? AND episode_number = ? AND deleted_at IS NULL
          `).get(targetShow.id, ep.season_number, ep.episode_number) as any;

          if (conflict) {
            // Hard delete source episode and its metadata
            db.prepare(`DELETE FROM media_metadata WHERE media_item_id = ? AND metadata_key LIKE ?`).run(sourceShow.id, `ep_${ep.id}_%`);
            db.prepare(`DELETE FROM episodes WHERE id = ?`).run(ep.id);
          } else {
            // Move source episode and its metadata to target
            db.prepare(`UPDATE media_metadata SET media_item_id = ? WHERE media_item_id = ? AND metadata_key LIKE ?`).run(targetShow.id, sourceShow.id, `ep_${ep.id}_%`);
            db.prepare(`UPDATE episodes SET show_id = ? WHERE id = ?`).run(targetShow.id, ep.id);
          }
        }

        // Hard delete the source show and its remaining metadata
        db.prepare(`DELETE FROM media_metadata WHERE media_item_id = ?`).run(sourceShow.id);
        db.prepare(`DELETE FROM media_items WHERE id = ?`).run(sourceShow.id);

        return reply.send({ success: true, message: 'Serien slogs ihop framgångsrikt' });
      } catch (err: any) {
        console.error('[Merge] Error:', err);
        return reply.code(500).send({ error: 'Kunde inte slå ihop serierna', details: err.message });
      }
    }
  );

  // GET /api/media/collections/:collectionId
  fastify.get(
    '/api/media/collections/:collectionId',
    async (request: FastifyRequest<{ Params: { collectionId: string } }>, reply: FastifyReply) => {
      const { collectionId } = request.params;

      try {
        // Library items in this collection
        const libraryItems = db.prepare(`
          SELECT id, title, year, poster_path, tmdb_id, is_favorite
          FROM media_items
          WHERE collection_id = ? AND deleted_at IS NULL
          ORDER BY COALESCE(year, 9999) ASC
        `).all(collectionId) as any[];

        const itemIds = libraryItems.map(i => i.id);
        const metadataRows = itemIds.length > 0
          ? db.prepare(`
              SELECT media_item_id, metadata_key, metadata_value
              FROM media_metadata
              WHERE media_item_id IN (${itemIds.map(() => '?').join(',')})
            `).all(...itemIds) as any[]
          : [];

        const libraryByTmdbId = new Map();
        for (const i of libraryItems) {
          const tmdbStr = i.tmdb_id?.toString();
          if (!tmdbStr) continue;

          const meta = metadataRows.filter(m => m.media_item_id === i.id).reduce((acc: any, curr) => {
            acc[curr.metadata_key] = curr.metadata_value;
            return acc;
          }, {});

          if (!libraryByTmdbId.has(tmdbStr)) {
            libraryByTmdbId.set(tmdbStr, { ...i, metadata: meta, versions: [] });
          }

          libraryByTmdbId.get(tmdbStr).versions.push({
            id: i.id,
            resolution: meta.resolution || meta.video_resolution || meta.quality || null
          });
        }

        // Fetch full collection from TMDB
        const tmdbKey = (db.prepare(`SELECT value FROM system_settings WHERE key='TMDB_API_KEY'`).get() as any)?.value;
        let allParts: any[] = [];
        let collectionName = '';

        if (tmdbKey) {
          try {
            const axios = require('axios');
            const tmdbResp = await axios.get(`https://api.themoviedb.org/3/collection/${collectionId}`, {
              params: { api_key: tmdbKey, language: 'sv-SE' },
            });
            collectionName = tmdbResp.data.name ?? '';
            allParts = (tmdbResp.data.parts ?? []).sort((a: any, b: any) =>
              (a.release_date ?? '').localeCompare(b.release_date ?? '')
            );
          } catch {}
        }

        // If TMDB failed, fall back to library items only
        if (allParts.length === 0) {
          allParts = libraryItems.map(i => ({
            id: i.tmdb_id,
            title: i.title,
            release_date: i.year ? `${i.year}-01-01` : '',
            poster_path: i.poster_path?.startsWith('http') ? null : i.poster_path,
          }));
        }

        const items = allParts.map((part: any) => {
          const tmdbId = part.id?.toString();
          const libItem = libraryByTmdbId.get(tmdbId);
          const posterPath = libItem?.poster_path
            ?? (part.poster_path ? `https://image.tmdb.org/t/p/w200${part.poster_path}` : null);
          return {
            id: libItem?.id ?? null,
            tmdb_id: tmdbId,
            title: part.title ?? libItem?.title ?? '',
            year: part.release_date ? new Date(part.release_date).getFullYear() : (libItem?.year ?? null),
            poster_path: posterPath,
            in_library: !!libItem,
            release_date: part.release_date ?? null,
            is_favorite: libItem?.is_favorite === 1,
            metadata: libItem?.metadata ?? null,
            versions: libItem?.versions ?? [],
          };
        });

        return reply.send({ collectionId, collectionName, items });
      } catch (error: any) {
        request.log.error(error);
        return reply.code(500).send({ error: 'Failed to fetch collection items', details: error.message });
      }
    }
  );

  // GET /api/media/:id/similar - Get similar/recommended media from TMDB (both in library and not)
  fastify.get(
    '/api/media/:id/similar',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;

      try {
        let movieTmdbId: string | undefined;
        let movieType: string | undefined;

        if (id.startsWith('external_')) {
          const match = id.match(/^external_(movie|show)_(.+)$/);
          if (match) {
            movieType = match[1] === 'show' ? 'Show' : 'Movie';
            movieTmdbId = match[2];
          }
        } else {
          const movie = db.prepare(`SELECT tmdb_id, type FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
          if (movie && movie.tmdb_id) {
            movieTmdbId = movie.tmdb_id;
            movieType = movie.type;
          }
        }

        if (!movieTmdbId) {
          return reply.code(404).send({ error: 'Media not found or no TMDB ID' });
        }

        // Fetch similar movies from TMDB
        const apiKey = db.prepare(`SELECT value FROM system_settings WHERE key = 'TMDB_API_KEY'`).get() as any;
        if (!apiKey || !apiKey.value) {
          return reply.code(400).send({ error: 'TMDB API key not configured' });
        }

        let similarMovies = [];
        try {
          const endpoint = movieType === 'Show' ? 'tv' : 'movie';
          const response = await axios.get(`https://api.themoviedb.org/3/${endpoint}/${movieTmdbId}/recommendations`, {
            params: {
              api_key: apiKey.value,
              language: 'sv-SE'
            }
          });
          similarMovies = response.data.results || [];
        } catch (tmdbErr: any) {
          request.log.warn(`Failed to fetch similar ${movieType}s from TMDB:`, tmdbErr.message);
          return reply.send({ id, items: [] });
        }

        const normalizedSimilar = similarMovies.map((m: any) => ({
          tmdb_id: m.id,
          title: m.title || m.name || '',
          year: m.release_date ? new Date(m.release_date).getFullYear() : (m.first_air_date ? new Date(m.first_air_date).getFullYear() : null),
          poster_path: m.poster_path ? `https://image.tmdb.org/t/p/w500${m.poster_path}` : null,
          overview: m.overview || '',
        }));

        if (normalizedSimilar.length === 0) {
          return reply.send({ id, items: [] });
        }

        const tmdbIds = normalizedSimilar.map((m: any) => m.tmdb_id).filter(Boolean);
        const placeholders = tmdbIds.map(() => '?').join(',');
        const libraryRows = tmdbIds.length > 0 ? db.prepare(`
          SELECT id, tmdb_id, is_favorite
          FROM media_items
          WHERE deleted_at IS NULL AND tmdb_id IN (${placeholders})
        `).all(...tmdbIds) as any[] : [];

        const libItemIds = libraryRows.map(r => r.id);
        const metadataRows = libItemIds.length > 0
          ? db.prepare(`
              SELECT media_item_id, metadata_key, metadata_value
              FROM media_metadata
              WHERE media_item_id IN (${libItemIds.map(() => '?').join(',')})
            `).all(...libItemIds) as any[]
          : [];

        const libraryMap = new Map();
        for (const row of libraryRows) {
          const tmdbStr = Number(row.tmdb_id);
          if (!tmdbStr) continue;

          const meta = metadataRows.filter(m => m.media_item_id === row.id).reduce((acc: any, curr) => {
            acc[curr.metadata_key] = curr.metadata_value;
            return acc;
          }, {});

          if (!libraryMap.has(tmdbStr)) {
            libraryMap.set(tmdbStr, { ...row, metadata: meta, versions: [] });
          }

          libraryMap.get(tmdbStr).versions.push({
            id: row.id,
            resolution: meta.resolution || meta.video_resolution || null
          });
        }

        const finalItems = normalizedSimilar.map((m: any) => {
          const libItem = libraryMap.get(Number(m.tmdb_id));
          return {
            id: libItem?.id || null,
            tmdb_id: m.tmdb_id,
            title: m.title,
            year: m.year,
            poster_path: m.poster_path,
            type: movieType,
            in_library: !!libItem,
            overview: m.overview,
            is_favorite: libItem?.is_favorite === 1,
            metadata: libItem?.metadata ?? null,
            versions: libItem?.versions ?? [],
          };
        });

        return reply.send({
          id,
          items: finalItems,
        });
      } catch (error: any) {
        request.log.error(error);
        return reply.code(500).send({ error: 'Failed to fetch similar items', details: error.message });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────
  // Playlist Routes
  // ─────────────────────────────────────────────────────────────

  // POST /api/playlists — Create a new playlist
  fastify.post(
    '/api/playlists',
    async (request: FastifyRequest<{ Body: { name: string } }>, reply: FastifyReply) => {
      const { name } = request.body;
      if (!name || !name.trim()) {
        return reply.code(400).send({ error: 'Playlist name is required' });
      }
      try {
        const id = `pl_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        db.prepare(`
          CREATE TABLE IF NOT EXISTS playlists (
            id TEXT PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        `).run();
        db.prepare(`INSERT INTO playlists (id, name) VALUES (?, ?)`).run(id, name.trim());
        return reply.status(201).send({ id, name: name.trim() });
      } catch (err: any) {
        if (err.message?.includes('UNIQUE')) {
          return reply.code(409).send({ error: 'Playlist already exists' });
        }
        return reply.code(500).send({ error: 'Failed to create playlist', details: err.message });
      }
    }
  );

  // POST /api/playlists/:id/items — Add a media item to a playlist
  fastify.post(
    '/api/playlists/:id/items',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { mediaItemId: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const { mediaItemId } = request.body;
      if (!mediaItemId) {
        return reply.code(400).send({ error: 'mediaItemId is required' });
      }
      try {
        db.prepare(`
          CREATE TABLE IF NOT EXISTS playlist_items (
            id TEXT PRIMARY KEY,
            playlist_id TEXT NOT NULL,
            media_item_id TEXT NOT NULL,
            added_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        `).run();
        const itemId = `pli_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        db.prepare(`INSERT INTO playlist_items (id, playlist_id, media_item_id) VALUES (?, ?, ?)`)
          .run(itemId, id, mediaItemId);
        return reply.status(201).send({ id: itemId, playlist_id: id, media_item_id: mediaItemId });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to add item to playlist', details: err.message });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────
  // Watchlist & Download Request Routes
  // ─────────────────────────────────────────────────────────────

  // GET /api/watchlist — Retrieve all watchlist items
  fastify.get(
    '/api/watchlist',
    async (request: FastifyRequest, reply: FastifyReply) => {
      try {
        const items = db.prepare(`SELECT * FROM watchlist ORDER BY added_at DESC`).all() as any[];
        return reply.send(items);
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to fetch watchlist', details: err.message });
      }
    }
  );

  // POST /api/watchlist — Add an item to the watchlist
  fastify.post(
    '/api/watchlist',
    async (request: FastifyRequest<{ Body: { tmdbId: string; title: string; type: string; year?: number; posterPath?: string } }>, reply: FastifyReply) => {
      const { tmdbId, title, type, year, posterPath } = request.body;
      if (!tmdbId || !title || !type) {
        return reply.code(400).send({ error: 'tmdbId, title, and type are required' });
      }
      try {
        const id = `wl_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        db.prepare(`
          INSERT INTO watchlist (id, tmdb_id, title, type, year, poster_path, status)
          VALUES (?, ?, ?, ?, ?, ?, 'pending')
          ON CONFLICT(tmdb_id) DO UPDATE SET status='pending'
        `).run(id, tmdbId.toString(), title, type, year ?? null, posterPath ?? null);
        
        return reply.status(201).send({ id, tmdb_id: tmdbId, title, type, year, poster_path: posterPath, status: 'pending' });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to add item to watchlist', details: err.message });
      }
    }
  );

  // DELETE /api/watchlist/:tmdbId — Remove an item from the watchlist
  fastify.delete(
    '/api/watchlist/:tmdbId',
    async (request: FastifyRequest<{ Params: { tmdbId: string } }>, reply: FastifyReply) => {
      const { tmdbId } = request.params;
      try {
        db.prepare(`DELETE FROM watchlist WHERE tmdb_id = ?`).run(tmdbId.toString());
        return reply.send({ success: true, message: 'Removed from watchlist' });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to remove from watchlist', details: err.message });
      }
    }
  );

  // GET /api/media/items/:id/tech-info — Run ffprobe on-demand and return structured technical info
  fastify.get(
    '/api/media/items/:id/tech-info',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      let filePath: string | null = null;

      const item = db.prepare('SELECT file_path, type FROM media_items WHERE id = ? AND deleted_at IS NULL').get(id) as any;
      if (item) {
        if (item.file_path) {
          filePath = item.file_path;
        } else if (item.type === 'Show') {
          // For shows, use the first available episode
          const ep = db.prepare(`SELECT file_path FROM episodes WHERE show_id = ? AND deleted_at IS NULL AND file_path IS NOT NULL LIMIT 1`).get(id) as any;
          filePath = ep?.file_path || null;
        }
      } else {
        // May be an episode ID
        const ep = db.prepare('SELECT file_path FROM episodes WHERE id = ? AND deleted_at IS NULL').get(id) as any;
        filePath = ep?.file_path || null;
      }

      if (!filePath) return reply.code(404).send({ error: 'No file found for this media item' });

      try {
        const info = await probeTechInfo(filePath);
        return reply.send(info);
      } catch (err: any) {
        return reply.code(500).send({ error: 'ffprobe failed', details: err.message });
      }
    }
  );

  // Register both GET and HEAD routes to support pre-warming
  const trailerStreamHandler = async (request: FastifyRequest<{ Querystring: { url?: string, title?: string, year?: string } }>, reply: FastifyReply) => {
      const youtubeUrl = (request.query as any).url as string | undefined;
      const title = (request.query as any).title as string | undefined;
      const year = (request.query as any).year as string | undefined;
      if (!youtubeUrl) return reply.code(400).send({ error: 'Missing url parameter' });

      try {
        const ytdlp = new YTDlpWrap();

        // Auto-download yt-dlp binary if not present
        const ytdlpPath = path.join(process.cwd(), 'yt-dlp' + (process.platform === 'win32' ? '.exe' : ''));
        if (!fs.existsSync(ytdlpPath)) {
          await YTDlpWrap.downloadFromGithub(ytdlpPath);
        }
        ytdlp.setBinaryPath(ytdlpPath);

        let query = youtubeUrl;
        if (youtubeUrl.includes('results?search_query=')) {
          query = `ytsearch10:${new URL(youtubeUrl).searchParams.get('search_query')}`;
        }

        const { execSync, spawn } = require('child_process');
        const crypto = require('crypto');

        const extractVideoId = (output: string) => {
          const lines = output.trim().split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('ERROR:') && !l.startsWith('WARNING:'));
          return lines.length > 0 ? lines[lines.length - 1] : '';
        };

        // Cache resolution
        // @ts-ignore
        if (!global.videoIdCache) global.videoIdCache = {};
        let videoId = '';
        
        // @ts-ignore
        if (global.videoIdCache[query]) {
          // @ts-ignore
          videoId = global.videoIdCache[query];
        } else {
          // 1. Find the first working ID
          try {
            const out = execSync(`"${ytdlpPath}" "${query}" --get-id -i --max-downloads 1 --no-warnings`).toString();
            videoId = extractVideoId(out);
          } catch (err: any) {
            const out = err.stdout?.toString();
            if (out) videoId = extractVideoId(out);
          }

          // FALLBACK: If the TMDB trailer url was dead, try a direct search using title and year
          if (!videoId && title) {
             const fallbackQuery = `ytsearch5:${title} ${year || ''} official trailer`;
             // @ts-ignore
             if (global.videoIdCache[fallbackQuery]) {
               // @ts-ignore
               videoId = global.videoIdCache[fallbackQuery];
             } else {
               try {
                 const out = execSync(`"${ytdlpPath}" "${fallbackQuery}" --get-id -i --max-downloads 1 --no-warnings`).toString();
                 videoId = extractVideoId(out);
                 // @ts-ignore
                 if (videoId) global.videoIdCache[fallbackQuery] = videoId;
               } catch (err: any) {
                 const out = err.stdout?.toString();
                 if (out) videoId = extractVideoId(out);
                 // @ts-ignore
                 if (videoId) global.videoIdCache[fallbackQuery] = videoId;
               }
             }
          }
          // @ts-ignore
          if (videoId) global.videoIdCache[query] = videoId;
        }

        if (!videoId) {
          return reply.code(404).send({ error: 'No available trailer found' });
        }

        // 2. Stream using ffmpeg on-the-fly merging or cache
        const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg');
        const tmpDir = require('os').tmpdir();
        const outputPath = path.join(tmpDir, `loom_trailer_${videoId}.mp4`);

        // If not cached, download and merge
        if (!fs.existsSync(outputPath) || fs.statSync(outputPath).size === 0) {
           const cp = spawn(ytdlpPath, [
             '-q',
             '--no-warnings',
             '--ffmpeg-location', ffmpegInstaller.path,
             '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best',
             '--merge-output-format', 'mp4',
             '-o', outputPath,
             `https://www.youtube.com/watch?v=${videoId}`
           ]);
           await new Promise<void>((resolve, reject) => {
             cp.on('close', (code: number | null) => {
               if (code === 0 && fs.existsSync(outputPath) && fs.statSync(outputPath).size > 0) resolve();
               else reject(new Error(`yt-dlp exited with code ${code}`));
             });
             cp.on('error', reject);
           });
        }

        // Serve cached file with Range support
        const stat = fs.statSync(outputPath);
        const range = request.headers.range;
        const contentType = 'video/mp4';

        reply.header('Accept-Ranges', 'bytes');
        reply.header('Content-Type', contentType);
        reply.header('Access-Control-Allow-Origin', '*');

        if (request.method === 'HEAD') {
          reply.raw.writeHead(200, {
            'Content-Length': stat.size,
            'Content-Type': contentType,
          });
          reply.raw.end();
          return;
        }

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
          fs.createReadStream(outputPath, { start, end }).pipe(reply.raw);
          return;
        }

        reply.raw.writeHead(200, {
          'Content-Length': stat.size,
          'Content-Type': contentType,
          'Accept-Ranges': 'bytes',
        });
        fs.createReadStream(outputPath).pipe(reply.raw);
        return;
      } catch (err: any) {
        request.log.error(err);
        return reply.code(500).send({ error: 'Failed to stream trailer', details: err.message });
      }
    };

  fastify.get('/api/media/trailer-stream', trailerStreamHandler);
  fastify.head('/api/media/trailer-stream', trailerStreamHandler);
}

function probeTechInfo(filePath: string): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const escaped = filePath.replace(/"/g, '\\"');
    const cmd = `"${ffprobeInstaller.path}" -v quiet -print_format json -show_streams -show_format "${escaped}"`;
    exec(cmd, { timeout: 20000, maxBuffer: 10 * 1024 * 1024 }, (err, stdout) => {
      if (err) return reject(err);
      try {
        const probe = JSON.parse(stdout);
        const streams: any[] = probe.streams || [];
        const format: any = probe.format || {};

        const coverArtCodecs = ['mjpeg', 'png', 'bmp', 'gif', 'tiff', 'webp'];
        const videoStream = streams.find(
          (s) => s.codec_type === 'video' && !coverArtCodecs.includes((s.codec_name || '').toLowerCase())
        );
        const audioStream = streams.find((s) => s.codec_type === 'audio');

        // Frame rate fraction → decimal string (e.g. "24000/1001" → "23.976")
        let frameRate: string | null = null;
        if (videoStream?.r_frame_rate) {
          const parts = (videoStream.r_frame_rate as string).split('/');
          if (parts.length === 2) {
            const fps = parseFloat(parts[0]) / parseFloat(parts[1]);
            frameRate = fps.toFixed(3).replace(/\.?0+$/, '');
          }
        }

        // Chroma subsampling from pix_fmt
        const pixFmt: string = videoStream?.pix_fmt || '';
        let chromaSubsampling: string | null = null;
        if (pixFmt.includes('420')) chromaSubsampling = '4:2:0';
        else if (pixFmt.includes('422')) chromaSubsampling = '4:2:2';
        else if (pixFmt.includes('444')) chromaSubsampling = '4:4:4';
        else if (pixFmt.includes('400')) chromaSubsampling = '4:0:0';

        // Resolution label
        const w: number = videoStream?.width || 0;
        const h: number = videoStream?.height || 0;
        let resolution: string | null = null;
        if (w >= 3200 || h >= 2000)      resolution = '4K';
        else if (w >= 1900 || h >= 1000) resolution = '1080p';
        else if (w >= 1100 || h >= 650)  resolution = '720p';
        else if (w >= 700  || h >= 420)  resolution = '480p';
        else if (h > 0)                  resolution = `${h}p`;

        // Container name
        const fmtName = (format.format_name || '').split(',')[0];
        const containerMap: Record<string, string> = {
          matroska: 'MKV', webm: 'WebM', mov: 'MOV', mp4: 'MP4',
          avi: 'AVI', mpeg: 'MPEG', mpegts: 'TS', flv: 'FLV', ogg: 'OGG',
        };
        const container = containerMap[fmtName] || fmtName.toUpperCase();

        // Video level (e.g. 41 → "4.1")
        let level: string | null = null;
        if (videoStream?.level != null) {
          const lvl = parseInt(String(videoStream.level), 10);
          if (!isNaN(lvl) && lvl > 0) level = `${Math.floor(lvl / 10)}.${lvl % 10}`;
        }

        // Aspect ratio as decimal (e.g. 1920/1040 → "1.85")
        let aspectRatio: string | null = null;
        if (w > 0 && h > 0) aspectRatio = (w / h).toFixed(2).replace(/\.?0+$/, '');

        // Duration
        const durationSec = parseFloat(format.duration || '0');
        const durH = Math.floor(durationSec / 3600);
        const durM = Math.floor((durationSec % 3600) / 60);
        const durS = Math.floor(durationSec % 60);
        const durationStr = durH > 0
          ? `${durH}:${String(durM).padStart(2, '0')}:${String(durS).padStart(2, '0')}`
          : `${durM}:${String(durS).padStart(2, '0')}`;

        resolve({
          filename: path.basename(filePath),
          file_path: filePath,
          file_size_bytes: parseInt(format.size || '0', 10),
          duration_str: durationStr,
          duration_seconds: Math.floor(durationSec),
          total_bitrate_kbps: Math.round(parseInt(format.bit_rate || '0', 10) / 1000),
          container,
          resolution,
          video: videoStream ? {
            codec: (videoStream.codec_name || '').toUpperCase(),
            profile: videoStream.profile || null,
            level,
            width: videoStream.width || null,
            height: videoStream.height || null,
            coded_width: videoStream.coded_width || null,
            coded_height: videoStream.coded_height || null,
            frame_rate: frameRate,
            bitrate_kbps: Math.round(parseInt(videoStream.bit_rate || '0', 10) / 1000) || null,
            bit_depth: parseInt(String(videoStream.bits_per_raw_sample || '0'), 10) || null,
            pix_fmt: pixFmt || null,
            chroma_subsampling: chromaSubsampling,
            chroma_location: videoStream.chroma_location || null,
            aspect_ratio: aspectRatio,
          } : null,
          audio: streams
            .filter((s) => s.codec_type === 'audio')
            .map((s) => ({
              codec: (s.codec_name || '').toUpperCase(),
              profile: s.profile || (s.codec_name || '').toUpperCase(),
              language: s.tags?.language || 'und',
              channels: s.channels || 2,
              bitrate_kbps: Math.round(parseInt(s.bit_rate || '0', 10) / 1000) || null,
              title: s.tags?.title || null,
            })),
          subtitles: streams
            .filter((s) => s.codec_type === 'subtitle')
            .map((s) => ({
              codec: (s.codec_name || '').toUpperCase(),
              language: s.tags?.language || 'und',
              title: s.tags?.title || null,
            })),
        });
      } catch (e) {
        reject(e);
      }
    });
  });
}
