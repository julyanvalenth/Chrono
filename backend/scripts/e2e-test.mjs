// End-to-end test of chrono-backend, mirroring what the Flutter app does.
// Creates a throwaway account and deletes it at the end.
import 'dotenv/config';
import { supabaseAdmin } from '../src/config/supabase.js';

const BASE = process.env.API_URL || process.env.BASE || 'http://localhost:3000';
let token = null;
let failures = 0;

async function call(method, path, body, query) {
  const url = new URL(BASE + path);
  if (query) for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
  const res = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, data: text ? JSON.parse(text) : null };
}

function check(name, ok, extra = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ': ' + extra : ''}`);
  if (!ok) failures++;
}

const h = (hh, mm = 0) => hh * 60 + mm;
// Real clock: the server works out "today" itself; we only send our UTC offset.
const TZ = { tz_offset: String(-new Date().getTimezoneOffset()) };
const TODAY = (new Date().getDay() + 6) % 7; // 0 = Monday
const TMR = (TODAY + 1) % 7; // flexible test blocks go on tomorrow, which is always in the future
const AI_FAILED = /trouble processing/i;
const rnd = Math.random().toString(16).slice(2, 14);
const email = `device-test-${rnd}@chrono.app`;
const password = `pw-${rnd}-${rnd}`;

// 1. health
let r = await call('GET', '/api/health');
check('health: database configured', r.data.database === 'configured', JSON.stringify(r.data.database));

// 2. signup + login + refresh
r = await call('POST', '/api/auth/signup', { email, password, name: 'Nadia' });
check('signup', r.status === 201 && r.data.access_token, r.data.error);
const userId = r.data.user?.id;
token = r.data.access_token;
const refresh = r.data.refresh_token;

r = await call('POST', '/api/auth/login', { email, password });
check('login', r.status === 200 && r.data.access_token, r.data.error);
token = r.data.access_token;

r = await call('POST', '/api/auth/refresh', { refresh_token: r.data.refresh_token ?? refresh });
check('refresh', r.status === 200 && r.data.access_token, r.data.error);
token = r.data.access_token;

r = await call('GET', '/api/me');
check('GET /api/me (fresh user)', r.status === 200 && r.data.preferences.onboarding_complete === false, r.data.error);

// 3. onboarding (same shape as the app's payload)
const courses = [
  { code: 'ds', name: 'Data Structures', days: [0, 3], start_min: h(8), end_min: h(9, 40), room: 'B-302', selected: true },
  { code: 'stats', name: 'Statistics', days: [1, 3], start_min: h(10), end_min: h(11, 40), room: 'A-204', selected: true },
  { code: 'hci', name: 'Human–Computer Interaction', days: [4], start_min: h(9), end_min: h(10, 40), room: 'Lab 3', selected: false },
];
const blocks = [
  { id: 'quiz-3', day: 3, title: 'Algorithm quiz prep', kind: 'focus', start_min: h(13), end_min: h(14) },
  { id: 'gym-3', day: TMR, title: 'Gym', kind: 'personal', start_min: h(16), end_min: h(17) },
  { id: 'hci-essay-3', day: TMR, title: 'HCI essay draft', kind: 'task', start_min: h(14, 45), end_min: h(15, 45) },
  { id: 'lunch-3', day: TMR, title: 'Lunch', kind: 'breakTime', start_min: h(12), end_min: h(12, 45) },
];
const deadlines = [
  { id: 'd-bem', title: 'BEM event proposal', course: 'Student organization', estimate: 120, due: 'Next Tue', urgent: false, planned: 0 },
];
r = await call('POST', '/api/me/onboarding', {
  preferences: { name: 'Nadia', focus_window: 'morning', bedtime: '23:00', break_minutes: 15 },
  courses, blocks, deadlines,
});
if (r.status !== 200) {
  console.log(`FAIL  onboarding: ${r.data?.error}\n\nStopping: the database isn't usable yet (run supabase-schema.sql / supabase-grants.sql).`);
  process.exit(1);
}
const lectures = r.data.blocks?.filter(b => b.kind === 'lecture') ?? [];
check('onboarding saved', r.status === 200 && r.data.preferences.onboarding_complete === true, r.data.error);
check('onboarding: 4 lecture blocks (unselected course skipped)', lectures.length === 4, `got ${lectures.length}`);
check('onboarding: 4 flex blocks with uuid ids', r.data.blocks.filter(b => b.kind !== 'lecture').length === 4);
check('onboarding: deadline saved', r.data.deadlines.length === 1);
let allBlocks = r.data.blocks;
const bem = r.data.deadlines[0];
const quiz = allBlocks.find(b => b.title === 'Algorithm quiz prep');
const gym = allBlocks.find(b => b.title === 'Gym');
const essay = allBlocks.find(b => b.title === 'HCI essay draft');
const lunch = allBlocks.find(b => b.title === 'Lunch');

// 4. block actions
r = await call('POST', `/api/blocks/${lunch.id}/done`);
check('mark done', r.status === 200 && r.data.done === true, r.data.error);
r = await call('POST', `/api/blocks/${essay.id}/push`, { minutes: 30 });
check('push 30 min', r.status === 200 && r.data.start_min === h(15, 15) && r.data.origin === 'moved', r.data.error);
r = await call('POST', `/api/deadlines/${bem.id}/toggle`);
check('toggle deadline', r.status === 200 && r.data.done === true, r.data.error);
await call('POST', `/api/deadlines/${bem.id}/toggle`);

