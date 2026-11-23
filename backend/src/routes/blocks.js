import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.use(requireAuth);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Normalise a block from the client into a DB row (keeps a valid uuid id). */
export function toBlockRow(b, userId) {
  const row = {
    user_id: userId,
    day: b.day,
    title: b.title,
    kind: b.kind,
    start_min: b.start_min,
    end_min: b.end_min,
    detail: b.detail ?? null,
    origin: b.origin ?? null,
    done: b.done ?? false,
    course_id: b.course_id && UUID.test(b.course_id) ? b.course_id : null,
  };
  row.id = b.id && UUID.test(b.id) ? b.id : randomUUID(); // every row needs the same keys in a bulk insert
  return row;
}

// GET /api/blocks  — all blocks for the user (optionally filter by ?day=3)
router.get('/', async (req, res) => {
  let query = supabaseAdmin
    .from('blocks')
    .select('*')
    .eq('user_id', req.userId)
    .order('day')
    .order('start_min');

  if (req.query.day !== undefined) {
    query = query.eq('day', parseInt(req.query.day, 10));
  }

  const { data, error } = await query;
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// POST /api/blocks  — create a new block
router.post('/', async (req, res) => {
  const { day, title, kind, start_min, end_min, detail, origin, done, course_id } = req.body;

  if (title == null || day == null || kind == null || start_min == null || end_min == null) {
    return res.status(400).json({ error: 'day, title, kind, start_min, end_min are required' });
  }

  const { data, error } = await supabaseAdmin.from('blocks').insert({
    user_id: req.userId,
    day, title, kind, start_min, end_min,
    detail: detail || null,
    origin: origin || null,
    done: done ?? false,
    course_id: course_id || null,
  }).select().single();

  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json(data);
});

// POST /api/blocks/replace  — replace every block with the given list
// Used by the app's Undo, which restores a whole earlier snapshot.
router.post('/replace', async (req, res) => {
  const list = req.body?.blocks;
  if (!Array.isArray(list)) return res.status(400).json({ error: 'blocks[] is required' });

  const rows = list.map(b => toBlockRow(b, req.userId));
  const { error: dErr } = await supabaseAdmin.from('blocks').delete().eq('user_id', req.userId);
  if (dErr) return res.status(500).json({ error: dErr.message });

  if (rows.length > 0) {
    const { error: iErr } = await supabaseAdmin.from('blocks').insert(rows);
    if (iErr) return res.status(500).json({ error: iErr.message });
  }

  const { data, error } = await supabaseAdmin
    .from('blocks').select('*').eq('user_id', req.userId).order('day').order('start_min');
  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// PUT /api/blocks/:id  — update a block
router.put('/:id', async (req, res) => {
  const { day, title, kind, start_min, end_min, detail, origin, done } = req.body;

  const { data, error } = await supabaseAdmin
    .from('blocks')
    .update({ day, title, kind, start_min, end_min, detail, origin, done })
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });
  if (!data) return res.status(404).json({ error: 'Block not found' });
  res.json(data);
});

// DELETE /api/blocks/:id
router.delete('/:id', async (req, res) => {
  const { error } = await supabaseAdmin
    .from('blocks')
    .delete()
    .eq('id', req.params.id)
    .eq('user_id', req.userId);

  if (error) return res.status(500).json({ error: error.message });
  res.json({ deleted: true });
});

// POST /api/blocks/:id/done  — toggle done
router.post('/:id/done', async (req, res) => {
  const { data: block } = await supabaseAdmin
    .from('blocks')
    .select('done')
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .single();

  if (!block) return res.status(404).json({ error: 'Block not found' });

  const { data, error } = await supabaseAdmin
    .from('blocks')
    .update({ done: !block.done })
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// POST /api/blocks/:id/push  — push a block by N minutes
router.post('/:id/push', async (req, res) => {
  const minutes = parseInt(req.body.minutes, 10) || 30;

  const { data: block } = await supabaseAdmin
    .from('blocks')
    .select('*')
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .single();

  if (!block) return res.status(404).json({ error: 'Block not found' });

  const { data, error } = await supabaseAdmin
    .from('blocks')
    .update({
      start_min: block.start_min + minutes,
      end_min: block.end_min + minutes,
      origin: 'moved',
    })
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

export default router;
