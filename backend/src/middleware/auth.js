import { supabaseAdmin } from '../config/supabase.js';

/**
 * Express middleware – verifies the Supabase JWT from the Authorization header.
 * On success, sets req.userId and req.accessToken.
 */
export async function requireAuth(req, res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid Authorization header' });
  }

  const token = header.slice(7);

  const { data, error } = await supabaseAdmin.auth.getUser(token);
  const user = data?.user;
  if (error || !user) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }

  req.userId = user.id;
  req.userEmail = user.email;
  req.accessToken = token;
  next();
}
