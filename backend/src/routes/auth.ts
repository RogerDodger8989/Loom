import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import bcrypt from 'bcryptjs';
import db from '../config/database';
import { pairingService } from '../services/pairing';
import crypto from 'crypto';

interface LoginBody {
  username?: string;
  password?: string;
}

interface PairRequestBody {
  deviceId?: string;
}

interface PairConfirmBody {
  code?: string;
  deviceName?: string;
}

export default async function authRoutes(fastify: FastifyInstance) {
  
  // 1. POST /api/auth/login
  fastify.post('/api/auth/login', async (request: FastifyRequest<{ Body: LoginBody }>, reply: FastifyReply) => {
    const { username, password } = request.body;

    if (!username || !password) {
      return reply.code(400).send({ error: 'Username and password are required' });
    }

    try {
      const user = db.prepare('SELECT * FROM users WHERE username = ?').all(username)[0] as {
        id: string;
        username: string;
        password_hash: string;
        role: 'Admin' | 'User';
      } | undefined;

      if (!user) {
        return reply.code(401).send({ error: 'Invalid username or password' });
      }

      const isPasswordMatch = bcrypt.compareSync(password, user.password_hash);
      if (!isPasswordMatch) {
        return reply.code(401).send({ error: 'Invalid username or password' });
      }

      // Generate JWT
      const token = fastify.jwt.sign({
        id: user.id,
        username: user.username,
        role: user.role
      });

      return reply.send({
        token,
        user: {
          id: user.id,
          username: user.username,
          role: user.role
        }
      });
    } catch (err) {
      console.error(err);
      return reply.code(500).send({ error: 'Internal server error' });
    }
  });

  // 2. POST /api/auth/pair/request
  // Unauthenticated TV app requests a PIN code and Device ID
  fastify.post('/api/auth/pair/request', async (request: FastifyRequest<{ Body: PairRequestBody }>, reply: FastifyReply) => {
    // If the device doesn't have a deviceId, we'll generate one
    const deviceId = request.body?.deviceId || crypto.randomUUID();
    
    const result = pairingService.requestPairing(deviceId);
    
    return reply.send({
      code: result.code,
      deviceId: result.deviceId,
      expiresAt: result.expiresAt
    });
  });

  // 3. GET /api/auth/pair/status
  // TV app polls this endpoint to check if the user confirmed the code
  fastify.get('/api/auth/pair/status', async (request: FastifyRequest<{ Querystring: { deviceId?: string } }>, reply: FastifyReply) => {
    const { deviceId } = request.query;

    if (!deviceId) {
      return reply.code(400).send({ error: 'Query parameter deviceId is required' });
    }

    const status = pairingService.checkStatus(deviceId);

    if (status.paired && status.userId) {
      // Find the paired user in the DB to sign a JWT
      try {
        const user = db.prepare('SELECT id, username, role FROM users WHERE id = ?').all(status.userId)[0] as {
          id: string;
          username: string;
          role: 'Admin' | 'User';
        } | undefined;

        if (!user) {
          return reply.code(404).send({ error: 'Paired user not found' });
        }

        const token = fastify.jwt.sign({
          id: user.id,
          username: user.username,
          role: user.role
        });

        return reply.send({
          paired: true,
          token,
          user: {
            id: user.id,
            username: user.username,
            role: user.role
          }
        });
      } catch (err) {
        console.error(err);
        return reply.code(500).send({ error: 'Internal server error pairing' });
      }
    }

    return reply.send({ paired: false });
  });

  // 4. POST /api/auth/pair/confirm
  // Authenticated user inputs code on device management screen
  fastify.post(
    '/api/auth/pair/confirm',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Authentication required' });
        }
      }]
    },
    async (request: FastifyRequest<{ Body: PairConfirmBody }>, reply: FastifyReply) => {
      const { code, deviceName } = request.body;
      const user = request.user as { id: string; username: string; role: string };

      if (!code) {
        return reply.code(400).send({ error: 'Pairing code is required' });
      }

      const success = pairingService.confirmPairing(code, user.id, deviceName || 'TV App');

      if (!success) {
        return reply.code(400).send({ error: 'Invalid or expired pairing code' });
      }

      return reply.send({ success: true, message: 'Device paired successfully!' });
    }
  );
}
