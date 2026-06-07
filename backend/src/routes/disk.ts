import { FastifyInstance, FastifyRequest } from 'fastify';
import db from '../config/database';
import * as fs from 'fs';
import * as path from 'path';

// ─── Helpers ───────────────────────────────────────────────────────────────

function getSetting(key: string, def: string): string {
  const row = db.prepare('SELECT value FROM system_settings WHERE key = ?').get(key) as { value: string } | undefined;
  return row?.value ?? def;
}

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
  if (!libraryBase) libraryBase = path.dirname(path.dirname(filePath));
  const relative = filePath.substring(libraryBase.length).replace(/^[/\\]/, '');
  return path.join(libraryBase, '.trash', relative);
}

function getFileSizeBytes(filePath: string | null | undefined): number {
  if (!filePath) return 0;
  try { return fs.statSync(filePath).size; } catch { return 0; }
}

function daysSince(dateStr: string | null | undefined): number | null {
  if (!dateStr) return null;
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return null;
  return Math.floor((Date.now() - d.getTime()) / (1000 * 60 * 60 * 24));
}

interface DiskRules {
  watchedEnabled: boolean;
  watchedDays: number;
  unseenEnabled: boolean;
  unseenDays: number;
  inactiveEnabled: boolean;
  inactiveDays: number;
  sizeEnabled: boolean;
  sizeGb: number;
  sizeRequireWatched: boolean;
  ratingEnabled: boolean;
  ratingMax: number;
  seriesMode: 'episode' | 'season' | 'show';
  protectFavorites: boolean;
}

function loadRules(): DiskRules {
  return {
    watchedEnabled:     getSetting('DISK_RULE_WATCHED_ENABLED', 'false') === 'true',
    watchedDays:        parseInt(getSetting('DISK_RULE_WATCHED_DAYS', '7'), 10) || 7,
    unseenEnabled:      getSetting('DISK_RULE_UNSEEN_ENABLED', 'false') === 'true',
    unseenDays:         parseInt(getSetting('DISK_RULE_UNSEEN_DAYS', '60'), 10) || 60,
    inactiveEnabled:    getSetting('DISK_RULE_INACTIVE_ENABLED', 'false') === 'true',
    inactiveDays:       parseInt(getSetting('DISK_RULE_INACTIVE_DAYS', '365'), 10) || 365,
    sizeEnabled:        getSetting('DISK_RULE_SIZE_ENABLED', 'false') === 'true',
    sizeGb:             parseFloat(getSetting('DISK_RULE_SIZE_GB', '50')) || 50,
    sizeRequireWatched: getSetting('DISK_RULE_SIZE_REQUIRE_WATCHED', 'false') === 'true',
    ratingEnabled:      getSetting('DISK_RULE_RATING_ENABLED', 'false') === 'true',
    ratingMax:          parseFloat(getSetting('DISK_RULE_RATING_MAX', '3')) || 3,
    seriesMode:         getSetting('DISK_RULE_SERIES_MODE', 'episode') as 'episode' | 'season' | 'show',
    protectFavorites:   getSetting('DISK_RULE_PROTECT_FAVORITES', 'true') === 'true',
  };
}

interface Candidate {
  id: string;
  item_type: 'movie' | 'episode' | 'season' | 'show';
  title: string;
  show_title?: string;
  show_id?: string;
  season_number?: number;
  episode_number?: number;
  file_path: string;
  file_size_bytes: number;
  file_size_mb: number;
  trigger_rules: string[];
  reason_details: string;
}

function getWatchInfo(mediaItemId: string, episodeId?: string): {
  isWatched: boolean;
  lastWatchedDate: string | null;
  lastActivityDate: string | null;
} {
  let row: any;
  if (episodeId) {
    row = db.prepare(
      `SELECT is_watched, updated_at FROM watch_history WHERE episode_id = ? ORDER BY updated_at DESC LIMIT 1`
    ).get(episodeId) as any;
  } else {
    row = db.prepare(
      `SELECT is_watched, updated_at FROM watch_history WHERE media_item_id = ? AND episode_id IS NULL ORDER BY updated_at DESC LIMIT 1`
    ).get(mediaItemId) as any;
  }
  if (!row) return { isWatched: false, lastWatchedDate: null, lastActivityDate: null };
  return {
    isWatched: row.is_watched === 1,
    lastWatchedDate: row.is_watched === 1 ? row.updated_at : null,
    lastActivityDate: row.updated_at,
  };
}

