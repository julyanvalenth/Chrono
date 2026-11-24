import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../logic/chrono_engine.dart';
import '../services/api_client.dart';

enum Stage { welcome, auth, source, prefs, building, app }

enum AuthMode { signUp, logIn }

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
  const ProposalMessage(super.id, {required this.changes, this.status = ProposalStatus.pending, this.deadlineId, this.remote = false});
  final List<Change> changes;
  final ProposalStatus status;
  final String? deadlineId;

  /// true when the proposal came from the backend (apply/dismiss go through the API).
  final bool remote;

  ProposalMessage withStatus(ProposalStatus s, {List<Change>? changes}) =>
      ProposalMessage(id, changes: changes ?? this.changes, status: s, deadlineId: deadlineId, remote: remote);
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


/// All app state lives here; widgets read it through [AppScope].
///
/// When [online] the app talks to chrono-backend (Supabase for data, Gemini
/// for chat). Local state is updated first so the UI stays instant, then the
/// change is saved to the server. When the backend can't be reached the app
/// falls back to the built-in rule-based engine, like the original demo.
class AppState extends ChangeNotifier {
  AppState({ChronoApi? api}) : api = api ?? ChronoApi() {
    reset(notify: false);
    _startClock();
  }

  Timer? _clock;

  /// Redraw on every new minute so "now" (the now line, "Happening now",
  /// minutes left, the greeting and the date) follows the real clock.
  void _startClock() {
    final n = DateTime.now();
    _clock = Timer(Duration(seconds: 60 - n.second, milliseconds: -n.millisecond), () {
      notifyListeners();
      _clock = Timer.periodic(const Duration(minutes: 1), (_) => notifyListeners());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  final ChronoApi api;

  /// Signed in to chrono-backend and reachable.
  bool online = false;
  String? connectionError;

  /// The saved session couldn't be checked because the server was unreachable.
  bool bootFailed = false;

  AuthMode authMode = AuthMode.signUp;
  String userName = 'Student';
  String userEmail = '';

  String get firstName => userName.trim().split(RegExp(r'\s+')).first;

  TextMessage get _greeting => TextMessage(
        'hello',
        fromUser: false,
        text: 'Hi $firstName. Tell me what changed today — a meeting, a new deadline, feeling sick — '
            'and I’ll rearrange the rest.',
      );

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
    // A new user starts empty: their classes come from the timetable they scan or type.
    courses = [];
    prefs = const Prefs();
    blocks = [];
    deadlines = [];
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

  // ---- backend ----

  /// True while [connect] runs; the shell shows the logo loading screen.
  bool booting = false;

  /// Restore the saved login and load the schedule. Safe to call again to retry.
  Future<void> connect() async {
    booting = true;
    bootFailed = false;
    notifyListeners();
    api.onSessionExpired = _sessionExpired;
    // Don't hold the user on the loading screen if the server is slow.
    final giveUp = Timer(const Duration(seconds: 8), () {
      if (booting) _set(() => booting = false);
    });
    try {
      if (!await api.restoreSession()) return; // not logged in → Welcome
      final snap = await api.me();
      _set(() {
        online = true;
        connectionError = null;
        _adoptUser(snap);
        if (snap.onboardingComplete) {
          _adopt(snap);
        } else {
          messages = [_greeting];
          stage = Stage.source;
        }
      });
      debugPrint('Chrono: connected to ${api.baseUrl} as $userEmail');
    } catch (e) {
      _set(() {
        online = false;
        connectionError = '$e';
        // Logged in but the server can't be reached: offer a retry instead of a broken app.
        bootFailed = api.hasSession;
      });
      debugPrint('Chrono: offline (${api.baseUrl}): $e');
    } finally {
      giveUp.cancel();
      if (booting) _set(() => booting = false);
    }
  }

  void _adoptUser(Snapshot snap) {
    userName = snap.name;
    userEmail = snap.email;
  }

  // ---- account ----

  void showAuth(AuthMode mode) => _set(() {
        authMode = mode;
        stage = Stage.auth;
      });

  /// Create an account. Returns an error message to show, or null on success.
  Future<String?> signUp({required String name, required String email, required String password}) =>
      _authenticate(() => api.signUp(name: name, email: email, password: password));

  /// Log in. Returns an error message to show, or null on success.
  Future<String?> logIn({required String email, required String password}) =>
      _authenticate(() => api.logIn(email: email, password: password));

  Future<String?> _authenticate(Future<void> Function() call) async {
    try {
      await call();
      final snap = await api.me();
      _set(() {
        reset(notify: false);
        online = true;
        bootFailed = false;
        _adoptUser(snap);
        messages = [_greeting];
        if (snap.onboardingComplete) {
          _adopt(snap);
        } else {
          stage = Stage.source;
        }
      });
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('Chrono auth failed: $e');
      return 'Couldn’t reach Chrono. Check your connection and try again.';
    }
  }

  Future<void> logOut() async {
    await api.logOut();
    _set(() {
      reset(notify: false);
      online = false;
      userName = 'Student';
      userEmail = '';
    });
  }

  void _sessionExpired() => _set(() {
        reset(notify: false);
        online = false;
        authMode = AuthMode.logIn;
        stage = Stage.auth;
        toast = ToastData(++_toastId, 'Session expired · please log in again');
      });

  /// Change the display name (profile).
  void setName(String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean == userName) return;
    _set(() => userName = clean);
    _sync(() => api.updatePreferences(name: clean));
  }

  void _adopt(Snapshot snap) {
    if (snap.courses.isNotEmpty) courses = snap.courses;
    blocks = snap.blocks;
    deadlines = snap.deadlines;
    prefs = Prefs(
      focus: FocusWindow.values.firstWhere((f) => f.name == snap.prefsFocus, orElse: () => FocusWindow.morning),
      bedtime: snap.bedtime,
      breakMin: snap.breakMin,
    );
    messages = [
      _greeting,
      for (final m in snap.messages) ?_messageFromJson(m),
    ];
    stage = Stage.app;
  }

  ChatMessage? _messageFromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    if (j['type'] == 'proposal') {
      return ProposalMessage(
        id,
        changes: changesFromJson((j['changes'] as List?) ?? const [], id),
        status: ProposalStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => ProposalStatus.pending),
        deadlineId: j['deadline_id'] as String?,
        remote: true,
      );
    }
    final text = j['content'] as String?;
    if (text == null) return null;
    return TextMessage(id, fromUser: j['from_user'] == true, text: text);
  }

