// /api/me — whole-account helpers for the app:
//   GET    /api/me             everything the app needs on launch, in one call
//   POST   /api/me/onboarding  save the onboarding result (prefs, courses, starter blocks, deadlines)
//   DELETE /api/me/data        wipe the user's schedule data (demo "reset")

import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { requireAuth } from '../middleware/auth.js';
import { toBlockRow } from './blocks.js';
import { toDeadlineRow } from './deadlines.js';

const router = Router();
router.use(requireAuth);

const PREF_KEYS = ['name', 'focus_window', 'bedtime', 'break_minutes', 'onboarding_complete'];

async function getOrCreatePrefs(userId) {
  const { data } = await supabaseAdmin.from('preferences').select('*').eq('user_id', userId).maybeSingle();
  if (data) return data;
  const { data: created, error } = await supabaseAdmin
    .from('preferences').insert({ user_id: userId }).select().single();
  if (error) throw new Error(error.message);
  return created;
}

async function snapshot(userId, email = null) {
  const [prefs, courses, blocks, deadlines, messages] = await Promise.all([
    getOrCreatePrefs(userId),
    supabaseAdmin.from('courses').select('*').eq('user_id', userId).order('created_at'),
    supabaseAdmin.from('blocks').select('*').eq('user_id', userId).order('day').order('start_min'),
    supabaseAdmin.from('deadlines').select('*').eq('user_id', userId).order('created_at'),
    supabaseAdmin.from('chat_messages').select('*').eq('user_id', userId).order('created_at'),
  ]);
  for (const r of [courses, blocks, deadlines, messages]) {
    if (r.error) throw new Error(r.error.message);
  }
  return {
    user: { id: userId, email },
    preferences: prefs,
    courses: courses.data,
    blocks: blocks.data,
    deadlines: deadlines.data,
    messages: messages.data,
  };
}

async function wipe(userId) {
  // Blocks first: they reference courses.
  for (const table of ['blocks', 'courses', 'deadlines', 'chat_messages']) {
    const { error } = await supabaseAdmin.from(table).delete().eq('user_id', userId);
    if (error) throw new Error(`${table}: ${error.message}`);
  }
}

// GET /api/me
router.get('/', async (req, res) => {
  res.json(await snapshot(req.userId, req.userEmail));
});

// POST /api/me/onboarding
// Body: { preferences, courses: [...], blocks: [...non-lecture blocks], deadlines: [...] }
router.post('/onboarding', async (req, res) => {
  const { preferences = {}, courses = [], blocks = [], deadlines = [] } = req.body ?? {};
  if (!Array.isArray(courses) || !Array.isArray(blocks) || !Array.isArray(deadlines)) {
    return res.status(400).json({ error: 'courses, blocks and deadlines must be arrays' });
  }

  await wipe(req.userId);

  // Courses → lecture blocks for the selected ones
  let savedCourses = [];
  if (courses.length > 0) {
    const { data, error } = await supabaseAdmin.from('courses').insert(courses.map(c => ({
      user_id: req.userId,
      code: c.code || '',
      name: c.name,
      days: c.days,
      start_min: c.start_min,
      end_min: c.end_min,
      room: c.room || '',
      selected: c.selected ?? true,
    }))).select();
    if (error) return res.status(500).json({ error: error.message });
    savedCourses = data;
  }

  const lectureRows = [];
  for (const c of savedCourses.filter(c => c.selected)) {
    for (const d of c.days) {
      // Same shape as flex rows: in a bulk insert, keys missing from a row become NULL, not the default.
      lectureRows.push(toBlockRow({
        day: d,
        title: c.name,
        kind: 'lecture',
        start_min: c.start_min,
        end_min: c.end_min,
        detail: c.room.startsWith('Lab') ? c.room : (c.room ? `Room ${c.room}` : null),
        course_id: c.id,
      }, req.userId));
    }
  }

  const flexRows = blocks.filter(b => b.kind !== 'lecture').map(b => toBlockRow({ ...b, id: null }, req.userId));
  const allBlocks = [...lectureRows, ...flexRows];
  if (allBlocks.length > 0) {
    const { error } = await supabaseAdmin.from('blocks').insert(allBlocks);
    if (error) return res.status(500).json({ error: error.message });
  }

  if (deadlines.length > 0) {
    const { error } = await supabaseAdmin
      .from('deadlines').insert(deadlines.map(d => toDeadlineRow({ ...d, id: null }, req.userId)));
    if (error) return res.status(500).json({ error: error.message });
  }

  await getOrCreatePrefs(req.userId);
  const updates = { onboarding_complete: true, updated_at: new Date().toISOString() };
  for (const k of PREF_KEYS) if (preferences[k] !== undefined) updates[k] = preferences[k];
  updates.onboarding_complete = true;
  const { error: pErr } = await supabaseAdmin.from('preferences').update(updates).eq('user_id', req.userId);
  if (pErr) return res.status(500).json({ error: pErr.message });

  res.json(await snapshot(req.userId, req.userEmail));
});

// DELETE /api/me/data
router.delete('/data', async (req, res) => {
  await wipe(req.userId);
  await getOrCreatePrefs(req.userId);
  await supabaseAdmin
    .from('preferences')
    .update({ onboarding_complete: false, updated_at: new Date().toISOString() })
    .eq('user_id', req.userId);
  res.json({ cleared: true });
});

export default router;
