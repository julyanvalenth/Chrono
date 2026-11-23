import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { requireAuth } from '../middleware/auth.js';
import { chat, validateChanges } from '../services/chrono-ai.js';

const router = Router();
router.use(requireAuth);

/**
 * Determine "today" (0=Mon … 6=Sun) and "now" (minutes from midnight).
 * - ?day=3&now=640 — use the client's clock (the app's demo clock does this)
 * - ?tz=Asia/Jakarta — compute from the server clock in that timezone
 * - otherwise UTC
 */
function todayAndNow(query) {
  const qDay = Number.parseInt(query.day, 10);
  const qNow = Number.parseInt(query.now, 10);
  if (qDay >= 0 && qDay <= 6 && qNow >= 0 && qNow < 24 * 60) {
    return { today: qDay, now: qNow };
  }

  const tz = query.tz || 'UTC';
  let d;
  try {
    d = new Date(new Date().toLocaleString('en-US', { timeZone: tz }));
  } catch {
    d = new Date();
  }
  const jsDay = d.getDay(); // 0=Sun
  return { today: jsDay === 0 ? 6 : jsDay - 1, now: d.getHours() * 60 + d.getMinutes() };
}

function fail(res, error, status = 500) {
  return res.status(status).json({ error: error?.message ?? String(error) });
}

// GET /api/chat  — message history
router.get('/', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('chat_messages')
    .select('*')
    .eq('user_id', req.userId)
    .order('created_at');

  if (error) return fail(res, error);
  res.json(data);
});

// POST /api/chat  — send a message, get the AI reply (+ proposal)
router.post('/', async (req, res) => {
  const message = req.body?.message?.trim();
  if (!message) return res.status(400).json({ error: 'message is required' });
  if (message.length > 1000) return res.status(400).json({ error: 'message is too long' });

  const { today, now } = todayAndNow(req.query);

  const { data: userMsg, error: umErr } = await supabaseAdmin
    .from('chat_messages')
    .insert({ user_id: req.userId, type: 'text', from_user: true, content: message })
    .select()
    .single();
  if (umErr) return fail(res, umErr);

  const [blocksRes, deadlinesRes, prefsRes] = await Promise.all([
    supabaseAdmin.from('blocks').select('*').eq('user_id', req.userId),
    supabaseAdmin.from('deadlines').select('*').eq('user_id', req.userId),
    supabaseAdmin.from('preferences').select('*').eq('user_id', req.userId).maybeSingle(),
  ]);

  const blocks = blocksRes.data || [];
  const deadlines = deadlinesRes.data || [];
  const prefs = prefsRes.data || { name: 'Student', focus_window: 'morning', bedtime: '23:00', break_minutes: 15 };

  const reply = await chat(message, blocks, deadlines, prefs, today, now);
  reply.changes = validateChanges(reply.changes, blocks);

  const { data: aiMsg, error: aiErr } = await supabaseAdmin
    .from('chat_messages')
    .insert({ user_id: req.userId, type: 'text', from_user: false, content: reply.text })
    .select()
    .single();
  if (aiErr) return fail(res, aiErr);

  // Existing deadline this plan is for (only if the id is real)
  let deadlineId = deadlines.some(d => d.id === reply.deadline_id) ? reply.deadline_id : null;

  let newDeadline = null;
  if (reply.new_deadline?.title) {
    const nd = reply.new_deadline;
    const { data: dl, error: dlErr } = await supabaseAdmin
      .from('deadlines')
      .insert({
        user_id: req.userId,
        title: String(nd.title),
        course: nd.course || 'Added in chat',
        estimate: Number.parseInt(nd.estimate, 10) || 120,
        due: nd.due || 'TBD',
        urgent: Boolean(nd.urgent),
        planned: 0,
      })
      .select()
      .single();
    if (dlErr) return fail(res, dlErr);
    newDeadline = dl;
    deadlineId = dl.id;
  }

  let proposalMsg = null;
  if (reply.changes.length > 0) {
    const { data: pm, error: pmErr } = await supabaseAdmin
      .from('chat_messages')
      .insert({
        user_id: req.userId,
        type: 'proposal',
        from_user: false,
        changes: reply.changes,
        status: 'pending',
        deadline_id: deadlineId,
      })
      .select()
      .single();
    if (pmErr) return fail(res, pmErr);
    proposalMsg = pm;
  }

  res.json({
    user_message: userMsg,
    ai_message: aiMsg,
    proposal: proposalMsg,
    new_deadline: newDeadline,
    ai_ok: !reply.error,
    model: reply.model ?? null,
  });
});

