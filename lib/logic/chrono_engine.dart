// A small rule-based stand-in for the Chrono assistant. It turns chat text into
// proposed schedule changes so the full flow (propose → apply → timeline) works
// without a backend. Swap `respond` for an API call to go live.

import '../data/models.dart';
import 'time_utils.dart';

class Slot {
  const Slot(this.day, this.start, this.end);
  final int day;
  final int start;
  final int end;
}

sealed class Change {
  const Change();
  String get targetId;
  int get targetDay;
}

class AddChange extends Change {
  const AddChange(this.block);
  final Block block;
  @override
  String get targetId => block.id;
  @override
  int get targetDay => block.day;
}

class MoveChange extends Change {
  const MoveChange({required this.blockId, required this.title, required this.kind, required this.from, required this.to});
  final String blockId;
  final String title;
  final Kind kind;
  final Slot from;
  final Slot to;
  @override
  String get targetId => blockId;
  @override
  int get targetDay => to.day;
}

class RemoveChange extends Change {
  const RemoveChange({required this.blockId, required this.title, required this.kind, required this.from});
  final String blockId;
  final String title;
  final Kind kind;
  final Slot from;
  @override
  String get targetId => blockId;
  @override
  int get targetDay => from.day;
}

class Reply {
  const Reply(this.text, {this.changes = const [], this.deadline, this.deadlineId});
  final String text;
  final List<Change> changes;
  final Deadline? deadline;
  final String? deadlineId; // deadline whose planned time grows when applied
}

String dayName(int d) => d == today ? 'Today' : d == today + 1 ? 'Tomorrow' : days[d].long;

String slotLabel(Slot s) => '${dayName(s.day)} ${range(s.start, s.end)}';

Slot slotOf(Block b) => Slot(b.day, b.start, b.end);

int _uid = 0;
String _newId(String p) => '$p-${DateTime.now().microsecondsSinceEpoch}-${_uid++}';

RegExp _re(String p) => RegExp(p, caseSensitive: false);

