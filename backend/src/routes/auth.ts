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

  // 5. POST /api/auth/pair/unpair
  // Unpair/remove a device ID from the database
  fastify.post('/api/auth/pair/unpair', async (request: FastifyRequest<{ Body: { deviceId?: string } }>, reply: FastifyReply) => {
    const { deviceId } = request.body || {};

    if (!deviceId) {
      return reply.code(400).send({ error: 'Device ID is required' });
    }

    const success = pairingService.unpairDevice(deviceId);

    if (!success) {
      return reply.code(500).send({ error: 'Failed to unpair device' });
    }

    return reply.send({ success: true, message: 'Device unpaired successfully!' });
  });

  // 6. GET /api/auth/devices
  // Authenticated: List all paired/trusted devices
  fastify.get(
    '/api/auth/devices',
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
      try {
        const devices = db.prepare('SELECT device_id, user_id, device_name, paired_at FROM paired_devices ORDER BY paired_at DESC').all();
        return reply.send(devices);
      } catch (err) {
        console.error('[Auth] Failed to retrieve devices:', err);
        return reply.code(500).send({ error: 'Failed to retrieve devices' });
      }
    }
  );

  // 7. PUT /api/auth/devices/rename
  // Authenticated: Rename a paired device
  fastify.put(
    '/api/auth/devices/rename',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Authentication required' });
        }
      }]
    },
    async (request: FastifyRequest<{ Body: { deviceId?: string; deviceName?: string } }>, reply: FastifyReply) => {
      const { deviceId, deviceName } = request.body || {};
      if (!deviceId || !deviceName) {
        return reply.code(400).send({ error: 'deviceId and deviceName are required' });
      }

      try {
        db.prepare('UPDATE paired_devices SET device_name = ? WHERE device_id = ?').run(deviceName, deviceId);
        console.log(`[Auth] Renamed device ${deviceId} to "${deviceName}"`);
        return reply.send({ success: true, message: `Device renamed to "${deviceName}"` });
      } catch (err) {
        console.error('[Auth] Failed to rename device:', err);
        return reply.code(500).send({ error: 'Failed to rename device' });
      }
    }
  );

  // 8. DELETE /api/auth/devices/:deviceId
  // Authenticated: Remove a specific paired device
  fastify.delete(
    '/api/auth/devices/:deviceId',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Authentication required' });
        }
      }]
    },
    async (request: FastifyRequest<{ Params: { deviceId: string } }>, reply: FastifyReply) => {
      const { deviceId } = request.params;
      if (!deviceId) {
        return reply.code(400).send({ error: 'Device ID is required' });
      }

      try {
        db.prepare('DELETE FROM paired_devices WHERE device_id = ?').run(deviceId);
        console.log(`[Auth] Removed device ${deviceId}`);
        return reply.send({ success: true, message: 'Device removed successfully' });
      } catch (err) {
        console.error('[Auth] Failed to remove device:', err);
        return reply.code(500).send({ error: 'Failed to remove device' });
      }
    }
  );
}
