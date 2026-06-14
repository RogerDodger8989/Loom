import fastify, { FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import * as dotenv from 'dotenv';
import authRoutes from './routes/auth';
import libraryRoutes, { setupFileWatchers } from './routes/library';
import mediaRoutes from './routes/media';
import markersRoutes from './routes/markers';
import settingsRoutes from './routes/settings';
import oauthRoutes from './routes/oauth';
import syncRoutes from './routes/sync';
import playbackRoutes from './routes/playback';
import calendarRoutes from './routes/calendar';
import notificationsRoutes from './routes/notifications';
import logsRoutes from './routes/logs';
import serverRoutes from './routes/server';
import usersRoutes from './routes/users';
import statsRoutes from './routes/stats';
import rssRoutes from './routes/rss';
import exportRoutes from './routes/export';
import diskRoutes from './routes/disk';
import musicRoutes from './routes/music';
import multipart from '@fastify/multipart';
import { addLog } from './services/log_store';
import db from './config/database'; // Import ensures database gets initialized and seeded on boot
import { syncAllExternalData } from './services/rating_sync';

// Load environment variables
dotenv.config();

const isTest = process.env.NODE_ENV === 'test';

// Intercept console output into the in-memory log store (skip in test mode)
if (!isTest) {
  const _origLog   = console.log.bind(console);
  const _origWarn  = console.warn.bind(console);
  const _origError = console.error.bind(console);
  console.log   = (...a) => { addLog('info',  a.map(String).join(' ')); _origLog(...a);   };
  console.warn  = (...a) => { addLog('warn',  a.map(String).join(' ')); _origWarn(...a);  };
  console.error = (...a) => { addLog('error', a.map(String).join(' ')); _origError(...a); };
}

export async function buildApp(): Promise<FastifyInstance> {
  const app = fastify({
    logger: isTest ? false : {
      transport: {
        target: 'pino-pretty',
        options: {
          colorize: true,
          translateTime: 'yyyy-mm-dd HH:MM:ss Z',
          ignore: 'pid,hostname'
        }
      }
    }
  });

  app.register(multipart, { limits: { fileSize: 100 * 1024 * 1024 } });

  app.register(cors, {
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
  });

  const jwtSecret = process.env.JWT_SECRET || 'loom-offgrid-super-secret-key-1337-abc-xyz';
  app.register(jwt, { secret: jwtSecret });

  // Base health-check route
  app.get('/', async () => ({
    app: 'LOOM',
    description: 'API-driven headless offgrid media server',
    status: 'ONLINE',
    time: new Date().toISOString()
  }));

  // Register API Routes
  app.register(authRoutes);
  app.register(libraryRoutes);
  app.register(mediaRoutes);
  app.register(markersRoutes);
  app.register(settingsRoutes);
  app.register(oauthRoutes);
  app.register(syncRoutes);
  app.register(playbackRoutes);
  app.register(calendarRoutes);
  app.register(notificationsRoutes);
  app.register(logsRoutes);
  app.register(serverRoutes);
  app.register(usersRoutes);
  app.register(statsRoutes);
  app.register(rssRoutes);
  app.register(exportRoutes);
  app.register(diskRoutes);
  app.register(musicRoutes);

  // Log every HTTP response to the in-memory log store (skip in test mode)
  if (!isTest) {
    app.addHook('onResponse', async (req, reply) => {
      const level = reply.statusCode >= 500 ? 'error' : reply.statusCode >= 400 ? 'warn' : 'info';
      addLog(level, `${req.method} ${req.url} → ${reply.statusCode}`);
    });
    app.addHook('onError', async (req, _reply, err) => {
      addLog('error', `${req.method} ${req.url} ✗ ${err.message}`);
    });
  }

  app.setErrorHandler((error, request, reply) => {
    app.log.error(error);
    if (error.statusCode) {
      return reply.code(error.statusCode).send({ error: error.message });
    }
    return reply.code(500).send({ error: 'Internal Server Error' });
  });

  return app;
}

// Start the real server only when not running under Jest
if (!isTest) {
  const PORT = parseInt(process.env.PORT || '8080', 10);
  const HOST = process.env.HOST || '0.0.0.0';

  const start = async () => {
    try {
      console.log('[Loom Server] Database status checked. Starting API listener...');
      const app = await buildApp();
      await app.listen({ port: PORT, host: HOST });
      console.log(`
██╗      ██████╗  ██████╗ ███╗   ███╗
██║     ██╔═══██╗██╔═══██╗████╗ ████║
██║     ██║   ██║██║   ██║██╔████╔██║
██║     ██║   ██║██║   ██║██║╚██╔╝██║
███████╗╚██████╔╝╚██████╔╝██║ ╚═╝ ██║
╚══════╝ ╚═════╝  ╚═════╝ ╚═╝     ╚═╝
    Headless Media Server is now online!
    👉 Server listening on http://${HOST}:${PORT}
      `);

      setupFileWatchers();

      syncAllExternalData().catch(e => {
        console.error('[Startup Sync] Failed to run syncAllExternalData:', e);
      });

      const syncIntervalMinutes = Number.parseInt(process.env.EXTERNAL_SYNC_INTERVAL_MINUTES || '45', 10);
      const safeIntervalMinutes = Number.isFinite(syncIntervalMinutes) && syncIntervalMinutes > 0
        ? syncIntervalMinutes
        : 45;

      setInterval(() => {
        syncAllExternalData().catch(e => {
          console.error('[Scheduled Sync] Failed to run syncAllExternalData:', e);
        });
      }, safeIntervalMinutes * 60 * 1000);

      console.log(`[Sync] Scheduled external sync every ${safeIntervalMinutes} minutes.`);
    } catch (err) {
      console.error(err);
      process.exit(1);
    }
  };

  start();
}