int? _parseTime(String text) {
  final m = _re(r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b').firstMatch(text) ??
      _re(r'\bat\s+(\d{1,2})(?::(\d{2}))?\b').firstMatch(text);
  if (m == null) return null;
  var hh = int.parse(m.group(1)!);
  final mm = int.parse(m.group(2) ?? '0');
  final ap = m.groupCount >= 3 ? m.group(3)?.toLowerCase() : null;
  if (ap == 'pm' && hh < 12) hh += 12;
  if (ap == 'am' && hh == 12) hh = 0;
  if (ap == null && hh < 7) hh += 12; // "at 3" during the day means 15:00
  return hh * 60 + mm;
}

int? _parseLength(String text) {
  final m = _re(r'(\d+(?:[.,]\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minutes)\b').firstMatch(text);
  if (m == null) return null;
  final n = double.parse(m.group(1)!.replaceAll(',', '.'));
  return m.group(2)!.toLowerCase().startsWith('h') ? (n * 60).round() : n.round();
}

String _titleCase(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return t;
  return t[0].toUpperCase() + t.substring(1);
}

Block? _findBlock(List<Block> blocks, String lower, [int? day]) {
  for (final b in dayBlocks(blocks, day ?? today)) {
    final title = b.title.toLowerCase();
    if (lower.contains(title)) return b;
    if (title.split(' ').any((w) => w.length > 3 && lower.contains(w))) return b;
  }
  return null;
}

Reply _addEvent(List<Block> blocks, String text, int start) {
  final len = _parseLength(text) ?? 60;
  final raw = text
      .replaceAll(_re(r'\b(urgent|add|new|please|today)\b'), '')
      .replaceAll(_re(r'\b(?:at\s+)?\d{1,2}(?::\d{2})?\s*(am|pm)?\b.*$'), '')
      .replaceAll(_re(r'\bat\s*$'), '');
  final title = _titleCase(raw).isEmpty ? 'New event' : _titleCase(raw);
  final end = start + len;
  final todays = dayBlocks(blocks, today);

  Block added(int s, int e) => Block(
        id: _newId('add'),
        day: today,
        title: title,
        kind: Kind.personal,
        start: s,
        end: e,
        origin: Origin.added,
        detail: 'Added by Chrono',
      );

  final clash = todays.where((b) => b.kind == Kind.lecture && overlaps(b.start, b.end, start, end)).firstOrNull;
  if (clash != null) {
    final alt = findSlot(blocks, today, len, start > now ? start : now);
    if (alt == null) return Reply('${clash.title} is a fixed class at that time, and I can’t find another ${duration(len)} slot today.');
    return Reply(
      '${clash.title} is fixed at that time, so I’d put $title at ${range(alt.start, alt.end)} instead.',
      changes: [AddChange(added(alt.start, alt.end))],
    );
  }

  final newBlock = added(start, end);
  final bumped = todays.where((b) => b.kind.flexible && overlaps(b.start, b.end, start, end)).toList();
  final changes = <Change>[];
  var working = [...blocks, newBlock];
  for (final b in bumped) {
    var day = today;
    var to = findSlot(working, today, b.length, b.start > now ? b.start : now, ignoreId: b.id);
    if (to == null) {
      day = today + 1;
      to = findSlot(working, day, b.length, h(8), ignoreId: b.id);
    }
    if (to == null) continue;
    final dest = to;
    changes.add(MoveChange(blockId: b.id, title: b.title, kind: b.kind, from: slotOf(b), to: Slot(day, dest.start, dest.end)));
    working = [for (final w in working) w.id == b.id ? w.copyWith(day: day, start: dest.start, end: dest.end) : w];
  }
  changes.add(AddChange(newBlock));

  final n = changes.length - 1;
  final text2 = n == 0
      ? 'Got it. $title is today ${range(start, end)}. That time was free, so nothing else moves.'
      : 'Got it. $title is today ${range(start, end)}. That overlaps $n flexible block${n > 1 ? 's' : ''}, so I moved ${n > 1 ? 'them' : 'it'} to your next free slot.';
  return Reply(text2, changes: changes);
}

Reply respond(String text, List<Block> blocks, List<Deadline> deadlines) {
  final t = text.toLowerCase();

  if (_re(r"how does my day|my day look|what's left|whats left").hasMatch(t)) {
    final todays = dayBlocks(blocks, today);
    final left = todays.where((b) => b.end > now && b.kind != Kind.breakTime).toList();
    var best = const Span(0, 0);
    var cursor = now;
    for (final b in todays) {
      if (b.start - cursor > best.length) best = Span(cursor, b.start);
      if (b.end > cursor) cursor = b.end;
    }
    final names = left.take(4).map((b) => b.title).join(', ');
    return Reply(
      '${left.length} blocks left today: $names${left.length > 4 ? '…' : ''}. Your longest free stretch is ${range(best.start, best.end)}.',
    );
  }

  if (_re(r'sick|clear my afternoon|clear the afternoon').hasMatch(t)) {
    final targets = dayBlocks(blocks, today)
        .where((b) => b.kind.flexible && b.start >= h(12) && b.end > now && b.title != 'Plan tomorrow')
        .toList();
    if (targets.isEmpty) return const Reply('Your afternoon is already clear. Rest up.');
    var working = [...blocks];
    final changes = <Change>[];
    for (final b in targets) {
      final to = findSlot(working, today + 1, b.length, h(8), ignoreId: b.id);
      if (to != null) {
        changes.add(MoveChange(blockId: b.id, title: b.title, kind: b.kind, from: slotOf(b), to: Slot(today + 1, to.start, to.end)));
        working = [for (final w in working) w.id == b.id ? w.copyWith(day: today + 1, start: to.start, end: to.end) : w];
      } else {
        changes.add(RemoveChange(blockId: b.id, title: b.title, kind: b.kind, from: slotOf(b)));
      }
    }
    final n = changes.length;
    return Reply(
      'Feel better. I’ll clear your afternoon and move $n block${n > 1 ? 's' : ''} to tomorrow. Classes stay as they are.',
      changes: changes,
    );
  }

  if (_re(r'\b(skip|cancel|remove|drop)\b').hasMatch(t)) {
    final b = _findBlock(blocks, t);
    if (b == null) return const Reply('I couldn’t find that block today. Try the name shown on your timeline.');
    if (b.kind == Kind.lecture) {
      return Reply('${b.title} is a class, so I keep it fixed. You can still skip it. I just won’t plan around that.');
    }
    return Reply(
      'Sure. I’ll take ${b.title} off today. That frees ${duration(b.length)} at ${range(b.start, b.end)}.',
      changes: [RemoveChange(blockId: b.id, title: b.title, kind: b.kind, from: slotOf(b))],
    );
  }

  if (_re(r'\bplan\b').hasMatch(t)) {
    final d = deadlines.where((x) => !x.done && t.contains(x.title.toLowerCase())).firstOrNull;
    if (d != null) {
      final remaining = (d.estimate - d.planned) < 30 ? 30 : d.estimate - d.planned;
      final len = remaining > 120 ? 120 : remaining;
      var day = today;
      var slot = findSlot(blocks, today, len, now);
      if (slot == null) {
        day = today + 1;
        slot = findSlot(blocks, day, len, h(8));
      }
      if (slot == null) {
        return Reply('I couldn’t find ${duration(len)} today or tomorrow for ${d.title}. Want me to look at the weekend?');
      }
      return Reply(
        '${d.title} still needs about ${duration(remaining)}. I found ${duration(len)} ${dayName(day).toLowerCase()} at ${range(slot.start, slot.end)}.',
        changes: [
          AddChange(Block(
            id: _newId('focus'),
            day: day,
            title: d.title,
            kind: Kind.focus,
            start: slot.start,
            end: slot.end,
            origin: Origin.added,
            detail: 'Added by Chrono',
          )),
        ],
        deadlineId: d.id,
      );
    }
  }

  if (_re(r'\bmove\b').hasMatch(t)) {
    final b = _findBlock(blocks, t);
    if (b != null && b.kind != Kind.lecture) {
      var day = today;
      var to = findSlot(blocks, day, b.length, b.end > now ? b.end : now, ignoreId: b.id);
      if (to == null) {
        day = today + 1;
        to = findSlot(blocks, day, b.length, h(8), ignoreId: b.id);
      }
      if (to == null) return Reply('There’s no ${duration(b.length)} slot left today or tomorrow for ${b.title}.');
      return Reply(
        'The next free ${duration(b.length)} for ${b.title} is ${dayName(day).toLowerCase()} ${range(to.start, to.end)}.',
        changes: [MoveChange(blockId: b.id, title: b.title, kind: b.kind, from: slotOf(b), to: Slot(day, to.start, to.end))],
      );
    }
  }

  final due = _re(r'^(?:add\s+)?(.+?)\s+due\s+(\w+)').firstMatch(text.trim());
  if (due != null) {
    final len = _parseLength(t) ?? 120;
    final title = _titleCase(due.group(1)!);
    final when = _titleCase(due.group(2)!);
    final deadline = Deadline(
      id: _newId('d'),
      title: title,
      course: 'Added in chat',
      estimate: len,
      due: when,
      urgent: false,
      planned: 0,
    );
    final slot = findSlot(blocks, today + 1, len > 90 ? 90 : len, h(8));
    return Reply(
      'Added $title, due $when, about ${duration(len)}. ${slot != null ? 'I can start with ${duration(slot.length)} tomorrow at ${range(slot.start, slot.end)}.' : 'Tell me when you want to work on it.'}',
      deadline: deadline,
      deadlineId: deadline.id,
      changes: slot == null
          ? const []
          : [
              AddChange(Block(
                id: _newId('focus'),
                day: today + 1,
                title: title,
                kind: Kind.focus,
                start: slot.start,
                end: slot.end,
                origin: Origin.added,
                detail: 'Added by Chrono',
              )),
            ],
    );
  }

  final at = _parseTime(t);
  if (at != null) return _addEvent(blocks, text, at);

  return const Reply(
    'I can add, move or clear blocks for you. Try “Meeting at 4pm for 1h”, “Skip gym today” or “How does my day look?”',
  );
}

List<Block> applyChanges(List<Block> blocks, List<Change> changes) {
  var next = [for (final b in blocks) b.copyWith(clearOrigin: true)];
  for (final c in changes) {
    switch (c) {
      case AddChange(:final block):
        next.add(block);
      case RemoveChange(:final blockId):
        next = next.where((b) => b.id != blockId).toList();
      case MoveChange(:final blockId, :final to):
        next = [
          for (final b in next) b.id == blockId ? b.copyWith(day: to.day, start: to.start, end: to.end, origin: Origin.moved) : b,
        ];
    }
  }
  return next;
}
