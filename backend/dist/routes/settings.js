"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = settingsRoutes;
const database_1 = __importDefault(require("../config/database"));
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
                'TMDB_USER_AUTH',
                'DEFAULT_SUBTITLE_LANG',
                'METADATA_LANGUAGE',
                'METADATA_FALLBACK_LANGUAGE',
                'DEFAULT_AUDIO_LANG',
                'WATCH_PROVIDER_REGION',
                'TITLE_DISPLAY_STYLE',
                'PREFER_LOCAL_NFO'
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
                TMDB_USER_AUTH: '',
                DEFAULT_SUBTITLE_LANG: 'sv',
                METADATA_LANGUAGE: 'sv-SE',
                METADATA_FALLBACK_LANGUAGE: 'en-US',
                DEFAULT_AUDIO_LANG: 'en',
                WATCH_PROVIDER_REGION: 'SE',
                TITLE_DISPLAY_STYLE: 'Translated',
                PREFER_LOCAL_NFO: 'true'
            };
            rows.forEach(r => {
                if (r.key in settings) {
                    settings[r.key] = r.value;
                }
            });
            return reply.send(settings);
        }
        catch (err) {
            console.error('[Settings] Failed to get settings:', err);
            return reply.code(500).send({ error: 'Failed to retrieve settings' });
        }
    };
    const authOptions = {
        preValidation: [async (request, reply) => {
                try {
                    await request.jwtVerify();
                }
                catch (err) {
                    reply.code(401).send({ error: 'Unauthorized' });
                }
            }]
    };
    fastify.get('/api/settings', authOptions, getSettingsHandler);
    fastify.get('/api/settings/tmdb', authOptions, getSettingsHandler);
    // PUT /api/settings
    // Updates Loom global system settings
    fastify.put('/api/settings', {
        preValidation: [async (request, reply) => {
                try {
                    await request.jwtVerify();
                }
                catch (err) {
                    reply.code(401).send({ error: 'Unauthorized' });
                }
            }]
    }, async (request, reply) => {
        try {
            const body = request.body;
            const updateSetting = (key, value) => {
                if (value !== undefined) {
                    database_1.default.prepare(`
              INSERT INTO system_settings (key, value) 
              VALUES (?, ?)
              ON CONFLICT(key) DO UPDATE SET value=excluded.value
            `).run(key, value);
                }
            };
            updateSetting('TMDB_API_KEY', body.TMDB_API_KEY);
            updateSetting('OMDB_API_KEY', body.OMDB_API_KEY);
            updateSetting('SIMKL_CLIENT_ID', body.SIMKL_CLIENT_ID);
            updateSetting('SIMKL_CLIENT_SECRET', body.SIMKL_CLIENT_SECRET);
            updateSetting('SIMKL_ACCESS_TOKEN', body.SIMKL_ACCESS_TOKEN);
            updateSetting('TRAKT_API_KEY', body.TRAKT_API_KEY);
            updateSetting('TRAKT_CLIENT_SECRET', body.TRAKT_CLIENT_SECRET);
            updateSetting('TRAKT_ACCESS_TOKEN', body.TRAKT_ACCESS_TOKEN);
            updateSetting('TMDB_USER_AUTH', body.TMDB_USER_AUTH);
            updateSetting('DEFAULT_SUBTITLE_LANG', body.DEFAULT_SUBTITLE_LANG);
            updateSetting('METADATA_LANGUAGE', body.METADATA_LANGUAGE);
            updateSetting('METADATA_FALLBACK_LANGUAGE', body.METADATA_FALLBACK_LANGUAGE);
            updateSetting('DEFAULT_AUDIO_LANG', body.DEFAULT_AUDIO_LANG);
            updateSetting('WATCH_PROVIDER_REGION', body.WATCH_PROVIDER_REGION);
            updateSetting('TITLE_DISPLAY_STYLE', body.TITLE_DISPLAY_STYLE);
            updateSetting('PREFER_LOCAL_NFO', body.PREFER_LOCAL_NFO);
            return reply.send({ success: true });
        }
        catch (err) {
            console.error('[Settings] Failed to update settings:', err);
            return reply.code(500).send({ error: 'Failed to update settings' });
        }
    });
}
