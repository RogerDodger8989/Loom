import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';
import https from 'https';
import http from 'http';
import { randomUUID } from 'crypto';

// Ensure rss_feeds table exists
db.exec(`
  CREATE TABLE IF NOT EXISTS rss_feeds (
    id TEXT PRIMARY KEY,
    url TEXT UNIQUE NOT NULL,
    title TEXT,
    added_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
  CREATE TABLE IF NOT EXISTS rss_items (
    id TEXT PRIMARY KEY,
    feed_id TEXT REFERENCES rss_feeds(id) ON DELETE CASCADE,
    guid TEXT,
    title TEXT,
    link TEXT,
    pub_date TEXT,
    description TEXT,
    fetched_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(feed_id, guid)
  );
`);

async function fetchUrl(url: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const mod = parsed.protocol === 'https:' ? https : http;
    const req = mod.get(url, { headers: { 'User-Agent': 'Loom-RSS/1.0' } }, (res) => {
      if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        fetchUrl(res.headers.location).then(resolve).catch(reject);
        return;
      }
      const chunks: Buffer[] = [];
      res.on('data', (d: Buffer) => chunks.push(d));
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    });
    req.on('error', reject);
    req.setTimeout(8000, () => { req.destroy(); reject(new Error('timeout')); });
  });
}

function parseRss(xml: string, feedId: string): Array<{ id: string; feed_id: string; guid: string; title: string; link: string; pub_date: string; description: string }> {
  const items: ReturnType<typeof parseRss> = [];
  const itemRegex = /<item[^>]*>([\s\S]*?)<\/item>/gi;
  let m;
  while ((m = itemRegex.exec(xml)) !== null) {
    const block = m[1];
    const get = (tag: string) => {
      const r = new RegExp(`<${tag}[^>]*><!\\[CDATA\\[([\\s\\S]*?)\\]\\]><\\/${tag}>|<${tag}[^>]*>([^<]*)<\\/${tag}>`, 'i');
      const match = r.exec(block);
      return (match?.[1] ?? match?.[2] ?? '').trim();
    };
    const guid = get('guid') || get('link') || randomUUID();
    items.push({
      id: randomUUID(),
      feed_id: feedId,
      guid,
      title: get('title'),
      link: get('link'),
      pub_date: get('pubDate'),
      description: get('description').replace(/<[^>]+>/g, '').substring(0, 500),
    });
  }
  return items;
}

function getFeedTitle(xml: string): string {
  // Strip everything from first <item> so we only look at channel-level title
  const channelPart = xml.replace(/<item[\s\S]*$/i, '');
  const m = /<title[^>]*><!\[CDATA\[([\s\S]*?)\]\]><\/title>|<title[^>]*>([^<]*)<\/title>/i.exec(channelPart);
  return (m?.[1] ?? m?.[2] ?? '').trim();
}

export default async function rssRoutes(fastify: FastifyInstance) {

  // GET /api/rss/feeds — lista alla feeds
  fastify.get('/api/rss/feeds', async (_req, reply) => {
    const feeds = db.prepare('SELECT * FROM rss_feeds ORDER BY added_at DESC').all();
    return reply.send(feeds);
  });

  // POST /api/rss/feeds — lägg till feed
  fastify.post<{ Body: { url?: string } }>('/api/rss/feeds', async (request, reply) => {
    const { url } = request.body ?? {};
    if (!url) return reply.code(400).send({ error: 'url krävs' });

    const existing = db.prepare('SELECT id FROM rss_feeds WHERE url = ?').get(url);
    if (existing) return reply.code(409).send({ error: 'Flödet finns redan' });

    const id = randomUUID();
    let title = url;
    try {
      const xml = await fetchUrl(url);
      title = getFeedTitle(xml) || url;
      db.prepare('INSERT INTO rss_feeds (id, url, title) VALUES (?, ?, ?)').run(id, url, title);
      const items = parseRss(xml, id);
      const ins = db.prepare('INSERT OR IGNORE INTO rss_items (id, feed_id, guid, title, link, pub_date, description) VALUES (?, ?, ?, ?, ?, ?, ?)');
      for (const it of items.slice(0, 50)) ins.run(it.id, it.feed_id, it.guid, it.title, it.link, it.pub_date, it.description);
    } catch (e: any) {
      db.prepare('INSERT OR IGNORE INTO rss_feeds (id, url, title) VALUES (?, ?, ?)').run(id, url, title);
    }

    return reply.code(201).send({ id, url, title });
  });

  // DELETE /api/rss/feeds/:id — ta bort feed
  fastify.delete<{ Params: { id: string } }>('/api/rss/feeds/:id', async (request, reply) => {
    db.prepare('DELETE FROM rss_feeds WHERE id = ?').run(request.params.id);
    return reply.send({ success: true });
  });

  // GET /api/rss/items — senaste poster (alla feeds)
  fastify.get('/api/rss/items', async (_req, reply) => {
    const items = db.prepare(`
      SELECT ri.*, rf.title AS feed_title FROM rss_items ri
      JOIN rss_feeds rf ON rf.id = ri.feed_id
      ORDER BY ri.pub_date DESC LIMIT 100
    `).all();
    return reply.send(items);
  });

  // POST /api/rss/refresh — hämta nytt från alla feeds
  fastify.post('/api/rss/refresh', async (_req, reply) => {
    const feeds = db.prepare('SELECT * FROM rss_feeds').all() as Array<{ id: string; url: string }>;
    let total = 0;
    const ins = db.prepare('INSERT OR IGNORE INTO rss_items (id, feed_id, guid, title, link, pub_date, description) VALUES (?, ?, ?, ?, ?, ?, ?)');
    for (const feed of feeds) {
      try {
        const xml = await fetchUrl(feed.url);
        const items = parseRss(xml, feed.id);
        for (const it of items.slice(0, 50)) {
          const r = ins.run(it.id, it.feed_id, it.guid, it.title, it.link, it.pub_date, it.description);
          total += r.changes;
        }
      } catch (_) {}
    }
    return reply.send({ newItems: total });
  });
}
