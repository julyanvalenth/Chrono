// Try POST /api/schedule/parse with an image and/or text.
// usage: node scripts/schedule-test.mjs [path/to/timetable.jpg]
// Needs the server running. Creates a throwaway user and deletes it afterwards.
import 'dotenv/config';
import { readFileSync } from 'node:fs';
import { supabaseAdmin } from '../src/config/supabase.js';

const BASE = process.env.API_URL || 'http://localhost:3000';
const rnd = Math.random().toString(16).slice(2, 14);
const email = `device-test-${rnd}@chrono.app`;

const signup = await fetch(`${BASE}/api/auth/signup`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password: `pw-${rnd}-${rnd}` }),
}).then(r => r.json());
const token = signup.access_token;
const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const hm = m => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

async function parse(label, body) {
  const t = Date.now();
  const res = await fetch(`${BASE}/api/schedule/parse`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  console.log(`\n== ${label}: HTTP ${res.status}, ${Date.now() - t}ms, model=${data.model}`);
  if (data.error) console.log('error:', data.error);
  for (const c of data.courses ?? []) {
    console.log(`  ${c.name.padEnd(36)} ${c.days.map(d => DAYS[d]).join('+').padEnd(9)} ${hm(c.start_min)}–${hm(c.end_min)}  ${c.room}  ${c.code}`);
  }
  if (data.note) console.log('  note:', data.note);
}

try {
  const img = process.argv[2];
  if (img) {
    const mime = img.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    await parse('image', { image: readFileSync(img).toString('base64'), mime_type: mime });
  }
  await parse('text (EN)', { text: 'Stats Tue & Thu 10am, HCI Friday 9-10.40 in Lab 3, Data Structures Mon & Thu 8am room B-302' });
  await parse('text (ID)', { text: 'kalkulus senin jam 1 siang sampai 14.40 di A-110, basis data rabu jam 8 pagi' });
  await parse('not a timetable', { text: 'aku suka nasi goreng' });
} finally {
  if (signup.user?.id) await supabaseAdmin.auth.admin.deleteUser(signup.user.id);
}
