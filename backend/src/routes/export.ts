import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import AdmZip from 'adm-zip';
import db from '../config/database';

interface ExportQuery {
  settings?: string;
  library_paths?: string;
  users?: string;
  watch_history?: string;
  watchlist?: string;
  markers?: string;
}

export default async function exportRoutes(fastify: FastifyInstance) {

  // GET /api/export — bygg en ZIP med valda kategorier
  fastify.get('/api/export', async (req: FastifyRequest<{ Querystring: ExportQuery }>, reply: FastifyReply) => {
    try { await req.jwtVerify(); } catch { return reply.code(401).send({ error: 'Unauthorized' }); }

    const q = req.query;
    const zip = new AdmZip();
    const includes: Record<string, boolean> = {};

    if (q.settings === 'true') {
      const rows = db.prepare('SELECT key, value FROM system_settings').all();
      zip.addFile('settings.json', Buffer.from(JSON.stringify(rows, null, 2), 'utf8'));
      includes.settings = true;
    }

    if (q.library_paths === 'true') {
      const rows = db.prepare('SELECT id, path, type, added_at FROM library_paths').all();
      zip.addFile('library_paths.json', Buffer.from(JSON.stringify(rows, null, 2), 'utf8'));
      includes.library_paths = true;
    }

    if (q.users === 'true') {
      const rows = db.prepare('SELECT id, username, password_hash, role FROM users').all();
      zip.addFile('users.json', Buffer.from(JSON.stringify(rows, null, 2), 'utf8'));
      includes.users = true;
    }

    if (q.watch_history === 'true') {
      const rows = db.prepare(
        'SELECT id, user_id, media_item_id, episode_id, last_position_seconds, total_duration_seconds, is_watched, updated_at FROM watch_history'
      ).all();
      zip.addFile('watch_history.json', Buffer.from(JSON.stringify(rows, null, 2), 'utf8'));
      includes.watch_history = true;
    }

    if (q.watchlist === 'true') {
      const rows = db.prepare(
        'SELECT id, tmdb_id, title, type, year, poster_path, added_at, status FROM watchlist'
      ).all();
      zip.addFile('watchlist.json', Buffer.from(JSON.stringify(rows, null, 2), 'utf8'));
      includes.watchlist = true;
    }

    if (q.markers === 'true') {
      const mediaMarkers = db.prepare(
        'SELECT id, media_item_id, episode_id, marker_type, start_time_seconds, end_time_seconds, title, source FROM media_markers'
      ).all();
      const episodeMarkers = db.prepare(
        'SELECT id, episode_id, marker_type, start_time_seconds, end_time_seconds FROM episode_markers'
      ).all();
      zip.addFile('markers.json', Buffer.from(
        JSON.stringify({ media_markers: mediaMarkers, episode_markers: episodeMarkers }, null, 2), 'utf8'
      ));
      includes.markers = true;
    }

    zip.addFile('manifest.json', Buffer.from(
      JSON.stringify({ version: '1', exported_at: new Date().toISOString(), includes }, null, 2), 'utf8'
    ));

    const date = new Date().toISOString().slice(0, 10);
    reply
      .header('Content-Type', 'application/zip')
      .header('Content-Disposition', `attachment; filename="loom_backup_${date}.zip"`)
      .send(zip.toBuffer());
  });

  // POST /api/import — importera från ZIP
  fastify.post('/api/import', async (req: FastifyRequest, reply: FastifyReply) => {
    try { await req.jwtVerify(); } catch { return reply.code(401).send({ error: 'Unauthorized' }); }

    const data = await (req as any).file();
    if (!data) return reply.code(400).send({ error: 'Ingen fil skickades.' });

    const chunks: Buffer[] = [];
    for await (const chunk of data.file) chunks.push(chunk);
    const buf = Buffer.concat(chunks);

    let zip: AdmZip;
    try { zip = new AdmZip(buf); } catch {
      return reply.code(400).send({ error: 'Filen är inte en giltig ZIP.' });
    }

    const manifestEntry = zip.getEntry('manifest.json');
    if (!manifestEntry) return reply.code(400).send({ error: 'Ogiltig backup-fil — manifest saknas.' });

    const manifest = JSON.parse(manifestEntry.getData().toString('utf8'));
    const results: Record<string, string> = {};

    if (manifest.includes?.settings) {
      const entry = zip.getEntry('settings.json');
      if (entry) {
        const rows: Array<{ key: string; value: string }> = JSON.parse(entry.getData().toString('utf8'));
        const stmt = db.prepare('INSERT INTO system_settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value');
        db.prepare('BEGIN').run();
        try {
          for (const r of rows) stmt.run(r.key, r.value);
          db.prepare('COMMIT').run();
          results.settings = `${rows.length} inställningar återställda`;
        } catch (e) { db.prepare('ROLLBACK').run(); throw e; }
      }
    }

    if (manifest.includes?.library_paths) {
      const entry = zip.getEntry('library_paths.json');
      if (entry) {
        const rows: Array<{ id: string; path: string; type: string; added_at: string }> = JSON.parse(entry.getData().toString('utf8'));
        const stmt = db.prepare('INSERT INTO library_paths (id, path, type, added_at) VALUES (?, ?, ?, ?) ON CONFLICT(path) DO UPDATE SET type = excluded.type');
        db.prepare('BEGIN').run();
        try {
          for (const r of rows) stmt.run(r.id, r.path, r.type, r.added_at);
          db.prepare('COMMIT').run();
          results.library_paths = `${rows.length} sökvägar återställda`;
        } catch (e) { db.prepare('ROLLBACK').run(); throw e; }
      }
    }

    if (manifest.includes?.users) {
      const entry = zip.getEntry('users.json');
      if (entry) {
        const rows: Array<{ id: string; username: string; password_hash: string; role: string }> = JSON.parse(entry.getData().toString('utf8'));
        const stmt = db.prepare('INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?) ON CONFLICT(username) DO UPDATE SET password_hash = excluded.password_hash, role = excluded.role');
        db.prepare('BEGIN').run();
        try {
          for (const r of rows) stmt.run(r.id, r.username, r.password_hash, r.role);
          db.prepare('COMMIT').run();
          results.users = `${rows.length} användare återställda`;
        } catch (e) { db.prepare('ROLLBACK').run(); throw e; }
      }
    }

    if (manifest.includes?.watch_history) {
      const entry = zip.getEntry('watch_history.json');
      if (entry) {
        const rows: Array<any> = JSON.parse(entry.getData().toString('utf8'));
        const stmt = db.prepare(`
          INSERT INTO watch_history (id, user_id, media_item_id, episode_id, last_position_seconds, total_duration_seconds, is_watched, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            last_position_seconds = excluded.last_position_seconds,
            total_duration_seconds = excluded.total_duration_seconds,
            is_watched = excluded.is_watched,
            updated_at = excluded.updated_at
        `);
        db.prepare('BEGIN').run();
        try {
          for (const r of rows) stmt.run(r.id, r.user_id, r.media_item_id, r.episode_id, r.last_position_seconds, r.total_duration_seconds, r.is_watched, r.updated_at);
          db.prepare('COMMIT').run();
          results.watch_history = `${rows.length} historikposter återställda`;
        } catch (e) { db.prepare('ROLLBACK').run(); throw e; }
      }
    }

    if (manifest.includes?.watchlist) {
      const entry = zip.getEntry('watchlist.json');
      if (entry) {
        const rows: Array<any> = JSON.parse(entry.getData().toString('utf8'));
        const stmt = db.prepare(`
          INSERT INTO watchlist (id, tmdb_id, title, type, year, poster_path, added_at, status)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(tmdb_id) DO UPDATE SET status = excluded.status, title = excluded.title
        `);
        db.prepare('BEGIN').run();
        try {
          for (const r of rows) stmt.run(r.id, r.tmdb_id, r.title, r.type, r.year, r.poster_path, r.added_at, r.status);
          db.prepare('COMMIT').run();
          results.watchlist = `${rows.length} titlar återställda`;
        } catch (e) { db.prepare('ROLLBACK').run(); throw e; }
      }
    }

    if (manifest.includes?.markers) {
      const entry = zip.getEntry('markers.json');
      if (entry) {
        const payload = JSON.parse(entry.getData().toString('utf8'));
        const mm: Array<any> = payload.media_markers ?? [];
        const em: Array<any> = payload.episode_markers ?? [];

        db.prepare('BEGIN').run();
        try {
          const mmStmt = db.prepare(`INSERT OR REPLACE INTO media_markers (id, media_item_id, episode_id, marker_type, start_time_seconds, end_time_seconds, title, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`);
          for (const r of mm) mmStmt.run(r.id, r.media_item_id, r.episode_id, r.marker_type, r.start_time_seconds, r.end_time_seconds, r.title, r.source);

          const emStmt = db.prepare(`INSERT OR REPLACE INTO episode_markers (id, episode_id, marker_type, start_time_seconds, end_time_seconds) VALUES (?, ?, ?, ?, ?)`);
          for (const r of em) emStmt.run(r.id, r.episode_id, r.marker_type, r.start_time_seconds, r.end_time_seconds);

          db.prepare('COMMIT').run();
          results.markers = `${mm.length} filmmarkörer + ${em.length} avsnittsmarkörer återställda`;
        } catch (e) { db.prepare('ROLLBACK').run(); throw e; }
      }
    }

    return reply.send({ success: true, results });
  });
}
