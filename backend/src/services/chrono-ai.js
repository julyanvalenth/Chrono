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
  // The week repeats, so after Sunday (6) comes Monday (0).
  const tmr = (today + 1) % 7;
  {
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
5. Keep responses brief, friendly, and in one or two sentences.
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
        "day": 3,
        "title": "Meeting",
        "kind": "personal",
        "start": 900,
        "end": 960,
        "detail": "Added by Chrono"
      }
    },
    
    // MOVE an existing block:
    {
      "type": "move",
      "blockId": "the-existing-block-uuid",
      "title": "Block Title",
      "kind": "task",
      "from": { "day": 3, "start": 885, "end": 945 },
      "to": { "day": 3, "start": 960, "end": 1020 }
    },
    
    // REMOVE a block:
    {
      "type": "remove",
      "blockId": "the-existing-block-uuid",
      "title": "Block Title",
      "kind": "task",
      "from": { "day": 3, "start": 960, "end": 1020 }
    }
  ],
  "deadline": null,
  // OR a new deadline object:
  // "deadline": {
  //   "title": "Stats quiz prep",
  //   "course": "Statistics",
  //   "estimate": 180,
  //   "due": "Monday",
  //   "urgent": false
  // },
  "deadlineId": null
  // If a change adds study time for an existing deadline, set deadlineId to that deadline's ID
  // so the planned time gets updated.
}

IMPORTANT:
- Use ONLY real block IDs from the schedule context when moving/removing.
- For new blocks, do NOT include an "id" field - the server generates it.
- Make sure start and end don't overlap with fixed lecture blocks.
- When picking free slots, use the free-slot information provided in the context.
- When the user just asks a question (like "how does my day look?"), return an empty changes array.
- Always return valid JSON. No markdown, no code fences.`;

/**
 * The prompt asks Gemini for camelCase keys (start/end/blockId); the database
 * and the app both use snake_case. Normalise here so everything downstream
 * (validation, storage, the Flutter client) sees one shape.
 */
function normaliseSlot(slot) {
  if (!slot) return slot;
  return { day: slot.day, start_min: slot.start_min ?? slot.start, end_min: slot.end_min ?? slot.end };
}

function normaliseChange(change) {
  if (change?.type === 'add') {
    const b = change.block ?? {};
    return {
      type: 'add',
      block: {
        day: b.day,
        title: b.title,
        kind: b.kind,
        start_min: b.start_min ?? b.start,
        end_min: b.end_min ?? b.end,
        detail: b.detail,
      },
    };
  }
  if (change?.type === 'move') {
    return {
      type: 'move',
      block_id: change.block_id ?? change.blockId,
      title: change.title,
      kind: change.kind,
      from: normaliseSlot(change.from),
      to: normaliseSlot(change.to),
    };
  }
  if (change?.type === 'remove') {
    return {
      type: 'remove',
      block_id: change.block_id ?? change.blockId,
      title: change.title,
      kind: change.kind,
      from: normaliseSlot(change.from),
    };
  }
  return change;
}

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
    const { text } = await generateJson(prompt);

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
      changes: Array.isArray(parsed.changes) ? parsed.changes.map(normaliseChange) : [],
      deadline: parsed.deadline || null,
      deadlineId: parsed.deadlineId || null,
    };
  } catch (err) {
    console.error('Gemini error:', err.message);
    // Fallback response
    return {
      text: "Sorry, I had trouble processing that. Try again - something like \"Meeting at 3pm for 1h\" or \"How does my day look?\"",
      changes: [],
      deadline: null,
      deadlineId: null,
    };
  }
}

/**
 * Validate proposed changes against the current blocks.
 * Removes invalid move/remove changes (bad IDs, moving lectures, etc.)
 */
export function validateChanges(changes, blocks) {
  const blockMap = new Map(blocks.map(b => [b.id, b]));
  const valid = [];

  for (const c of changes) {
    if (c.type === 'add') {
      // Add changes just need valid times
      if (c.block && c.block.start_min < c.block.end_min) {
        valid.push(c);
      }
    } else if (c.type === 'move') {
      const target = blockMap.get(c.block_id);
      if (target && target.kind !== 'lecture' && c.to?.start_min < c.to?.end_min) {
        valid.push(c);
      }
    } else if (c.type === 'remove') {
      const target = blockMap.get(c.block_id);
      if (target && target.kind !== 'lecture') {
        valid.push(c);
      }
    }
  }

  return valid;
}
