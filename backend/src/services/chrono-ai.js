import { generateJson } from '../config/gemini.js';
import { clock, range, duration, dayBlocks, gaps, h } from '../utils/time.js';
import {
  DAY_LONG, weekDates, weekIndexOf, weekdayIndex, dayLabel, longLabel,
  parseDateRefs, parseIso, daysBetween, isoDate,
} from '../utils/dates.js';
import { plannedFromBlocks } from '../utils/deadlines.js';

function blockTable(list, now) {
  const lines = ['| Time | Title | Kind | ID | Done |', '|------|-------|------|----|------|'];
  for (const block of list) {
    const state = now == null ? '' : block.end_min <= now ? ' (past)' : block.start_min <= now ? ' (NOW)' : '';
    lines.push(`| ${range(block.start_min, block.end_min)} | ${block.title} | ${block.kind} | ${block.id} | ${block.done}${state} |`);
  }
  return lines;
}

function dueText(due, today) {
  const date = parseIso(due);
  if (!date) return due;
  const diff = daysBetween(today, date);
  const when = diff < 0 ? `${-diff} day(s) overdue` : diff === 0 ? 'today' : diff === 1 ? 'tomorrow' : `in ${diff} days`;
  return `${due} (${dayLabel(date)}, ${when})`;
}

export function buildContext(blocks, deadlines, prefs, clockInfo, message = '') {
  const { today, now, viewDay = null } = clockInfo;
  const todayIdx = weekdayIndex(today);
  const week = weekDates(today);
  const lines = [];

  lines.push('## Calendar');
  lines.push(`Today is ${longLabel(today)} (day index ${todayIdx}). Current time: ${clock(now)}.`);
  if (viewDay != null) {
    lines.push(
      `The Today tab is currently open on ${longLabel(week[viewDay])} (day index ${viewDay}). ` +
      'This is NOT where things go by default. Use it only when the message says "this day", "that day" or similar without naming a date.',
    );
  }
  lines.push('');
  lines.push('Days that can hold blocks (this week only):');
  lines.push('| Index | Day | Date |');
  lines.push('|-------|-----|------|');
  week.forEach((date, index) => lines.push(`| ${index} | ${DAY_LONG[index]}${index === todayIdx ? ' (today)' : ''} | ${isoDate(date)} (${dayLabel(date)}) |`));
  lines.push(`Next week starts ${longLabel(addOneWeek(week[6]))}. Blocks cannot be placed there yet.`);

  const mentioned = parseDateRefs(message, today);
  if (mentioned.length > 0) {
    lines.push('');
    lines.push("Dates the user's message names (detected by the server, use these because they override everything else):");
    for (const date of mentioned) {
      const index = weekIndexOf(date, today);
      lines.push(`- ${longLabel(date)} -> ${index == null ? (daysBetween(today, date) < 0 ? 'in the past' : 'outside this week, no day index') : `day index ${index}`}`);
    }
  }
  lines.push('');

  lines.push('## User Preferences');
  lines.push(`- Name: ${prefs.name}`);
  lines.push(`- Best focus time: ${prefs.focus_window}`);
  lines.push(`- Bedtime: ${prefs.bedtime}`);
  lines.push(`- Break between blocks: ${prefs.break_minutes} min`);
  lines.push('');

  lines.push('## Schedule This Week');
  week.forEach((date, index) => {
    const isToday = index === todayIdx;
    if (index < todayIdx) {
      lines.push(`### ${DAY_LONG[index]} ${isoDate(date)} (day index ${index}): PAST, cannot be changed`);
      lines.push('');
      return;
    }
    const list = dayBlocks(blocks, index);
    lines.push(`### ${DAY_LONG[index]} ${isoDate(date)} (day index ${index})${isToday ? `: TODAY, now ${clock(now)}` : ''}`);
    lines.push(list.length === 0 ? 'No blocks scheduled.' : blockTable(list, isToday ? now : null));
    const free = gaps(blocks, index, isToday ? Math.max(now, h(8)) : h(8), h(22)).filter(gap => gap.end - gap.start >= 30);
    if (free.length > 0) {
      lines.push(`Free slots${isToday ? ' from now' : ''} (30 min or more): ${free.map(gap => range(gap.start, gap.end)).join(', ')}`);
    }
    lines.push('');
  });

  const open = deadlines.filter(deadline => !deadline.done);
  if (open.length > 0) {
    lines.push('## Open Deadlines');
    lines.push('| Title | Course | Estimate | On calendar | Due | ID |');
    lines.push('|-------|--------|----------|-------------|-----|----|');
    for (const deadline of open) {
      lines.push(`| ${deadline.title} | ${deadline.course} | ${duration(deadline.estimate)} | ${duration(plannedFromBlocks(deadline, blocks))} | ${dueText(deadline.due, today)} | ${deadline.id} |`);
    }
  } else {
    lines.push('## Open Deadlines\nNone.');
  }

  return lines.join('\n');
}

