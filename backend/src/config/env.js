// Load backend/.env before any config module reads process.env. Import this
// first. The path is resolved from this file, so it works no matter which folder
// the server is started from. On Vercel there is no .env file; the project's
// environment variables are used instead (dotenv never overrides them).
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

dotenv.config({ path: fileURLToPath(new URL('../../.env', import.meta.url)), quiet: true });