// POST /api/chat/:id/apply  — apply a proposal's changes
router.post('/:id/apply', async (req, res) => {
  const { data: proposal, error: pErr } = await supabaseAdmin
    .from('chat_messages')
    .select('*')
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .eq('type', 'proposal')
    .maybeSingle();

  if (pErr || !proposal) return res.status(404).json({ error: 'Proposal not found' });
  if (proposal.status !== 'pending') {
    return res.status(400).json({ error: `Proposal already ${proposal.status}` });
  }

  // Claim the proposal first so a double tap can't apply it twice.
  const { data: claimed } = await supabaseAdmin
    .from('chat_messages')
    .update({ status: 'applied' })
    .eq('id', proposal.id)
    .eq('status', 'pending')
    .select('id');
  if (!claimed?.length) return res.status(400).json({ error: 'Proposal already resolved' });

  // Like the app: only blocks touched by this proposal keep an origin badge.
  await supabaseAdmin
    .from('blocks')
    .update({ origin: null })
    .eq('user_id', req.userId)
    .not('origin', 'is', null);

  const changes = proposal.changes || [];
  const addedIds = [];
  let addedMinutes = 0;

  for (const c of changes) {
    if (c.type === 'add') {
      const b = c.block;
      const { data, error } = await supabaseAdmin
        .from('blocks')
        .insert({
          user_id: req.userId,
          day: b.day,
          title: b.title,
          kind: b.kind || 'personal',
          start_min: b.start_min,
          end_min: b.end_min,
          detail: b.detail || 'Added by Chrono',
          origin: 'added',
        })
        .select('id')
        .single();
      if (error) return fail(res, error);
      addedIds.push(data.id);
      addedMinutes += b.end_min - b.start_min;
    } else if (c.type === 'move') {
      const { error } = await supabaseAdmin
        .from('blocks')
        .update({ day: c.to.day, start_min: c.to.start_min, end_min: c.to.end_min, origin: 'moved' })
        .eq('id', c.block_id)
        .eq('user_id', req.userId);
      if (error) return fail(res, error);
    } else if (c.type === 'remove') {
      const { error } = await supabaseAdmin
        .from('blocks')
        .delete()
        .eq('id', c.block_id)
        .eq('user_id', req.userId);
      if (error) return fail(res, error);
    }
  }

  if (proposal.deadline_id && addedMinutes > 0) {
    const { data: dl } = await supabaseAdmin
      .from('deadlines')
      .select('planned')
      .eq('id', proposal.deadline_id)
      .eq('user_id', req.userId)
      .maybeSingle();
    if (dl) {
      await supabaseAdmin
        .from('deadlines')
        .update({ planned: dl.planned + addedMinutes })
        .eq('id', proposal.deadline_id)
        .eq('user_id', req.userId);
    }
  }

  const [allBlocks, allDeadlines] = await Promise.all([
    supabaseAdmin.from('blocks').select('*').eq('user_id', req.userId).order('day').order('start_min'),
    supabaseAdmin.from('deadlines').select('*').eq('user_id', req.userId).order('created_at'),
  ]);

  res.json({
    applied: true,
    changes_count: changes.length,
    added_ids: addedIds,
    blocks: allBlocks.data,
    deadlines: allDeadlines.data,
  });
});

// POST /api/chat/:id/dismiss  — dismiss a proposal
router.post('/:id/dismiss', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('chat_messages')
    .update({ status: 'dismissed' })
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .eq('type', 'proposal')
    .eq('status', 'pending')
    .select();

  if (error || !data?.length) {
    return res.status(404).json({ error: 'Proposal not found or already resolved' });
  }
  res.json({ dismissed: true });
});

// DELETE /api/chat  — clear history
router.delete('/', async (req, res) => {
  const { error } = await supabaseAdmin.from('chat_messages').delete().eq('user_id', req.userId);
  if (error) return fail(res, error);
  res.json({ cleared: true });
});

export default router;