function getOwnerRating(mediaItemId: string): number | null {
  const row = db.prepare(
    `SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'my_rating'`
  ).get(mediaItemId) as any;
  if (!row?.metadata_value) return null;
  const n = parseFloat(row.metadata_value);
  return isNaN(n) ? null : n;
}

function isFavorite(mediaItemId: string): boolean {
  const row = db.prepare(
    `SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = 'is_favorite'`
  ).get(mediaItemId) as any;
  return row?.metadata_value === 'true' || row?.metadata_value === '1';
}

interface EvalResult {
  match: boolean;
  triggers: string[];
  details: string;
}

function evaluateRules(rules: DiskRules, params: {
  isWatched: boolean;
  lastWatchedDate: string | null;
  lastActivityDate: string | null;
  addedAt: string;
  fileSizeBytes: number;
  ownerRating: number | null;
  favorite: boolean;
}): EvalResult {
  if (rules.protectFavorites && params.favorite) {
    return { match: false, triggers: [], details: 'Skyddad (favorit)' };
  }

  const triggers: string[] = [];
  const details: string[] = [];

  if (rules.watchedEnabled && params.isWatched) {
    const daysAgo = daysSince(params.lastWatchedDate);
    if (daysAgo !== null && daysAgo >= rules.watchedDays) {
      triggers.push('watched');
      details.push(`Sedd för ${daysAgo} dagar sedan (gräns: ${rules.watchedDays} d)`);
    }
  }

  if (rules.unseenEnabled && !params.isWatched) {
    const daysAgo = daysSince(params.addedAt);
    if (daysAgo !== null && daysAgo >= rules.unseenDays) {
      triggers.push('unseen');
      details.push(`Osedd i ${daysAgo} dagar sedan tillagd (gräns: ${rules.unseenDays} d)`);
    }
  }

  if (rules.inactiveEnabled) {
    const lastActivity = params.lastActivityDate ?? params.addedAt;
    const daysAgo = daysSince(lastActivity);
    if (daysAgo !== null && daysAgo >= rules.inactiveDays) {
      triggers.push('inactive');
      details.push(`Inaktiv i ${daysAgo} dagar (gräns: ${rules.inactiveDays} d)`);
    }
  }

  if (rules.sizeEnabled) {
    const sizeGb = params.fileSizeBytes / (1024 ** 3);
    const meetsWatchReq = !rules.sizeRequireWatched || params.isWatched;
    if (sizeGb >= rules.sizeGb && meetsWatchReq) {
      triggers.push('size');
      details.push(`${sizeGb.toFixed(1)} GB ≥ gräns ${rules.sizeGb} GB`);
    }
  }

  if (rules.ratingEnabled && params.ownerRating !== null) {
    if (params.ownerRating <= rules.ratingMax) {
      triggers.push('rating');
      details.push(`Betyg ${params.ownerRating}/10 ≤ gräns ${rules.ratingMax}`);
    }
  }

  return { match: triggers.length > 0, triggers, details: details.join(' • ') };
}

// ─── Scan logic (shared by dry-run and cleanup) ────────────────────────────