// 5. chat with Gemini → proposal → apply
const t0 = Date.now();
r = await call('POST', '/api/chat', { message: 'Org meeting tomorrow at 6pm for 1h' }, TZ);
check('chat reply from Gemini', r.status === 200 && !!r.data.ai_message?.content && !AI_FAILED.test(r.data.ai_message.content), `${Date.now() - t0}ms, text="${r.data.ai_message?.content}"`);
const proposal = r.data.proposal;
check('chat produced a proposal', proposal && proposal.changes.length > 0, JSON.stringify(proposal?.changes));

if (proposal) {
  r = await call('POST', `/api/chat/${proposal.id}/apply`);
  check('apply proposal', r.status === 200 && r.data.applied === true, r.data.error);
  check('apply returned added_ids', Array.isArray(r.data.added_ids) && r.data.added_ids.length >= 1, JSON.stringify(r.data.added_ids));
  const added = r.data.blocks.find(b => b.id === r.data.added_ids[0]);
  check('added block is in schedule with origin=added', added?.origin === 'added', added ? `${added.title} day ${added.day} ${added.start_min}-${added.end_min}` : 'missing');
  check('old origin flags cleared', r.data.blocks.find(b => b.id === essay.id)?.origin !== 'moved');

  r = await call('POST', `/api/chat/${proposal.id}/apply`);
  check('double apply is rejected', r.status === 400);
}

// 6. Indonesian + question (no changes)
r = await call('POST', '/api/chat', { message: 'Gimana jadwalku besok?' }, TZ);
check('question answered, no proposal', r.status === 200 && !AI_FAILED.test(r.data.ai_message?.content ?? '') && !r.data.proposal, `"${r.data.ai_message?.content}"`);

r = await call('POST', '/api/chat', { message: 'Skip algorithm quiz prep today' }, { day: 3, now: h(10, 40) });
const skipAnswer = r.data.ai_message?.content ?? '';
const removesQuiz = r.data.proposal?.changes.some(c => c.type === 'remove' && c.block_id === quiz.id) ?? false;
check(
  'skip named block uses the device day',
  r.status === 200 && r.data.ai_ok === true && removesQuiz && !/don't have|not scheduled|no .*scheduled/i.test(skipAnswer),
  `"${skipAnswer}", model=${r.data.model}, proposal=${JSON.stringify(r.data.proposal)}`,
);

// 7. deadline planning links the deadline
r = await call('POST', '/api/chat', { message: 'Plan time for BEM event proposal' }, TZ);
check('plan deadline → proposal linked to deadline', r.data.proposal?.deadline_id === bem.id, `deadline_id=${r.data.proposal?.deadline_id}`);
if (r.data.proposal) {
  const ap = await call('POST', `/api/chat/${r.data.proposal.id}/apply`);
  const dl = ap.data.deadlines?.find(d => d.id === bem.id);
  check('deadline planned minutes increased', dl?.planned > 0, `planned=${dl?.planned}`);
}

// 8. dismiss
r = await call('POST', '/api/chat', { message: 'Skip gym tomorrow' }, TZ);
if (r.data.proposal) {
  const d = await call('POST', `/api/chat/${r.data.proposal.id}/dismiss`);
  check('dismiss proposal', d.status === 200 && d.data.dismissed, d.data.error);
} else {
  check('skip gym produced a proposal', false, `"${r.data.ai_message?.content}"`);
}

// 9. undo = replace blocks/deadlines with the onboarding snapshot
r = await call('POST', '/api/blocks/replace', { blocks: allBlocks });
check('undo: replace blocks keeps original ids', r.status === 200 && r.data.length === allBlocks.length && r.data.some(b => b.id === gym.id), r.data.error);
r = await call('POST', '/api/deadlines/replace', { deadlines: [bem] });
check('undo: replace deadlines', r.status === 200 && r.data[0]?.id === bem.id, r.data.error);

// 10. history + delete + wipe
r = await call('GET', '/api/me');
check('history saved', r.data.messages.length >= 6, `${r.data.messages.length} messages`);
r = await call('DELETE', `/api/blocks/${gym.id}`);
check('delete block', r.status === 200);
r = await call('DELETE', '/api/me/data');
r = await call('GET', '/api/me');
check('reset wipes data', r.data.blocks.length === 0 && r.data.messages.length === 0 && !r.data.preferences.onboarding_complete);

// 11. logout ends the session
r = await call('POST', '/api/auth/login', { email, password });
const session2 = r.data;
token = session2.access_token;
r = await call('POST', '/api/auth/logout');
check('logout', r.status === 200);
r = await call('POST', '/api/auth/refresh', { refresh_token: session2.refresh_token });
check('refresh after logout is rejected', r.status === 401, r.data.error);

r = await call('POST', '/api/auth/signup', { email, password, name: 'Dup' });
check('duplicate sign-up → 409', r.status === 409, r.data.error);

// 12. auth guard
token = 'not-a-token';
r = await call('GET', '/api/blocks');
check('bad token → 401', r.status === 401);

console.log(`\n${failures === 0 ? 'ALL PASSED' : failures + ' FAILED'}`);
if (userId) {
  const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
  console.log(error ? `could not delete test user: ${error.message}` : 'test user deleted');
}
process.exit(failures === 0 ? 0 : 1);
