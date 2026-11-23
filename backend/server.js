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
const PORT = process.env.PORT || 3000;

// ---- Middleware ----
app.use(cors());
app.use(express.json({ limit: '10mb' })); // timetable photos arrive as base64
app.use((req, res, next) => { req.body ??= {}; next(); }); // Express 5 leaves it undefined

// ---- Health check (no auth) ----
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    database: supabaseConfigured ? 'configured' : 'missing SUPABASE_* in .env',
    ai: geminiConfigured ? { provider: 'gemini', models: GEMINI_MODELS } : 'missing GEMINI_API_KEY in .env',
  });
});

// Everything below needs the database.
app.use('/api', (req, res, next) => {
  if (supabaseConfigured) return next();
  res.status(503).json({ error: 'Database not configured: fill SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_KEY in .env' });
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
  res.status(500).json({ error: err.message || 'Internal server error' });
});

// ---- Start ----
// 0.0.0.0 so a phone on the same Wi-Fi (or the Android emulator) can reach it.
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n  🕐 Chrono backend running on http://localhost:${PORT}`);
  console.log(`     Database: ${supabaseConfigured ? 'Supabase ✓' : 'NOT CONFIGURED'}`);
  console.log(`     AI:       ${geminiConfigured ? `Gemini ✓ (${GEMINI_MODELS.join(' → ')})` : 'NOT CONFIGURED'}\n`);
});
