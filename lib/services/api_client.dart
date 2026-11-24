// HTTP client for chrono-backend (Express + Supabase + Gemini).
//
// Base URL: pass --dart-define=CHRONO_API_URL=http://<host>:3000 to override.
// Defaults: Android emulator → http://10.0.2.2:3000, everything else → http://localhost:3000.
//
// Auth: email + password accounts (Supabase Auth through the backend). After
// sign-up / log-in the session (access + refresh token) is kept in
// shared_preferences so the user stays logged in; an expired access token is
// refreshed automatically. The password itself is never stored.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../logic/chrono_engine.dart';

const _envUrl = String.fromEnvironment('CHRONO_API_URL');

String get defaultApiUrl {
  if (_envUrl.isNotEmpty) return _envUrl;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:3000';
  return 'http://localhost:3000';
}

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'ApiException($status): $message';
}

/// Everything returned by GET /api/me.
class Snapshot {
  const Snapshot({
    required this.email,
    required this.name,
    required this.prefsFocus,
    required this.bedtime,
    required this.breakMin,
    required this.onboardingComplete,
    required this.courses,
    required this.blocks,
    required this.deadlines,
    required this.messages,
  });
  final String email;
  final String name;
  final String prefsFocus;
  final String bedtime;
  final int breakMin;
  final bool onboardingComplete;
  final List<Course> courses;
  final List<Block> blocks;
  final List<Deadline> deadlines;
  final List<Map<String, dynamic>> messages;
}

/// Reply from POST /api/chat.
class ChatReply {
  const ChatReply({required this.aiId, required this.text, this.proposalId, this.changes = const [], this.newDeadline, this.deadlineId});
  final String aiId;
  final String text;
  final String? proposalId;
  final List<Change> changes;
  final Deadline? newDeadline;
  final String? deadlineId;
}

/// Result of POST /api/schedule/parse.
class ScheduleRead {
  const ScheduleRead(this.courses, this.note);
  final List<Course> courses;
  final String note; // why nothing was found, or what was unclear
}

/// Reply from POST /api/chat/:id/apply.
class ApplyResult {
  const ApplyResult(this.blocks, this.deadlines, this.addedIds);
  final List<Block> blocks;
  final List<Deadline> deadlines;
  final List<String> addedIds;
}

class ChronoApi {
  ChronoApi({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? defaultApiUrl,
        _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  String? _token;
  String? _refreshToken;
  Future<void>? _refreshing;

  /// Called when the session can't be refreshed any more (user must log in again).
  void Function()? onSessionExpired;

  static const _kAccess = 'chrono.access_token';
  static const _kRefresh = 'chrono.refresh_token';
  static const _timeout = Duration(seconds: 45);

  bool get hasSession => _refreshToken != null;

  // ---------------- auth ----------------

  /// Load a saved session. Returns false when the user has to log in.
  Future<bool> restoreSession() async {
    final sp = await SharedPreferences.getInstance();
    // Device accounts from before login existed are gone; forget their credentials.
    await sp.remove('chrono.email');
    await sp.remove('chrono.password');
    _token = sp.getString(_kAccess);
    _refreshToken = sp.getString(_kRefresh);
    return _refreshToken != null;
  }

  Future<void> signUp({required String name, required String email, required String password}) async {
    final res = await _send('POST', '/api/auth/signup',
        body: {'name': name, 'email': email, 'password': password}, auth: false);
    await _saveSession(res);
  }

  Future<void> logIn({required String email, required String password}) async {
    final res = await _send('POST', '/api/auth/login', body: {'email': email, 'password': password}, auth: false);
    await _saveSession(res);
  }

  /// End the session on the server (best effort) and forget it here.
  Future<void> logOut() async {
    if (_token != null) {
      try {
        await _send('POST', '/api/auth/logout', retried: true).timeout(const Duration(seconds: 5));
      } catch (_) {/* offline or already expired: forgetting it locally is enough */}
    }
    await _clearSession();
  }

  Future<void> _saveSession(dynamic res) async {
    _token = res['access_token'] as String;
    _refreshToken = res['refresh_token'] as String;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kAccess, _token!);
    await sp.setString(_kRefresh, _refreshToken!);
  }

  Future<void> _clearSession() async {
    _token = null;
    _refreshToken = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kAccess);
    await sp.remove(_kRefresh);
  }

  /// Swap the refresh token for a new access token. Concurrent callers share one
  /// request, because Supabase rotates the refresh token on every use.
  Future<void> _refresh() => _refreshing ??= () async {
        try {
          final rt = _refreshToken;
          if (rt == null) throw ApiException(401, 'Please log in.');
          try {
            final res = await _send('POST', '/api/auth/refresh', body: {'refresh_token': rt}, auth: false);
            await _saveSession(res);
          } on ApiException catch (e) {
            if (e.status == 401 || e.status == 400) {
              await _clearSession();
              onSessionExpired?.call();
            }
            rethrow;
          }
        } finally {
          _refreshing = null;
        }
      }();

