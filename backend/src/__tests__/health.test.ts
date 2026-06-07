import { buildApp } from '../index';
import { FastifyInstance } from 'fastify';

describe('GET / (hälsokontroll)', () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('returnerar 200 med app-info', async () => {
    const res = await app.inject({ method: 'GET', url: '/' });

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.app).toBe('LOOM');
    expect(body.status).toBe('ONLINE');
    expect(body).toHaveProperty('time');
  });
});
