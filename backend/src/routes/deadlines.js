import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.use(requireAuth);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Normalise a deadline from the client into a DB row (keeps a valid uuid id). */
export function toDeadlineRow(d, userId) {
  const row = {
    user_id: userId,
    title: d.title,
    course: d.course ?? '',
    estimate: d.estimate,
    due: d.due,
    urgent: d.urgent ?? false,
    planned: d.planned ?? 0,
    done: d.done ?? false,
  };
  row.id = d.id && UUID.test(d.id) ? d.id : randomUUID(); // every row needs the same keys in a bulk insert
  return row;
}

// GET /api/deadlines
router.get('/', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('deadlines')
    .select('*')
    .eq('user_id', req.userId)
    .order('created_at');

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// POST /api/deadlines
router.post('/', async (req, res) => {
  const { title, course, estimate, due, urgent, planned, done } = req.body;

  if (!title || estimate == null || !due) {
    return res.status(400).json({ error: 'title, estimate, due are required' });
  }

  const { data, error } = await supabaseAdmin.from('deadlines').insert({
    user_id: req.userId,
    title,
    course: course || '',
    estimate,
    due,
    urgent: urgent ?? false,
    planned: planned ?? 0,
    done: done ?? false,
  }).select().single();

  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json(data);
});

// POST /api/deadlines/replace  — replace every deadline (used by Undo)
router.post('/replace', async (req, res) => {
  const list = req.body?.deadlines;
  if (!Array.isArray(list)) return res.status(400).json({ error: 'deadlines[] is required' });

  const rows = list.map(d => toDeadlineRow(d, req.userId));
  const { error: dErr } = await supabaseAdmin.from('deadlines').delete().eq('user_id', req.userId);
  if (dErr) return res.status(500).json({ error: dErr.message });

  if (rows.length > 0) {
    const { error: iErr } = await supabaseAdmin.from('deadlines').insert(rows);
    if (iErr) return res.status(500).json({ error: iErr.message });
  }

  const { data, error } = await supabaseAdmin
    .from('deadlines').select('*').eq('user_id', req.userId).order('created_at');
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// PUT /api/deadlines/:id
router.put('/:id', async (req, res) => {
  const updates = {};
  for (const key of ['title', 'course', 'estimate', 'due', 'urgent', 'planned', 'done']) {
    if (req.body[key] !== undefined) updates[key] = req.body[key];
  }

  const { data, error } = await supabaseAdmin
    .from('deadlines')
    .update(updates)
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });
  if (!data) return res.status(404).json({ error: 'Deadline not found' });
  res.json(data);
});

// DELETE /api/deadlines/:id
router.delete('/:id', async (req, res) => {
  const { error } = await supabaseAdmin
    .from('deadlines')
    .delete()
    .eq('id', req.params.id)
    .eq('user_id', req.userId);

  if (error) return res.status(500).json({ error: error.message });
  res.json({ deleted: true });
});

// POST /api/deadlines/:id/toggle — toggle done
router.post('/:id/toggle', async (req, res) => {
  const { data: deadline } = await supabaseAdmin
    .from('deadlines')
    .select('done')
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .single();

  if (!deadline) return res.status(404).json({ error: 'Deadline not found' });

  const { data, error } = await supabaseAdmin
    .from('deadlines')
    .update({ done: !deadline.done })
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

export default router;
