import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { requireAuth } from '../middleware/auth.js';
import { chat, validateChanges, reconcileDates } from '../services/chrono-ai.js';
import { clientToday, weekdayIndex, normaliseDue, dueWithinADay } from '../utils/dates.js';
import { plannedFromBlocks, sameTitle } from '../utils/deadlines.js';

const router = Router();
router.use(requireAuth);

function intParam(value, min, max) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isInteger(number) && number >= min && number <= max ? number : null;
}

function linkedDeadlineId(reply, deadlines) {
  if (reply.deadlineId && deadlines.some(deadline => deadline.id === reply.deadlineId)) return reply.deadlineId;
  for (const change of reply.changes) {
    if (change.type !== 'add') continue;
    const linked = deadlines.find(deadline => !deadline.done && sameTitle(deadline.title, change.block.title));
    if (linked) return linked.id;
  }
  return null;
}

router.get('/', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('chat_messages')
    .select('*')
    .eq('user_id', req.userId)
    .order('created_at');

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

router.post('/', async (req, res) => {
  const { message } = req.body;
  if (!message?.trim()) {
    return res.status(400).json({ error: 'message is required' });
  }

  const { today, now } = clientToday(req.query);
  const todayIdx = weekdayIndex(today);
  const viewDay = intParam(req.query.view_day, 0, 6);

  const { data: userMsg, error: umErr } = await supabaseAdmin
    .from('chat_messages')
    .insert({
      user_id: req.userId,
      type: 'text',
      from_user: true,
      content: message.trim(),
    })
    .select()
    .single();

  if (umErr) return res.status(500).json({ error: umErr.message });

  const [blocksRes, deadlinesRes, prefsRes] = await Promise.all([
    supabaseAdmin.from('blocks').select('*').eq('user_id', req.userId),
    supabaseAdmin.from('deadlines').select('*').eq('user_id', req.userId),
    supabaseAdmin.from('preferences').select('*').eq('user_id', req.userId).single(),
  ]);

  const blocks = blocksRes.data || [];
  const deadlines = deadlinesRes.data || [];
  const prefs = prefsRes.data || { name: 'Student', focus_window: 'morning', bedtime: '23:00', break_minutes: 15 };

  const reply = await chat(message.trim(), blocks, deadlines, prefs, { today, now, viewDay });
  reply.changes = validateChanges(reconcileDates(reply.changes, today), blocks, { todayIdx, now });

  const { data: aiMsg } = await supabaseAdmin
    .from('chat_messages')
    .insert({
      user_id: req.userId,
      type: 'text',
      from_user: false,
      content: reply.text,
    })
    .select()
    .single();

  let newDeadlineId = linkedDeadlineId(reply, deadlines);
  let newDeadline = null;
  if (reply.deadline?.title) {
    const title = String(reply.deadline.title).trim();
    const due = normaliseDue(reply.deadline.due, today);
    const estimate = Number.isFinite(+reply.deadline.estimate) && +reply.deadline.estimate > 0
      ? Math.round(+reply.deadline.estimate)
      : 120;
    const fields = {
      estimate,
      due,
      urgent: dueWithinADay(due, today) ?? reply.deadline.urgent ?? false,
    };
    const existing = deadlines.find(deadline => !deadline.done && sameTitle(deadline.title, title));
    if (existing) {
      const updates = {};
      if (Number.isFinite(+reply.deadline.estimate) && +reply.deadline.estimate > 0) updates.estimate = estimate;
      if (String(reply.deadline.due ?? '').trim() && String(reply.deadline.due).trim().toUpperCase() !== 'TBD') {
        updates.due = due;
        updates.urgent = fields.urgent;
      }
      if (Object.keys(updates).length === 0) {
        newDeadline = existing;
      } else {
        const { data: updated } = await supabaseAdmin
          .from('deadlines')
          .update(updates)
          .eq('id', existing.id)
          .eq('user_id', req.userId)
          .select()
          .single();
        newDeadline = updated ?? { ...existing, ...updates };
      }
    } else {
      const { data: created } = await supabaseAdmin
        .from('deadlines')
        .insert({
          user_id: req.userId,
          title,
          course: reply.deadline.course || 'Added in chat',
          planned: 0,
          ...fields,
        })
        .select()
        .single();
      newDeadline = created ?? null;
    }
    if (newDeadline) newDeadlineId = newDeadline.id;
  }

  let proposalMsg = null;
  if (reply.changes.length > 0) {
    const { data: pm } = await supabaseAdmin
      .from('chat_messages')
      .insert({
        user_id: req.userId,
        type: 'proposal',
        from_user: false,
        changes: reply.changes,
        status: 'pending',
        deadline_id: newDeadlineId,
      })
      .select()
      .single();
    proposalMsg = pm;
  }

  res.json({
    user_message: userMsg,
    ai_message: aiMsg,
    ai_ok: reply.ok !== false,
    model: reply.model ?? null,
    proposal: proposalMsg ? { ...proposalMsg, deadlineId: proposalMsg.deadline_id } : null,
    deadline: newDeadline,
    new_deadline: newDeadline,
  });
});

router.post('/:id/apply', async (req, res) => {
  const { data: proposal, error: pErr } = await supabaseAdmin
    .from('chat_messages')
    .select('*')
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .eq('type', 'proposal')
    .single();

  if (pErr || !proposal) {
    return res.status(404).json({ error: 'Proposal not found' });
  }
  if (proposal.status !== 'pending') {
    return res.status(400).json({ error: `Proposal already ${proposal.status}` });
  }

  const changes = proposal.changes || [];
  const addedIds = [];
  const touchedIds = [];

  for (const change of changes) {
    if (change.type === 'add') {
      const block = change.block;
      const { data: created } = await supabaseAdmin.from('blocks').insert({
        user_id: req.userId,
        day: block.day,
        title: block.title,
        kind: block.kind || 'personal',
        start_min: block.start_min,
        end_min: block.end_min,
        detail: block.detail || 'Added by Chrono',
        origin: 'added',
      }).select().single();
      if (created) {
        addedIds.push(created.id);
        touchedIds.push(created.id);
      }
    } else if (change.type === 'move') {
      await supabaseAdmin
        .from('blocks')
        .update({
          day: change.to.day,
          start_min: change.to.start_min,
          end_min: change.to.end_min,
          origin: 'moved',
        })
        .eq('id', change.block_id)
        .eq('user_id', req.userId);
      touchedIds.push(change.block_id);
    } else if (change.type === 'remove') {
      await supabaseAdmin
        .from('blocks')
        .delete()
        .eq('id', change.block_id)
        .eq('user_id', req.userId);
    }
  }

  await supabaseAdmin
    .from('chat_messages')
    .update({ status: 'applied' })
    .eq('id', req.params.id);

  let originQuery = supabaseAdmin
    .from('blocks')
    .update({ origin: null })
    .eq('user_id', req.userId)
    .not('origin', 'is', null);
  if (touchedIds.length > 0) originQuery = originQuery.not('id', 'in', `(${touchedIds.join(',')})`);
  await originQuery;

  const [{ data: allBlocks }, { data: deadlineRows }] = await Promise.all([
    supabaseAdmin
      .from('blocks')
      .select('*')
      .eq('user_id', req.userId)
      .order('day')
      .order('start_min'),
    supabaseAdmin
      .from('deadlines')
      .select('*')
      .eq('user_id', req.userId)
      .order('created_at'),
  ]);

  const allDeadlines = [];
  for (const deadline of deadlineRows ?? []) {
    const planned = plannedFromBlocks(deadline, allBlocks ?? []);
    if (planned !== deadline.planned) {
      await supabaseAdmin.from('deadlines').update({ planned }).eq('id', deadline.id).eq('user_id', req.userId);
    }
    allDeadlines.push({ ...deadline, planned });
  }

  res.json({ applied: true, changes_count: changes.length, blocks: allBlocks, deadlines: allDeadlines, added_ids: addedIds });
});

router.post('/:id/dismiss', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('chat_messages')
    .update({ status: 'dismissed' })
    .eq('id', req.params.id)
    .eq('user_id', req.userId)
    .eq('type', 'proposal')
    .eq('status', 'pending')
    .select()
    .single();

  if (error || !data) {
    return res.status(404).json({ error: 'Proposal not found or already resolved' });
  }
  res.json({ dismissed: true });
});

router.delete('/', async (req, res) => {
  const { error } = await supabaseAdmin
    .from('chat_messages')
    .delete()
    .eq('user_id', req.userId);

  if (error) return res.status(500).json({ error: error.message });
  res.json({ cleared: true });
});

export default router;
