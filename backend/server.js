// Run the API as a normal Node server (local development: npm run dev).
// On Vercel the same app runs as a serverless function instead (api/index.js).
// .env is loaded by app.js (src/config/env.js) before the config modules run.
import app from './app.js';
import { supabaseConfigured } from './src/config/supabase.js';
import { geminiConfigured, GEMINI_MODELS } from './src/config/gemini.js';

const PORT = process.env.PORT || 3000;

// 0.0.0.0 so a phone on the same Wi-Fi (or the Android emulator) can reach it.
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n  🕐 Chrono backend running on http://localhost:${PORT}`);
  console.log(`     Database: ${supabaseConfigured ? 'Supabase ✓' : 'NOT CONFIGURED'}`);
  console.log(`     AI:       ${geminiConfigured ? `Gemini ✓ (${GEMINI_MODELS.join(' → ')})` : 'NOT CONFIGURED'}\n`);
});
