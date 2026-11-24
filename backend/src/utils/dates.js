export const DAY_LONG = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
export const DAY_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
export const MONTH_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const two = n => String(n).padStart(2, '0');

export function ymd(y, m, d) {
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d ? date : null;
}

export function addDays(date, n) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + n));
}

export function daysBetween(a, b) {
  return Math.round((Date.UTC(b.getUTCFullYear(), b.getUTCMonth(), b.getUTCDate())
    - Date.UTC(a.getUTCFullYear(), a.getUTCMonth(), a.getUTCDate())) / 86400000);
}

export function isoDate(date) {
  return `${String(date.getUTCFullYear()).padStart(4, '0')}-${two(date.getUTCMonth() + 1)}-${two(date.getUTCDate())}`;
}

function validDate(y, m, d) {
  return ymd(y, m, d);
}

export function parseIso(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return null;
  return validDate(Number(match[1]), Number(match[2]), Number(match[3]));
}

export function weekdayIndex(date) {
  return date.getUTCDay() === 0 ? 6 : date.getUTCDay() - 1;
}

export function mondayOf(date) {
  return addDays(date, -weekdayIndex(date));
}

export function weekDates(today) {
  const monday = mondayOf(today);
  return Array.from({ length: 7 }, (_, i) => addDays(monday, i));
}

export function weekIndexOf(date, today) {
  const index = daysBetween(mondayOf(today), date);
  return index >= 0 && index <= 6 ? index : null;
}

export function dayLabel(date) {
  return `${DAY_SHORT[weekdayIndex(date)]} ${date.getUTCDate()} ${MONTH_SHORT[date.getUTCMonth()]}`;
}

export function longLabel(date) {
  return `${DAY_LONG[weekdayIndex(date)]} ${date.getUTCDate()} ${MONTH_SHORT[date.getUTCMonth()]} ${date.getUTCFullYear()}`;
}

function numberParam(value) {
  return value == null || value === '' ? null : Number(value);
}

function fallbackToday(query, serverNow) {
  const offset = numberParam(query.tz_offset);
  if (offset != null && Number.isFinite(offset)) {
    const local = new Date(serverNow.getTime() + offset * 60000);
    return {
      today: new Date(Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate())),
      now: local.getUTCHours() * 60 + local.getUTCMinutes(),
    };
  }

  if (query.tz) {
    try {
      const parts = new Intl.DateTimeFormat('en-US', {
        timeZone: query.tz,
        year: 'numeric',
        month: 'numeric',
        day: 'numeric',
        hour: 'numeric',
        minute: 'numeric',
        hourCycle: 'h23',
      }).formatToParts(serverNow);
      const get = type => Number(parts.find(part => part.type === type)?.value);
      return {
        today: new Date(Date.UTC(get('year'), get('month') - 1, get('day'))),
        now: get('hour') * 60 + get('minute'),
      };
    } catch {
      // Invalid timezone names use UTC below.
    }
  }

  return {
    today: new Date(Date.UTC(serverNow.getUTCFullYear(), serverNow.getUTCMonth(), serverNow.getUTCDate())),
    now: serverNow.getUTCHours() * 60 + serverNow.getUTCMinutes(),
  };
}

export function clientToday(query = {}, serverNow = new Date()) {
  const given = parseIso(query.date);
  const nowMin = numberParam(query.now);
  const hasNow = nowMin != null && Number.isInteger(nowMin) && nowMin >= 0 && nowMin < 1440;
  if (given && hasNow) return { today: given, now: nowMin };

  const fallback = fallbackToday(query, serverNow);
  const day = numberParam(query.day);
  if (Number.isInteger(day) && day >= 0 && day <= 6 && hasNow) {
    return { today: addDays(mondayOf(fallback.today), day), now: nowMin };
  }
  return fallback;
}

const MONTHS = {
  jan: 1, januari: 1, january: 1,
  feb: 2, februari: 2, february: 2,
  mar: 3, maret: 3, march: 3,
  apr: 4, april: 4,
  mei: 5, may: 5,
  jun: 6, juni: 6, june: 6,
  jul: 7, juli: 7, july: 7,
  agu: 8, agt: 8, agustus: 8, aug: 8, august: 8,
  sep: 9, sept: 9, september: 9,
  okt: 10, oktober: 10, oct: 10, october: 10,
  nov: 11, november: 11,
  des: 12, desember: 12, dec: 12, december: 12,
};

const MONTH_RE = 'januari|january|jan|februari|february|feb|maret|march|mar|april|apr|mei|may|juni|june|jun|juli|july|jul|'
  + 'agustus|august|agu|agt|aug|september|sept|sep|oktober|october|okt|oct|november|nov|desember|december|des|dec';

