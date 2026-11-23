// Chrono AI Service — replaces the regex-based chrono_engine.dart with Gemini.
//
// Strategy: Send Gemini the full schedule context and ask it to return
// structured JSON with both the response text and proposed changes.
// The server then validates and stores the changes.

import { generateJson } from '../config/gemini.js';
import {
  clock, range, duration, dayName,
  dayBlocks, gaps, findSlot, freeMinutes, h, overlaps,
} from '../utils/time.js';

/** Build a text summary of the user's schedule for Gemini's context. */
function buildContext(blocks, deadlines, prefs, today, now) {
  const lines = [];

  lines.push(`## User Preferences`);
  lines.push(`- Name: ${prefs.name}`);
  lines.push(`- Best focus time: ${prefs.focus_window}`);
  lines.push(`- Bedtime: ${prefs.bedtime}`);
  lines.push(`- Break between blocks: ${prefs.break_minutes} min`);
  lines.push('');

  // Today's schedule
  const todayBlocks = dayBlocks(blocks, today);
  lines.push(`## Week`);
  lines.push(`Day indices this week: ${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((n, i) => `${i}=${n}`).join(', ')}.`);
  lines.push(`Today is day index ${today}. Days before ${today} are in the past.`);
  lines.push('');
  lines.push(`## Today (${dayName(today, today)}, day index ${today})`);
  lines.push(`Current time: ${clock(now)}`);
  lines.push(`Free time today: ${duration(freeMinutes(blocks, today))}`);
  lines.push('');

  if (todayBlocks.length === 0) {
    lines.push('No blocks scheduled today.');
  } else {
    lines.push('| Time | Title | Kind | ID | Done |');
    lines.push('|------|-------|------|----|------|');
    for (const b of todayBlocks) {
      const past = b.end_min <= now ? ' (past)' : b.start_min <= now ? ' (NOW)' : '';
      lines.push(`| ${range(b.start_min, b.end_min)} | ${b.title} | ${b.kind} | ${b.id} | ${b.done}${past} |`);
    }
  }
  lines.push('');

  // Free slots today
  const freeToday = gaps(blocks, today, Math.max(now, h(8)), h(22))
    .filter(g => (g.end - g.start) >= 30);
  if (freeToday.length > 0) {
    lines.push('Free slots today (≥30 min):');
    for (const g of freeToday) {
      lines.push(`- ${range(g.start, g.end)} (${duration(g.end - g.start)})`);
    }
  }
  lines.push('');

  // Tomorrow's schedule
  const tmr = today + 1;
  if (tmr <= 6) {
    const tmrBlocks = dayBlocks(blocks, tmr);
    lines.push(`## Tomorrow (${dayName(tmr, today)}, day index ${tmr})`);
    if (tmrBlocks.length === 0) {
      lines.push('No blocks scheduled tomorrow.');
    } else {
      lines.push('| Time | Title | Kind | ID |');
      lines.push('|------|-------|------|----|');
      for (const b of tmrBlocks) {
        lines.push(`| ${range(b.start_min, b.end_min)} | ${b.title} | ${b.kind} | ${b.id} |`);
      }
    }
    const freeTmr = gaps(blocks, tmr, h(8), h(22)).filter(g => (g.end - g.start) >= 30);
    if (freeTmr.length > 0) {
      lines.push('Free slots tomorrow (≥30 min):');
      for (const g of freeTmr) {
        lines.push(`- ${range(g.start, g.end)} (${duration(g.end - g.start)})`);
      }
    }
    lines.push('');
  }

  // Deadlines
  const openDeadlines = deadlines.filter(d => !d.done);
  if (openDeadlines.length > 0) {
    lines.push('## Open Deadlines');
    lines.push('| Title | Course | Estimate | Planned | Due | Urgent | ID |');
    lines.push('|-------|--------|----------|---------|-----|--------|----|');
    for (const d of openDeadlines) {
      lines.push(`| ${d.title} | ${d.course} | ${duration(d.estimate)} | ${duration(d.planned)} | ${d.due} | ${d.urgent} | ${d.id} |`);
    }
  }

  return lines.join('\n');
}

