"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = settingsRoutes;
const database_1 = __importDefault(require("../config/database"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const DEBUG_LOG = path.resolve(__dirname, '../../../config/settings_debug.log');
function dbg(msg, data) {
    const line = `[${new Date().toISOString()}] ${msg}${data !== undefined ? '\n' + JSON.stringify(data, null, 2) : ''}\n`;
    fs.appendFileSync(DEBUG_LOG, line);
}
async function settingsRoutes(fastify) {
    // GET /api/settings & /api/settings/tmdb
    // Retrieves current Loom global system settings
    const getSettingsHandler = async (request, reply) => {
        try {
            const keys = [
                'TMDB_API_KEY',
                'OMDB_API_KEY',
                'SIMKL_CLIENT_ID',
                'SIMKL_CLIENT_SECRET',
                'SIMKL_ACCESS_TOKEN',
                'TRAKT_API_KEY',
                'TRAKT_CLIENT_SECRET',
                'TRAKT_ACCESS_TOKEN',
                'TRAKT_REFRESH_TOKEN',
                'IMDB_USER_ID',
                'TMDB_USER_AUTH',
                'DEFAULT_SUBTITLE_LANG',
                'METADATA_LANGUAGE',
                'METADATA_FALLBACK_LANGUAGE',
                'DEFAULT_AUDIO_LANG',
                'WATCH_PROVIDER_REGION',
                'TITLE_DISPLAY_STYLE',
                'PREFER_LOCAL_NFO',
                'HOME_LAYOUT',
                'sync_trakt_ratings',
                'sync_trakt_watched',
                'sync_simkl_ratings',
                'sync_simkl_watched',
                'POSTER_SIZE_STEP',
                'SERVER_NAME',
                'DISCORD_WEBHOOK_URL',
                'SMTP_HOST',
                'SMTP_PORT',
                'SMTP_USER',
                'SMTP_PASS',
                'SMTP_FROM',
                'SMTP_TO',
                'SCAN_SKIP_WORDS',
                'SCAN_MIN_SIZE_MB',
                'SHOW_CLOCK',
                'VERSION_PRIORITY',
                'ALWAYS_ON_TOP',
            ];
            const placeholders = keys.map(() => '?').join(',');
            const rows = database_1.default.prepare(`SELECT key, value FROM system_settings WHERE key IN (${placeholders})`).all(...keys);
            const settings = {
                TMDB_API_KEY: '',
                OMDB_API_KEY: '',
                SIMKL_CLIENT_ID: '',
                SIMKL_CLIENT_SECRET: '',
                SIMKL_ACCESS_TOKEN: '',
                TRAKT_API_KEY: '',
                TRAKT_CLIENT_SECRET: '',
                TRAKT_ACCESS_TOKEN: '',
                TRAKT_REFRESH_TOKEN: '',
                IMDB_USER_ID: '',
                TMDB_USER_AUTH: '',
                DEFAULT_SUBTITLE_LANG: 'sv',
                METADATA_LANGUAGE: 'sv-SE',
                METADATA_FALLBACK_LANGUAGE: 'en-US',
                DEFAULT_AUDIO_LANG: 'en',
                WATCH_PROVIDER_REGION: 'SE',
                TITLE_DISPLAY_STYLE: 'Translated',
                PREFER_LOCAL_NFO: 'true',
                HOME_LAYOUT: '',
                sync_trakt_ratings: 'true',
                sync_trakt_watched: 'true',
                sync_simkl_ratings: 'true',
                sync_simkl_watched: 'true',
                POSTER_SIZE_STEP: '1',
                SERVER_NAME: '',
                DISCORD_WEBHOOK_URL: '',
                SMTP_HOST: '',
                SMTP_PORT: '587',
                SMTP_USER: '',
                SMTP_PASS: '',
                SMTP_FROM: '',
                SMTP_TO: '',
                SCAN_SKIP_WORDS: '',
                SCAN_MIN_SIZE_MB: '0',
                SHOW_CLOCK: 'false',
                VERSION_PRIORITY: '1080p,720p,4K',
                ALWAYS_ON_TOP: 'false',
            };
            rows.forEach(r => {
                if (r.key in settings) {
                    settings[r.key] = r.value;
                }
            });
            dbg('GET /api/settings — returnerar till klient', settings);
            return reply.send(settings);
        }
        catch (err) {
            console.error('[Settings] Failed to get settings:', err);
            return reply.code(500).send({ error: 'Failed to retrieve settings' });
        }
    };
    fastify.get('/api/settings', getSettingsHandler);
    fastify.get('/api/settings/tmdb', getSettingsHandler);
    // PUT /api/settings
    // Updates Loom global system settings
    fastify.put('/api/settings', async (request, reply) => {
        try {
            const body = request.body;
            dbg('PUT /api/settings — mottagen payload från klient', body);
            const savedKeys = {};
            const updateSetting = (key, value) => {
                if (value !== undefined) {
                    database_1.default.prepare(`
              INSERT INTO system_settings (key, value)
              VALUES (?, ?)
              ON CONFLICT(key) DO UPDATE SET value=excluded.value
            `).run(key, value);
                    savedKeys[key] = value;
                }
            };
            updateSetting('TMDB_API_KEY', body.TMDB_API_KEY);
            updateSetting('OMDB_API_KEY', body.OMDB_API_KEY);
            updateSetting('SIMKL_CLIENT_ID', body.SIMKL_CLIENT_ID);
            updateSetting('SIMKL_CLIENT_SECRET', body.SIMKL_CLIENT_SECRET);
            updateSetting('TRAKT_API_KEY', body.TRAKT_API_KEY);
            updateSetting('TRAKT_CLIENT_SECRET', body.TRAKT_CLIENT_SECRET);
            updateSetting('TRAKT_ACCESS_TOKEN', body.TRAKT_ACCESS_TOKEN);
            updateSetting('TRAKT_REFRESH_TOKEN', body.TRAKT_REFRESH_TOKEN);
            updateSetting('SIMKL_ACCESS_TOKEN', body.SIMKL_ACCESS_TOKEN);
            updateSetting('IMDB_USER_ID', body.IMDB_USER_ID);
            updateSetting('TMDB_USER_AUTH', body.TMDB_USER_AUTH);
            updateSetting('DEFAULT_SUBTITLE_LANG', body.DEFAULT_SUBTITLE_LANG);
            updateSetting('METADATA_LANGUAGE', body.METADATA_LANGUAGE);
            updateSetting('METADATA_FALLBACK_LANGUAGE', body.METADATA_FALLBACK_LANGUAGE);
            updateSetting('DEFAULT_AUDIO_LANG', body.DEFAULT_AUDIO_LANG);
            updateSetting('WATCH_PROVIDER_REGION', body.WATCH_PROVIDER_REGION);
            updateSetting('TITLE_DISPLAY_STYLE', body.TITLE_DISPLAY_STYLE);
            updateSetting('PREFER_LOCAL_NFO', body.PREFER_LOCAL_NFO);
            updateSetting('HOME_LAYOUT', body.HOME_LAYOUT);
            updateSetting('sync_trakt_ratings', body.sync_trakt_ratings);
            updateSetting('sync_trakt_watched', body.sync_trakt_watched);
            updateSetting('sync_simkl_ratings', body.sync_simkl_ratings);
            updateSetting('sync_simkl_watched', body.sync_simkl_watched);
            updateSetting('POSTER_SIZE_STEP', body.POSTER_SIZE_STEP);
            updateSetting('DISCORD_WEBHOOK_URL', body.DISCORD_WEBHOOK_URL);
            updateSetting('SMTP_HOST', body.SMTP_HOST);
            updateSetting('SMTP_PORT', body.SMTP_PORT);
            updateSetting('SMTP_USER', body.SMTP_USER);
            updateSetting('SMTP_PASS', body.SMTP_PASS);
            updateSetting('SMTP_FROM', body.SMTP_FROM);
            updateSetting('SMTP_TO', body.SMTP_TO);
            updateSetting('SERVER_NAME', body.SERVER_NAME);
            updateSetting('SCAN_SKIP_WORDS', body.SCAN_SKIP_WORDS);
            updateSetting('SCAN_MIN_SIZE_MB', body.SCAN_MIN_SIZE_MB);
            updateSetting('SHOW_CLOCK', body.SHOW_CLOCK);
            updateSetting('VERSION_PRIORITY', body.VERSION_PRIORITY);
            updateSetting('ALWAYS_ON_TOP', body.ALWAYS_ON_TOP);
            dbg('PUT /api/settings — faktiskt sparade till DB', savedKeys);
            return reply.send({ success: true });
        }
        catch (err) {
            dbg('PUT /api/settings — FEL vid sparning', { error: String(err) });
            console.error('[Settings] Failed to update settings:', err);
            return reply.code(500).send({ error: 'Failed to update settings' });
        }
    });
}
