import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { getEntries, getAllAsText } from '../services/log_store';

export default async function logsRoutes(fastify: FastifyInstance) {

  // GET /api/logs — recent entries, optional ?sinceId=N for incremental polling
  fastify.get('/api/logs', async (request: FastifyRequest, reply: FastifyReply) => {
    const { sinceId } = request.query as { sinceId?: string };
    const sinceIdNum = sinceId ? parseInt(sinceId, 10) : undefined;
    return reply.send({ entries: getEntries(sinceIdNum) });
  });

  // GET /api/logs/download — full log as plain-text file
  fastify.get('/api/logs/download', async (_request: FastifyRequest, reply: FastifyReply) => {
    const text = getAllAsText();
    reply.header('Content-Type', 'text/plain; charset=utf-8');
    reply.header('Content-Disposition', `attachment; filename="loom-${new Date().toISOString().slice(0,10)}.log"`);
    return reply.send(text);
  });
}
