import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { v4 as uuidv4 } from 'uuid';
import db from '../config/database';
import {
  scanChaptersForItem,
  extractAudioFingerprint,
  storeFingerprintForEpisode,
  detectAndStoreIntroForShow,
  ensureFingerprintUniqueIndex,
} from '../services/marker_service';

// Track in-progress background scans to avoid duplicates
const activeScanJobs = new Set<string>();

export default async function markersRoutes(fastify: FastifyInstance) {
  ensureFingerprintUniqueIndex();

  // GET /api/markers/:id — list all markers for a media item or episode
  fastify.get(
    '/api/markers/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      try {
        // Try episode first, then media_item
        const episodeRow = db.prepare(`SELECT id FROM episodes WHERE id = ?`).get(id) as any;
        const mediaRow = !episodeRow
          ? db.prepare(`SELECT id FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any
          : null;

        if (!episodeRow && !mediaRow) {
          return reply.code(404).send({ error: 'Not found' });
        }

        const markers = db.prepare(`
          SELECT id, marker_type, start_time_seconds, end_time_seconds, title, source
          FROM media_markers
          WHERE ${episodeRow ? 'episode_id = ?' : 'media_item_id = ?'}
          ORDER BY start_time_seconds ASC
        `).all(id);

        // Also include legacy episode_markers
        const legacy = episodeRow
          ? db.prepare(`
              SELECT id, marker_type, start_time_seconds, end_time_seconds, NULL as title, 'manual' as source
              FROM episode_markers WHERE episode_id = ?
            `).all(id)
          : [];

        return reply.send({ markers: [...markers, ...legacy] });
      } catch (err: any) {
        return reply.code(500).send({ error: err.message });
      }
    }
  );

  // POST /api/markers/scan-chapters/:id — extract chapter markers from file
  fastify.post(
    '/api/markers/scan-chapters/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const jobKey = `chapters:${id}`;
      if (activeScanJobs.has(jobKey)) {
        return reply.send({ status: 'already_running' });
      }
      activeScanJobs.add(jobKey);

      // Determine if movie or episode
      let filePath: string | null = null;
      let mediaItemId: string | null = null;
      let episodeId: string | null = null;

      const movie = db.prepare(`SELECT file_path FROM media_items WHERE id = ? AND deleted_at IS NULL`).get(id) as any;
      if (movie) {
        filePath = movie.file_path;
        mediaItemId = id;
      } else {
        const ep = db.prepare(`SELECT file_path FROM episodes WHERE id = ?`).get(id) as any;
        if (ep) {
          filePath = ep.file_path;
          episodeId = id;
        }
      }

      if (!filePath) {
        activeScanJobs.delete(jobKey);
        return reply.code(404).send({ error: 'Item not found' });
      }

      reply.send({ status: 'scanning' });

      setImmediate(async () => {
        try {
          const count = await scanChaptersForItem(filePath!, mediaItemId, episodeId);
          console.log(`[Markers] Chapter scan for ${id}: ${count} chapters found`);
        } catch (e) {
          console.error(`[Markers] Chapter scan failed for ${id}:`, e);
        } finally {
          activeScanJobs.delete(jobKey);
        }
      });
    }
  );

  // POST /api/markers/scan-fingerprint/:episodeId — compute audio fingerprint for an episode
  fastify.post(
    '/api/markers/scan-fingerprint/:episodeId',
    async (request: FastifyRequest<{ Params: { episodeId: string } }>, reply: FastifyReply) => {
      const { episodeId } = request.params;
      const jobKey = `fp:${episodeId}`;
      if (activeScanJobs.has(jobKey)) {
        return reply.send({ status: 'already_running' });
      }
      activeScanJobs.add(jobKey);

      const ep = db.prepare(`SELECT file_path, show_id FROM episodes WHERE id = ?`).get(episodeId) as any;
      if (!ep) {
        activeScanJobs.delete(jobKey);
        return reply.code(404).send({ error: 'Episode not found' });
      }

      reply.send({ status: 'scanning', episodeId });

      setImmediate(async () => {
        try {
          const { fingerprint, durationSeconds } = await extractAudioFingerprint(ep.file_path);
          storeFingerprintForEpisode(episodeId, fingerprint, durationSeconds);
          console.log(`[Markers] Fingerprint for episode ${episodeId}: ${fingerprint.length} units`);

          // Auto-detect intro if show has enough fingerprinted episodes
          if (ep.show_id) {
            const fpCount = (db.prepare(`
              SELECT COUNT(*) as cnt FROM audio_fingerprints af
              JOIN episodes e ON e.id = af.episode_id
              WHERE e.show_id = ?
            `).get(ep.show_id) as any).cnt;

            if (fpCount >= 2) {
              const result = await detectAndStoreIntroForShow(ep.show_id);
              console.log(`[Markers] Intro detection for show ${ep.show_id}: ${result.markersCreated} markers created`);
            }
          }
        } catch (e) {
          console.error(`[Markers] Fingerprint scan failed for ${episodeId}:`, e);
        } finally {
          activeScanJobs.delete(jobKey);
        }
      });
    }
  );

  // POST /api/markers/scan-show/:showId — fingerprint ALL episodes of a show (background)
  fastify.post(
    '/api/markers/scan-show/:showId',
    async (request: FastifyRequest<{ Params: { showId: string } }>, reply: FastifyReply) => {
      const { showId } = request.params;
      const jobKey = `show:${showId}`;
      if (activeScanJobs.has(jobKey)) {
        return reply.send({ status: 'already_running' });
      }
      activeScanJobs.add(jobKey);

      const episodes = db.prepare(`
        SELECT id, file_path FROM episodes WHERE show_id = ? ORDER BY season_number, episode_number
      `).all(showId) as Array<{ id: string; file_path: string }>;

      if (episodes.length === 0) {
        activeScanJobs.delete(jobKey);
        return reply.code(404).send({ error: 'No episodes found' });
      }

      reply.send({ status: 'scanning', episodeCount: episodes.length });

      setImmediate(async () => {
        try {
          let processed = 0;
          for (const ep of episodes) {
            const existing = db.prepare(`SELECT id FROM audio_fingerprints WHERE episode_id = ?`).get(ep.id);
            if (existing) { processed++; continue; }

            try {
              const { fingerprint, durationSeconds } = await extractAudioFingerprint(ep.file_path);
              storeFingerprintForEpisode(ep.id, fingerprint, durationSeconds);
              processed++;
              console.log(`[Markers] Show scan ${showId}: ${processed}/${episodes.length} episodes fingerprinted`);
            } catch (e) {
              console.error(`[Markers] Failed to fingerprint episode ${ep.id}:`, e);
            }
          }

          if (processed >= 2) {
            const result = await detectAndStoreIntroForShow(showId);
            console.log(`[Markers] Show ${showId} intro detection: ${result.markersCreated} markers`);
          }
        } catch (e) {
          console.error(`[Markers] Show scan failed for ${showId}:`, e);
        } finally {
          activeScanJobs.delete(jobKey);
        }
      });
    }
  );

  // POST /api/markers/detect-intro/:showId — (re)detect intro using existing fingerprints
  fastify.post(
    '/api/markers/detect-intro/:showId',
    async (request: FastifyRequest<{ Params: { showId: string } }>, reply: FastifyReply) => {
      const { showId } = request.params;
      try {
        const result = await detectAndStoreIntroForShow(showId);
        return reply.send(result);
      } catch (err: any) {
        return reply.code(500).send({ error: err.message });
      }
    }
  );

  // POST /api/markers — create a manual marker
  fastify.post(
    '/api/markers',
    async (request: FastifyRequest<{
      Body: {
        mediaItemId?: string;
        episodeId?: string;
        markerType: string;
        startSeconds: number;
        endSeconds: number;
        title?: string;
      }
    }>, reply: FastifyReply) => {
      const { mediaItemId, episodeId, markerType, startSeconds, endSeconds, title } = request.body;
      if (!markerType || startSeconds == null || endSeconds == null) {
        return reply.code(400).send({ error: 'markerType, startSeconds, endSeconds required' });
      }
      try {
        const id = uuidv4();
        db.prepare(`
          INSERT INTO media_markers (id, media_item_id, episode_id, marker_type, start_time_seconds, end_time_seconds, title, source)
          VALUES (?, ?, ?, ?, ?, ?, ?, 'manual')
        `).run(id, mediaItemId ?? null, episodeId ?? null, markerType, startSeconds, endSeconds, title ?? null);
        return reply.code(201).send({ id });
      } catch (err: any) {
        return reply.code(500).send({ error: err.message });
      }
    }
  );

  // DELETE /api/markers/:markerId — delete a specific marker
  fastify.delete(
    '/api/markers/:markerId',
    async (request: FastifyRequest<{ Params: { markerId: string } }>, reply: FastifyReply) => {
      const { markerId } = request.params;
      try {
        db.prepare(`DELETE FROM media_markers WHERE id = ?`).run(markerId);
        return reply.send({ success: true });
      } catch (err: any) {
        return reply.code(500).send({ error: err.message });
      }
    }
  );

  // GET /api/markers/scan-status — check active scans
  fastify.get(
    '/api/markers/scan-status',
    async (_request: FastifyRequest, reply: FastifyReply) => {
      return reply.send({ activeScans: [...activeScanJobs] });
    }
  );
}
