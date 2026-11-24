import 'dart:convert';

import 'package:chrono/data/models.dart';
import 'package:chrono/logic/chrono_engine.dart';
import 'package:chrono/logic/dates.dart';
import 'package:chrono/logic/suggestions.dart';
import 'package:chrono/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void useTuesday() => appClock = () => DateTime(2026, 11, 24, 14, 5);

AddChange? firstAdd(Reply r) => r.changes.whereType<AddChange>().firstOrNull;

Deadline deadline(
  String id,
  String due, {
  bool done = false,
  bool urgent = false,
  int planned = 0,
}) => Deadline(
  id: id,
  title: 'Essay',
  course: 'English',
  estimate: 180,
  due: due,
  urgent: urgent,
  planned: planned,
  done: done,
);

void main() {
  tearDown(() => appClock = DateTime.now);

  group('the app uses the real calendar', () {
    test('week, today and now come from the clock', () {
      useTuesday();
      expect(today, 1);
      expect(now, 14 * 60 + 5);
      expect(days.map((d) => d.date).toList(), [23, 24, 25, 26, 27, 28, 29]);
      expect(days[1].month, 'NOV');
    });

    test('the week rolls over month boundaries', () {
      appClock = () => DateTime(2026, 12, 31, 10);
      expect(days[0].date, 28);
      expect(days[4].date, 1);
      expect(days[4].month, 'JAN');
    });

    test('deadline labels and urgency follow real dates', () {
      useTuesday();
      final items = [
        deadline('today', '2026-11-24'),
        deadline('tomorrow', '2026-11-25'),
        deadline('friday', '2026-11-27'),
        deadline('next-monday', '2026-11-30'),
        deadline('later', '2026-12-08'),
        deadline('past', '2026-11-23'),
        deadline('done', '2026-11-25', done: true),
      ];
      expect(items.map((d) => d.dueLabel).toList(), [
        'Today',
        'Tomorrow',
        'Fri',
        'Next Mon',
        '8 Dec',
        'Overdue',
        'Tomorrow',
      ]);
      expect(items.map((d) => d.isUrgent).toList(), [
        true,
        true,
        false,
        false,
        false,
        true,
        false,
      ]);
    });
  });

  group('a date in the message decides the day', () {
    test('no date means today', () {
      useTuesday();
      final r = respond('Meeting at 4pm for 1h', [], []);
      expect(firstAdd(r)?.block.day, 1);
    });

    test('weekday, day and month, Indonesian tanggal and besok resolve', () {
      useTuesday();
      expect(
        firstAdd(respond('Meeting Friday at 3pm for 1h', [], []))?.block.day,
        4,
      );
      expect(
        firstAdd(
          respond('Study group 28 Nov at 10am for 2h', [], []),
        )?.block.day,
        5,
      );
      expect(
        firstAdd(respond('Rapat besok jam 10 selama 1 jam', [], []))?.block.day,
        2,
      );
      final b = firstAdd(
        respond('tambah rapat tanggal 27 jam 3 selama 2 jam', [], []),
      )!.block;
      expect([b.day, b.start, b.length, b.title], [4, 15 * 60, 120, 'Rapat']);
    });

    test('a date beyond this week is refused', () {
      useTuesday();
      final r = respond('Meeting 3 Dec at 3pm', [], []);
      expect(r.changes, isEmpty);
    });

    test('a past date and a block crossing midnight are refused', () {
      useTuesday();
      expect(respond('Meeting 2026-11-23 at 3pm', [], []).changes, isEmpty);
      expect(respond('Meeting at 10am for 1h', [], []).changes, isEmpty);
      expect(respond('Meeting at 11pm for 2h', [], []).changes, isEmpty);
    });

    test('plan and move refuse past targets', () {
      useTuesday();
      final blocks = [
        const Block(
          id: 'gym',
          day: 1,
          title: 'Gym',
          kind: Kind.personal,
          start: 540,
          end: 600,
        ),
      ];
      expect(
        respond('Plan time for Essay 2026-11-23', blocks, [
          deadline('essay', '2026-11-27'),
        ]).changes,
        isEmpty,
      );
      expect(respond('Move gym to today at 10am', blocks, []).changes, isEmpty);
    });

    test('a move uses the destination after from', () {
      useTuesday();
      final blocks = [
        const Block(
          id: 'gym-fri',
          day: 4,
          title: 'Gym',
          kind: Kind.personal,
          start: 900,
          end: 960,
        ),
        const Block(
          id: 'gym-tue',
          day: 1,
          title: 'Gym',
          kind: Kind.personal,
          start: 900,
          end: 960,
        ),
      ];
      final r = respond('Move gym from Friday 3pm to Saturday 4pm', blocks, []);
      final change = r.changes.single as MoveChange;
      expect(change.blockId, 'gym-fri');
      expect(change.to.day, 5);
      expect(change.to.start, 16 * 60);
    });

    test('Sunday has no tomorrow inside the week', () {
      appClock = () => DateTime(2026, 11, 29, 9);
      final r = respond('Meeting tomorrow at 3pm', [], []);
      expect(r.changes, isEmpty);
      expect(dayName(7), 'Day 7');
    });
  });

  group('deadlines follow the calendar', () {
    test('a deadline said in chat gets a real date and an early session', () {
      useTuesday();
      final r = respond('Essay due Friday, 3h', [], []);
      expect(r.deadline?.due, '2026-11-27');
      expect(r.deadline?.estimate, 180);
      final day = firstAdd(r)!.block.day;
      expect(day >= 2 && day <= 4, isTrue);
      expect(firstAdd(r)?.block.title, 'Essay');
    });

    test('Indonesian deadline wording resolves the date and estimate', () {
      useTuesday();
      final d = respond(
        'Tugas UX deadline tanggal 30 nov, 2 jam',
        [],
        [],
      ).deadline!;
      expect([d.title, d.due, d.estimate], ['Tugas UX', '2026-11-30', 120]);
    });

    test('an existing deadline is updated instead of duplicated', () {
      useTuesday();
      final existing = deadline('dl-1', '2026-11-30');
      final r = respond('Essay due Friday, 3h', [], [existing]);
      expect(r.deadline?.id, 'dl-1');
      expect(r.deadline?.due, '2026-11-27');
    });

    test('progress comes from blocks and ignores classes', () {
      useTuesday();
      final d = deadline('dl-1', '2026-11-27', urgent: false);
      final blocks = [
        const Block(
          id: 'focus',
          day: 2,
          title: 'Essay',
          kind: Kind.focus,
          start: 540,
          end: 630,
        ),
        const Block(
          id: 'chapter',
          day: 3,
          title: 'Essay chapter',
          kind: Kind.task,
          start: 540,
          end: 600,
        ),
        const Block(
          id: 'class',
          day: 4,
          title: 'Essay lecture',
          kind: Kind.lecture,
          start: 540,
          end: 660,
        ),
      ];
      expect(d.planned, 0);
      expect(d.plannedFor(blocks), 90);
      expect(d.plannedFor([blocks.first]), 90);
      expect(d.plannedFor([]), 0);
    });

    test('suggestions use live progress rather than the stored counter', () {
      useTuesday();
      final d = deadline('dl-1', '2026-11-27', planned: 180);
      final blocks = [
        const Block(
          id: 'focus',
          day: 1,
          title: 'Essay',
          kind: Kind.focus,
          start: 60,
          end: 120,
        ),
      ];
      final prompts = suggestPrompts(
        blocks: blocks,
        deadlines: [d],
        focusWindow: 'morning',
        bedtime: '23:00',
        day: today,
        now: 0,
      );
      expect(prompts, contains('Plan time for Essay'));
    });
  });

  group('date parsing and API clock', () {
    List<String> p(String s) =>
        parseDateRefs(s, DateTime(2026, 11, 24)).map(isoDate).toList();

    test(
      'English and Indonesian references resolve without clock false positives',
      () {
        expect(p('Meeting 27 Nov at 3pm'), ['2026-11-27']);
        expect(p("rapat jum'at jam 3"), ['2026-11-27']);
        expect(p('kumpul senin depan'), ['2026-11-30']);
        expect(p('rencana minggu depan'), isEmpty);
        expect(p('move gym from friday to saturday'), [
          '2026-11-27',
          '2026-11-28',
        ]);
        expect(p('call at 15:30 for 45 min'), isEmpty);
        expect(p('January 3 2028'), ['2028-01-03']);
        expect(p('January 3, 2028'), ['2028-01-03']);
        expect(p('3 Jan, 2028'), ['2028-01-03']);
      },
    );

    test(
      'chat sends the real date, clock, timezone and selected day',
      () async {
        useTuesday();
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'ai_message': {'id': 'ai-1', 'content': 'ok'},
              'proposal': null,
              'new_deadline': null,
            }),
            200,
            headers: {'Content-Type': 'application/json'},
          );
        });
        final api = ChronoApi(baseUrl: 'http://localhost:3000', client: client);
        final reply = await api.chat('Meeting Friday at 3pm', viewDay: 4);
        expect(reply.text, 'ok');
        expect(captured?.url.queryParameters['date'], '2026-11-24');
        expect(captured?.url.queryParameters['now'], '845');
        expect(captured?.url.queryParameters['view_day'], '4');
        expect(captured?.url.queryParameters['tz_offset'], isNotEmpty);
        client.close();
      },
    );
  });
}
