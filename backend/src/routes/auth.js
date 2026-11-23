import { Router } from 'express';
import { supabaseAdmin, supabaseAuthClient } from '../config/supabase.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Supabase auth errors → messages the app can show as-is. */
function friendly(error) {
  const m = error?.message ?? '';
  if (/already (been )?registered|already exists/i.test(m)) {
    return { status: 409, error: 'An account with this email already exists. Log in instead.' };
  }
  if (/invalid login credentials/i.test(m)) return { status: 401, error: 'Wrong email or password.' };
  if (/email not confirmed/i.test(m)) return { status: 401, error: 'Please confirm your email first.' };
  if (/password/i.test(m) && /(short|least|weak)/i.test(m)) {
    return { status: 400, error: 'Password must be at least 6 characters.' };
  }
  if (/refresh token/i.test(m)) return { status: 401, error: 'Your session expired. Please log in again.' };
  if (/rate limit/i.test(m)) return { status: 429, error: 'Too many attempts. Wait a moment and try again.' };
  return { status: 400, error: m || 'Something went wrong. Try again.' };
}

async function session(data) {
  const { data: prefs } = await supabaseAdmin
    .from('preferences').select('name').eq('user_id', data.user.id).maybeSingle();
  return {
    user: { id: data.user.id, email: data.user.email, name: prefs?.name ?? null },
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
    expires_at: data.session.expires_at,
  };
}

// POST /api/auth/signup  { name, email, password }
router.post('/signup', async (req, res) => {
  const email = String(req.body.email ?? '').trim().toLowerCase();
  const password = String(req.body.password ?? '');
  const name = String(req.body.name ?? '').trim().slice(0, 40);

  if (!EMAIL.test(email)) return res.status(400).json({ error: 'Enter a valid email address.' });
  if (password.length < 6) return res.status(400).json({ error: 'Password must be at least 6 characters.' });

  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true, // prototype: no confirmation email
    user_metadata: { name },
  });
  if (error) {
    const f = friendly(error);
    return res.status(f.status).json({ error: f.error });
  }

  await supabaseAdmin.from('preferences').insert({ user_id: data.user.id, name: name || 'Student' });

  const { data: signIn, error: signInError } = await supabaseAuthClient().auth.signInWithPassword({ email, password });
  if (signInError) {
    const f = friendly(signInError);
    return res.status(f.status).json({ error: f.error });
  }

  res.status(201).json(await session(signIn));
});

// POST /api/auth/login  { email, password }
router.post('/login', async (req, res) => {
  const email = String(req.body.email ?? '').trim().toLowerCase();
  const password = String(req.body.password ?? '');
  if (!email || !password) return res.status(400).json({ error: 'Enter your email and password.' });

  const { data, error } = await supabaseAuthClient().auth.signInWithPassword({ email, password });
  if (error) {
    const f = friendly(error);
    return res.status(f.status).json({ error: f.error });
  }

  res.json(await session(data));
});

// POST /api/auth/refresh  { refresh_token }
router.post('/refresh', async (req, res) => {
  const refresh_token = req.body.refresh_token;
  if (!refresh_token) return res.status(400).json({ error: 'refresh_token is required' });

  const { data, error } = await supabaseAuthClient().auth.refreshSession({ refresh_token });
  if (error || !data.session) {
    const f = friendly(error ?? { message: 'refresh token' });
    return res.status(401).json({ error: f.error });
  }

  res.json(await session(data));
});

// POST /api/auth/logout  — ends this session (its refresh token stops working)
router.post('/logout', requireAuth, async (req, res) => {
  const { error } = await supabaseAdmin.auth.admin.signOut(req.accessToken, 'local');
  if (error) console.warn('Logout:', error.message);
  res.json({ logged_out: true });
});

export default router;
