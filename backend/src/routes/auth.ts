import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import bcrypt from 'bcryptjs';
import db from '../config/database';
import * as fs from 'fs';
import * as path from 'path';

const avatarsDir = path.resolve(__dirname, '../../../config/avatars');
const AUTH_DEBUG_LOG = path.resolve(__dirname, '../../../config/settings_debug.log');
function dbg(msg: string, data?: any) {
  const line = `[${new Date().toISOString()}] ${msg}${data !== undefined ? '\n' + JSON.stringify(data, null, 2) : ''}\n`;
  fs.appendFileSync(AUTH_DEBUG_LOG, line);
}

interface LoginBody {
  username?: string;
  password?: string;
}

interface JwtUser { id: string; username: string; role: string; }

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

  // 2. GET /api/auth/profiles — public list of users for profile picker (no passwords)
  fastify.get('/api/auth/profiles', async (_request: FastifyRequest, reply: FastifyReply) => {
    const rows = db.prepare(
      `SELECT id, username, full_name, role, avatar_path,
              CASE WHEN pin_hash IS NOT NULL AND pin_hash != '' THEN 1 ELSE 0 END AS has_pin
       FROM users ORDER BY username ASC`
    ).all();
    return reply.send(rows);
  });

  // 3. GET /api/auth/me — hämta inloggad användares profil
  fastify.get('/api/auth/me',
    {
      preValidation: [async (request, reply) => {
        try { await request.jwtVerify(); } catch { reply.code(401).send({ error: 'Unauthorized' }); }
      }]
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const caller = request.user as JwtUser;
      const row = db.prepare('SELECT id, username, full_name, role, avatar_path FROM users WHERE id = ?').get(caller.id) as {
        id: string; username: string; full_name: string | null; role: string; avatar_path: string | null;
      } | undefined;
      if (!row) return reply.code(404).send({ error: 'Användaren finns inte' });
      dbg(`GET /api/auth/me — returnerar profil för user ${caller.id}`, row);
      return reply.send(row);
    }
  );

  // 4. PUT /api/auth/me — byta eget lösenord / namn / användarnamn / PIN
  fastify.put('/api/auth/me',
    {
      preValidation: [async (request, reply) => {
        try { await request.jwtVerify(); } catch { reply.code(401).send({ error: 'Unauthorized' }); }
      }]
    },
    async (request: FastifyRequest<{
      Body: {
        currentPassword?: string;
        newPassword?: string;
        full_name?: string;
        newUsername?: string;
        pin?: string | null;
      }
    }>, reply: FastifyReply) => {
      const caller = request.user as JwtUser;
      const { currentPassword, newPassword, full_name, newUsername, pin } = request.body ?? {};

      const row = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(caller.id) as { password_hash: string } | undefined;
      if (!row) return reply.code(404).send({ error: 'Användaren finns inte' });

      // Byta lösenord kräver currentPassword
      if (newPassword !== undefined) {
        if (!currentPassword) return reply.code(400).send({ error: 'currentPassword krävs för att byta lösenord' });
        if (!bcrypt.compareSync(currentPassword, row.password_hash)) {
          return reply.code(401).send({ error: 'Fel nuvarande lösenord' });
        }
        if (newPassword.length < 6) return reply.code(400).send({ error: 'Nytt lösenord måste vara minst 6 tecken' });
        const newHash = bcrypt.hashSync(newPassword, 10);
        db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(newHash, caller.id);
      }

      if (full_name !== undefined) {
        db.prepare('UPDATE users SET full_name = ? WHERE id = ?').run(full_name || null, caller.id);
      }

      if (newUsername !== undefined) {
        const conflict = db.prepare('SELECT id FROM users WHERE username = ? AND id != ?').get(newUsername, caller.id);
        if (conflict) return reply.code(409).send({ error: 'Användarnamnet är redan taget' });
        db.prepare('UPDATE users SET username = ? WHERE id = ?').run(newUsername, caller.id);
      }

      if (pin !== undefined) {
        const pinHash = pin ? bcrypt.hashSync(pin, 10) : null;
        const pinPlain = pin || null;
        db.prepare('UPDATE users SET pin_hash = ?, pin_plain = ? WHERE id = ?').run(pinHash, pinPlain, caller.id);
      }

      // Return a fresh JWT so the frontend reflects any username change immediately
      const updated = db.prepare('SELECT id, username, role, full_name, avatar_path FROM users WHERE id = ?').get(caller.id) as any;
      const newToken = fastify.jwt.sign({ id: updated.id, username: updated.username, role: updated.role });
      dbg(`PUT /api/auth/me — sparade för user ${caller.id}`, { full_name: updated.full_name, username: updated.username });
      return reply.send({ success: true, token: newToken });
    }
  );

  // 4. POST /api/auth/me/avatar — ladda upp profilbild
  fastify.post('/api/auth/me/avatar',
    {
      preValidation: [async (request, reply) => {
        try { await request.jwtVerify(); } catch { reply.code(401).send({ error: 'Unauthorized' }); }
      }]
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      const caller = (request.user as JwtUser);
      const data = await (request as any).file();
      if (!data) return reply.code(400).send({ error: 'Ingen fil skickades' });

      const chunks: Buffer[] = [];
      for await (const chunk of data.file) chunks.push(chunk);
      const buf = Buffer.concat(chunks);

      if (!fs.existsSync(avatarsDir)) fs.mkdirSync(avatarsDir, { recursive: true });
      const filePath = path.join(avatarsDir, `${caller.id}.jpg`);
      fs.writeFileSync(filePath, buf);

      const avatarUrl = `/api/avatars/${caller.id}.jpg`;
      db.prepare('UPDATE users SET avatar_path = ? WHERE id = ?').run(avatarUrl, caller.id);
      return reply.send({ success: true, avatar_path: avatarUrl });
    }
  );

  // 6. GET /api/avatars/:userId.jpg — servera profilbild
  fastify.get('/api/avatars/:filename', async (request: FastifyRequest<{ Params: { filename: string } }>, reply: FastifyReply) => {
    const { filename } = request.params;
    const filePath = path.join(avatarsDir, filename);
    if (!fs.existsSync(filePath)) return reply.code(404).send({ error: 'Not found' });
    const buf = fs.readFileSync(filePath);
    reply.header('Content-Type', 'image/jpeg');
    reply.header('Cache-Control', 'public, max-age=3600');
    return reply.send(buf);
  });

  // 7. POST /api/auth/login-pin — logga in med userId + PIN, returnerar JWT
  fastify.post('/api/auth/login-pin',
    async (request: FastifyRequest<{ Body: { userId?: string; pin?: string } }>, reply: FastifyReply) => {
      const { userId, pin } = request.body ?? {};
      if (!userId || !pin) return reply.code(400).send({ error: 'userId och pin krävs' });
      const user = db.prepare('SELECT id, username, role, pin_hash FROM users WHERE id = ?').get(userId) as {
        id: string; username: string; role: string; pin_hash: string | null;
      } | undefined;
      if (!user) return reply.code(404).send({ error: 'Användaren finns inte' });
      if (!user.pin_hash) return reply.code(400).send({ error: 'Ingen PIN satt för denna användare' });
      if (!bcrypt.compareSync(pin, user.pin_hash)) return reply.code(401).send({ error: 'Fel PIN' });
      const token = fastify.jwt.sign({ id: user.id, username: user.username, role: user.role });
      return reply.send({ token, user: { id: user.id, username: user.username, role: user.role } });
    }
  );

  // 8. POST /api/auth/verify-pin — kontrollera PIN (för profilväljaren)
  fastify.post('/api/auth/verify-pin',
    async (request: FastifyRequest<{ Body: { userId?: string; pin?: string } }>, reply: FastifyReply) => {
      const { userId, pin } = request.body ?? {};
      if (!userId || !pin) return reply.code(400).send({ error: 'userId och pin krävs' });
      const row = db.prepare('SELECT pin_hash FROM users WHERE id = ?').get(userId) as { pin_hash: string | null } | undefined;
      if (!row) return reply.code(404).send({ error: 'Användaren finns inte' });
      if (!row.pin_hash) return reply.code(200).send({ valid: true }); // ingen PIN satt = tillåt
      const valid = bcrypt.compareSync(pin, row.pin_hash);
      return reply.send({ valid });
    }
  );

}
