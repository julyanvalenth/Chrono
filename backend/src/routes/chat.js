import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { requireAuth } from '../middleware/auth.js';
import { chat, validateChanges } from '../services/chrono-ai.js';

const router = Router();
router.use(requireAuth);

/**
 * Determine "today" and "now" from the user's timezone.
 * Client can pass ?tz=Asia/Jakarta (or tz offset), otherwise UTC.
 */
function todayAndNow(query) {
  const tz = query.tz || 'UTC';
  let d;
  try {
    // Parse in user's timezone
    const str = new Date().toLocaleString('en-US', { timeZone: tz });
    d = new Date(str);
  } catch {
    d = new Date();
  }
  // JS getDay() returns 0=Sun, we need 0=Mon
  const jsDay = d.getDay();
  const today = jsDay === 0 ? 6 : jsDay - 1;
  const now = d.getHours() * 60 + d.getMinutes();
  return { today, now };
}

// GET /api/chat  — get message history
router.get('/', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('chat_messages')
    .select('*')
    .eq('user_id', req.userId)
    .order('created_at');

  if (error) return res.status(500).json({ error: error.message });
  res.json(data);
});

// POST /api/chat  — send a message, get AI response
router.post('/', async (req, res) => {
  const { message } = req.body;
  if (!message?.trim()) {
    return res.status(400).json({ error: 'message is required' });
  }

  const { today, now } = todayAndNow(req.query);

  // Save user message
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

  // Fetch user's current data
  const [blocksRes, deadlinesRes, prefsRes] = await Promise.all([
    supabaseAdmin.from('blocks').select('*').eq('user_id', req.userId),
    supabaseAdmin.from('deadlines').select('*').eq('user_id', req.userId),
    supabaseAdmin.from('preferences').select('*').eq('user_id', req.userId).single(),
  ]);

  const blocks = blocksRes.data || [];
  const deadlines = deadlinesRes.data || [];
  const prefs = prefsRes.data || { name: 'Student', focus_window: 'morning', bedtime: '23:00', break_minutes: 15 };

  // Call Gemini
  const reply = await chat(message.trim(), blocks, deadlines, prefs, today, now);

  // Validate changes
  reply.changes = validateChanges(reply.changes, blocks);

  // Save AI text response
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

  // If there are new deadlines, create them
  let newDeadlineId = reply.deadlineId;
  if (reply.deadline) {
    const { data: dl } = await supabaseAdmin
      .from('deadlines')
      .insert({
        user_id: req.userId,
        title: reply.deadline.title,
        course: reply.deadline.course || 'Added in chat',
        estimate: reply.deadline.estimate || 120,
        due: reply.deadline.due || 'TBD',
        urgent: reply.deadline.urgent ?? false,
        planned: 0,
      })
      .select()
      .single();

    if (dl) newDeadlineId = dl.id;
  }

  // If there are proposed changes, save as a proposal message
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

  const newDeadline = reply.deadline ? { id: newDeadlineId, ...reply.deadline } : null;

  res.json({
    user_message: userMsg,
    ai_message: aiMsg,
    proposal: proposalMsg ? { ...proposalMsg, deadlineId: proposalMsg.deadline_id } : null,
    deadline: newDeadline,
    new_deadline: newDeadline,
  });
});

// POST /api/chat/:id/apply  — apply proposed changes
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
  let addedMinutes = 0;
  const addedIds = [];
  const touchedIds = [];

  // Apply each change
  for (const c of changes) {
    if (c.type === 'add') {
      const block = c.block;
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
      addedMinutes += (block.end_min - block.start_min);
    } else if (c.type === 'move') {
      await supabaseAdmin
        .from('blocks')
        .update({
          day: c.to.day,
          start_min: c.to.start_min,
          end_min: c.to.end_min,
          origin: 'moved',
        })
        .eq('id', c.block_id)
        .eq('user_id', req.userId);
      touchedIds.push(c.block_id);
    } else if (c.type === 'remove') {
      await supabaseAdmin
        .from('blocks')
        .delete()
        .eq('id', c.block_id)
        .eq('user_id', req.userId);
    }
  }

  // Update proposal status
  await supabaseAdmin
    .from('chat_messages')
    .update({ status: 'applied' })
    .eq('id', req.params.id);

  // Update deadline planned time if applicable
  if (proposal.deadline_id && addedMinutes > 0) {
    const { data: dl } = await supabaseAdmin
      .from('deadlines')
      .select('planned')
      .eq('id', proposal.deadline_id)
      .eq('user_id', req.userId)
      .single();

    if (dl) {
      await supabaseAdmin
        .from('deadlines')
        .update({ planned: dl.planned + addedMinutes })
        .eq('id', proposal.deadline_id);
    }
  }

  // Clear origin flags on other blocks (like the app does)
  let originQuery = supabaseAdmin
    .from('blocks')
    .update({ origin: null })
    .eq('user_id', req.userId)
    .not('origin', 'is', null);
  if (touchedIds.length > 0) originQuery = originQuery.not('id', 'in', `(${touchedIds.join(',')})`);
  await originQuery;

  // Return updated blocks and deadlines
  const [{ data: allBlocks }, { data: allDeadlines }] = await Promise.all([
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

  res.json({ applied: true, changes_count: changes.length, blocks: allBlocks, deadlines: allDeadlines, added_ids: addedIds });
});

// POST /api/chat/:id/dismiss  — dismiss proposed changes
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

// DELETE /api/chat  — clear chat history
router.delete('/', async (req, res) => {
  const { error } = await supabaseAdmin
    .from('chat_messages')
    .delete()
    .eq('user_id', req.userId);

  if (error) return res.status(500).json({ error: error.message });
  res.json({ cleared: true });
});

export default router;
