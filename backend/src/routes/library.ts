import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { mediaScanner } from '../services/scanner';

interface ScanBody {
  path?: string;
  type?: 'Movie' | 'Show' | 'Music';
  preferLocalNfo?: boolean;
}

let isScanning = false;
let lastScanResult: any = null;

export default async function libraryRoutes(fastify: FastifyInstance) {
  
  // POST /api/library/scan
  // Triggers media directory scanning in the background
  fastify.post(
    '/api/library/scan',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Authentication required' });
        }
      }]
    },
    async (request: FastifyRequest<{ Body: ScanBody }>, reply: FastifyReply) => {
      const { path: scanPath, type, preferLocalNfo } = request.body;

      if (!scanPath || !type) {
        return reply.code(400).send({ error: 'Parameters "path" and "type" are required' });
      }

      if (!['Movie', 'Show', 'Music'].includes(type)) {
        return reply.code(400).send({ error: 'Type must be one of: Movie, Show, Music' });
      }

      if (isScanning) {
        return reply.code(409).send({ error: 'A library scan is already in progress' });
      }

      isScanning = true;
      lastScanResult = null;

      // Execute scanning asynchronously in the background
      const localNfoPref = preferLocalNfo !== false;
      
      console.log(`[Library] Initiating background scan of "${scanPath}" (${type})...`);
      
      mediaScanner.scanLibrary(scanPath, type, localNfoPref)
        .then((result) => {
          isScanning = false;
          lastScanResult = {
            success: true,
            timestamp: new Date().toISOString(),
            ...result
          };
          console.log(`[Library] Background scan finished successfully.`);
        })
        .catch((err) => {
          isScanning = false;
          lastScanResult = {
            success: false,
            timestamp: new Date().toISOString(),
            error: err.message || String(err)
          };
          console.error(`[Library] Background scan failed:`, err);
        });

      return reply.code(202).send({
        message: 'Library scan triggered successfully in the background',
        status: 'scanning'
      });
    }
  );

  // GET /api/library/status
  // Returns current scanner state
  fastify.get(
    '/api/library/status',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Authentication required' });
        }
      }]
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      return reply.send({
        isScanning,
        lastScanResult
      });
    }
  );
}
