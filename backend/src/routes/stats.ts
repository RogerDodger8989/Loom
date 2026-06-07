import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import * as os from 'os';
import * as fs from 'fs';
import * as path from 'path';
import db from '../config/database';

const dbPath = path.resolve(__dirname, '../../../config/loom.db');
const startedAt = Date.now();

function sampleCpu(): { idle: number; total: number }[] {
  return os.cpus().map(c => {
    const total = Object.values(c.times).reduce((a, b) => a + b, 0);
    return { idle: c.times.idle, total };
  });
}

async function getCpuPercent(): Promise<number> {
  const s1 = sampleCpu();
  await new Promise(r => setTimeout(r, 500));
  const s2 = sampleCpu();
  let idleDelta = 0, totalDelta = 0;
  for (let i = 0; i < s1.length; i++) {
    idleDelta  += s2[i].idle  - s1[i].idle;
    totalDelta += s2[i].total - s1[i].total;
  }
  return totalDelta === 0 ? 0 : Math.round((1 - idleDelta / totalDelta) * 100);
}

export default async function statsRoutes(fastify: FastifyInstance) {

  // GET /api/stats/realtime — CPU, RAM, upptime, DB-storlek
  fastify.get('/api/stats/realtime', async (_req, reply) => {
    const cpuPercent = await getCpuPercent();
    const totalMem  = os.totalmem();
    const freeMem   = os.freemem();
    const usedMem   = totalMem - freeMem;
    const dbSize    = fs.existsSync(dbPath) ? fs.statSync(dbPath).size : 0;
    const uptimeSeconds = Math.floor((Date.now() - startedAt) / 1000);

    return reply.send({
      cpuPercent,
      totalMemBytes: totalMem,
      usedMemBytes:  usedMem,
      memPercent:    Math.round((usedMem / totalMem) * 100),
      dbSizeBytes:   dbSize,
      uptimeSeconds,
      cpuModel:      os.cpus()[0]?.model ?? 'okänd',
      cpuCores:      os.cpus().length,
    });
  });

  // GET /api/stats/history?userId=X&days=30&startDate=2024-01-01&endDate=2024-12-31&limit=50
  fastify.get('/api/stats/history', async (req, reply) => {
    const { userId, days, startDate, endDate, limit: limitStr } = (req.query as any);
    const daysNum  = parseInt(days  ?? '0', 10) || 0;
    const limitNum = parseInt(limitStr ?? '50', 10) || 50;

    const conditions: string[] = ['1=1'];
    const params: any[] = [];

    if (userId) {
      conditions.push('wh.user_id = ?');
      params.push(userId);
    }

    if (startDate || endDate) {
      if (startDate) {
        conditions.push('date(wh.updated_at) >= ?');
        params.push(startDate);
      }
      if (endDate) {
        conditions.push('date(wh.updated_at) <= ?');
        params.push(endDate);
      }
    } else if (daysNum > 0) {
      conditions.push(`wh.updated_at >= datetime('now', '-${daysNum} days')`);
    }

    const where = conditions.join(' AND ');

    const totalWatched = (db.prepare(`
      SELECT COUNT(*) as c FROM watch_history wh
      WHERE ${where} AND wh.is_watched = 1
    `).get(...params) as { c: number }).c;

    const totalMinutes = (db.prepare(`
      SELECT COALESCE(SUM(total_duration_seconds), 0) as s
      FROM watch_history wh
      WHERE ${where} AND wh.is_watched = 1
    `).get(...params) as { s: number }).s;

    // All-time totals (no filter) for dashboard stats
    const allTimeTotals = db.prepare(`
      SELECT
        COUNT(DISTINCT CASE WHEN wh.is_watched = 1 THEN COALESCE(wh.media_item_id, wh.episode_id) END) AS uniqueTitles,
        COALESCE(SUM(CASE WHEN wh.is_watched = 1 THEN wh.total_duration_seconds ELSE 0 END), 0)         AS totalSeconds,
        COUNT(DISTINCT wh.user_id) AS activeUsers
      FROM watch_history wh
    `).get() as any;

    const recent = db.prepare(`
      SELECT
        wh.id,
        wh.media_item_id,
        wh.updated_at,
        wh.is_watched,
        wh.last_position_seconds,
        wh.total_duration_seconds,
        u.username,
        COALESCE(m.title, ep.title) AS title,
        COALESCE(m.type, 'Episode')  AS type,
        m.poster_path,
        m.year,
        ep.season_number,
        ep.episode_number
      FROM watch_history wh
      LEFT JOIN users u         ON u.id = wh.user_id
      LEFT JOIN media_items m   ON m.id = wh.media_item_id AND m.deleted_at IS NULL
      LEFT JOIN episodes ep     ON ep.id = wh.episode_id
      WHERE ${where}
      ORDER BY wh.updated_at DESC
      LIMIT ?
    `).all(...params, limitNum);

    return reply.send({
      totalWatched,
      totalMinutes: Math.round(totalMinutes / 60),
      allTimeTotals,
      recent,
    });
  });

  // GET /api/stats/users — per-användarstatistik
  fastify.get('/api/stats/users', async (_req, reply) => {
    const rows = db.prepare(`
      SELECT
        u.id,
        u.username,
        u.role,
        COUNT(wh.id)                                          AS totalEntries,
        COALESCE(SUM(wh.is_watched), 0)                       AS watched,
        COALESCE(SUM(CASE WHEN wh.is_watched = 1 THEN wh.total_duration_seconds ELSE 0 END), 0) AS totalSeconds,
        MAX(wh.updated_at)                                    AS lastSeen
      FROM users u
      LEFT JOIN watch_history wh ON wh.user_id = u.id
      GROUP BY u.id
      ORDER BY watched DESC
    `).all();
    return reply.send(rows);
  });

  // GET /api/stats/tops — top 10 film, TV-serier och användare
  fastify.get('/api/stats/tops', async (_req, reply) => {
    const topMovies = db.prepare(`
      SELECT
        m.id,
        m.title,
        m.poster_path,
        m.year,
        m.type,
        COUNT(wh.id)                                      AS playCount,
        COALESCE(SUM(wh.total_duration_seconds), 0)       AS totalSeconds
      FROM watch_history wh
      JOIN media_items m ON m.id = wh.media_item_id AND m.deleted_at IS NULL
      WHERE m.type = 'Movie' AND wh.is_watched = 1
      GROUP BY m.id
      ORDER BY playCount DESC
      LIMIT 10
    `).all();

    const topShows = db.prepare(`
      SELECT
        m.id,
        m.title,
        m.poster_path,
        m.year,
        m.type,
        COUNT(wh.id)                                      AS playCount,
        COALESCE(SUM(wh.total_duration_seconds), 0)       AS totalSeconds
      FROM watch_history wh
      JOIN episodes ep ON ep.id = wh.episode_id
      JOIN media_items m ON m.id = ep.show_id AND m.deleted_at IS NULL
      WHERE wh.is_watched = 1
      GROUP BY m.id
      ORDER BY playCount DESC
      LIMIT 10
    `).all();

    const topUsers = db.prepare(`
      SELECT
        u.id,
        u.username,
        u.role,
        COALESCE(SUM(wh.is_watched), 0)                       AS watched,
        COALESCE(SUM(CASE WHEN wh.is_watched = 1 THEN wh.total_duration_seconds ELSE 0 END), 0) AS totalSeconds
      FROM users u
      LEFT JOIN watch_history wh ON wh.user_id = u.id
        AND wh.updated_at >= datetime('now', '-30 days')
      GROUP BY u.id
      ORDER BY totalSeconds DESC
      LIMIT 10
    `).all();

    return reply.send({ topMovies, topShows, topUsers });
  });

  // GET /api/stats/media/:mediaId/plays — spelningshistorik för ett specifikt medium
  fastify.get('/api/stats/media/:mediaId/plays', async (req, reply) => {
    const { mediaId } = req.params as { mediaId: string };

    const mediaItem = db.prepare(`
      SELECT id, title, type, poster_path FROM media_items WHERE id = ? AND deleted_at IS NULL
    `).get(mediaId) as any;

    if (!mediaItem) return reply.status(404).send({ error: 'Media hittades inte' });

    let plays: any[];

    if (mediaItem.type === 'Movie') {
      plays = db.prepare(`
        SELECT
          u.id                                                          AS userId,
          u.username,
          wh.updated_at,
          wh.is_watched,
          wh.last_position_seconds,
          wh.total_duration_seconds,
          datetime(wh.updated_at, '-' || wh.last_position_seconds || ' seconds') AS started_at_approx
        FROM watch_history wh
        JOIN users u ON u.id = wh.user_id
        WHERE wh.media_item_id = ?
        ORDER BY wh.updated_at DESC
      `).all(mediaId) as any[];
    } else {
      // TV-serie — aggregerat per användare
      plays = db.prepare(`
        SELECT
          u.id                                                                    AS userId,
          u.username,
          MAX(wh.updated_at)                                                      AS updated_at,
          COUNT(wh.id)                                                            AS episode_count,
          COALESCE(SUM(wh.is_watched), 0)                                        AS completed_count,
          COALESCE(SUM(CASE WHEN wh.is_watched = 1 THEN wh.total_duration_seconds ELSE wh.last_position_seconds END), 0) AS totalSeconds,
          MIN(datetime(wh.updated_at, '-' || wh.last_position_seconds || ' seconds')) AS first_watched_approx
        FROM watch_history wh
        JOIN users u ON u.id = wh.user_id
        JOIN episodes ep ON ep.id = wh.episode_id
        WHERE ep.show_id = ?
        GROUP BY u.id
        ORDER BY updated_at DESC
      `).all(mediaId) as any[];
    }

    return reply.send({ mediaItem, plays });
  });
}