const SYSTEM_PROMPT = `You are Chrono, an AI scheduling assistant for university students. You help manage their daily schedule by adding, moving, and removing time blocks.

## Rules
1. **Classes (kind: "lecture") are FIXED.** Never move or remove them. Plan everything else around them.
2. **Flexible blocks** (focus, task, personal, breakTime) can be moved or removed.
3. When adding a new block that overlaps a flexible block, propose moving the flexible block to the next available free slot.
4. When you can't find a free slot today, look at tomorrow.
5. Keep responses brief, friendly, and in one or two sentences. Reply in the same language the user writes in (e.g. Indonesian or English).
6. Always use 24-hour time internally (minutes from midnight).
7. The week uses day indices: 0=Monday, 1=Tuesday, 2=Wednesday, 3=Thursday, 4=Friday, 5=Saturday, 6=Sunday.

## What You Can Do
- **Add events**: User says "Meeting at 3pm for 1h" → add a new block.
- **Remove blocks**: "Skip gym today" → remove that block.
- **Move blocks**: "Move essay to my next free slot" → move the block.
- **Clear time**: "I'm sick, clear my afternoon" → move afternoon flex blocks to tomorrow.
- **Day summary**: "How does my day look?" → summarize remaining blocks and free time.
- **Add deadlines**: "Stats quiz due Monday, 3h" → create a deadline and optionally schedule first session.
- **Plan deadline work**: "Plan time for HCI essay" → find a slot for deadline work.

## Response Format
Return a JSON object with this exact structure:
{
  "text": "Your friendly response message to the user.",
  "changes": [
    // Array of changes to propose. Can be empty if just answering a question.
    // Each change is one of:
    
    // ADD a new block:
    {
      "type": "add",
      "block": {
        "title": "Meeting",
        "day": 3,
        "kind": "personal",
        "start_min": 900,
        "end_min": 960,
        "detail": "Added by Chrono"
      }
    },
    
    // MOVE an existing block:
    {
      "type": "move",
      "block_id": "the-existing-block-uuid",
      "title": "Block Title",
      "kind": "task",
      "from": { "day": 3, "start_min": 885, "end_min": 945 },
      "to": { "day": 3, "start_min": 960, "end_min": 1020 }
    },
    
    // REMOVE a block:
    {
      "type": "remove",
      "block_id": "the-existing-block-uuid",
      "title": "Block Title",
      "kind": "task",
      "from": { "day": 3, "start_min": 960, "end_min": 1020 }
    }
  ],
  "new_deadline": null,
  // OR a new deadline object:
  // "new_deadline": {
  //   "title": "Stats quiz prep",
  //   "course": "Statistics",
  //   "estimate": 180,
  //   "due": "Monday",
  //   "urgent": false
  // },
  "deadline_id": null
  // If a change adds study time for an existing deadline, set this to that deadline's ID
  // so the planned time gets updated.
}

IMPORTANT:
- Use ONLY real block IDs from the schedule context when moving/removing.
- For new blocks, do NOT include an "id" field — the server generates it.
- Make sure start_min and end_min don't overlap with fixed lecture blocks.
- When picking free slots, use the free-slot information provided in the context.
- When the user just asks a question (like "how does my day look?"), return an empty changes array.
- Always return valid JSON. No markdown, no code fences.`;

/**
 * Send a user message to Gemini and get back a structured reply.
 *
 * @param {string} message  - The user's chat message
 * @param {Array}  blocks   - All the user's blocks (all days)
 * @param {Array}  deadlines - All the user's deadlines
 * @param {object} prefs    - User preferences { name, focus_window, bedtime, break_minutes }
 * @param {number} today    - Current day index (0-6)
 * @param {number} now      - Current time in minutes from midnight
 * @returns {Promise<object>} - { text, changes, new_deadline, deadline_id }
 */