  // ---------------- transport ----------------

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query, bool auth = true, bool retried = false}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = {
      'Content-Type': 'application/json',
      if (auth && _token != null) 'Authorization': 'Bearer $_token',
    };
    final req = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);

    final streamed = await _http.send(req).timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    final data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));

    if (res.statusCode == 401 && auth && !retried) {
      await _refresh(); // access tokens expire after an hour
      return _send(method, path, body: body, query: query, auth: auth, retried: true);
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, (data is Map ? data['error'] : null)?.toString() ?? 'HTTP ${res.statusCode}');
    }
    return data;
  }

  // ---------------- endpoints ----------------

  Future<bool> health() async {
    try {
      final r = await _http.get(Uri.parse('$baseUrl/api/health')).timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Snapshot> me() async => _snapshot(await _send('GET', '/api/me'));

  /// Read a timetable with Gemini: a photo/screenshot ([image] + [mimeType]) or free [text].
  Future<ScheduleRead> parseSchedule({String? text, Uint8List? image, String mimeType = 'image/jpeg'}) async {
    final res = await _send('POST', '/api/schedule/parse', body: {
      if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
      if (image != null) 'image': base64Encode(image),
      if (image != null) 'mime_type': mimeType,
    });
    final list = res['courses'] as List;
    return ScheduleRead(
      [
        for (var i = 0; i < list.length; i++)
          Course(
            id: 'ai-$i',
            code: (list[i]['code'] as String?) ?? '',
            name: list[i]['name'] as String,
            days: [for (final d in list[i]['days'] as List) _int(d)],
            start: _int(list[i]['start_min']),
            end: _int(list[i]['end_min']),
            room: (list[i]['room'] as String?) ?? '',
          ),
      ],
      (res['note'] as String?) ?? '',
    );
  }

  Future<Snapshot> saveOnboarding({
    required String focus,
    required String bedtime,
    required int breakMin,
    required List<Course> courses,
    required List<Block> flexBlocks,
    required List<Deadline> deadlines,
  }) async {
    final res = await _send('POST', '/api/me/onboarding', body: {
      'preferences': {'focus_window': focus, 'bedtime': bedtime, 'break_minutes': breakMin},
      'courses': [for (final c in courses) courseToJson(c)],
      'blocks': [for (final b in flexBlocks) blockToJson(b)],
      'deadlines': [for (final d in deadlines) deadlineToJson(d)],
    });
    return _snapshot(res);
  }

  Future<void> wipe() => _send('DELETE', '/api/me/data');

  /// Save profile name and/or work preferences (only the fields given).
  Future<void> updatePreferences({String? name, String? focus, String? bedtime, int? breakMin}) =>
      _send('PUT', '/api/preferences', body: {
        'name': ?name,
        'focus_window': ?focus,
        'bedtime': ?bedtime,
        'break_minutes': ?breakMin,
      });

  Future<void> toggleDone(String id) => _send('POST', '/api/blocks/$id/done');
  Future<void> pushBlock(String id, int minutes) => _send('POST', '/api/blocks/$id/push', body: {'minutes': minutes});
  Future<void> deleteBlock(String id) => _send('DELETE', '/api/blocks/$id');
  Future<void> toggleDeadline(String id) => _send('POST', '/api/deadlines/$id/toggle');

  Future<List<Block>> replaceBlocks(List<Block> blocks) async {
    final res = await _send('POST', '/api/blocks/replace', body: {'blocks': [for (final b in blocks) blockToJson(b)]});
    return [for (final j in res as List) blockFromJson(j)];
  }

  Future<List<Deadline>> replaceDeadlines(List<Deadline> deadlines) async {
    final res = await _send('POST', '/api/deadlines/replace', body: {'deadlines': [for (final d in deadlines) deadlineToJson(d)]});
    return [for (final j in res as List) deadlineFromJson(j)];
  }

  /// Send a chat message. The server works out "today" and "now" from its own clock;
  /// the device's UTC offset tells it which timezone the user is in (e.g. 420 for WIB).
  Future<ChatReply> chat(String message) async {
    final offset = DateTime.now().timeZoneOffset.inMinutes;
    final res = await _send('POST', '/api/chat', body: {'message': message}, query: {'tz_offset': '$offset'});
    final ai = res['ai_message'] as Map<String, dynamic>;
    final proposal = res['proposal'] as Map<String, dynamic>?;
    final nd = res['new_deadline'] as Map<String, dynamic>?;
    return ChatReply(
      aiId: ai['id'] as String,
      text: (ai['content'] as String?) ?? '',
      proposalId: proposal?['id'] as String?,
      changes: proposal == null ? const [] : changesFromJson(proposal['changes'] as List, proposal['id'] as String),
      newDeadline: nd == null ? null : deadlineFromJson(nd),
      deadlineId: proposal?['deadline_id'] as String?,
    );
  }

  Future<ApplyResult> apply(String proposalId) async {
    final res = await _send('POST', '/api/chat/$proposalId/apply');
    return ApplyResult(
      [for (final j in res['blocks'] as List) blockFromJson(j)],
      [for (final j in res['deadlines'] as List) deadlineFromJson(j)],
      [for (final id in res['added_ids'] as List) id as String],
    );
  }

  Future<void> dismiss(String proposalId) => _send('POST', '/api/chat/$proposalId/dismiss');

  Snapshot _snapshot(dynamic res) {
    final p = res['preferences'] as Map<String, dynamic>;
    return Snapshot(
      email: (res['user']?['email'] as String?) ?? '',
      name: (p['name'] as String?) ?? 'Student',
      prefsFocus: (p['focus_window'] as String?) ?? 'morning',
      bedtime: (p['bedtime'] as String?) ?? '23:00',
      breakMin: (p['break_minutes'] as num?)?.toInt() ?? 15,
      onboardingComplete: p['onboarding_complete'] == true,
      courses: [for (final j in res['courses'] as List) courseFromJson(j)],
      blocks: [for (final j in res['blocks'] as List) blockFromJson(j)],
      deadlines: [for (final j in res['deadlines'] as List) deadlineFromJson(j)],
      messages: [for (final j in res['messages'] as List) j as Map<String, dynamic>],
    );
  }
}

// ---------------- JSON mapping ----------------

Kind kindFromJson(String? s) => Kind.values.firstWhere((k) => k.name == s, orElse: () => Kind.personal);

Origin? originFromJson(String? s) => switch (s) { 'added' => Origin.added, 'moved' => Origin.moved, _ => null };

int _int(dynamic v) => (v as num).toInt();

Block blockFromJson(dynamic j) => Block(
      id: j['id'] as String,
      day: _int(j['day']),
      title: j['title'] as String,
      kind: kindFromJson(j['kind'] as String?),
      start: _int(j['start_min']),
      end: _int(j['end_min']),
      detail: j['detail'] as String?,
      origin: originFromJson(j['origin'] as String?),
      done: j['done'] == true,
      courseId: j['course_id'] as String?,
    );

Map<String, dynamic> blockToJson(Block b) => {
      'id': b.id,
      'day': b.day,
      'title': b.title,
      'kind': b.kind.name,
      'start_min': b.start,
      'end_min': b.end,
      'detail': b.detail,
      'origin': b.origin?.name,
      'done': b.done,
      'course_id': b.courseId,
    };

Course courseFromJson(dynamic j) => Course(
      id: j['id'] as String,
      name: j['name'] as String,
      days: [for (final d in j['days'] as List) _int(d)],
      start: _int(j['start_min']),
      end: _int(j['end_min']),
      room: (j['room'] as String?) ?? '',
      selected: j['selected'] != false,
      code: (j['code'] as String?) ?? '',
    );

Map<String, dynamic> courseToJson(Course c) => {
      'code': c.code.isNotEmpty ? c.code : c.id,
      'name': c.name,
      'days': c.days,
      'start_min': c.start,
      'end_min': c.end,
      'room': c.room,
      'selected': c.selected,
    };

Deadline deadlineFromJson(dynamic j) => Deadline(
      id: j['id'] as String,
      title: j['title'] as String,
      course: (j['course'] as String?) ?? '',
      estimate: _int(j['estimate']),
      due: (j['due'] as String?) ?? 'TBD',
      urgent: j['urgent'] == true,
      planned: _int(j['planned'] ?? 0),
      done: j['done'] == true,
    );

Map<String, dynamic> deadlineToJson(Deadline d) => {
      'id': d.id,
      'title': d.title,
      'course': d.course,
      'estimate': d.estimate,
      'due': d.due,
      'urgent': d.urgent,
      'planned': d.planned,
      'done': d.done,
    };

Slot _slot(dynamic j, {int? fallbackDay}) => Slot(_int(j['day'] ?? fallbackDay ?? today), _int(j['start_min']), _int(j['end_min']));

/// Server proposal changes → the app's Change classes. Added blocks get a
/// temporary id (`<proposalId>-new-<i>`) until the server assigns the real one.
List<Change> changesFromJson(List list, String proposalId) {
  final out = <Change>[];
  var i = 0;
  for (final c in list) {
    switch (c['type']) {
      case 'add':
        final b = c['block'];
        out.add(AddChange(Block(
          id: '$proposalId-new-${i++}',
          day: _int(b['day']),
          title: b['title'] as String,
          kind: kindFromJson(b['kind'] as String?),
          start: _int(b['start_min']),
          end: _int(b['end_min']),
          detail: (b['detail'] as String?) ?? 'Added by Chrono',
          origin: Origin.added,
        )));
      case 'move':
        out.add(MoveChange(
          blockId: c['block_id'] as String,
          title: c['title'] as String,
          kind: kindFromJson(c['kind'] as String?),
          from: _slot(c['from']),
          to: _slot(c['to'], fallbackDay: _int(c['from']['day'])),
        ));
      case 'remove':
        out.add(RemoveChange(
          blockId: c['block_id'] as String,
          title: c['title'] as String,
          kind: kindFromJson(c['kind'] as String?),
          from: _slot(c['from']),
        ));
    }
  }
  return out;
}
