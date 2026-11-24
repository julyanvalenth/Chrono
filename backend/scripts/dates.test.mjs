import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ymd, isoDate, parseDateRefs, weekIndexOf, weekDates, clientToday, normaliseDue,
  dayLabel, dueWithinADay,
} from '../src/utils/dates.js';

const today = ymd(2026, 11, 24);
const P = text => parseDateRefs(text, today).map(isoDate).join(',');

test('week dates and labels use the real calendar', () => {
  assert.equal(isoDate(weekDates(today)[0]), '2026-11-23');
  assert.equal(isoDate(weekDates(today)[6]), '2026-11-29');
  assert.equal(weekIndexOf(ymd(2026, 11, 27), today), 4);
  assert.equal(weekIndexOf(ymd(2026, 11, 30), today), null);
  assert.equal(dayLabel(ymd(2026, 11, 27)), 'Fri 27 Nov');
});

test('English and Indonesian date references resolve correctly', () => {
  assert.equal(P('Meeting 27 Nov at 3pm'), '2026-11-27');
  assert.equal(P('meeting nov 27 at 3pm'), '2026-11-27');
  assert.equal(P('meeting 27/11 at 3pm'), '2026-11-27');
  assert.equal(P('plan 2026-11-28'), '2026-11-28');
  assert.equal(P('tambah rapat tanggal 27 jam 3'), '2026-11-27');
  assert.equal(P('tugas tanggal 10'), '2026-12-10');
  assert.equal(P('tugas tanggal 27 november'), '2026-11-27');
  assert.equal(P('besok ada kuis'), '2026-11-25');
  assert.equal(P('lusa ada kuis'), '2026-11-26');
  assert.equal(P('hari ini kosong'), '2026-11-24');
  assert.equal(P('quiz day after tomorrow'), '2026-11-26');
  assert.equal(P('meeting Friday at 3pm'), '2026-11-27');
  assert.equal(P("rapat jum'at jam 3"), '2026-11-27');
  assert.equal(P('due Monday'), '2026-11-30');
  assert.equal(P('kumpul senin depan'), '2026-11-30');
  assert.equal(P('call next friday'), '2026-12-04');
  assert.equal(P('lari hari minggu'), '2026-11-29');
  assert.equal(P('rencana minggu depan'), '');
  assert.equal(P('rencana minggu ini'), '');
  assert.equal(P('move gym from friday to saturday'), '2026-11-27,2026-11-28');
  assert.equal(P('Meeting at 3pm for 1h'), '');
  assert.equal(P('call at 15:30 for 45 min'), '');
  assert.equal(P('31 nov'), '');
  assert.equal(P('besok dan 29 nov'), '2026-11-25,2026-11-29');
  assert.equal(parseDateRefs('exam 3 Jan', ymd(2026, 12, 28)).map(isoDate).join(), '2027-01-03');
  assert.equal(parseDateRefs('exam January 3 2028', ymd(2026, 12, 28)).map(isoDate).join(), '2028-01-03');
  assert.equal(parseDateRefs('exam January 3, 2028', today).map(isoDate).join(), '2028-01-03');
  assert.equal(parseDateRefs('exam 3 Jan, 2028', today).map(isoDate).join(), '2028-01-03');
  assert.equal(parseDateRefs('tugas tanggal 5', ymd(2026, 12, 20)).map(isoDate).join(), '2027-01-05');
});

test('client clocks win and timezone fallbacks stay compatible', () => {
  const dated = clientToday({ date: '2026-11-24', now: '845' });
  assert.equal(isoDate(dated.today), '2026-11-24');
  assert.equal(dated.now, 845);

  const server = new Date(Date.UTC(2026, 10, 24, 20, 30));
  const jakarta = clientToday({ tz_offset: '420' }, server);
  assert.equal(isoDate(jakarta.today), '2026-11-25');
  assert.equal(jakarta.now, 210);

  const legacy = clientToday({ day: '4', now: '845', tz_offset: '420' }, server);
  assert.equal(isoDate(legacy.today), '2026-11-27');
  assert.equal(legacy.now, 845);

  const namedZone = clientToday({ tz: 'Asia/Jakarta' }, server);
  assert.equal(isoDate(namedZone.today), '2026-11-25');
  assert.equal(namedZone.now, 210);

  const utc = clientToday({}, server);
  assert.equal(isoDate(utc.today), '2026-11-24');
  assert.equal(utc.now, 1230);
  assert.equal(isoDate(clientToday({ date: 'nope', now: 'x' }, server).today), '2026-11-24');
});

test('deadline due dates normalize without discarding legacy text', () => {
  assert.equal(normaliseDue('2026-11-27', today), '2026-11-27');
  assert.equal(normaliseDue('Friday', today), '2026-11-27');
  assert.equal(normaliseDue('30 Nov', today), '2026-11-30');
  assert.equal(normaliseDue('whenever', today), 'whenever');
  assert.equal(normaliseDue(null, today), 'TBD');
  assert.equal(dueWithinADay('2026-11-25', today), true);
  assert.equal(dueWithinADay('2026-11-27', today), false);
  assert.equal(dueWithinADay('Tomorrow', today), null);
});