  /// Run a server call in the background; local state is already updated.
  void _sync(Future<void> Function() call) {
    if (!online) return;
    call().catchError((Object e) {
      debugPrint('Chrono sync failed: $e');
      _set(() => toast = ToastData(++_toastId, 'Couldn’t save to server'));
    });
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

  /// Read a class timetable with the AI (photo/screenshot or typed text) and use
  /// the result as this user's courses. Returns a message to show when nothing
  /// usable came back, or null on success.
  Future<String?> readSchedule({String? text, Uint8List? image, String mimeType = 'image/jpeg'}) async {
    if (!online) return 'Couldn’t reach Chrono. Check your connection and try again.';
    try {
      final r = await api.parseSchedule(text: text, image: image, mimeType: mimeType);
      if (r.courses.isEmpty) {
        return r.note.isNotEmpty ? r.note : 'No classes found. Try a clearer photo or type them in.';
      }
      _set(() => courses = r.courses);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('Chrono schedule read failed: $e');
      return 'Couldn’t reach Chrono. Check your connection and try again.';
    }
  }

  void setPrefs({FocusWindow? focus, String? bedtime, int? breakMin}) {
    _set(() {
      prefs = Prefs(
        focus: focus ?? prefs.focus,
        bedtime: bedtime ?? prefs.bedtime,
        breakMin: breakMin ?? prefs.breakMin,
      );
    });
    // During onboarding they are saved with the rest at the end; afterwards (profile) right away.
    if (stage == Stage.app) {
      _sync(() => api.updatePreferences(focus: focus?.name, bedtime: bedtime, breakMin: breakMin));
    }
  }

  void finishOnboarding() {
    // Only the user's own classes. Focus blocks, tasks and deadlines are added
    // later by the user (chat, or "Plan with Chrono").
    final lectures = classBlocks(courses);
    _set(() {
      stage = Stage.app;
      tab = AppTab.home;
      blocks = lectures;
      deadlines = [];
    });
    if (!online) return;
    api
        .saveOnboarding(
          focus: prefs.focus.name,
          bedtime: prefs.bedtime,
          breakMin: prefs.breakMin,
          courses: courses,
          flexBlocks: const [],
          deadlines: const [],
        )
        .then((snap) => _set(() {
              // Server copies carry real (uuid) ids from here on.
              courses = snap.courses;
              blocks = snap.blocks;
              deadlines = snap.deadlines;
              sheetId = null;
            }))
        .catchError((Object e) {
      debugPrint('Chrono onboarding sync failed: $e');
      _set(() {
        online = false;
        toast = ToastData(++_toastId, 'Server unavailable · working offline');
      });
    });
  }

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
        _sync(() => api.toggleDone(id));
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
        _sync(() => api.pushBlock(id, minutes));
      });

  void remove(String id) => _set(() {
        final b = blocks.firstWhere((x) => x.id == id);
        toast = _toast('${b.title} removed');
        blocks = blocks.where((x) => x.id != id).toList();
        sheetId = null;
        _sync(() => api.deleteBlock(id));
      });

  // ---- chat ----
  void send(String text) {
    final clean = text.trim();
    if (clean.isEmpty || thinking) return;
    _set(() {
      messages = [...messages, TextMessage('m${++_msgId}', fromUser: true, text: clean)];
      thinking = true;
    });
    if (online) {
      _sendRemote(clean);
    } else {
      Timer(const Duration(milliseconds: 900), () => _replyLocally(clean));
    }
  }

  /// Ask Gemini through the backend. The server uses its real clock in the
  /// user's timezone, the same "now" the UI shows.
  Future<void> _sendRemote(String text) async {
    try {
      final r = await api.chat(text);
      _set(() {
        thinking = false;
        messages = [
          ...messages,
          TextMessage(r.aiId, fromUser: false, text: r.text),
          if (r.proposalId != null && r.changes.isNotEmpty)
            ProposalMessage(r.proposalId!, changes: r.changes, deadlineId: r.deadlineId, remote: true),
        ];
        if (r.newDeadline != null) deadlines = [...deadlines, r.newDeadline!];
      });
    } catch (e) {
      debugPrint('Chrono chat failed, answering offline: $e');
      _replyLocally(text, offline: true);
    }
  }

  void _replyLocally(String clean, {bool offline = false}) {
    final r = respond(clean, blocks, deadlines);
    _set(() {
      thinking = false;
      messages = [
        ...messages,
        TextMessage('m${++_msgId}', fromUser: false, text: r.text),
        if (r.changes.isNotEmpty) ProposalMessage('m${++_msgId}', changes: r.changes, deadlineId: r.deadlineId),
      ];
      if (r.deadline != null) deadlines = [...deadlines, r.deadline!];
      if (offline) toast = ToastData(++_toastId, 'Server unreachable · offline reply');
    });
  }

  void decide(String messageId, ProposalStatus decision) {
    final p = messages.whereType<ProposalMessage>().where((m) => m.id == messageId).firstOrNull;
    if (p == null || p.status != ProposalStatus.pending) return;
    _set(() {
      messages = [for (final m in messages) m.id == messageId ? p.withStatus(decision) : m];
      if (decision == ProposalStatus.dismissed) {
        if (p.remote) _sync(() => api.dismiss(p.id));
        return;
      }
      final added = p.changes.whereType<AddChange>().fold(0, (s, c) => s + c.block.length);
      final n = p.changes.length;
      toast = _toast('Schedule updated · $n change${n > 1 ? 's' : ''}', focus: [for (final c in p.changes) c.targetId]);
      blocks = applyChanges(blocks, p.changes);
      if (p.deadlineId != null) {
        deadlines = [for (final d in deadlines) d.id == p.deadlineId ? d.copyWith(planned: d.planned + added) : d];
      }
      if (p.remote) {
        _applyRemote(p);
      } else {
        // Offline-engine proposal while online: save the resulting schedule.
        _sync(() async {
          final server = await api.replaceBlocks(blocks);
          _set(() => blocks = server);
        });
      }
    });
  }

  Future<void> _applyRemote(ProposalMessage p) async {
    if (!online) return;
    try {
      final r = await api.apply(p.id);
      // Swap the temporary ids of added blocks for the ones the server made.
      final tempIds = [for (final c in p.changes.whereType<AddChange>()) c.block.id];
      final idMap = {
        for (var i = 0; i < tempIds.length && i < r.addedIds.length; i++) tempIds[i]: r.addedIds[i],
      };
      final fixed = [
        for (final c in p.changes)
          if (c is AddChange && idMap.containsKey(c.block.id)) AddChange(_withId(c.block, idMap[c.block.id]!)) else c,
      ];
      _set(() {
        blocks = r.blocks;
        deadlines = r.deadlines;
        messages = [for (final m in messages) m.id == p.id ? p.withStatus(ProposalStatus.applied, changes: fixed) : m];
        final t = toast;
        if (t != null && t.focusIds.any(idMap.containsKey)) {
          toast = ToastData(t.id, t.text,
              undoBlocks: t.undoBlocks,
              undoDeadlines: t.undoDeadlines,
              focusIds: [for (final f in t.focusIds) idMap[f] ?? f]);
        }
      });
    } catch (e) {
      debugPrint('Chrono apply failed: $e');
      _set(() => toast = ToastData(++_toastId, 'Couldn’t save to server'));
    }
  }

  Block _withId(Block b, String id) => Block(
        id: id,
        day: b.day,
        title: b.title,
        kind: b.kind,
        start: b.start,
        end: b.end,
        detail: b.detail,
        origin: b.origin,
        done: b.done,
        courseId: b.courseId,
      );

  // ---- deadlines ----
  void toggleDeadline(String id) => _set(() {
        deadlines = [for (final d in deadlines) d.id == id ? d.copyWith(done: !d.done) : d];
        _sync(() => api.toggleDeadline(id));
      });

  // ---- toast ----
  void undo() => _set(() {
        final t = toast;
        if (t == null || !t.canUndo) return;
        blocks = t.undoBlocks!;
        deadlines = t.undoDeadlines!;
        toast = ToastData(++_toastId, 'Change undone');
        final b = blocks, d = deadlines;
        _sync(() async {
          await api.replaceBlocks(b);
          await api.replaceDeadlines(d);
        });
      });

  void dismissToast(int id) {
    if (toast?.id != id) return;
    _set(() => toast = null);
  }

  /// Demo menu "Reset": clear local state and the server copy.
  void resetDemo() {
    reset(notify: false);
    if (online) stage = Stage.source; // still logged in: start onboarding again
    notifyListeners();
    _sync(api.wipe);
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
