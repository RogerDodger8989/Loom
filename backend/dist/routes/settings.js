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
const personalKeys = [
    'SIMKL_CLIENT_ID',
    'SIMKL_CLIENT_SECRET',
    'SIMKL_ACCESS_TOKEN',
    'TRAKT_API_KEY',
    'TRAKT_CLIENT_SECRET',
    'TRAKT_ACCESS_TOKEN',
    'TRAKT_REFRESH_TOKEN',
    'IMDB_USER_ID',
    'DEFAULT_SUBTITLE_LANG',
    'METADATA_LANGUAGE',
    'METADATA_FALLBACK_LANGUAGE',
    'DEFAULT_AUDIO_LANG',
    'WATCH_PROVIDER_REGION',
    'TITLE_DISPLAY_STYLE',
    'SHOW_RELEASE_VERSION',
    'PREFER_LOCAL_NFO',
    'HOME_LAYOUT',
    'sync_trakt_ratings',
    'sync_trakt_watched',
    'sync_simkl_ratings',
    'sync_simkl_watched',
    'POSTER_SIZE_STEP'
];
async function settingsRoutes(fastify) {
    // GET /api/settings & /api/settings/tmdb
    // Retrieves current Loom settings (merges global and user-specific if authenticated)
    const getSettingsHandler = async (request, reply) => {
        try {
            let caller;
            if (request.headers.authorization) {
                try {
                    await request.jwtVerify();
                    caller = request.user;
                }
                catch (e) {
                    // ignore, they get global defaults
                }
            }
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
                'SHOW_RELEASE_VERSION',
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
                'DISK_RULE_WATCHED_ENABLED',
                'DISK_RULE_WATCHED_DAYS',
                'DISK_RULE_UNSEEN_ENABLED',
                'DISK_RULE_UNSEEN_DAYS',
                'DISK_RULE_INACTIVE_ENABLED',
                'DISK_RULE_INACTIVE_DAYS',
                'DISK_RULE_SIZE_ENABLED',
                'DISK_RULE_SIZE_GB',
                'DISK_RULE_SIZE_REQUIRE_WATCHED',
                'DISK_RULE_RATING_ENABLED',
                'DISK_RULE_RATING_MAX',
                'DISK_RULE_SERIES_MODE',
                'DISK_RULE_PROTECT_FAVORITES',
            ];
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
                SHOW_RELEASE_VERSION: 'true',
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
                DISK_RULE_WATCHED_ENABLED: 'false',
                DISK_RULE_WATCHED_DAYS: '7',
                DISK_RULE_UNSEEN_ENABLED: 'false',
                DISK_RULE_UNSEEN_DAYS: '60',
                DISK_RULE_INACTIVE_ENABLED: 'false',
                DISK_RULE_INACTIVE_DAYS: '365',
                DISK_RULE_SIZE_ENABLED: 'false',
                DISK_RULE_SIZE_GB: '50',
                DISK_RULE_SIZE_REQUIRE_WATCHED: 'false',
                DISK_RULE_RATING_ENABLED: 'false',
                DISK_RULE_RATING_MAX: '3',
                DISK_RULE_SERIES_MODE: 'episode',
                DISK_RULE_PROTECT_FAVORITES: 'true',
            };
            const systemKeys = keys.filter(k => !personalKeys.includes(k));
            const placeholders = systemKeys.map(() => '?').join(',');
            const rows = database_1.default.prepare(`SELECT key, value FROM system_settings WHERE key IN (${placeholders})`).all(...systemKeys);
            rows.forEach(r => {
                if (r.key in settings) {
                    settings[r.key] = r.value;
                }
            });
            // If authenticated, overwrite with user-specific settings
            if (caller) {
                const userRows = database_1.default.prepare(`SELECT key, value FROM user_settings WHERE user_id = ?`).all(caller.id);
                userRows.forEach(r => {
                    if (r.key in settings && personalKeys.includes(r.key)) {
                        settings[r.key] = r.value;
                    }
                });
            }
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
    // Updates Loom global and user system settings
    fastify.put('/api/settings', {
        preValidation: [async (request, reply) => {
                try {
                    await request.jwtVerify();
                }
                catch {
                    reply.code(401).send({ error: 'Unauthorized' });
                }
            }]
    }, async (request, reply) => {
        try {
            const body = request.body;
            const caller = request.user;
            const isAdmin = caller.role === 'Admin';
            dbg('PUT /api/settings — mottagen payload från klient', body);
            const savedKeys = {};
            const updateSetting = (key, value) => {
                if (value !== undefined) {
                    if (personalKeys.includes(key)) {
                        // Save to user_settings
                        database_1.default.prepare(`
                INSERT INTO user_settings (user_id, key, value)
                VALUES (?, ?, ?)
                ON CONFLICT(user_id, key) DO UPDATE SET value=excluded.value
              `).run(caller.id, key, value);
                        savedKeys[key] = value;
                    }
                    else if (isAdmin) {
                        // Save to system_settings only if Admin
                        database_1.default.prepare(`
                INSERT INTO system_settings (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value=excluded.value
              `).run(key, value);
                        savedKeys[key] = value;
                    }
                }
            };
            const allKeys = [
                'TMDB_API_KEY', 'OMDB_API_KEY', 'SIMKL_CLIENT_ID', 'SIMKL_CLIENT_SECRET',
                'SIMKL_ACCESS_TOKEN', 'TRAKT_API_KEY', 'TRAKT_CLIENT_SECRET', 'TRAKT_ACCESS_TOKEN',
                'TRAKT_REFRESH_TOKEN', 'IMDB_USER_ID', 'TMDB_USER_AUTH', 'DEFAULT_SUBTITLE_LANG',
                'METADATA_LANGUAGE', 'METADATA_FALLBACK_LANGUAGE', 'DEFAULT_AUDIO_LANG',
                'WATCH_PROVIDER_REGION', 'TITLE_DISPLAY_STYLE', 'SHOW_RELEASE_VERSION',
                'PREFER_LOCAL_NFO', 'HOME_LAYOUT', 'sync_trakt_ratings', 'sync_trakt_watched',
                'sync_simkl_ratings', 'sync_simkl_watched', 'POSTER_SIZE_STEP', 'DISCORD_WEBHOOK_URL',
                'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM', 'SMTP_TO', 'SERVER_NAME',
                'SCAN_SKIP_WORDS', 'SCAN_MIN_SIZE_MB', 'SHOW_CLOCK', 'VERSION_PRIORITY', 'ALWAYS_ON_TOP',
                'DISK_RULE_WATCHED_ENABLED', 'DISK_RULE_WATCHED_DAYS', 'DISK_RULE_UNSEEN_ENABLED',
                'DISK_RULE_UNSEEN_DAYS', 'DISK_RULE_INACTIVE_ENABLED', 'DISK_RULE_INACTIVE_DAYS',
                'DISK_RULE_SIZE_ENABLED', 'DISK_RULE_SIZE_GB', 'DISK_RULE_SIZE_REQUIRE_WATCHED',
                'DISK_RULE_RATING_ENABLED', 'DISK_RULE_RATING_MAX', 'DISK_RULE_SERIES_MODE',
                'DISK_RULE_PROTECT_FAVORITES'
            ];
            for (const k of allKeys) {
                updateSetting(k, body[k]);
            }
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
