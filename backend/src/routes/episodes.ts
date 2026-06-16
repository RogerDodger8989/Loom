import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';
import { v4 as uuidv4 } from 'uuid';
import path from 'path';
import fs from 'fs';
import { computeTrashPath } from '../utils/trash';

const anonymousUser = { id: 'public', username: 'guest', role: 'user' };

export default async function episodesRoutes(fastify: FastifyInstance) {
  // POST /api/media/items/:id/season/:season/favorite
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

  // GET /api/media/episodes/:episodeId
  // Returns a single episode with watch status for the current user
  fastify.get(
    '/api/media/episodes/:episodeId',
    async (request: FastifyRequest<{ Params: { episodeId: string } }>, reply: FastifyReply) => {
      const user = (request.user as { id: string } | undefined) ?? anonymousUser;
      const { episodeId } = request.params;
      try {
        const ep = db.prepare(`
          SELECT e.id, e.show_id, e.season_number, e.episode_number, e.title, e.file_path,
                 e.air_date, e.overview, e.still_path
          FROM episodes e
          WHERE e.id = ? AND (e.deleted_at IS NULL OR e.deleted_at = '')
        `).get(episodeId) as any;
        if (!ep) return reply.code(404).send({ error: 'Episode not found' });

        const wh = db.prepare(`SELECT is_watched, last_position_seconds FROM watch_history WHERE user_id = ? AND episode_id = ?`).get(user.id, episodeId) as any;
        return reply.send({
          ...Object.fromEntries(Object.entries(ep)),
          is_watched: wh?.is_watched ?? 0,
          playback_progress: wh?.last_position_seconds ?? 0,
        });
      } catch (err) {
        console.error('[Episodes] fetchById failed:', err);
        return reply.code(500).send({ error: 'Failed to fetch episode' });
      }
    }
  );

  // POST /api/media/episodes/:episodeId/progress
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
}
