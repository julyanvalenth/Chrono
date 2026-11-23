// Reads a class timetable (photo/screenshot of a KRS or campus portal, or free
// text) with Gemini and returns structured courses for onboarding.

import { generateJson } from '../config/gemini.js';

const PROMPT = `You read university class timetables for a student scheduling app.
The input is either a photo/screenshot of a timetable (KRS, campus portal, a printed or handwritten schedule)
or a short text the student typed. It may be in Indonesian or English.

Extract every WEEKLY class meeting and return JSON exactly like:
{
  "courses": [
    {
      "code": "COMP6048",          // course code if visible, else ""
      "name": "Data Structures",   // course name as written (clean, title case; no codes)
      "days": [0, 3],              // 0=Monday 1=Tuesday 2=Wednesday 3=Thursday 4=Friday 5=Saturday 6=Sunday
      "start": "08:00",            // 24-hour HH:MM
      "end": "09:40",              // 24-hour HH:MM
      "room": "B-302"              // room/lab/online if visible, else ""
    }
  ],
  "note": ""                        // one short sentence if something was unclear, else ""
}

Rules:
- Indonesian days: Senin=0, Selasa=1, Rabu=2, Kamis=3, Jumat/Jum'at=4, Sabtu=5, Minggu=6.
- One entry per course per distinct time slot. If a course meets on several days at the SAME time, put all those
  days in one entry. If the times differ (e.g. lecture vs lab), make separate entries (you may add " (Lab)" to the name).
- Convert 12-hour times (10am, 1.30pm) and dotted times (07.20) to 24-hour HH:MM.
- If only a start time is given, assume a 100-minute class.
- If a timetable lists specific dates for one week, still return them as weekly days.
- Ignore exams, breaks, holidays and non-class rows.
- If the input is not a timetable or nothing can be read, return {"courses": [], "note": "<why>"}.
- Return valid JSON only. No markdown.`;

function toMin(hhmm) {
  const m = /^(\d{1,2})[:.](\d{2})$/.exec(String(hhmm ?? '').trim());
  if (!m) return null;
  const h = Number(m[1]), min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/** Keep only well-formed courses; merge exact duplicates. */
export function cleanCourses(raw) {
  const out = [];
  const seen = new Set();
  for (const c of Array.isArray(raw) ? raw : []) {
    const name = String(c?.name ?? '').trim();
    const start = toMin(c?.start);
    let end = toMin(c?.end);
    if (start != null && end == null) end = start + 100;
    const days = [...new Set((Array.isArray(c?.days) ? c.days : []).map(Number))]
      .filter(d => Number.isInteger(d) && d >= 0 && d <= 6)
      .sort();
    if (!name || start == null || end == null || end <= start || days.length === 0) continue;
    const key = `${name.toLowerCase()}|${days.join(',')}|${start}|${end}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      code: String(c?.code ?? '').trim().slice(0, 20),
      name: name.slice(0, 80),
      days,
      start_min: start,
      end_min: end,
      room: String(c?.room ?? '').trim().slice(0, 40),
    });
  }
  return out.slice(0, 30);
}

/**
 * @param {{ text?: string, image?: { data: string, mimeType: string } }} input
 * @returns {Promise<{ courses: Array, note: string, model: string }>}
 */
export async function readSchedule({ text, image }) {
  const parts = [{ text: PROMPT }];
  if (image) parts.push({ inlineData: { data: image.data, mimeType: image.mimeType } });
  if (text) parts.push({ text: `Student's text:\n"""${text}"""` });

  const { text: out, model } = await generateJson(parts, { timeout: 45_000 });
  let parsed;
  try {
    parsed = JSON.parse(out);
  } catch {
    parsed = JSON.parse(out.replace(/```json?\s*/g, '').replace(/```/g, '').trim());
  }
  return { courses: cleanCourses(parsed.courses), note: String(parsed.note ?? ''), model };
}
