import db from '../config/database';
import https from 'https';
import http from 'http';
import nodemailer from 'nodemailer';

function getSetting(key: string): string {
  try {
    const row = db.prepare('SELECT value FROM system_settings WHERE key = ?').get(key) as { value: string } | undefined;
    return row?.value ?? '';
  } catch { return ''; }
}

export async function sendDiscordNotification(message: string): Promise<void> {
  const webhookUrl = getSetting('DISCORD_WEBHOOK_URL');
  if (!webhookUrl) return;
  try {
    const body = JSON.stringify({ content: message });
    const url = new URL(webhookUrl);
    const isHttps = url.protocol === 'https:';
    const options = {
      hostname: url.hostname,
      port: url.port ? parseInt(url.port) : (isHttps ? 443 : 80),
      path: url.pathname + url.search,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    };
    await new Promise<void>((resolve, reject) => {
      const req = (isHttps ? https : http).request(options, (res) => {
        res.statusCode && res.statusCode < 300 ? resolve() : reject(new Error(`${res.statusCode}`));
        res.resume();
      });
      req.on('error', reject);
      req.write(body);
      req.end();
    });
  } catch (e) {
    console.warn('[Notify] Discord misslyckades:', e);
  }
}

export async function sendEmailNotification(subject: string, text: string): Promise<void> {
  const host = getSetting('SMTP_HOST');
  const to   = getSetting('SMTP_TO');
  if (!host || !to) return;
  try {
    const port = parseInt(getSetting('SMTP_PORT') || '587', 10);
    const user = getSetting('SMTP_USER');
    const pass = getSetting('SMTP_PASS');
    const from = getSetting('SMTP_FROM') || user || 'loom@localhost';
    const transporter = nodemailer.createTransport({
      host, port, secure: port === 465,
      auth: user ? { user, pass } : undefined,
    });
    await transporter.sendMail({ from, to, subject, text });
  } catch (e) {
    console.warn('[Notify] E-post misslyckades:', e);
  }
}

export async function notifyScanComplete(added: number, updated: number, path: string): Promise<void> {
  if (added === 0 && updated === 0) return;
  const msg = `🎬 **Loom** – Skanning klar för \`${path}\`\n➕ ${added} tillagda  ·  🔄 ${updated} uppdaterade`;
  const subject = `Loom – Skanning klar (${added} nya)`;
  const text = `Skanning klar för: ${path}\nTillagda: ${added}\nUppdaterade: ${updated}`;
  await Promise.all([
    sendDiscordNotification(msg),
    sendEmailNotification(subject, text),
  ]);
}
