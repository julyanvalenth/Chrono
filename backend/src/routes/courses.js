import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();
router.use(requireAuth);

// GET /api/courses
router.get('/', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('courses')
    .select('*')
    .eq('user_id', req.userId)
    .order('created_at');

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// POST /api/courses  — create a course
router.post('/', async (req, res) => {
  const { code, name, days, start_min, end_min, room, selected } = req.body;

  if (!name || !days || start_min == null || end_min == null) {
    return res.status(400).json({ error: 'name, days, start_min, end_min are required' });
  }

  const { data, error } = await supabaseAdmin.from('courses').insert({
    user_id: req.userId,
    code: code || '',
    name,
    days,
    start_min,
    end_min,
    room: room || '',
    selected: selected ?? true,
  }).select().single();

  if (error) return res.status(500).json({ error: error.message });
  res.status(201).json(data);
});

// PUT /api/courses/:id
router.put('/:id', async (req, res) => {
  const updates = {};
  for (const key of ['code', 'name', 'days', 'start_min', 'end_min', 'room', 'selected']) {
    if (req.body[key] !== undefined) updates[key] = req.body[key];
  }

  const { data, error } = await supabaseAdmin
    .from('courses')
    .update(updates)
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });
  if (!data) return res.status(404).json({ error: 'Course not found' });
  res.json(data);
});

// DELETE /api/courses/:id
router.delete('/:id', async (req, res) => {
  const { error } = await supabaseAdmin
    .from('courses')
    .delete()
    .eq('id', req.params.id)
    .eq('user_id', req.userId);

  if (error) return res.status(500).json({ error: error.message });
  res.json({ deleted: true });
});

// POST /api/courses/:id/toggle — toggle selected
router.post('/:id/toggle', async (req, res) => {
  const { data: course } = await supabaseAdmin
    .from('courses')
    .select('selected')
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .single();

  if (!course) return res.status(404).json({ error: 'Course not found' });

  const { data, error } = await supabaseAdmin
    .from('courses')
    .update({ selected: !course.selected })
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .select()
    .single();

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// POST /api/courses/generate-blocks — regenerate lecture blocks from selected courses
router.post('/generate-blocks', async (req, res) => {
  // Fetch selected courses
  const { data: courses, error: cErr } = await supabaseAdmin
    .from('courses')
    .select('*')
    .eq('user_id', req.userId)
    .eq('selected', true);

  if (cErr) return res.status(500).json({ error: cErr.message });

  // Delete existing lecture blocks
  await supabaseAdmin
    .from('blocks')
    .delete()
    .eq('user_id', req.userId)
    .eq('kind', 'lecture');

  // Generate new lecture blocks
  const lectureBlocks = [];
  for (const c of courses) {
    for (const d of c.days) {
      lectureBlocks.push({
        user_id: req.userId,
        day: d,
        title: c.name,
        kind: 'lecture',
        start_min: c.start_min,
        end_min: c.end_min,
        detail: c.room.startsWith('Lab') ? c.room : (c.room ? `Room ${c.room}` : null),
        course_id: c.id,
      });
    }
  }

  if (lectureBlocks.length > 0) {
    const { error: iErr } = await supabaseAdmin.from('blocks').insert(lectureBlocks);
    if (iErr) return res.status(500).json({ error: iErr.message });
  }

  // Return all blocks
  const { data: allBlocks } = await supabaseAdmin
    .from('blocks')
    .select('*')
    .eq('user_id', req.userId)
    .order('day')
    .order('start_min');

  res.json({ generated: lectureBlocks.length, blocks: allBlocks });
});

export default router;