function addOneWeek(date) {
  return new Date(date.getTime() + 7 * 86400000);
}

const SYSTEM_PROMPT = `You are Chrono, an AI scheduling assistant for university students. You help manage their schedule by adding, moving, and removing time blocks, and by keeping track of deadlines.

## Rules
1. Classes (kind: "lecture") are FIXED. Never move or remove them. Plan everything else around them.
2. Flexible blocks (focus, task, personal, breakTime) can be moved or removed.
3. When adding a block that overlaps a flexible block, propose moving the flexible block to the next available free slot.
4. Keep responses brief, friendly, and in one or two sentences. Answer in the language the user writes in.
5. Always use 24-hour time internally as minutes from midnight.
6. Never add blocks in the past, either on days before today or earlier than the current time today.
7. The week uses day indices: 0=Monday, 1=Tuesday, 2=Wednesday, 3=Thursday, 4=Friday, 5=Saturday, 6=Sunday.
8. The schedule context is the source of truth. If the block the user names appears in that day's table, propose the change. Never reply that it is missing when it is listed there.
9. Match blocks by meaning, not exact spelling. "algorithm quiz prep" matches "Algorithm quiz prep" or "Quiz prep".

## Dates
- The Calendar section lists today's real date and the seven days of this week with their day index and date.
- If the message names a date or day, plan on exactly that date. Never substitute another day or the day open in the Today tab.
- If the message names no date, use today.
- The day open in the Today tab is only a hint for phrases like "this day" or "that day".
- Every block added or moved to must carry "date" (yyyy-MM-dd) as well as "day", and they must agree.
- If the named date is outside this week or in the past, do not create blocks for it. Say so briefly and suggest a day this week. Deadlines can be due on any date.
- Use the server's resolved dates when they are listed.

## What You Can Do
- Add events: "Meeting at 3pm for 1h" adds a block today. "Meeting Friday 3pm" adds it on Friday.
- Remove blocks: "Skip gym today" removes that block.
- Move blocks: "Move essay to Friday 2pm" moves the block to that date.
- Clear time: "I'm sick, clear my afternoon" moves afternoon flexible blocks to the next day, or removes them if the week is over.
- Summarize a day: "How does my day look?" summarizes that day's blocks and free time.
- Add deadlines: "Stats quiz due Monday, 3h" creates a deadline and can schedule the first session.
- Plan deadline work: "Plan time for HCI essay" finds free slots before the due date.

## Deadlines
- When the user mentions a due date and it is not already in Open Deadlines, return a deadline object even if the message also adds a block.
- "due" must be a real date as yyyy-MM-dd. Use null only if no date was given.
- "estimate" is total work in minutes. If absent, use a sensible value from 60 to 240.
- Deadline work blocks must have exactly the deadline's title, kind "focus" or "task", and end before the due date.
- Set "deadlineId" to the existing deadline's ID when scheduling its work. Leave it null for a new deadline.
- Do not create a second deadline for something already in Open Deadlines.

## Response Format
Return only this JSON structure:
{
  "text": "Your friendly response message to the user.",
  "changes": [
    { "type": "add", "block": { "day": 4, "date": "2026-11-27", "title": "Meeting", "kind": "personal", "start": 900, "end": 960, "detail": "Added by Chrono" } },
    { "type": "move", "blockId": "the-existing-block-uuid", "title": "Block Title", "kind": "task", "from": { "day": 3, "start": 885, "end": 945 }, "to": { "day": 4, "date": "2026-11-27", "start": 960, "end": 1020 } },
    { "type": "remove", "blockId": "the-existing-block-uuid", "title": "Block Title", "kind": "task", "from": { "day": 3, "start": 960, "end": 1020 } }
  ],
  "deadline": null,
  "deadlineId": null
}

A new deadline object has this shape:
{ "title": "Stats quiz prep", "course": "Statistics", "estimate": 180, "due": "2026-11-30", "urgent": false }

IMPORTANT:
- Use only real block IDs from the schedule context when moving or removing.
- Do not include an id field for new blocks.
- Do not overlap fixed lecture blocks. Use the listed free slots.
- Return an empty changes array for questions that do not change the schedule.
- Return valid JSON without markdown or code fences.`;

