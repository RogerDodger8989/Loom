import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import bcrypt from 'bcryptjs';
import db from '../config/database';
import { randomUUID } from 'crypto';

interface JwtUser { id: string; username: string; role: string; }

const adminHook = async (request: FastifyRequest, reply: FastifyReply) => {
  try { await request.jwtVerify(); } catch { return reply.code(401).send({ error: 'Unauthorized' }); }
  const user = request.user as JwtUser;
  if (user.role !== 'Admin') return reply.code(403).send({ error: 'Admin required' });
};

export default async function usersRoutes(fastify: FastifyInstance) {

  // GET /api/users — lista alla användare (Admin)
  fastify.get('/api/users', { preValidation: [adminHook] }, async (_req, reply) => {
    const rows = db.prepare(
      `SELECT id, username, full_name, role, avatar_path, pin_plain,
              CASE WHEN pin_hash IS NOT NULL AND pin_hash != '' THEN 1 ELSE 0 END AS has_pin
       FROM users ORDER BY username ASC`
    ).all();
    return reply.send(rows);
  });

  // POST /api/users — skapa ny användare (Admin)
  fastify.post<{ Body: { username?: string; password?: string; role?: string; full_name?: string; pin?: string } }>(
    '/api/users',
    { preValidation: [adminHook] },
    async (request, reply) => {
      const { username, password, role, full_name, pin } = request.body ?? {};
      if (!username || !password) return reply.code(400).send({ error: 'username och password krävs' });
      if (role !== 'Admin' && role !== 'User') return reply.code(400).send({ error: 'role måste vara Admin eller User' });

      const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
      if (existing) return reply.code(409).send({ error: 'Användarnamnet är redan taget' });

      const id = randomUUID();
      const hash = bcrypt.hashSync(password, 10);
      const pinHash = pin ? bcrypt.hashSync(pin, 10) : null;
      db.prepare('INSERT INTO users (id, username, password_hash, role, full_name, pin_hash) VALUES (?, ?, ?, ?, ?, ?)')
        .run(id, username, hash, role, full_name ?? null, pinHash);
      return reply.code(201).send({ id, username, role, full_name: full_name ?? null });
    }
  );

  // PUT /api/users/:id — uppdatera användare (Admin)
  fastify.put<{ Params: { id: string }; Body: { username?: string; full_name?: string; role?: string; password?: string; pin?: string | null } }>(
    '/api/users/:id',
    { preValidation: [adminHook] },
    async (request, reply) => {
      const { id } = request.params;
      const { username, full_name, role, password, pin } = request.body ?? {};

      const row = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
      if (!row) return reply.code(404).send({ error: 'Användaren finns inte' });

      if (username !== undefined) {
        const conflict = db.prepare('SELECT id FROM users WHERE username = ? AND id != ?').get(username, id);
        if (conflict) return reply.code(409).send({ error: 'Användarnamnet är redan taget' });
        db.prepare('UPDATE users SET username = ? WHERE id = ?').run(username, id);
      }
      if (full_name !== undefined) {
        db.prepare('UPDATE users SET full_name = ? WHERE id = ?').run(full_name || null, id);
      }
      if (role === 'Admin' || role === 'User') {
        db.prepare('UPDATE users SET role = ? WHERE id = ?').run(role, id);
      }
      if (password) {
        const hash = bcrypt.hashSync(password, 10);
        db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(hash, id);
      }
      if (pin !== undefined) {
        // pin=null removes PIN, pin=string sets new PIN
        const pinHash = pin ? bcrypt.hashSync(pin, 10) : null;
        const pinPlain = pin || null;
        db.prepare('UPDATE users SET pin_hash = ?, pin_plain = ? WHERE id = ?').run(pinHash, pinPlain, id);
      }

      const updated = db.prepare('SELECT id, username, full_name, role FROM users WHERE id = ?').get(id) as { id: string; username: string; full_name: string | null; role: string };
      return reply.send(updated);
    }
  );

  // DELETE /api/users/:id — ta bort användare (Admin, ej sig själv)
  fastify.delete<{ Params: { id: string } }>(
    '/api/users/:id',
    { preValidation: [adminHook] },
    async (request, reply) => {
      const { id } = request.params;
      const caller = request.user as JwtUser;
      if (caller.id === id) return reply.code(400).send({ error: 'Du kan inte ta bort ditt eget konto' });

      const row = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
      if (!row) return reply.code(404).send({ error: 'Användaren finns inte' });

      db.prepare('DELETE FROM users WHERE id = ?').run(id);
      return reply.send({ success: true });
    }
  );
}
