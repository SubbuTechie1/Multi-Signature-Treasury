import express, { Express, Request, Response } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';
import dotenv from 'dotenv';
import { treasuryRouter } from './routes/treasury';
import { proposalRouter } from './routes/proposal';
import { policyRouter } from './routes/policy';
import { emergencyRouter } from './routes/emergency';
import { logger } from './utils/logger';
import { errorHandler } from './middleware/errorHandler';

// Load environment variables
dotenv.config();

const app: Express = express();
const PORT = process.env.PORT || 3000;

// ==================== Middleware ====================

// Security
app.use(helmet());

// CORS
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  credentials: true,
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP, please try again later.',
});
app.use('/api/', limiter);

// Body parsing
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Logging
if (process.env.NODE_ENV !== 'test') {
  app.use(morgan('combined', { stream: { write: (message) => logger.info(message.trim()) } }));
}

// ==================== Routes ====================

app.get('/', (_req: Request, res: Response) => {
  res.json({
    name: 'Multi-Signature Treasury API',
    version: '1.0.0',
    status: 'running',
    endpoints: {
      treasury: '/api/v1/treasury',
      proposal: '/api/v1/proposal',
      policy: '/api/v1/policy',
      emergency: '/api/v1/emergency',
    },
  });
});

app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// API routes
app.use('/api/v1/treasury', treasuryRouter);
app.use('/api/v1/proposal', proposalRouter);
app.use('/api/v1/policy', policyRouter);
app.use('/api/v1/emergency', emergencyRouter);

// ==================== Error Handling ====================

// 404 handler
app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: 'Not Found', message: 'The requested resource does not exist' });
});

// Global error handler
app.use(errorHandler);

// ==================== Server ====================

if (process.env.NODE_ENV !== 'test') {
  app.listen(PORT, () => {
    logger.info(`🚀 Server running on port ${PORT}`);
    logger.info(`📝 Environment: ${process.env.NODE_ENV || 'development'}`);
    logger.info(`🔗 Network: ${process.env.SUI_NETWORK || 'testnet'}`);
  });
}

export default app;
