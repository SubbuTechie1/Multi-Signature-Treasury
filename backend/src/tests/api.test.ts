import request from 'supertest';
import app from '../src/index';

describe('Treasury API', () => {
  describe('POST /api/v1/treasury/create', () => {
    it('should validate request body', async () => {
      const response = await request(app)
        .post('/api/v1/treasury/create')
        .send({
          // Missing required fields
        });

      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('error');
    });

    it('should reject invalid threshold', async () => {
      const response = await request(app)
        .post('/api/v1/treasury/create')
        .send({
          signers: ['0x123', '0x456'],
          threshold: 10, // Too high
        });

      expect(response.status).toBe(400);
    });
  });

  describe('GET /api/v1/treasury/:id', () => {
    it('should return 404 for non-existent treasury', async () => {
      const response = await request(app)
        .get('/api/v1/treasury/0xinvalid');

      expect(response.status).toBe(404);
    });
  });
});

describe('Proposal API', () => {
  describe('POST /api/v1/proposal/create', () => {
    it('should validate proposal request', async () => {
      const response = await request(app)
        .post('/api/v1/proposal/create')
        .send({
          // Missing fields
        });

      expect(response.status).toBe(400);
    });

    it('should reject more than 50 transactions', async () => {
      const transactions = Array(51).fill({
        recipient: '0x123',
        amount: '1000',
        coin_type: '0x2::sui::SUI',
      });

      const response = await request(app)
        .post('/api/v1/proposal/create')
        .send({
          treasury_id: '0xtreasury',
          proposer: '0xproposer',
          transactions,
          category: 0,
        });

      expect(response.status).toBe(400);
    });
  });

  describe('GET /api/v1/proposal/list', () => {
    it('should return proposals list', async () => {
      const response = await request(app)
        .get('/api/v1/proposal/list');

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('proposals');
      expect(response.body).toHaveProperty('total');
    });

    it('should accept query parameters', async () => {
      const response = await request(app)
        .get('/api/v1/proposal/list?limit=10&offset=0');

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('limit', 10);
      expect(response.body).toHaveProperty('offset', 0);
    });
  });
});

describe('Health Check', () => {
  it('should return healthy status', async () => {
    const response = await request(app).get('/health');

    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('status', 'healthy');
    expect(response.body).toHaveProperty('timestamp');
  });
});

describe('404 Handler', () => {
  it('should return 404 for unknown routes', async () => {
    const response = await request(app).get('/api/v1/unknown');

    expect(response.status).toBe(404);
    expect(response.body).toHaveProperty('error');
  });
});
