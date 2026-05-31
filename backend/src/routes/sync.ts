import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { syncAllExternalData, syncStatus } from '../services/rating_sync';

export default async function syncRoutes(fastify: FastifyInstance) {
  
  // POST /api/sync/trigger
  // Triggers Trakt & Simkl synchronization in the background
  fastify.post(
    '/api/sync/trigger',
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
      if (syncStatus.isSyncing) {
        return reply.code(409).send({ error: 'A synchronization process is already in progress' });
      }

      console.log('[Sync Route] Triggering manual full external sync in background...');
      
      // Run sync in the background
      syncAllExternalData().catch((err) => {
        console.error('[Sync Route] Background manual sync failed:', err);
      });

      return reply.code(202).send({
        message: 'Sync triggered successfully in the background',
        status: 'syncing'
      });
    }
  );

  // GET /api/sync/status
  // Returns current sync progress and last result
  fastify.get(
    '/api/sync/status',
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
      return reply.send(syncStatus);
    }
  );
}
