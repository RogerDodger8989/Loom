import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';

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
        'sync_simkl_watched'
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
        sync_simkl_watched: 'true'
      };

      rows.forEach(r => {
        if (r.key in settings) {
          (settings as any)[r.key] = r.value;
        }
      });
      
      return reply.send(settings);
    } catch (err) {
      console.error('[Settings] Failed to get settings:', err);
      return reply.code(500).send({ error: 'Failed to retrieve settings' });
    }
  };

  const authOptions = {
    preValidation: [async (request: FastifyRequest, reply: FastifyReply) => {
      try {
        await request.jwtVerify();
      } catch (err) {
        reply.code(401).send({ error: 'Unauthorized' });
      }
    }]
  };

  fastify.get('/api/settings', authOptions, getSettingsHandler);
  fastify.get('/api/settings/tmdb', authOptions, getSettingsHandler);

  // PUT /api/settings
  // Updates Loom global system settings
  fastify.put(
    '/api/settings',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized' });
        }
      }]
    },
    async (request: FastifyRequest<{ Body: { 
      TMDB_API_KEY?: string; 
      OMDB_API_KEY?: string; 
      SIMKL_CLIENT_ID?: string; 
      SIMKL_CLIENT_SECRET?: string;
      SIMKL_ACCESS_TOKEN?: string;
      TRAKT_API_KEY?: string;
      TRAKT_CLIENT_SECRET?: string;
      TRAKT_ACCESS_TOKEN?: string;
      TMDB_USER_AUTH?: string;
      DEFAULT_SUBTITLE_LANG?: string;
      METADATA_LANGUAGE?: string;
      METADATA_FALLBACK_LANGUAGE?: string;
      DEFAULT_AUDIO_LANG?: string;
      WATCH_PROVIDER_REGION?: string;
      TITLE_DISPLAY_STYLE?: string;
      PREFER_LOCAL_NFO?: string;
      HOME_LAYOUT?: string;
      sync_trakt_ratings?: string;
      sync_trakt_watched?: string;
      sync_simkl_ratings?: string;
      sync_simkl_watched?: string;
    } }>, reply: FastifyReply) => {
      try {
        const body = request.body;
        
        const updateSetting = (key: string, value: string | undefined) => {
          if (value !== undefined) {
            db.prepare(`
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
        updateSetting('HOME_LAYOUT', body.HOME_LAYOUT);
        updateSetting('sync_trakt_ratings', body.sync_trakt_ratings);
        updateSetting('sync_trakt_watched', body.sync_trakt_watched);
        updateSetting('sync_simkl_ratings', body.sync_simkl_ratings);
        updateSetting('sync_simkl_watched', body.sync_simkl_watched);

        return reply.send({ success: true });
      } catch (err) {
        console.error('[Settings] Failed to update settings:', err);
        return reply.code(500).send({ error: 'Failed to update settings' });
      }
    }
  );
}
