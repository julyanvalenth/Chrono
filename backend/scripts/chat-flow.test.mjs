import test, { mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

const url = path => new URL(path, import.meta.url).href;
let nextId = 1;
const db = { blocks: [], deadlines: [], chat_messages: [], preferences: [] };

function resetDb() {
  nextId = 1;
  db.blocks = [
    { id: 'b-lec', user_id: 'u1', day: 4, title: 'Software Engineering', kind: 'lecture', start_min: 780, end_min: 880, origin: null, done: false },
    { id: 'b-gym', user_id: 'u1', day: 1, title: 'Gym', kind: 'personal', start_min: 960, end_min: 1020, origin: null, done: false },
  ];
  db.deadlines = [];
  db.chat_messages = [];
  db.preferences = [{ user_id: 'u1', name: 'Ey', focus_window: 'morning', bedtime: '23:00', break_minutes: 15 }];
}

class Query {
  constructor(table) {
    this.table = table;
    this.op = 'select';
    this.filters = [];
    this.payload = null;
    this.wantSingle = false;
    this.order_ = null;
  }
  select() { return this; }
  insert(payload) { this.op = 'insert'; this.payload = payload; return this; }
  update(payload) { this.op = 'update'; this.payload = payload; return this; }
  delete() { this.op = 'delete'; return this; }
  eq(key, value) { this.filters.push(row => row[key] === value); return this; }
  not(key, op, value) {
    if (op === 'is') this.filters.push(row => row[key] !== value);
    if (op === 'in') {
      const ids = String(value).replace(/[()]/g, '').split(',');
      this.filters.push(row => !ids.includes(row[key]));
    }
    return this;
  }
  order(key) { this.order_ = key; return this; }
  single() { this.wantSingle = true; return this; }
  then(resolve, reject) { return Promise.resolve(this.run()).then(resolve, reject); }
  run() {
    const rows = db[this.table];
    const match = row => this.filters.every(filter => filter(row));
    let out;
    if (this.op === 'insert') {
      const list = (Array.isArray(this.payload) ? this.payload : [this.payload]).map(payload => ({
        id: `id-${nextId++}`, done: false, created_at: nextId, ...payload,
      }));
      rows.push(...list);
      out = list;
    } else if (this.op === 'update') {
      out = rows.filter(match);
      out.forEach(row => Object.assign(row, this.payload));
    } else if (this.op === 'delete') {
      out = rows.filter(match);
      db[this.table] = rows.filter(row => !match(row));
    } else {
      out = rows.filter(match);
      if (this.order_) out = [...out].sort((a, b) => a[this.order_] > b[this.order_] ? 1 : -1);
    }
    out = out.map(row => ({ ...row }));
    if (this.wantSingle) return { data: out[0] ?? null, error: out[0] ? null : { message: 'not found' } };
    return { data: out, error: null };
  }
}

let prompts = [];
let geminiReply = {};
mock.module(url('../src/config/supabase.js'), {
  namedExports: { supabaseAdmin: { from: table => new Query(table) } },
});
mock.module(url('../src/middleware/auth.js'), {
  namedExports: { requireAuth: (req, _res, next) => { req.userId = 'u1'; next(); } },
});
mock.module(url('../src/config/gemini.js'), {
  namedExports: {
    generateJson: async prompt => {
      prompts.push(prompt);
      return { text: JSON.stringify(geminiReply), model: 'test-model' };
    },
  },
});

const { default: router } = await import('../src/routes/chat.js');
const app = express();
app.use(express.json());
app.use('/api/chat', router);
const server = app.listen(0);
const base = `http://127.0.0.1:${server.address().port}`;
test.after(() => server.close());

const CLOCK = 'date=2026-11-24&now=845&tz_offset=420';
const post = (path, body) => fetch(`${base}${path}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body ?? {}),
}).then(response => response.json());
const ask = (message, extra = '') => post(`/api/chat?${CLOCK}${extra}`, { message });

test('the AI receives the real date and the whole week', async () => {
  resetDb();
  prompts = [];
  geminiReply = { text: 'ok', changes: [], deadline: null, deadlineId: null };
  const response = await ask('how does my day look?');
  const prompt = prompts[0];
  assert.match(prompt, /Today is Tuesday 24 Nov 2026 \(day index 1\)\. Current time: 14:05/);
  assert.match(prompt, /\| 4 \| Friday \| 2026-11-27 \(Fri 27 Nov\) \|/);
  assert.match(prompt, /### Friday 2026-11-27 \(day index 4\)/);
  assert.match(prompt, /Software Engineering/);
  assert.match(prompt, /### Monday 2026-11-23 \(day index 0\): PAST/);
  assert.doesNotMatch(prompt, /15 Oct|Oct 15/);
  assert.equal(response.ai_ok, true);
  assert.equal(response.model, 'test-model');
});

test('a message date overrides the selected day and a wrong model index', async () => {
  resetDb();
  prompts = [];
  geminiReply = {
    text: 'Meeting set for Friday.',
    changes: [{ type: 'add', block: { day: 1, date: '2026-11-27', title: 'Meeting', kind: 'personal', start: 900, end: 960 } }],
    deadline: null,
    deadlineId: null,
  };
  const response = await ask('Meeting on Friday 27 Nov at 3pm', '&view_day=2');
  assert.equal(response.proposal.changes.length, 1);
  assert.equal(response.proposal.changes[0].block.day, 4);
  assert.equal(response.proposal.changes[0].block.date, undefined);
  assert.match(prompts[0], /Today tab is currently open on Wednesday 25 Nov 2026 \(day index 2\)/);
  assert.match(prompts[0], /Friday 27 Nov 2026 -> day index 4/);
});

test('past, out-of-week, past-time, and malformed slots are dropped', async () => {
  resetDb();
  geminiReply = {
    text: 'ok',
    changes: [
      { type: 'add', block: { day: 0, date: '2026-11-23', title: 'Past day', kind: 'personal', start: 900, end: 960 } },
      { type: 'add', block: { day: 0, date: '2026-12-03', title: 'Next week', kind: 'personal', start: 900, end: 960 } },
      { type: 'add', block: { day: 1, date: '2026-11-24', title: 'Past time', kind: 'personal', start: 500, end: 560 } },
      { type: 'add', block: { day: 2, date: '2026-11-25', title: 'Bad span', kind: 'personal', start: -1, end: 1500 } },
      { type: 'add', block: { day: 5, date: '2026-11-28', title: 'Saturday', kind: 'personal', start: 600, end: 660 } },
    ],
    deadline: null,
    deadlineId: null,
  };
  const response = await ask('three things');
  assert.deepEqual(response.proposal.changes.map(change => change.block.title), ['Saturday']);
});

test('a new deadline uses a real date and progress follows applied blocks', async () => {
  resetDb();
  geminiReply = {
    text: 'Added Essay, due Friday.',
    changes: [{ type: 'add', block: { day: 2, date: '2026-11-25', title: 'Essay', kind: 'focus', start: 540, end: 630 } }],
    deadline: { title: 'Essay', course: 'English', estimate: 180, due: 'Friday', urgent: false },
    deadlineId: null,
  };
  const response = await ask('Essay due Friday, 3h');
  assert.ok(response.new_deadline?.id);
  assert.equal(response.new_deadline.due, '2026-11-27');
  assert.equal(response.new_deadline.estimate, 180);
  assert.equal(response.proposal.deadline_id, response.new_deadline.id);
  assert.equal(db.deadlines.length, 1);

  const applied = await post(`/api/chat/${response.proposal.id}/apply`);
  assert.equal(applied.applied, true);
  const deadline = applied.deadlines.find(row => row.id === response.new_deadline.id);
  assert.equal(deadline.planned, 90);
  assert.equal(db.deadlines[0].planned, 90);
  assert.ok(applied.blocks.some(block => block.title === 'Essay' && block.day === 2));
});

test('an existing deadline is linked even when the model omits its id', async () => {
  resetDb();
  db.deadlines = [{
    id: 'dl-1', user_id: 'u1', title: 'HCI essay draft', course: 'HCI', estimate: 240,
    due: '2026-11-29', urgent: false, planned: 0, done: false,
  }];
  geminiReply = {
    text: 'Two hours on Thursday.',
    changes: [{ type: 'add', block: { day: 3, date: '2026-11-26', title: 'HCI essay draft', kind: 'focus', start: 600, end: 720 } }],
    deadline: null,
    deadlineId: null,
  };
  const response = await ask('Plan time for HCI essay draft on Thursday');
  assert.equal(response.proposal.deadline_id, 'dl-1');
  const applied = await post(`/api/chat/${response.proposal.id}/apply`);
  assert.equal(applied.deadlines.find(row => row.id === 'dl-1').planned, 120);
});

test('mentioning the same deadline updates it instead of duplicating it', async () => {
  resetDb();
  db.deadlines = [{
    id: 'dl-1', user_id: 'u1', title: 'Essay', course: 'English', estimate: 120,
    due: '2026-11-30', urgent: false, planned: 0, done: false,
  }];
  geminiReply = {
    text: 'Moved the due date.', changes: [],
    deadline: { title: 'essay', estimate: 180, due: '2026-11-27' }, deadlineId: null,
  };
  const response = await ask('Actually the essay is due Friday, 3h');
  assert.equal(db.deadlines.length, 1);
  assert.equal(response.new_deadline.id, 'dl-1');
  assert.equal(response.new_deadline.due, '2026-11-27');
  assert.equal(db.deadlines[0].estimate, 180);
});

test('moves and removals recalculate progress without double counting', async () => {
  resetDb();
  db.deadlines = [{
    id: 'dl-1', user_id: 'u1', title: 'Thesis', course: 'Research', estimate: 240,
    due: '2026-11-29', urgent: false, planned: 999, done: false,
  }];
  db.blocks.push(
    { id: 'b-thesis-1', user_id: 'u1', day: 2, title: 'Thesis', kind: 'focus', start_min: 540, end_min: 600, origin: null, done: false },
    { id: 'b-thesis-2', user_id: 'u1', day: 3, title: 'Thesis chapter', kind: 'focus', start_min: 540, end_min: 570, origin: null, done: false },
  );
  geminiReply = {
    text: 'Adjusted the sessions.',
    changes: [
      { type: 'move', blockId: 'b-thesis-1', title: 'Thesis', kind: 'focus', from: { day: 2, start: 540, end: 600 }, to: { day: 4, date: '2026-11-27', start: 540, end: 600 } },
      { type: 'remove', blockId: 'b-thesis-2', title: 'Thesis chapter', kind: 'focus', from: { day: 3, start: 540, end: 570 } },
    ],
    deadline: null,
    deadlineId: null,
  };
  const response = await ask('Move one thesis session and remove the other');
  const applied = await post(`/api/chat/${response.proposal.id}/apply`);
  assert.equal(applied.deadlines.find(row => row.id === 'dl-1').planned, 60);
  assert.equal(db.deadlines[0].planned, 60);
});

test('missing deadline details do not overwrite an existing deadline', async () => {
  resetDb();
  db.deadlines = [{
    id: 'dl-1', user_id: 'u1', title: 'Essay', course: 'English', estimate: 180,
    due: '2026-11-30', urgent: false, planned: 45, done: false,
  }];
  geminiReply = {
    text: 'I can work on Essay.',
    changes: [{ type: 'add', block: { day: 3, date: '2026-11-26', title: 'Essay', kind: 'focus', start: 600, end: 660 } }],
    deadline: { title: 'Essay' }, deadlineId: null,
  };
  const response = await ask('Plan time for Essay');
  assert.equal(response.new_deadline.id, 'dl-1');
  assert.equal(response.new_deadline.due, '2026-11-30');
  assert.equal(response.new_deadline.estimate, 180);
  assert.equal(db.deadlines[0].due, '2026-11-30');
  assert.equal(db.deadlines[0].estimate, 180);
});

test('invalid dates and unknown block kinds are rejected', async () => {
  resetDb();
  geminiReply = {
    text: 'Proposed.', deadline: null, deadlineId: null,
    changes: [
      { type: 'add', block: { day: 4, date: 'bad', title: 'One', kind: 'personal', start: 600, end: 660 } },
      { type: 'add', block: { day: 4, title: 'Two', kind: 'bogus', start: 600, end: 660 } },
    ],
  };
  const response = await ask('Add two blocks');
  assert.equal(response.proposal, null);
  assert.equal(response.ai_message.changes, undefined);
});

test('missing client clocks fall back to the timezone offset', async () => {
  resetDb();
  prompts = [];
  geminiReply = { text: 'ok', changes: [], deadline: null, deadlineId: null };
  await post('/api/chat?tz_offset=420', { message: 'hi' });
  assert.match(prompts[0], /Today is \w+day \d+ \w{3} \d{4}/);
});
