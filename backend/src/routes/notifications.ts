import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';
import nodemailer from 'nodemailer';
import https from 'https';
import http from 'http';

function getSetting(key: string): string {
  const row = db.prepare('SELECT value FROM system_settings WHERE key = ?').get(key) as { value: string } | undefined;
  return row?.value ?? '';
}

export default async function notificationsRoutes(fastify: FastifyInstance) {

  // POST /api/notifications/test/discord
  fastify.post('/api/notifications/test/discord', async (_request: FastifyRequest, reply: FastifyReply) => {
    const webhookUrl = getSetting('DISCORD_WEBHOOK_URL');
    if (!webhookUrl) {
      return reply.code(400).send({ error: 'Ingen Discord webhook-URL konfigurerad.' });
    }
    try {
      const body = JSON.stringify({ content: '🎬 **Loom** – Testnotifiering. Webhook fungerar!' });
      const url = new URL(webhookUrl);
      const isHttps = url.protocol === 'https:';
      const options = {
        hostname: url.hostname,
        port: url.port ? parseInt(url.port) : (isHttps ? 443 : 80),
        path: url.pathname + url.search,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
      };

      await new Promise<void>((resolve, reject) => {
        const req = (isHttps ? https : http).request(options, (res) => {
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            resolve();
          } else {
            reject(new Error(`Discord svarade med statuskod ${res.statusCode}`));
          }
          res.resume();
        });
        req.on('error', reject);
        req.write(body);
        req.end();
      });

      return reply.send({ success: true });
    } catch (err: any) {
      return reply.code(500).send({ error: err.message ?? 'Kunde inte skicka Discord-notifiering' });
    }
  });

  // POST /api/notifications/test/email
  fastify.post('/api/notifications/test/email', async (_request: FastifyRequest, reply: FastifyReply) => {
    const host = getSetting('SMTP_HOST');
    const portStr = getSetting('SMTP_PORT');
    const port = portStr ? parseInt(portStr, 10) : 587;
    const user = getSetting('SMTP_USER');
    const pass = getSetting('SMTP_PASS');
    const from = getSetting('SMTP_FROM') || user || 'loom@localhost';
    const to = getSetting('SMTP_TO');

    if (!host || !to) {
      return reply.code(400).send({ error: 'SMTP-host och mottagaradress krävs.' });
    }

    try {
      const transporter = nodemailer.createTransport({
        host,
        port,
        secure: port === 465,
        auth: user ? { user, pass } : undefined,
      });

      await transporter.sendMail({
        from,
        to,
        subject: 'Loom – Testmeddelande',
        text: 'Det här är ett testmeddelande från din Loom-server.',
        html: '<p>Det här är ett <strong>testmeddelande</strong> från din <strong>Loom</strong>-server.</p>',
      });

      return reply.send({ success: true });
    } catch (err: any) {
      return reply.code(500).send({ error: err.message ?? 'Kunde inte skicka e-post' });
    }
  });
}
