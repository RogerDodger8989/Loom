import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

const dbPath = path.resolve(__dirname, '../../../config/loom.db');
const restorePath = path.resolve(__dirname, '../../../config/loom.db.restore');

const startedAt = Date.now();

function getSetting(key: string): string {
  const row = db.prepare('SELECT value FROM system_settings WHERE key = ?').get(key) as { value: string } | undefined;
  return row?.value ?? '';
}

export default async function serverRoutes(fastify: FastifyInstance) {

  // GET /api/server/info
  fastify.get('/api/server/info', async (_req: FastifyRequest, reply: FastifyReply) => {
    const dbSize = fs.existsSync(dbPath) ? fs.statSync(dbPath).size : 0;
    const mediaCount = (db.prepare('SELECT COUNT(*) as c FROM media_items WHERE deleted_at IS NULL').get() as { c: number }).c;
    const episodeCount = (db.prepare('SELECT COUNT(*) as c FROM episodes').get() as { c: number }).c;
    const userCount = (db.prepare('SELECT COUNT(*) as c FROM users').get() as { c: number }).c;
    const uptimeSeconds = Math.floor((Date.now() - startedAt) / 1000);

    return reply.send({
      serverName: getSetting('SERVER_NAME') || 'Loom',
      port: parseInt(process.env.PORT || '8080', 10),
      uptimeSeconds,
      dbSizeBytes: dbSize,
      mediaCount,
      episodeCount,
      userCount,
      nodeVersion: process.version,
      platform: os.platform(),
    });
  });

  // POST /api/server/db/optimize
  fastify.post('/api/server/db/optimize', async (_req: FastifyRequest, reply: FastifyReply) => {
    try {
      db.exec('PRAGMA optimize;');
      db.exec('PRAGMA wal_checkpoint(TRUNCATE);');
      db.exec('VACUUM;');
      const dbSize = fs.existsSync(dbPath) ? fs.statSync(dbPath).size : 0;
      console.log(`[Server] Database optimized. Size: ${(dbSize / 1024 / 1024).toFixed(2)} MB`);
      return reply.send({ success: true, dbSizeBytes: dbSize });
    } catch (err: any) {
      return reply.code(500).send({ error: err.message ?? 'Optimize failed' });
    }
  });

  // GET /api/server/db/backup — streams the SQLite file
  fastify.get('/api/server/db/backup', async (_req: FastifyRequest, reply: FastifyReply) => {
    try {
      // Checkpoint WAL so the .db file is complete
      db.exec('PRAGMA wal_checkpoint(TRUNCATE);');
      const stat = fs.statSync(dbPath);
      const date = new Date().toISOString().slice(0, 10);
      reply.header('Content-Type', 'application/octet-stream');
      reply.header('Content-Disposition', `attachment; filename="loom-backup-${date}.db"`);
      reply.header('Content-Length', stat.size);
      return reply.send(fs.createReadStream(dbPath));
    } catch (err: any) {
      return reply.code(500).send({ error: err.message ?? 'Backup failed' });
    }
  });

  // POST /api/server/restart — Admin-only, exits process (pm2/nodemon restarts it)
  fastify.post('/api/server/restart', async (req: FastifyRequest, reply: FastifyReply) => {
    const authHeader = (req.headers as any).authorization as string | undefined;
    if (!authHeader?.startsWith('Bearer ')) return reply.code(401).send({ error: 'Unauthorized' });
    const token = authHeader.slice(7);
    let role = '';
    try {
      const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString());
      role = payload.role ?? '';
    } catch { return reply.code(401).send({ error: 'Invalid token' }); }
    if (role !== 'Admin') return reply.code(403).send({ error: 'Requires Admin' });

    setTimeout(() => process.exit(0), 1000);
    return reply.send({ success: true, message: 'Servern startas om...' });
  });

  // POST /api/server/db/restore — multipart upload, saves as .restore then restarts
  fastify.post('/api/server/db/restore', async (req: FastifyRequest, reply: FastifyReply) => {
    try {
      const data = await (req as any).file();
      if (!data) return reply.code(400).send({ error: 'Ingen fil skickades.' });

      const chunks: Buffer[] = [];
      for await (const chunk of data.file) {
        chunks.push(chunk);
      }
      const buf = Buffer.concat(chunks);

      // Validate SQLite magic bytes: "SQLite format 3\000"
      if (buf.length < 16 || buf.slice(0, 6).toString() !== 'SQLite') {
        return reply.code(400).send({ error: 'Filen är inte en giltig SQLite-databas.' });
      }

      fs.writeFileSync(restorePath, buf);
      console.log('[Server] Restore file saved. Restarting server...');

      // Restart after short delay so the response can be sent
      setTimeout(() => process.exit(0), 1500);

      return reply.send({ success: true, message: 'Återställning sparad. Servern startas om...' });
    } catch (err: any) {
      return reply.code(500).send({ error: err.message ?? 'Restore failed' });
    }
  });
}