function scanCandidates(rules: DiskRules): Candidate[] {
  const candidates: Candidate[] = [];

  // Movies
  const movies = db.prepare(
    `SELECT id, title, file_path, added_at FROM media_items WHERE type='Movie' AND deleted_at IS NULL`
  ).all() as any[];

  for (const m of movies) {
    const { isWatched, lastWatchedDate, lastActivityDate } = getWatchInfo(m.id);
    const fileSizeBytes = getFileSizeBytes(m.file_path);
    const result = evaluateRules(rules, {
      isWatched, lastWatchedDate, lastActivityDate,
      addedAt: m.added_at, fileSizeBytes,
      ownerRating: getOwnerRating(m.id),
      favorite: isFavorite(m.id),
    });
    if (result.match) {
      candidates.push({
        id: m.id, item_type: 'movie', title: m.title,
        file_path: m.file_path ?? '',
        file_size_bytes: fileSizeBytes,
        file_size_mb: Math.round(fileSizeBytes / (1024 ** 2)),
        trigger_rules: result.triggers,
        reason_details: result.details,
      });
    }
  }

  const shows = db.prepare(
    `SELECT id, title, added_at FROM media_items WHERE type='Show' AND deleted_at IS NULL`
  ).all() as any[];

  if (rules.seriesMode === 'episode') {
    for (const show of shows) {
      const eps = db.prepare(
        `SELECT id, title, file_path, season_number, episode_number FROM episodes WHERE show_id = ? AND deleted_at IS NULL`
      ).all(show.id) as any[];
      for (const ep of eps) {
        const { isWatched, lastWatchedDate, lastActivityDate } = getWatchInfo(show.id, ep.id);
        const fileSizeBytes = getFileSizeBytes(ep.file_path);
        const result = evaluateRules(rules, {
          isWatched, lastWatchedDate, lastActivityDate,
          addedAt: show.added_at, fileSizeBytes,
          ownerRating: getOwnerRating(show.id),
          favorite: isFavorite(show.id),
        });
        if (result.match) {
          candidates.push({
            id: ep.id, item_type: 'episode',
            title: ep.title ?? `Avsnitt ${ep.episode_number}`,
            show_title: show.title, show_id: show.id,
            season_number: ep.season_number, episode_number: ep.episode_number,
            file_path: ep.file_path ?? '',
            file_size_bytes: fileSizeBytes,
            file_size_mb: Math.round(fileSizeBytes / (1024 ** 2)),
            trigger_rules: result.triggers,
            reason_details: result.details,
          });
        }
      }
    }
  } else if (rules.seriesMode === 'season') {
    for (const show of shows) {
      const seasonRows = db.prepare(
        `SELECT DISTINCT season_number FROM episodes WHERE show_id = ? AND deleted_at IS NULL`
      ).all(show.id) as any[];
      for (const { season_number } of seasonRows) {
        const eps = db.prepare(
          `SELECT id, file_path FROM episodes WHERE show_id = ? AND season_number = ? AND deleted_at IS NULL`
        ).all(show.id, season_number) as any[];
        if (!eps.length) continue;

        let allWatched = true, lastWatched: string | null = null;
        let totalBytes = 0, lastActivity: string | null = null;
        for (const ep of eps) {
          const w = getWatchInfo(show.id, ep.id);
          if (!w.isWatched) allWatched = false;
          if (w.lastWatchedDate && (!lastWatched || w.lastWatchedDate > lastWatched)) lastWatched = w.lastWatchedDate;
          if (w.lastActivityDate && (!lastActivity || w.lastActivityDate > lastActivity)) lastActivity = w.lastActivityDate;
          totalBytes += getFileSizeBytes(ep.file_path);
        }

        const result = evaluateRules(rules, {
          isWatched: allWatched, lastWatchedDate: allWatched ? lastWatched : null,
          lastActivityDate: lastActivity, addedAt: show.added_at,
          fileSizeBytes: totalBytes,
          ownerRating: getOwnerRating(show.id), favorite: isFavorite(show.id),
        });
        if (result.match) {
          candidates.push({
            id: `${show.id}:s${season_number}`, item_type: 'season',
            title: `Säsong ${season_number}`, show_title: show.title, show_id: show.id,
            season_number, file_path: eps.map((e: any) => e.file_path).join('|'),
            file_size_bytes: totalBytes, file_size_mb: Math.round(totalBytes / (1024 ** 2)),
            trigger_rules: result.triggers, reason_details: result.details,
          });
        }
      }
    }
  } else if (rules.seriesMode === 'show') {
    for (const show of shows) {
      const eps = db.prepare(
        `SELECT id, file_path FROM episodes WHERE show_id = ? AND deleted_at IS NULL`
      ).all(show.id) as any[];
      if (!eps.length) continue;

      let allWatched = true, lastWatched: string | null = null;
      let totalBytes = 0, lastActivity: string | null = null;
      for (const ep of eps) {
        const w = getWatchInfo(show.id, ep.id);
        if (!w.isWatched) allWatched = false;
        if (w.lastWatchedDate && (!lastWatched || w.lastWatchedDate > lastWatched)) lastWatched = w.lastWatchedDate;
        if (w.lastActivityDate && (!lastActivity || w.lastActivityDate > lastActivity)) lastActivity = w.lastActivityDate;
        totalBytes += getFileSizeBytes(ep.file_path);
      }

      const result = evaluateRules(rules, {
        isWatched: allWatched, lastWatchedDate: allWatched ? lastWatched : null,
        lastActivityDate: lastActivity, addedAt: show.added_at,
        fileSizeBytes: totalBytes,
        ownerRating: getOwnerRating(show.id), favorite: isFavorite(show.id),
      });
      if (result.match) {
        candidates.push({
          id: show.id, item_type: 'show', title: show.title, show_id: show.id,
          file_path: eps.map((e: any) => e.file_path).join('|'),
          file_size_bytes: totalBytes, file_size_mb: Math.round(totalBytes / (1024 ** 2)),
          trigger_rules: result.triggers, reason_details: result.details,
        });
      }
    }
  }

  return candidates;
}

