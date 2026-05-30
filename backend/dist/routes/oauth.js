"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = oauthRoutes;
const database_1 = __importDefault(require("../config/database"));
const rating_sync_1 = require("../services/rating_sync");
async function oauthRoutes(fastify) {
    // Helper to fetch setting from DB
    const getSetting = (key) => {
        const row = database_1.default.prepare('SELECT value FROM system_settings WHERE key = ?').get(key);
        return row ? row.value : '';
    };
    // Helper to save setting to DB
    const saveSetting = (key, value) => {
        database_1.default.prepare(`
      INSERT INTO system_settings (key, value) 
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value
    `).run(key, value);
    };
    // HTML Response template for beautiful feedback
    const renderResponsePage = (title, message, isError) => {
        const color = isError ? '#FF6B6B' : '#8A5BFF';
        return `
      <!DOCTYPE html>
      <html>
      <head>
        <title>${title}</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=initial-scale=1.0">
        <style>
          body {
            background-color: #0A0617;
            color: #FFFFFF;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
          }
          .card {
            background-color: #0F0B1E;
            border: 1px solid rgba(255, 255, 255, 0.05);
            border-radius: 20px;
            padding: 40px;
            text-align: center;
            max-width: 450px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
          }
          h1 {
            color: ${color};
            margin-top: 0;
            font-size: 28px;
          }
          p {
            color: rgba(255, 255, 255, 0.7);
            font-size: 16px;
            line-height: 1.6;
          }
          .btn {
            background-color: ${color};
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 30px;
            font-size: 16px;
            font-weight: bold;
            cursor: pointer;
            margin-top: 20px;
            text-decoration: none;
            display: inline-block;
          }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>${title}</h1>
          <p>${message}</p>
          <button class="btn" onclick="window.close()">Stäng fönster</button>
        </div>
      </body>
      </html>
    `;
    };
    // ----------------------------------------------------
    // TRAKT OAUTH
    // ----------------------------------------------------
    // GET /api/oauth/trakt/authorize
    fastify.get('/api/oauth/trakt/authorize', async (request, reply) => {
        const clientId = getSetting('TRAKT_API_KEY');
        if (!clientId) {
            reply.type('text/html');
            return reply.code(400).send(renderResponsePage('Trakt-konfiguration saknas', 'Ange ditt Trakt API Client ID (Trakt API Key) i Loom-inställningarna först innan du försöker ansluta.', true));
        }
        const host = request.headers.host || 'localhost:8080';
        const protocol = request.headers['x-forwarded-proto'] || 'http';
        const callbackUrl = `${protocol}://${host}/api/oauth/trakt/callback`;
        const authorizeUrl = `https://trakt.tv/oauth/authorize?response_type=code&client_id=${clientId}&redirect_uri=${encodeURIComponent(callbackUrl)}`;
        return reply.redirect(authorizeUrl);
    });
    // GET /api/oauth/trakt/callback
    fastify.get('/api/oauth/trakt/callback', async (request, reply) => {
        const { code } = request.query;
        if (!code) {
            reply.type('text/html');
            return reply.code(400).send(renderResponsePage('Auktorisering misslyckades', 'Ingen auktoriseringskod mottogs från Trakt.', true));
        }
        const clientId = getSetting('TRAKT_API_KEY');
        const clientSecret = getSetting('TRAKT_CLIENT_SECRET');
        const host = request.headers.host || 'localhost:8080';
        const protocol = request.headers['x-forwarded-proto'] || 'http';
        const callbackUrl = `${protocol}://${host}/api/oauth/trakt/callback`;
        console.log('[OAuth] Attempting Trakt token exchange:', {
            clientId: clientId ? `${clientId.substring(0, 5)}...` : 'MISSING',
            clientSecret: clientSecret ? 'PRESENT' : 'MISSING',
            code: code ? 'PRESENT' : 'MISSING',
            callbackUrl
        });
        if (!clientId || !clientSecret) {
            reply.type('text/html');
            return reply.code(400).send(renderResponsePage('Konfigurationsfel', 'Trakt Client ID och Client Secret måste båda vara ifyllda i Loom inställningar för att slutföra kopplingen.', true));
        }
        try {
            const response = await fetch('https://api.trakt.tv/oauth/token', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'User-Agent': 'Loom-Media-Server/1.0.0'
                },
                body: JSON.stringify({
                    code,
                    client_id: clientId,
                    client_secret: clientSecret,
                    redirect_uri: callbackUrl,
                    grant_type: 'authorization_code'
                })
            });
            if (!response.ok) {
                const errorText = await response.text();
                console.error('[OAuth] Trakt token exchange failed:', response.status, errorText);
                reply.type('text/html');
                return reply.code(500).send(renderResponsePage('Token-utbyte misslyckades', `Trakt returnerade ett fel: ${response.status} ${response.statusText}. Vänligen kontrollera att ditt Client ID och Client Secret är korrekta och sparade i inställningarna.`, true));
            }
            const data = await response.json();
            saveSetting('TRAKT_ACCESS_TOKEN', data.access_token);
            // Trigger automatic background rating import immediately
            (0, rating_sync_1.importRatingsFromTrakt)();
            reply.type('text/html');
            return reply.send(renderResponsePage('Trakt ansluten!', 'Loom har nu kopplats till ditt Trakt.tv-konto och påbörjat import av dina sparade betyg i bakgrunden.', false));
        }
        catch (err) {
            console.error('[OAuth] Trakt callback error:', err);
            reply.type('text/html');
            return reply.code(500).send(renderResponsePage('Internt fel', 'Ett oväntat fel uppstod under anslutningen till Trakt.', true));
        }
    });
    // ----------------------------------------------------
    // SIMKL OAUTH
    // ----------------------------------------------------
    // GET /api/oauth/simkl/authorize
    fastify.get('/api/oauth/simkl/authorize', async (request, reply) => {
        const clientId = getSetting('SIMKL_CLIENT_ID');
        if (!clientId) {
            reply.type('text/html');
            return reply.code(400).send(renderResponsePage('Simkl-konfiguration saknas', 'Ange ditt Simkl Client ID i Loom-inställningarna först innan du försöker ansluta.', true));
        }
        const host = request.headers.host || 'localhost:8080';
        const protocol = request.headers['x-forwarded-proto'] || 'http';
        const callbackUrl = `${protocol}://${host}/api/oauth/simkl/callback`;
        const authorizeUrl = `https://simkl.com/oauth/authorize?response_type=code&client_id=${clientId}&redirect_uri=${encodeURIComponent(callbackUrl)}`;
        return reply.redirect(authorizeUrl);
    });
    // GET /api/oauth/simkl/callback
    fastify.get('/api/oauth/simkl/callback', async (request, reply) => {
        const { code } = request.query;
        if (!code) {
            reply.type('text/html');
            return reply.code(400).send(renderResponsePage('Auktorisering misslyckades', 'Ingen auktoriseringskod mottogs från Simkl.', true));
        }
        const clientId = getSetting('SIMKL_CLIENT_ID');
        const clientSecret = getSetting('SIMKL_CLIENT_SECRET');
        const host = request.headers.host || 'localhost:8080';
        const protocol = request.headers['x-forwarded-proto'] || 'http';
        const callbackUrl = `${protocol}://${host}/api/oauth/simkl/callback`;
        console.log('[OAuth] Attempting Simkl token exchange:', {
            clientId: clientId ? `${clientId.substring(0, 5)}...` : 'MISSING',
            clientSecret: clientSecret ? 'PRESENT' : 'MISSING',
            code: code ? 'PRESENT' : 'MISSING',
            callbackUrl
        });
        if (!clientId || !clientSecret) {
            reply.type('text/html');
            return reply.code(400).send(renderResponsePage('Konfigurationsfel', 'Simkl Client ID och Client Secret måste båda vara ifyllda i Loom inställningar för att slutföra kopplingen.', true));
        }
        try {
            const response = await fetch('https://api.simkl.com/oauth/token', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'User-Agent': 'Loom-Media-Server/1.0.0'
                },
                body: JSON.stringify({
                    grant_type: 'authorization_code',
                    code,
                    client_id: clientId,
                    client_secret: clientSecret,
                    redirect_uri: callbackUrl
                })
            });
            if (!response.ok) {
                const errorText = await response.text();
                console.error('[OAuth] Simkl token exchange failed:', response.status, errorText);
                reply.type('text/html');
                return reply.code(500).send(renderResponsePage('Token-utbyte misslyckades', `Simkl returnerade ett fel: ${response.status} ${response.statusText}. Vänligen kontrollera att ditt Client ID och Client Secret är korrekta och sparade i inställningarna.`, true));
            }
            const data = await response.json();
            saveSetting('SIMKL_ACCESS_TOKEN', data.access_token);
            // Trigger automatic background rating import immediately
            (0, rating_sync_1.importRatingsFromSimkl)();
            reply.type('text/html');
            return reply.send(renderResponsePage('Simkl ansluten!', 'Loom har nu kopplats till ditt Simkl-konto och påbörjat import av dina sparade betyg i bakgrunden.', false));
        }
        catch (err) {
            console.error('[OAuth] Simkl callback error:', err);
            reply.type('text/html');
            return reply.code(500).send(renderResponsePage('Internt fel', 'Ett oväntat fel uppstod under anslutningen till Simkl.', true));
        }
    });
}
