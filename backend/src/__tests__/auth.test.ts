import { buildApp } from '../index';
import { FastifyInstance } from 'fastify';

describe('Auth Routes', () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
  });

  // ── POST /api/auth/login ───────────────────────────────────────────────

  describe('POST /api/auth/login', () => {
    it('returnerar 400 när body saknas helt', async () => {
      const res = await app.inject({
        method: 'POST',
        url: '/api/auth/login',
        payload: {},
      });
      expect(res.statusCode).toBe(400);
      expect(JSON.parse(res.body)).toHaveProperty('error');
    });

    it('returnerar 400 när lösenord saknas', async () => {
      const res = await app.inject({
        method: 'POST',
        url: '/api/auth/login',
        payload: { username: 'admin' },
      });
      expect(res.statusCode).toBe(400);
    });

    it('returnerar 401 vid fel lösenord', async () => {
      const res = await app.inject({
        method: 'POST',
        url: '/api/auth/login',
        payload: { username: 'admin', password: 'fel_lösenord' },
      });
      expect(res.statusCode).toBe(401);
      expect(JSON.parse(res.body).error).toMatch(/Invalid/i);
    });

    it('returnerar 401 vid okänt användarnamn', async () => {
      const res = await app.inject({
        method: 'POST',
        url: '/api/auth/login',
        payload: { username: 'finns_inte', password: 'vadsomhelst' },
      });
      expect(res.statusCode).toBe(401);
    });

    it('returnerar 200 med JWT-token vid korrekt inloggning (standard-admin)', async () => {
      const res = await app.inject({
        method: 'POST',
        url: '/api/auth/login',
        payload: { username: 'admin', password: 'adminpassword' },
      });
      expect(res.statusCode).toBe(200);
      const body = JSON.parse(res.body);
      expect(body).toHaveProperty('token');
      expect(body.user.username).toBe('admin');
      expect(body.user.role).toBe('Admin');
    });
  });

  // ── GET /api/auth/profiles ─────────────────────────────────────────────

  describe('GET /api/auth/profiles', () => {
    it('returnerar en lista med användarprofiler', async () => {
      const res = await app.inject({ method: 'GET', url: '/api/auth/profiles' });
      expect(res.statusCode).toBe(200);
      const body = JSON.parse(res.body);
      expect(Array.isArray(body)).toBe(true);
      // Standard-admin ska alltid finnas (skapas vid första start)
      expect(body.length).toBeGreaterThan(0);
      expect(body[0]).toHaveProperty('username');
      expect(body[0]).not.toHaveProperty('password_hash');
    });
  });

  // ── PUT /api/auth/me (byta lösenord) ──────────────────────────────────

  describe('PUT /api/auth/me', () => {
    it('returnerar 401 utan JWT-token', async () => {
      const res = await app.inject({
        method: 'PUT',
        url: '/api/auth/me',
        payload: { currentPassword: 'adminpassword', newPassword: 'nytt123' },
      });
      expect(res.statusCode).toBe(401);
    });

    it('returnerar 400 om nytt lösenord är för kort (< 6 tecken)', async () => {
      // Logga in först för att få token
      const loginRes = await app.inject({
        method: 'POST',
        url: '/api/auth/login',
        payload: { username: 'admin', password: 'adminpassword' },
      });
      const { token } = JSON.parse(loginRes.body);

      const res = await app.inject({
        method: 'PUT',
        url: '/api/auth/me',
        headers: { Authorization: `Bearer ${token}` },
        payload: { currentPassword: 'adminpassword', newPassword: '123' },
      });
      expect(res.statusCode).toBe(400);
    });
  });
});
