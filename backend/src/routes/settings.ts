import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';
import * as fs from 'fs';
import * as path from 'path';

const DEBUG_LOG = path.resolve(__dirname, '../../../config/settings_debug.log');
function dbg(msg: string, data?: any) {
  const line = `[${new Date().toISOString()}] ${msg}${data !== undefined ? '\n' + JSON.stringify(data, null, 2) : ''}\n`;
  fs.appendFileSync(DEBUG_LOG, line);
}

export default async function settingsRoutes(fastify: FastifyInstance) {
  
  // GET /api/settings & /api/settings/tmdb
  // Retrieves current Loom global system settings
  const getSettingsHandler = async (request: FastifyRequest, reply: FastifyReply) => {
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
      const placeholders = keys.map(() => '?').join(',');
      const rows = db.prepare(`SELECT key, value FROM system_settings WHERE key IN (${placeholders})`).all(...keys) as { key: string, value: string }[];
      
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

      rows.forEach(r => {
        if (r.key in settings) {
          (settings as any)[r.key] = r.value;
        }
      });

      dbg('GET /api/settings — returnerar till klient', settings);
      return reply.send(settings);
    } catch (err) {
      console.error('[Settings] Failed to get settings:', err);
      return reply.code(500).send({ error: 'Failed to retrieve settings' });
    }
  };

  fastify.get('/api/settings', getSettingsHandler);
  fastify.get('/api/settings/tmdb', getSettingsHandler);

  // PUT /api/settings
  // Updates Loom global system settings
  fastify.put(
    '/api/settings',
    async (request: FastifyRequest<{ Body: { 
      TMDB_API_KEY?: string; 
      OMDB_API_KEY?: string; 
      SIMKL_CLIENT_ID?: string; 
      SIMKL_CLIENT_SECRET?: string;
      SIMKL_ACCESS_TOKEN?: string;
      TRAKT_API_KEY?: string;
      TRAKT_CLIENT_SECRET?: string;
      TRAKT_ACCESS_TOKEN?: string;
      TRAKT_REFRESH_TOKEN?: string;
      IMDB_USER_ID?: string;
      TMDB_USER_AUTH?: string;
      DEFAULT_SUBTITLE_LANG?: string;
      METADATA_LANGUAGE?: string;
      METADATA_FALLBACK_LANGUAGE?: string;
      DEFAULT_AUDIO_LANG?: string;
      WATCH_PROVIDER_REGION?: string;
      TITLE_DISPLAY_STYLE?: string;
      SHOW_RELEASE_VERSION?: string;
      PREFER_LOCAL_NFO?: string;
      HOME_LAYOUT?: string;
      sync_trakt_ratings?: string;
      sync_trakt_watched?: string;
      sync_simkl_ratings?: string;
      sync_simkl_watched?: string;
      POSTER_SIZE_STEP?: string;
      DISCORD_WEBHOOK_URL?: string;
      SMTP_HOST?: string;
      SMTP_PORT?: string;
      SMTP_USER?: string;
      SMTP_PASS?: string;
      SMTP_FROM?: string;
      SMTP_TO?: string;
      SERVER_NAME?: string;
      SCAN_SKIP_WORDS?: string;
      SCAN_MIN_SIZE_MB?: string;
      SHOW_CLOCK?: string;
      VERSION_PRIORITY?: string;
      ALWAYS_ON_TOP?: string;
      DISK_RULE_WATCHED_ENABLED?: string;
      DISK_RULE_WATCHED_DAYS?: string;
      DISK_RULE_UNSEEN_ENABLED?: string;
      DISK_RULE_UNSEEN_DAYS?: string;
      DISK_RULE_INACTIVE_ENABLED?: string;
      DISK_RULE_INACTIVE_DAYS?: string;
      DISK_RULE_SIZE_ENABLED?: string;
      DISK_RULE_SIZE_GB?: string;
      DISK_RULE_SIZE_REQUIRE_WATCHED?: string;
      DISK_RULE_RATING_ENABLED?: string;
      DISK_RULE_RATING_MAX?: string;
      DISK_RULE_SERIES_MODE?: string;
      DISK_RULE_PROTECT_FAVORITES?: string;
    } }>, reply: FastifyReply) => {
      try {
        const body = request.body;
        dbg('PUT /api/settings — mottagen payload från klient', body);

        const savedKeys: Record<string, string> = {};
        const updateSetting = (key: string, value: string | undefined) => {
          if (value !== undefined) {
            db.prepare(`
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
        updateSetting('SHOW_RELEASE_VERSION', body.SHOW_RELEASE_VERSION);
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
        updateSetting('DISK_RULE_WATCHED_ENABLED', body.DISK_RULE_WATCHED_ENABLED);
        updateSetting('DISK_RULE_WATCHED_DAYS', body.DISK_RULE_WATCHED_DAYS);
        updateSetting('DISK_RULE_UNSEEN_ENABLED', body.DISK_RULE_UNSEEN_ENABLED);
        updateSetting('DISK_RULE_UNSEEN_DAYS', body.DISK_RULE_UNSEEN_DAYS);
        updateSetting('DISK_RULE_INACTIVE_ENABLED', body.DISK_RULE_INACTIVE_ENABLED);
        updateSetting('DISK_RULE_INACTIVE_DAYS', body.DISK_RULE_INACTIVE_DAYS);
        updateSetting('DISK_RULE_SIZE_ENABLED', body.DISK_RULE_SIZE_ENABLED);
        updateSetting('DISK_RULE_SIZE_GB', body.DISK_RULE_SIZE_GB);
        updateSetting('DISK_RULE_SIZE_REQUIRE_WATCHED', body.DISK_RULE_SIZE_REQUIRE_WATCHED);
        updateSetting('DISK_RULE_RATING_ENABLED', body.DISK_RULE_RATING_ENABLED);
        updateSetting('DISK_RULE_RATING_MAX', body.DISK_RULE_RATING_MAX);
        updateSetting('DISK_RULE_SERIES_MODE', body.DISK_RULE_SERIES_MODE);
        updateSetting('DISK_RULE_PROTECT_FAVORITES', body.DISK_RULE_PROTECT_FAVORITES);

        dbg('PUT /api/settings — faktiskt sparade till DB', savedKeys);
        return reply.send({ success: true });
      } catch (err) {
        dbg('PUT /api/settings — FEL vid sparning', { error: String(err) });
        console.error('[Settings] Failed to update settings:', err);
        return reply.code(500).send({ error: 'Failed to update settings' });
      }
    }
  );
}
