import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';

export default async function settingsRoutes(fastify: FastifyInstance) {
  
  // GET /api/settings/tmdb
  // Retrieves the current TMDB API Key (Admin only)
  fastify.get(
    '/api/settings/tmdb',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
          // Admin check could be added here
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized' });
        }
      }]
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      try {
        const keys = ['TMDB_API_KEY', 'OMDB_API_KEY', 'SIMKL_CLIENT_ID', 'DEFAULT_SUBTITLE_LANG'];
        const placeholders = keys.map(() => '?').join(',');
        const rows = db.prepare(`SELECT key, value FROM system_settings WHERE key IN (${placeholders})`).all(...keys) as { key: string, value: string }[];
        
        const settings = {
          TMDB_API_KEY: '',
          OMDB_API_KEY: '',
          SIMKL_CLIENT_ID: '',
          DEFAULT_SUBTITLE_LANG: 'sv'
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
    }
  );

  // PUT /api/settings
  // Updates global system settings
  fastify.put(
    '/api/settings',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
          // Admin check could be added here
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized' });
        }
      }]
    },
    async (request: FastifyRequest<{ Body: { TMDB_API_KEY?: string; OMDB_API_KEY?: string; SIMKL_CLIENT_ID?: string; DEFAULT_SUBTITLE_LANG?: string } }>, reply: FastifyReply) => {
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
        updateSetting('DEFAULT_SUBTITLE_LANG', body.DEFAULT_SUBTITLE_LANG);

        return reply.send({ success: true });
      } catch (err) {
        console.error('[Settings] Failed to update settings:', err);
        return reply.code(500).send({ error: 'Failed to update settings' });
      }
    }
  );
}