// ─── Move file to trash helper ─────────────────────────────────────────────

function moveToTrash(filePath: string): void {
  if (!filePath || !fs.existsSync(filePath)) return;
  const dest = computeTrashPath(filePath);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.renameSync(filePath, dest);
}

// ─── Route export ──────────────────────────────────────────────────────────

export default async function diskRoutes(fastify: FastifyInstance) {

  // GET /api/disk/stats — library size overview
  fastify.get('/api/disk/stats', async (_req, reply) => {
    try {
      const movies = db.prepare(
        `SELECT file_path FROM media_items WHERE type='Movie' AND deleted_at IS NULL AND file_path IS NOT NULL`
      ).all() as any[];
      const episodes = db.prepare(
        `SELECT e.file_path FROM episodes e INNER JOIN media_items m ON m.id = e.show_id WHERE m.deleted_at IS NULL AND e.deleted_at IS NULL AND e.file_path IS NOT NULL`
      ).all() as any[];

      let movieBytes = 0, showBytes = 0;
      for (const m of movies) movieBytes += getFileSizeBytes(m.file_path);
      for (const e of episodes) showBytes += getFileSizeBytes(e.file_path);
      const totalBytes = movieBytes + showBytes;

      return reply.send({
        total_bytes: totalBytes,
        total_gb: +(totalBytes / (1024 ** 3)).toFixed(2),
        movies_bytes: movieBytes,
        movies_gb: +(movieBytes / (1024 ** 3)).toFixed(2),
        shows_bytes: showBytes,
        shows_gb: +(showBytes / (1024 ** 3)).toFixed(2),
        movie_count: movies.length,
        episode_count: episodes.length,
      });
    } catch (err: any) {
      return reply.code(500).send({ error: 'Failed to compute disk stats', details: err.message });
    }
  });

  // GET /api/disk/scan — dry-run: returns candidates without deleting anything
  fastify.get('/api/disk/scan', async (_req, reply) => {
    try {
      const rules = loadRules();
      const candidates = scanCandidates(rules);
      const totalBytes = candidates.reduce((acc, c) => acc + c.file_size_bytes, 0);
      return reply.send({
        candidates,
        total_candidates: candidates.length,
        total_freeable_bytes: totalBytes,
        total_freeable_gb: +(totalBytes / (1024 ** 3)).toFixed(2),
      });
    } catch (err: any) {
      return reply.code(500).send({ error: 'Failed to run disk scan', details: err.message });
    }
  });

  // POST /api/disk/cleanup — move matching items to trash (marked AUTO-RADERAT)
  fastify.post(
    '/api/disk/cleanup',
    async (request: FastifyRequest<{ Body: { ids?: string[] } }>, reply) => {
      try {
        const rules = loadRules();
        const selectedIds: string[] | undefined = (request.body as any)?.ids;
        const candidates = scanCandidates(rules).filter(c => !selectedIds || selectedIds.includes(c.id));

        const deleted: Array<{ id: string; title: string; item_type: string }> = [];
        const errors: string[] = [];

        for (const c of candidates) {
          const ruleTag = c.trigger_rules.join(',');
          try {
            if (c.item_type === 'movie') {
              moveToTrash(c.file_path);
              db.prepare(
                `UPDATE media_items SET deleted_at = datetime('now'), delete_source = 'auto', delete_rule = ? WHERE id = ?`
              ).run(ruleTag, c.id);
              deleted.push({ id: c.id, title: c.title, item_type: 'movie' });

            } else if (c.item_type === 'episode') {
              moveToTrash(c.file_path);
              db.prepare(
                `UPDATE episodes SET deleted_at = datetime('now'), delete_source = 'auto', delete_rule = ? WHERE id = ?`
              ).run(ruleTag, c.id);
              // Soft-delete show if no active episodes remain
              const remaining = (db.prepare(
                `SELECT COUNT(*) as cnt FROM episodes WHERE show_id = ? AND deleted_at IS NULL`
              ).get(c.show_id) as any)?.cnt ?? 0;
              if (remaining === 0) {
                db.prepare(
                  `UPDATE media_items SET deleted_at = datetime('now'), delete_source = 'auto', delete_rule = ? WHERE id = ?`
                ).run(ruleTag, c.show_id);
              }
              deleted.push({ id: c.id, title: `${c.show_title} S${String(c.season_number).padStart(2,'0')}E${String(c.episode_number).padStart(2,'0')}`, item_type: 'episode' });

            } else if (c.item_type === 'season') {
              const eps = db.prepare(
                `SELECT id, file_path FROM episodes WHERE show_id = ? AND season_number = ? AND deleted_at IS NULL`
              ).all(c.show_id, c.season_number) as any[];
              for (const ep of eps) {
                try { moveToTrash(ep.file_path); } catch (e: any) { errors.push(ep.file_path + ': ' + e.message); }
                db.prepare(
                  `UPDATE episodes SET deleted_at = datetime('now'), delete_source = 'auto', delete_rule = ? WHERE id = ?`
                ).run(ruleTag, ep.id);
              }
              const remaining = (db.prepare(
                `SELECT COUNT(*) as cnt FROM episodes WHERE show_id = ? AND deleted_at IS NULL`
              ).get(c.show_id) as any)?.cnt ?? 0;
              if (remaining === 0) {
                db.prepare(
                  `UPDATE media_items SET deleted_at = datetime('now'), delete_source = 'auto', delete_rule = ? WHERE id = ?`
                ).run(ruleTag, c.show_id);
              }
              deleted.push({ id: c.id, title: `${c.show_title} Säsong ${c.season_number}`, item_type: 'season' });

            } else if (c.item_type === 'show') {
              const eps = db.prepare(
                `SELECT id, file_path FROM episodes WHERE show_id = ? AND deleted_at IS NULL`
              ).all(c.show_id) as any[];
              for (const ep of eps) {
                try { moveToTrash(ep.file_path); } catch (e: any) { errors.push(ep.file_path + ': ' + e.message); }
                db.prepare(
                  `UPDATE episodes SET deleted_at = datetime('now'), delete_source = 'auto', delete_rule = ? WHERE id = ?`
                ).run(ruleTag, ep.id);
              }
              db.prepare(
                `UPDATE media_items SET deleted_at = datetime('now'), delete_source = 'auto', delete_rule = ? WHERE id = ?`
              ).run(ruleTag, c.show_id ?? c.id);
              deleted.push({ id: c.id, title: c.title, item_type: 'show' });
            }
          } catch (e: any) {
            errors.push(`${c.title}: ${e.message}`);
          }
        }

        return reply.send({
          success: true,
          deleted_count: deleted.length,
          deleted,
          errors: errors.length ? errors : undefined,
        });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to run cleanup', details: err.message });
      }
    }
  );
}
