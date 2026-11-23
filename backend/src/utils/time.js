// Time utility functions — ported from lib/logic/time_utils.dart

export const DAY_START = 7 * 60;   // 07:00
export const DAY_END   = 23 * 60;  // 23:00

export function h(hh, mm = 0) {
  return hh * 60 + mm;
}

export function pad(n) {
  return n.toString().padStart(2, '0');
}

export function clock(m) {
  return `${pad(Math.floor(m / 60))}:${pad(m % 60)}`;
}

export function range(a, b) {
  return `${clock(a)}–${clock(b)}`;
}

export function duration(min) {
  const hh = Math.floor(min / 60);
  const mm = min % 60;
  if (hh === 0) return `${mm}m`;
  if (mm === 0) return `${hh}h`;
  return `${hh}h ${mm}m`;
}

export function overlaps(aStart, aEnd, bStart, bEnd) {
  return aStart < bEnd && bStart < aEnd;
}

/** Sort blocks for a given day. */
export function dayBlocks(blocks, day) {
  return blocks
    .filter(b => b.day === day)
    .sort((a, b) => a.start_min - b.start_min);
}

/** Free-time gaps on a day between `from` and `to`. */
export function gaps(blocks, day, from, to) {
  const out = [];
  let cursor = from;
  for (const b of dayBlocks(blocks, day)) {
    if (b.start_min > cursor) {
      out.push({ start: cursor, end: Math.min(b.start_min, to) });
    }
    if (b.end_min > cursor) cursor = b.end_min;
    if (cursor >= to) break;
  }
  if (cursor < to) out.push({ start: cursor, end: to });
  return out.filter(g => g.end > g.start);
}

/** Total free minutes (gaps ≥ 15 min) between 08:00 and 22:40. */
export function freeMinutes(blocks, day) {
  return gaps(blocks, day, h(8), h(22, 40))
    .map(g => g.end - g.start)
    .filter(m => m >= 15)
    .reduce((s, m) => s + m, 0);
}

/** First slot of `len` minutes on `day`, starting ≥ `after`, ending by 22:00. */
export function findSlot(blocks, day, len, after, ignoreId = null) {
  const list = dayBlocks(blocks, day).filter(b => b.id !== ignoreId);
  const candidates = [
    Math.max(after, h(8)),
    ...list.map(b => b.end_min).filter(e => e >= after),
  ].sort((a, b) => a - b);

  for (const start of candidates) {
    const end = start + len;
    if (end > h(22)) break;
    if (!list.some(b => overlaps(b.start_min, b.end_min, start, end))) {
      return { start, end };
    }
  }
  return null;
}

/** Day names for context. */
const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

export function dayName(d, today) {
  if (d === today) return 'Today';
  if (d === today + 1) return 'Tomorrow';
  return DAY_NAMES[d] ?? `Day ${d}`;
}
