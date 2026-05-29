import fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import * as dotenv from 'dotenv';
import authRoutes from './routes/auth';
import libraryRoutes from './routes/library';
import mediaRoutes from './routes/media';
import db from './config/database'; // Import ensures database gets initialized and seeded on boot

// Load environment variables
dotenv.config();

const app = fastify({
  logger: {
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

// Configure CORS - Crucial for local desktop and mobile/TV client requests
app.register(cors, {
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
});

// Configure JWT Authentication
// In a production offgrid Docker image, this can be supplied via environment variable
const jwtSecret = process.env.JWT_SECRET || 'loom-offgrid-super-secret-key-1337-abc-xyz';
app.register(jwt, {
  secret: jwtSecret
});

// Declare a base test route
app.get('/', async () => {
  return { 
    app: 'LOOM', 
    description: 'API-driven headless offgrid media server',
    status: 'ONLINE',
    time: new Date().toISOString()
  };
});

// Register API Routes
app.register(authRoutes);
app.register(libraryRoutes);
app.register(mediaRoutes);

// Global Error Handler
app.setErrorHandler((error, request, reply) => {
  app.log.error(error);
  if (error.statusCode) {
    return reply.code(error.statusCode).send({ error: error.message });
  }
  return reply.code(500).send({ error: 'Internal Server Error' });
});

// Start the server
const PORT = parseInt(process.env.PORT || '8080', 10);
const HOST = process.env.HOST || '0.0.0.0'; // Bind to all interfaces for local TV/Docker network access

const start = async () => {
  try {
    // Check DB status
    console.log('[Loom Server] Database status checked. Starting API listener...');
    
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
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
};

start();
