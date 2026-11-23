import { createClient } from '@supabase/supabase-js';

const { SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_KEY } = process.env;

const PLACEHOLDER = /your-project|your-anon-key|your-service-role-key/;

export const supabaseConfigured = Boolean(
  SUPABASE_URL && SUPABASE_ANON_KEY && SUPABASE_SERVICE_KEY &&
  !PLACEHOLDER.test(`${SUPABASE_URL}${SUPABASE_ANON_KEY}${SUPABASE_SERVICE_KEY}`),
);

if (!supabaseConfigured) {
  console.warn('\n  ⚠  Supabase is not configured. Fill SUPABASE_URL, SUPABASE_ANON_KEY and');
  console.warn('     SUPABASE_SERVICE_KEY in .env (see chrono-backend-guide.md, Step 1).\n');
}

// No session is ever stored on these clients: the server is stateless and
// serves many users, so a stored session would leak between requests.
const serverAuth = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };

const url = supabaseConfigured ? SUPABASE_URL : 'http://localhost:54321';

// Admin client (service role) – bypasses RLS. Used for all table access; every
// query is scoped with .eq('user_id', req.userId).
export const supabaseAdmin = createClient(url, supabaseConfigured ? SUPABASE_SERVICE_KEY : 'missing', {
  auth: serverAuth,
});

/**
 * A fresh anon client for sign-in / refresh. Signing in on the admin client
 * would make its later queries run as that user, so this is kept separate.
 */
export function supabaseAuthClient() {
  return createClient(url, supabaseConfigured ? SUPABASE_ANON_KEY : 'missing', { auth: serverAuth });
}

/**
 * A Supabase client scoped to a user's JWT, so RLS policies apply.
 */
export function supabaseForUser(accessToken) {
  return createClient(url, supabaseConfigured ? SUPABASE_ANON_KEY : 'missing', {
    auth: serverAuth,
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
}
