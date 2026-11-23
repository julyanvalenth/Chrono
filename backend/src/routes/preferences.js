import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.use(requireAuth);

// GET /api/preferences
router.get('/', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('preferences')
    .select('*')
    .eq('user_id', req.userId)
    .single();

  if (error || !data) {
    // Create default preferences if they don't exist
    const { data: created, error: cErr } = await supabaseAdmin
      .from('preferences')
      .insert({ user_id: req.userId })
      .select()
      .single();

    if (cErr) return res.status(500).json({ error: cErr.message });
    return res.json(created);
  }

  res.json(data);
});

// PUT /api/preferences
router.put('/', async (req, res) => {
  const updates = {};
  for (const key of ['name', 'focus_window', 'bedtime', 'break_minutes', 'onboarding_complete']) {
    if (req.body[key] !== undefined) updates[key] = req.body[key];
  }
  updates.updated_at = new Date().toISOString();

  const { data, error } = await supabaseAdmin
    .from('preferences')
    .update(updates)
    .eq('user_id', req.userId)
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

export default router;
