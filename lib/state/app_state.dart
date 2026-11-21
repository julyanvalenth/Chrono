import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../logic/chrono_engine.dart';

enum Stage { welcome, source, prefs, building, app }

enum AppTab { home, today, chat, deadlines }

enum FocusWindow { morning, afternoon, night }

enum ProposalStatus { pending, applied, dismissed }

sealed class ChatMessage {
  const ChatMessage(this.id);
  final String id;
}

class TextMessage extends ChatMessage {
  const TextMessage(super.id, {required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

class ProposalMessage extends ChatMessage {
  const ProposalMessage(super.id, {required this.changes, this.status = ProposalStatus.pending, this.deadlineId});
  final List<Change> changes;
  final ProposalStatus status;
  final String? deadlineId;

  ProposalMessage withStatus(ProposalStatus s) => ProposalMessage(id, changes: changes, status: s, deadlineId: deadlineId);
}

class ToastData {
  const ToastData(this.id, this.text, {this.undoBlocks, this.undoDeadlines, this.focusIds = const []});
  final int id;
  final String text;
  final List<Block>? undoBlocks;
  final List<Deadline>? undoDeadlines;
  final List<String> focusIds;
  bool get canUndo => undoBlocks != null;
}

class Prefs {
  const Prefs({this.focus = FocusWindow.morning, this.bedtime = '23:00', this.breakMin = 15});
  final FocusWindow focus;
  final String bedtime;
  final int breakMin;
}

const _greeting = TextMessage(
  'hello',
  fromUser: false,
  text: 'Morning, Nadia. Two classes and three focus blocks today.\nTell me what changed — I’ll rearrange the rest.',
);

/// All app state lives here; widgets read it through [AppScope].
class AppState extends ChangeNotifier {
  AppState() {
    reset(notify: false);
  }

  late Stage stage;
  late AppTab tab;
  late List<Course> courses;
  late Prefs prefs;
  late List<Block> blocks;
  late List<Deadline> deadlines;
  late List<ChatMessage> messages;
  late bool thinking;
  late int selectedDay;
  String? sheetId;
  ToastData? toast;
  String? scrollTo;

  int _msgId = 0;
  int _toastId = 0;

  void reset({bool notify = true}) {
    stage = Stage.welcome;
    tab = AppTab.home;
    courses = [...seedCourses];
    prefs = const Prefs();
    blocks = [...classBlocks(courses), ...seedFlexBlocks];
    deadlines = [...seedDeadlines];
    messages = [_greeting];
    thinking = false;
    selectedDay = today;
    sheetId = null;
    toast = null;
    scrollTo = null;
    if (notify) notifyListeners();
  }

  void _set(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  // ---- navigation ----
  void goStage(Stage s) => _set(() => stage = s);

  void goTab(AppTab t) => _set(() {
        if (t == AppTab.today && tab != AppTab.today) selectedDay = today;
        tab = t;
        sheetId = null;
      });

  void selectDay(int d) => _set(() => selectedDay = d);

  void showBlock(String id, {int? day}) => _set(() {
        stage = Stage.app;
        tab = AppTab.today;
        selectedDay = day ?? blocks.firstWhere((b) => b.id == id, orElse: () => blocks.first).day;
        sheetId = id;
      });

  void viewInTimeline(String id, int day) => _set(() {
        tab = AppTab.today;
        selectedDay = day;
        scrollTo = id;
      });

  void scrolled() => scrollTo = null;

  // ---- onboarding ----
  void toggleCourse(String id) =>
      _set(() => courses = [for (final c in courses) c.id == id ? c.toggled() : c]);

  void setPrefs({FocusWindow? focus, String? bedtime, int? breakMin}) => _set(() {
        prefs = Prefs(
          focus: focus ?? prefs.focus,
          bedtime: bedtime ?? prefs.bedtime,
          breakMin: breakMin ?? prefs.breakMin,
        );
      });

  void finishOnboarding() => _set(() {
        stage = Stage.app;
        tab = AppTab.home;
        blocks = [...classBlocks(courses), ...seedFlexBlocks];
      });

  // ---- blocks ----
  void openSheet(String? id) => _set(() => sheetId = id);

  Block? get sheetBlock => sheetId == null ? null : blocks.where((b) => b.id == sheetId).firstOrNull;

  ToastData _toast(String text, {List<String> focus = const []}) =>
      ToastData(++_toastId, text, undoBlocks: blocks, undoDeadlines: deadlines, focusIds: focus);

  void markDone(String id) => _set(() {
        final b = blocks.firstWhere((x) => x.id == id);
        toast = _toast(b.done ? '${b.title} reopened' : '${b.title} marked done');
        blocks = [for (final x in blocks) x.id == id ? x.copyWith(done: !x.done) : x];
        sheetId = null;
      });

  void push(String id, int minutes) => _set(() {
        final b = blocks.firstWhere((x) => x.id == id);
        toast = _toast('${b.title} pushed $minutes min', focus: [id]);
        blocks = [
          for (final x in blocks)
            x.id == id
                ? x.copyWith(start: x.start + minutes, end: x.end + minutes, origin: Origin.moved)
                : x.copyWith(clearOrigin: true),
        ];
        sheetId = null;
      });

  void remove(String id) => _set(() {
        final b = blocks.firstWhere((x) => x.id == id);
        toast = _toast('${b.title} removed');
        blocks = blocks.where((x) => x.id != id).toList();
        sheetId = null;
      });

  // ---- chat ----
  void send(String text) {
    final clean = text.trim();
    if (clean.isEmpty || thinking) return;
    _set(() {
      messages = [...messages, TextMessage('m${++_msgId}', fromUser: true, text: clean)];
      thinking = true;
    });
    Timer(const Duration(milliseconds: 900), () {
      final r = respond(clean, blocks, deadlines);
      _set(() {
        thinking = false;
        messages = [
          ...messages,
          TextMessage('m${++_msgId}', fromUser: false, text: r.text),
          if (r.changes.isNotEmpty) ProposalMessage('m${++_msgId}', changes: r.changes, deadlineId: r.deadlineId),
        ];
        if (r.deadline != null) deadlines = [...deadlines, r.deadline!];
      });
    });
  }

  void decide(String messageId, ProposalStatus decision) {
    final p = messages.whereType<ProposalMessage>().where((m) => m.id == messageId).firstOrNull;
    if (p == null || p.status != ProposalStatus.pending) return;
    _set(() {
      messages = [for (final m in messages) m.id == messageId ? p.withStatus(decision) : m];
      if (decision == ProposalStatus.dismissed) return;
      final added = p.changes.whereType<AddChange>().fold(0, (s, c) => s + c.block.length);
      final n = p.changes.length;
      toast = _toast('Schedule updated · $n change${n > 1 ? 's' : ''}', focus: [for (final c in p.changes) c.targetId]);
      blocks = applyChanges(blocks, p.changes);
      if (p.deadlineId != null) {
        deadlines = [for (final d in deadlines) d.id == p.deadlineId ? d.copyWith(planned: d.planned + added) : d];
      }
    });
  }

  // ---- deadlines ----
  void toggleDeadline(String id) =>
      _set(() => deadlines = [for (final d in deadlines) d.id == id ? d.copyWith(done: !d.done) : d]);

  // ---- toast ----
  void undo() => _set(() {
        final t = toast;
        if (t == null || !t.canUndo) return;
        blocks = t.undoBlocks!;
        deadlines = t.undoDeadlines!;
        toast = ToastData(++_toastId, 'Change undone');
      });

  void dismissToast(int id) {
    if (toast?.id != id) return;
    _set(() => toast = null);
  }

  /// Jump straight to a screen (used by the demo menu).
  void jump({Stage? stage, AppTab? tab, int? day, String? sheet}) => _set(() {
        if (stage != null) this.stage = stage;
        if (tab != null) this.tab = tab;
        if (day != null) selectedDay = day;
        sheetId = sheet;
      });
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to changes (for callbacks).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
