import 'package:chrono/data/models.dart';
import 'package:chrono/logic/suggestions.dart';
import 'package:chrono/main.dart';
import 'package:chrono/services/api_client.dart';
import 'package:chrono/screens/home.dart';
import 'package:chrono/screens/onboarding.dart';
import 'package:chrono/state/app_state.dart';
import 'package:chrono/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal host so a single screen can be mounted without the tab shell.
Widget host(AppState state, Widget child) => AppScope(
      state: state,
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: C.bg),
        home: Scaffold(body: child),
      ),
    );

const _emptySnapshot = Snapshot(
  email: 'student@example.com',
  name: 'Student',
  prefsFocus: 'morning',
  bedtime: '23:00',
  breakMin: 15,
  onboardingComplete: true,
  courses: [],
  blocks: [],
  deadlines: [],
  messages: [],
);

class _FakeApi extends ChronoApi {
  _FakeApi(this.snapshot);

  final Snapshot snapshot;
  bool restoreCalled = false;
  int pulls = 0;
  int pushes = 0;

  @override
  Future<bool> restoreSession() async {
    restoreCalled = true;
    return true;
  }

  @override
  Future<Snapshot> me() async {
    pulls++;
    return snapshot;
  }

  @override
  Future<Snapshot> saveOnboarding({
    required String focus,
    required String bedtime,
    required int breakMin,
    required List<Course> courses,
    required List<Block> flexBlocks,
    required List<Deadline> deadlines,
  }) async {
    pushes++;
    return snapshot;
  }
}

void main() {
  testWidgets('app builds on the welcome screen', (tester) async {
    await tester.pumpWidget(ChronoApp(state: AppState()));
    expect(find.byType(ChronoApp), findsOneWidget);
  });

  testWidgets('Welcome has no example schedule data', (tester) async {
    await tester.pumpWidget(host(AppState(), const WelcomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Data Structures'), findsNothing);
    expect(find.text('Quiz prep'), findsNothing);
    expect(find.text('Org meeting'), findsNothing);
    expect(find.text('HCI essay'), findsNothing);
  });

  test('a fresh state starts empty, with no demo schedule', () {
    final state = AppState();
    expect(state.courses, isEmpty);
    expect(state.blocks, isEmpty);
    expect(state.deadlines, isEmpty);
  });

  test('offline preference edits stay pending', () {
    final state = AppState()
      ..online = false
      ..stage = Stage.app;
    state.setPrefs(focus: FocusWindow.evening);

    expect(state.pendingChanges, isTrue);
    expect(state.prefs.focus, FocusWindow.evening);
  });

  test('manual sync reconnects and pushes pending edits', () async {
    final api = _FakeApi(_emptySnapshot);
    final state = AppState(api: api)
      ..online = false
      ..stage = Stage.app
      ..pendingChanges = true;

    await state.syncNow();

    expect(api.restoreCalled, isTrue);
    expect(api.pulls, 1);
    expect(api.pushes, 1);
    expect(state.online, isTrue);
    expect(state.pendingChanges, isFalse);
    expect(state.toast?.text, 'Synced with the server');
  });

  test('sync adopts an empty course list', () async {
    final api = _FakeApi(_emptySnapshot);
    final state = AppState(api: api)
      ..online = true
      ..stage = Stage.app
      ..courses = [
        const Course(id: 'old', name: 'Old course', days: [0], start: 480, end: 540, room: ''),
      ];

    await state.syncNow();

    expect(state.courses, isEmpty);
  });

  test('the clock follows the real calendar, not a fixed demo date', () {
    final real = DateTime.now();
    expect(today, real.weekday - 1);
    expect(now, real.hour * 60 + real.minute);
    expect(days.length, 7);
    expect(days[today].long, isNotEmpty);
  });

  test('prompts follow the schedule; nothing invented when it is empty', () {
    final empty = suggestPrompts(
      blocks: const [],
      deadlines: const [],
      focusWindow: 'morning',
      bedtime: '23:00',
      day: today,
      now: now,
    );
    expect(empty, isNot(contains('Skip algorithm quiz prep today')));

    final block = Block(
      id: 'quiz',
      day: today,
      title: 'Algorithm quiz prep',
      kind: Kind.focus,
      start: 60,
      end: 120,
    );
    final withBlock = suggestPrompts(
      blocks: [block],
      deadlines: const [],
      focusWindow: 'morning',
      bedtime: '23:00',
      day: today,
      now: 0,
    );
    expect(withBlock, contains('Skip algorithm quiz prep today'));
  });

  testWidgets('Home shows a sync button and the real greeting', (tester) async {
    final state = AppState()..userName = 'Nadia';
    state.stage = Stage.app;
    await tester.pumpWidget(host(state, const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sync now'), findsOneWidget);
    expect(find.textContaining('Nadia'), findsWidgets);
    expect(find.textContaining('Good '), findsWidgets);
  });

  testWidgets('Home keeps the sync button visible for pending changes', (tester) async {
    final state = AppState()
      ..stage = Stage.app
      ..pendingChanges = true;
    await tester.pumpWidget(host(state, const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Unsynced changes · tap to sync'), findsOneWidget);
  });

  testWidgets('work preferences offer more than three choices', (tester) async {
    final state = AppState();
    await tester.pumpWidget(host(state, const SingleChildScrollView(child: WorkPrefsFields())));
    await tester.pumpAndSettle();

    expect(find.text('Evening'), findsOneWidget);
    expect(find.text('21:00'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
  });

  testWidgets('picking a preference stores it', (tester) async {
    final state = AppState();
    await tester.pumpWidget(host(state, const SingleChildScrollView(child: WorkPrefsFields())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Evening'));
    await tester.pumpAndSettle();
    expect(state.prefs.focus, FocusWindow.evening);

    await tester.tap(find.text('45 min'));
    await tester.pumpAndSettle();
    expect(state.prefs.breakMin, 45);
  });
}