export async function chat(message, blocks, deadlines, prefs, today, now) {
  const context = buildContext(blocks, deadlines, prefs, today, now);

  const prompt = `${SYSTEM_PROMPT}

---

## Current Schedule Context

${context}

---

## User Message
"${message}"

Respond with the JSON object described above.`;

  try {
    const { text, model } = await generateJson(prompt);

    // Parse the JSON response
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      // If Gemini wraps in code fences, strip them
      const cleaned = text.replace(/```json?\s*/g, '').replace(/```\s*/g, '').trim();
      parsed = JSON.parse(cleaned);
    }

    // Validate the structure
    return {
      text: parsed.text || "I'm not sure how to help with that. Try telling me about a schedule change!",
      changes: Array.isArray(parsed.changes) ? parsed.changes : [],
      new_deadline: parsed.new_deadline || null,
      deadline_id: parsed.deadline_id || null,
      model,
    };
  } catch (err) {
    console.error('Gemini error:', err.message);
    // Fallback response
    return {
      text: "Sorry, I had trouble processing that. Try again — something like \"Meeting at 3pm for 1h\" or \"How does my day look?\"",
      changes: [],
      new_deadline: null,
      deadline_id: null,
      error: true,
    };
  }
}

const KINDS = new Set(['lecture', 'focus', 'task', 'personal', 'breakTime']);

function validSlot(day, start, end) {
  return Number.isInteger(day) && day >= 0 && day <= 6 &&
    Number.isInteger(start) && Number.isInteger(end) &&
    start >= 0 && end <= 24 * 60 && start < end;
}

function hitsLecture(blocks, day, start, end, ignoreId = null) {
  return blocks.some(b => b.kind === 'lecture' && b.id !== ignoreId && b.day === day &&
    overlaps(b.start_min, b.end_min, start, end));
}

/**
 * Validate proposed changes against the current blocks.
 * Drops anything invalid (unknown IDs, touching lectures, bad times, clashing
 * with a class) and fills title/kind/from from the real block so the client
 * never shows data the model made up.
 */
export function validateChanges(changes, blocks) {
  const blockMap = new Map(blocks.map(b => [b.id, b]));
  const valid = [];
  const touched = new Set();

  for (const c of changes ?? []) {
    if (c?.type === 'add') {
      const b = c.block ?? {};
      const day = Number(b.day), start = Number(b.start_min), end = Number(b.end_min);
      if (!b.title || !validSlot(day, start, end)) continue;
      if (hitsLecture(blocks, day, start, end)) continue;
      const kind = KINDS.has(b.kind) && b.kind !== 'lecture' ? b.kind : 'personal';
      valid.push({
        type: 'add',
        block: { title: String(b.title), day, kind, start_min: start, end_min: end, detail: b.detail || 'Added by Chrono' },
      });
    } else if (c?.type === 'move') {
      const target = blockMap.get(c.block_id);
      if (!target || target.kind === 'lecture' || touched.has(target.id)) continue;
      const day = Number(c.to?.day ?? target.day), start = Number(c.to?.start_min), end = Number(c.to?.end_min);
      if (!validSlot(day, start, end) || hitsLecture(blocks, day, start, end)) continue;
      touched.add(target.id);
      valid.push({
        type: 'move',
        block_id: target.id,
        title: target.title,
        kind: target.kind,
        from: { day: target.day, start_min: target.start_min, end_min: target.end_min },
        to: { day, start_min: start, end_min: end },
      });
    } else if (c?.type === 'remove') {
      const target = blockMap.get(c.block_id);
      if (!target || target.kind === 'lecture' || touched.has(target.id)) continue;
      touched.add(target.id);
      valid.push({
        type: 'remove',
        block_id: target.id,
        title: target.title,
        kind: target.kind,
        from: { day: target.day, start_min: target.start_min, end_min: target.end_min },
      });
    }
  }

  return valid;
}