function normaliseSlot(slot) {
  if (!slot) return slot;
  return {
    day: slot.day,
    date: slot.date,
    start_min: slot.start_min ?? slot.start,
    end_min: slot.end_min ?? slot.end,
  };
}

function normaliseChange(change) {
  if (change?.type === 'add') {
    const block = change.block ?? {};
    return {
      type: 'add',
      block: {
        day: block.day,
        date: block.date,
        title: block.title,
        kind: block.kind,
        start_min: block.start_min ?? block.start,
        end_min: block.end_min ?? block.end,
        detail: block.detail,
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

export async function chat(message, blocks, deadlines, prefs, clockInfo) {
  const context = buildContext(blocks, deadlines, prefs, clockInfo, message);
  const prompt = `${SYSTEM_PROMPT}

---

${context}

---

## User Message
${JSON.stringify(message)}

Respond with the JSON object described above.`;

  try {
    const { text, model } = await generateJson(prompt);
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = JSON.parse(text.replace(/```json?\s*/g, '').replace(/```\s*/g, '').trim());
    }
    return {
      text: parsed.text || "I'm not sure how to help with that. Try telling me about a schedule change!",
      changes: Array.isArray(parsed.changes) ? parsed.changes.map(normaliseChange) : [],
      deadline: parsed.deadline && typeof parsed.deadline === 'object' ? parsed.deadline : null,
      deadlineId: parsed.deadlineId || null,
      ok: true,
      model,
    };
  } catch (error) {
    console.error('Gemini error:', error.message);
    return {
      text: 'Sorry, I had trouble processing that. Try again with something like "Meeting at 3pm for 1h" or "How does my day look?"',
      changes: [],
      deadline: null,
      deadlineId: null,
      ok: false,
      model: null,
    };
  }
}

export function reconcileDates(changes, today) {
  const fix = target => {
    if (!target) return target;
    const { date, ...rest } = target;
    if (date == null || date === '') return rest;
    const parsed = parseIso(date);
    if (!parsed) return { ...rest, day: -1 };
    return { ...rest, day: weekIndexOf(parsed, today) ?? -1 };
  };
  return changes.map(change => {
    if (change?.type === 'add' && change.block) return { ...change, block: fix(change.block) };
    if (change?.type === 'move') {
      return {
        ...change,
        to: fix(change.to),
        from: change.from ? omitDate(change.from) : change.from,
      };
    }
    if (change?.type === 'remove' && change.from) return { ...change, from: omitDate(change.from) };
    return change;
  });
}

function omitDate(slot) {
  const { date, ...rest } = slot;
  return rest;
}

const KINDS = new Set(['lecture', 'focus', 'task', 'personal', 'breakTime']);
const validKind = kind => KINDS.has(kind);
const validDay = (day, todayIdx) => Number.isInteger(day) && day >= todayIdx && day <= 6;
const validSpan = (start, end) => Number.isInteger(start) && Number.isInteger(end) && start >= 0 && end <= 1440 && start < end;
const matchesSource = (block, slot) => validDay(slot?.day, 0)
  && validSpan(slot.start_min, slot.end_min)
  && slot.day === block.day
  && slot.start_min === block.start_min
  && slot.end_min === block.end_min;

export function validateChanges(changes, blocks, { todayIdx = 0, now = 0 } = {}) {
  const blockMap = new Map(blocks.map(block => [block.id, block]));
  const valid = [];
  const validTarget = slot => validDay(slot?.day, todayIdx) && validSpan(slot?.start_min, slot?.end_min)
    && !(slot.day === todayIdx && slot.start_min < now);

  for (const change of changes) {
    if (change.type === 'add') {
      const block = change.block;
      if (block && typeof block.title === 'string' && block.title.trim() && validKind(block.kind) && validTarget(block)) {
        valid.push(change);
      }
    } else if (change.type === 'move') {
      const target = blockMap.get(change.block_id);
      if (target && target.kind !== 'lecture' && validKind(change.kind) && matchesSource(target, change.from) && validTarget(change.to)) {
        valid.push(change);
      }
    } else if (change.type === 'remove') {
      const target = blockMap.get(change.block_id);
      if (target && target.kind !== 'lecture' && validKind(change.kind) && matchesSource(target, change.from)) {
        valid.push(change);
      }
    }
  }
  return valid;
}