const WEEKDAYS = {
  monday: 0, mon: 0, senin: 0,
  tuesday: 1, tues: 1, tue: 1, selasa: 1,
  wednesday: 2, wed: 2, rabu: 2,
  thursday: 3, thurs: 3, thur: 3, thu: 3, kamis: 3,
  friday: 4, fri: 4, jumat: 4, "jum'at": 4,
  saturday: 5, sat: 5, sabtu: 5,
  sunday: 6, sun: 6, minggu: 6, ahad: 6,
};

function inferYear(month, day, today) {
  const candidate = validDate(today.getUTCFullYear(), month, day);
  if (!candidate) return null;
  return daysBetween(candidate, today) > 180 ? validDate(today.getUTCFullYear() + 1, month, day) : candidate;
}

export function parseDateRefs(text, today) {
  let work = String(text).toLowerCase();
  const found = [];

  const mask = match => {
    work = work.slice(0, match.index) + ' '.repeat(match[0].length) + work.slice(match.index + match[0].length);
  };

  const run = (regex, toDate) => {
    for (const match of [...work.matchAll(regex)]) {
      const date = toDate(match);
      if (!date) continue;
      found.push({ index: match.index, date });
      mask(match);
    }
  };

  run(/\b(\d{4})-(\d{2})-(\d{2})\b/g, m => validDate(Number(m[1]), Number(m[2]), Number(m[3])));

  run(/\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/g, m => {
    const day = Number(m[1]);
    const month = Number(m[2]);
    if (m[3] != null) {
      let year = Number(m[3]);
      if (year < 100) year += 2000;
      return validDate(year, month, day);
    }
    return inferYear(month, day, today);
  });

  run(new RegExp(`\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?(${MONTH_RE})\\b(?:,?\\s+(\\d{4}))?`, 'g'), m => {
    const year = m[3] == null ? null : Number(m[3]);
    const day = Number(m[1]);
    const month = MONTHS[m[2]];
    return year == null ? inferYear(month, day, today) : validDate(year, month, day);
  });

  run(new RegExp(`\\b(${MONTH_RE})\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?!:)(?:,?\\s+(\\d{4}))?`, 'g'), m => {
    const year = m[3] == null ? null : Number(m[3]);
    const day = Number(m[2]);
    const month = MONTHS[m[1]];
    return year == null ? inferYear(month, day, today) : validDate(year, month, day);
  });

  run(/\b(?:tanggal|tgl)\.?\s*(\d{1,2})(?!\d)/g, m => {
    const day = Number(m[1]);
    const thisMonth = validDate(today.getUTCFullYear(), today.getUTCMonth() + 1, day);
    if (thisMonth >= today) return thisMonth;
    const next = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 1));
    return validDate(next.getUTCFullYear(), next.getUTCMonth() + 1, day);
  });

  run(/\b(?:day after tomorrow|lusa)\b/g, () => addDays(today, 2));
  run(/\b(?:tomorrow|tmrw|besok)\b/g, () => addDays(today, 1));
  run(/\b(?:yesterday|kemarin)\b/g, () => addDays(today, -1));
  run(/\b(?:today|tonight|hari ini|malam ini)\b/g, () => today);

  run(new RegExp(`\\b(?:(next|depan)\\s+)?(${Object.keys(WEEKDAYS).join('|')})\\b(\\s+(?:depan|next)\\b)?`, 'g'), m => {
    const key = m[2].replaceAll("'", '');
    if (key === 'minggu' && (m[3] || /^\s*(ini|lalu|kemarin|depan|ke-?\d|\d)/.test(work.slice(matchEnd(m))))) {
      return null;
    }
    let date = addDays(mondayOf(today), WEEKDAYS[key]);
    if (m[1] || m[3]) {
      date = addDays(date, 7);
    } else if (date < today) {
      date = addDays(date, 7);
    }
    return date;
  });

  found.sort((a, b) => a.index - b.index);
  return found.filter((entry, index) => !found.slice(0, index).some(other => isoDate(other.date) === isoDate(entry.date))).map(entry => entry.date);
}

function matchEnd(match) {
  return match.index + match[0].length;
}

export function normaliseDue(due, today) {
  const text = String(due ?? '').trim();
  if (!text) return 'TBD';
  const parsed = parseIso(text) ?? parseDateRefs(text, today)[0];
  return parsed ? isoDate(parsed) : text;
}

export function dueWithinADay(due, today) {
  const date = parseIso(due);
  return date ? daysBetween(today, date) <= 1 : null;
}
