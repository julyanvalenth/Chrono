// The Express app. Used by server.js (local / any Node host) and by
// api/index.js (Vercel serverless function).
import 'dotenv/config';
import express from 'express';
import cors from 'cors';

import { supabaseConfigured } from './src/config/supabase.js';
import { geminiConfigured, GEMINI_MODELS } from './src/config/gemini.js';
import authRoutes from './src/routes/auth.js';
import blocksRoutes from './src/routes/blocks.js';
import coursesRoutes from './src/routes/courses.js';
import deadlinesRoutes from './src/routes/deadlines.js';
import preferencesRoutes from './src/routes/preferences.js';
import chatRoutes from './src/routes/chat.js';
import meRoutes from './src/routes/me.js';
import scheduleRoutes from './src/routes/schedule.js';

const app = express();

// ---- Middleware ----
app.use(cors());
// Timetable photos arrive as base64. Vercel caps request bodies at 4.5 MB.
app.use(express.json({ limit: '4.5mb' }));
app.use((req, res, next) => { req.body ??= {}; next(); }); // Express 5 leaves it undefined

// ---- Health check (no auth) ----
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    database: supabaseConfigured ? 'configured' : 'missing SUPABASE_* env vars',
    ai: geminiConfigured ? { provider: 'gemini', models: GEMINI_MODELS } : 'missing GEMINI_API_KEY env var',
  });
});

// Everything below needs the database.
app.use('/api', (req, res, next) => {
  if (supabaseConfigured) return next();
  res.status(503).json({ error: 'Database not configured: set SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_KEY' });
});

// ---- Routes ----
app.use('/api/auth', authRoutes);
app.use('/api/me', meRoutes);
app.use('/api/schedule', scheduleRoutes);
app.use('/api/blocks', blocksRoutes);
app.use('/api/courses', coursesRoutes);
app.use('/api/deadlines', deadlinesRoutes);
app.use('/api/preferences', preferencesRoutes);
app.use('/api/chat', chatRoutes);

app.use('/api', (req, res) => res.status(404).json({ error: `No route ${req.method} ${req.originalUrl}` }));

// ---- Error handler (Express 5 forwards async errors here) ----
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err);
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'Invalid JSON body' });
  if (err.type === 'entity.too.large') return res.status(413).json({ error: 'Request is too large' });
  res.status(500).json({ error: err.message || 'Internal server error' });
});

export default app;
