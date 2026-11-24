// Rule-based fallback for chat when the backend cannot be reached.

import '../data/models.dart';
import 'dates.dart';
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
  const MoveChange({
    required this.blockId,
    required this.title,
    required this.kind,
    required this.from,
    required this.to,
  });
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
  const RemoveChange({
    required this.blockId,
    required this.title,
    required this.kind,
    required this.from,
  });
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
  const Reply(
    this.text, {
    this.changes = const [],
    this.deadline,
    this.deadlineId,
  });
  final String text;
  final List<Change> changes;
  final Deadline? deadline;
  final String? deadlineId;
}

String dayName(int d) {
  if (d == today) return 'Today';
  if (d == today + 1 && d <= 6) return 'Tomorrow';
  return d >= 0 && d <= 6 ? days[d].long : 'Day $d';
}

String whenLabel(int day) {
  if (day == today) return 'today';
  if (day == today + 1 && day <= 6) return 'tomorrow';
  return dayLabelOf(day, todayDate);
}

String slotLabel(Slot s) => '${dayName(s.day)} ${range(s.start, s.end)}';

Slot slotOf(Block b) => Slot(b.day, b.start, b.end);

int _uid = 0;
String _newId(String p) =>
    '$p-${DateTime.now().microsecondsSinceEpoch}-${_uid++}';

RegExp _re(String p) => RegExp(p, caseSensitive: false);

int? _parseTime(String text) {
  final m =
      _re(r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b').firstMatch(text) ??
      _re(r'\b(?:at|jam|pukul)\s+(\d{1,2})(?:[:.](\d{2}))?\b').firstMatch(text);
  if (m == null) return null;
  var hh = int.parse(m.group(1)!);
  final mm = int.parse(m.group(2) ?? '0');
  final ap = m.groupCount >= 3 ? m.group(3)?.toLowerCase() : null;
  if (ap == 'pm' && hh < 12) hh += 12;
  if (ap == 'am' && hh == 12) hh = 0;
  if (ap == null && hh < 7) hh += 12;
  return hh * 60 + mm;
}

int? _parseLength(String text) {
  for (final m in _re(
    r'(\d+(?:[.,]\d+)?)\s*(h|hr|hrs|hour|hours|jam|m|min|mins|minutes|menit)\b',
  ).allMatches(text)) {
    final unit = m.group(2)!.toLowerCase();
    final after = text.substring(m.end);
    if (unit == 'jam' &&
        _re(r'^\s*\d').hasMatch(after) &&
        !_re(r'^\s*\d+\s*(menit|min)').hasMatch(after)) {
      continue;
    }
    if (_re(r'(tanggal|tgl)\.?\s*$').hasMatch(text.substring(0, m.start))) {
      continue;
    }
    final n = double.parse(m.group(1)!.replaceAll(',', '.'));
    return unit.startsWith('h') || unit == 'jam' ? (n * 60).round() : n.round();
  }
  return null;
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
    if (title.split(' ').any((w) => w.length > 3 && lower.contains(w))) {
      return b;
    }
  }
  return null;
}

Block? _findBlockThisWeek(List<Block> blocks, String lower) {
  final onToday = _findBlock(blocks, lower, today);
  if (onToday != null) return onToday;
  for (var d = today + 1; d <= 6; d++) {
    final b = _findBlock(blocks, lower, d);
    if (b != null) return b;
  }
  return null;
}

({int day, Span slot})? _firstSlot(
  List<Block> blocks,
  int len,
  int fromDay,
  int lastDay, {
  int? afterOnFirst,
}) {
  for (var d = fromDay; d <= lastDay && d <= 6; d++) {
    final after = d == fromDay
        ? (afterOnFirst ?? (d == today ? now : h(8)))
        : h(8);
    final slot = findSlot(blocks, d, len, after);
    if (slot != null) return (day: d, slot: slot);
  }
  return null;
}

String _stripDateWords(String s) => s.replaceAll(
  _re(
    r"\b(?:today|tonight|tomorrow|tmrw|besok|lusa|hari ini|malam ini|on|pada|hari|tanggal|tgl|next|depan|"
    r"monday|tuesday|wednesday|thursday|friday|saturday|sunday|senin|selasa|rabu|kamis|jum'?at|sabtu|minggu)\b",
  ),
  ' ',
);

Reply _addEvent(List<Block> blocks, String text, int start, int day) {
  final len = _parseLength(text) ?? 60;
  if (len <= 0 || start + len > 1440) {
    return Reply(
      'That block does not fit in one day. Try a shorter duration or an earlier time.',
    );
  }
  final raw =
      _stripDateWords(
            text.replaceAll(
              _re(r'\b(urgent|add|new|please|tambah(?:kan)?|buat(?:kan)?)\b'),
              '',
            ),
          )
          .replaceAll(
            _re(
              r'\b(?:at\s+|jam\s+|pukul\s+)?\d{1,2}(?::\d{2})?\s*(am|pm)?\b.*$',
            ),
            '',
          )
          .replaceAll(_re(r'\b(?:at|jam|pukul)\s*$'), '');
  final title = _titleCase(raw).isEmpty ? 'New event' : _titleCase(raw);
  final end = start + len;
  final onDay = dayBlocks(blocks, day);
  final isToday = day == today;
  final when = whenLabel(day);

  Block added(int s, int e) => Block(
    id: _newId('add'),
    day: day,
    title: title,
    kind: Kind.personal,
    start: s,
    end: e,
    origin: Origin.added,
    detail: 'Added by Chrono',
  );

  final clash = onDay
      .where(
        (b) => b.kind == Kind.lecture && overlaps(b.start, b.end, start, end),
      )
      .firstOrNull;
  if (clash != null) {
    final alt = findSlot(
      blocks,
      day,
      len,
      isToday && now > start ? now : start,
    );
    if (alt == null) {
      return Reply(
        '${clash.title} is a fixed class at that time, and I can’t find another ${duration(len)} slot $when.',
      );
    }
    return Reply(
      '${clash.title} is fixed at that time, so I’d put $title $when at ${range(alt.start, alt.end)} instead.',
      changes: [AddChange(added(alt.start, alt.end))],
    );
  }

  final newBlock = added(start, end);
  final bumped = onDay
      .where((b) => b.kind.flexible && overlaps(b.start, b.end, start, end))
      .toList();
  final changes = <Change>[];
  var working = [...blocks, newBlock];
  for (final b in bumped) {
    var to = day;
    var slot = findSlot(
      working,
      day,
      b.length,
      isToday && b.start <= now ? now : b.start,
      ignoreId: b.id,
    );
    if (slot == null && day < 6) {
      to = day + 1;
      slot = findSlot(working, to, b.length, h(8), ignoreId: b.id);
    }
    if (slot == null) continue;
    final dest = slot;
    changes.add(
      MoveChange(
        blockId: b.id,
        title: b.title,
        kind: b.kind,
        from: slotOf(b),
        to: Slot(to, dest.start, dest.end),
      ),
    );
    working = [
      for (final w in working)
        w.id == b.id
            ? w.copyWith(day: to, start: dest.start, end: dest.end)
            : w,
    ];
  }
  changes.add(AddChange(newBlock));

  final n = changes.length - 1;
  final text2 = n == 0
      ? 'Got it: $title, $when ${range(start, end)}. That time was free, so nothing else moves.'
      : 'Got it: $title, $when ${range(start, end)}. That overlaps $n flexible block${n > 1 ? 's' : ''}, so I moved ${n > 1 ? 'them' : 'it'} to your next free slot.';
  return Reply(text2, changes: changes);
}

Reply respond(String text, List<Block> blocks, List<Deadline> deadlines) {
  final t = text.toLowerCase();
  final todayD = todayDate;
  final refs = parseDateRefs(text, todayD);
  final named = [
    for (final d in refs) weekIndexOf(d, todayD),
  ].whereType<int>().firstOrNull;
  final outside = named == null
      ? refs
            .where((d) => weekIndexOf(d, todayD) == null && !d.isBefore(todayD))
            .firstOrNull
      : null;
  final day = named ?? today;
  final left0 = day == today ? now : 0;

  if (_re(
    r"how does my day|my day look|what's left|whats left|jadwalku|jadwal saya|agenda",
  ).hasMatch(t)) {
    final onDay = dayBlocks(blocks, day);
    final left = onDay
        .where((b) => b.end > left0 && b.kind != Kind.breakTime)
        .toList();
    if (left.isEmpty) {
      return Reply(
        'Nothing else planned ${whenLabel(day)}. Your whole day is open.',
      );
    }
    var best = const Span(0, 0);
    var cursor = day == today ? now : h(8);
    for (final b in onDay) {
      if (b.start - cursor > best.length) best = Span(cursor, b.start);
      if (b.end > cursor) cursor = b.end;
    }
    final names = left.take(4).map((b) => b.title).join(', ');
    return Reply(
      '${left.length} block${left.length > 1 ? 's' : ''} ${day == today ? 'left today' : 'on ${whenLabel(day)}'}: $names${left.length > 4 ? '…' : ''}. Your longest free stretch is ${range(best.start, best.end)}.',
    );
  }

  if (_re(r'sick|clear my afternoon|clear the afternoon|sakit').hasMatch(t)) {
    final targets = dayBlocks(blocks, day)
        .where(
          (b) =>
              b.kind.flexible &&
              b.start >= h(12) &&
              b.end > left0 &&
              b.title != 'Plan tomorrow',
        )
        .toList();
    if (targets.isEmpty) {
      return const Reply('Your afternoon is already clear. Rest up.');
    }
    final next = day < 6 ? day + 1 : null;
    var working = [...blocks];
    final changes = <Change>[];
    for (final b in targets) {
      final to = next == null
          ? null
          : findSlot(working, next, b.length, h(8), ignoreId: b.id);
      if (to != null) {
        changes.add(
          MoveChange(
            blockId: b.id,
            title: b.title,
            kind: b.kind,
            from: slotOf(b),
            to: Slot(next!, to.start, to.end),
          ),
        );
        working = [
          for (final w in working)
            w.id == b.id
                ? w.copyWith(day: next, start: to.start, end: to.end)
                : w,
        ];
      } else {
        changes.add(
          RemoveChange(
            blockId: b.id,
            title: b.title,
            kind: b.kind,
            from: slotOf(b),
          ),
        );
      }
    }
    final n = changes.length;
    return Reply(
      'Feel better. I’ll clear your afternoon and move $n block${n > 1 ? 's' : ''} to ${next == null ? 'later' : whenLabel(next)}. Classes stay as they are.',
      changes: changes,
    );
  }

  if (_re(r'\b(skip|cancel|remove|drop|batalkan|batal|hapus)\b').hasMatch(t)) {
    final b = _findBlock(blocks, t, day);
    if (b == null) {
      return Reply(
        'I couldn’t find that block ${whenLabel(day)}. Try the name shown on your timeline.',
      );
    }
    if (b.kind == Kind.lecture) {
      return Reply(
        '${b.title} is a class, so I keep it fixed. You can still skip it. I just won’t plan around that.',
      );
    }
    return Reply(
      'Sure: I’ll take ${b.title} off ${whenLabel(day)}. That frees ${duration(b.length)} at ${range(b.start, b.end)}.',
      changes: [
        RemoveChange(
          blockId: b.id,
          title: b.title,
          kind: b.kind,
          from: slotOf(b),
        ),
      ],
    );
  }

  if (_re(r'\bplan\b|rencanakan|jadwalkan').hasMatch(t)) {
    final d = deadlines
        .where((x) => !x.done && t.contains(x.title.toLowerCase()))
        .firstOrNull;
    if (d != null) {
      if (named != null && named < today) {
        return const Reply(
          'That date has passed. Choose today or a later day.',
        );
      }
      final planned = d.plannedFor(blocks);
      final remaining = (d.estimate - planned) < 30 ? 30 : d.estimate - planned;
      final len = remaining > 120 ? 120 : remaining;
      final dueIdx = d.dueDate == null ? null : weekIndexOf(d.dueDate!, todayD);
      final lastDay =
          named ??
          (dueIdx == null
              ? (today > 4 ? 6 : today + 2)
              : (dueIdx < today ? today : dueIdx));
      final found = _firstSlot(blocks, len, named ?? today, named ?? lastDay);
      if (found == null) {
        return Reply(
          'I couldn’t find ${duration(len)} ${named == null ? 'before ${d.title} is due' : 'on ${whenLabel(named)}'} for ${d.title}. Want me to look at another day?',
        );
      }
      final slot = found.slot;
      return Reply(
        '${d.title} still needs about ${duration(remaining)}. I found ${duration(len)} ${whenLabel(found.day)} at ${range(slot.start, slot.end)}.',
        changes: [
          AddChange(
            Block(
              id: _newId('focus'),
              day: found.day,
              title: d.title,
              kind: Kind.focus,
              start: slot.start,
              end: slot.end,
              origin: Origin.added,
              detail: 'Added by Chrono',
            ),
          ),
        ],
        deadlineId: d.id,
      );
    }
  }

  if (_re(r'\b(move|pindah(?:kan)?)\b').hasMatch(t)) {
    final fromTo = _re(
      r'\b(?:from|dari)\s+(.+?)\s+(?:to|ke)\s+(.+)$',
    ).firstMatch(text);
    final sourceDay = fromTo == null
        ? null
        : [
            for (final d in parseDateRefs(fromTo.group(1)!, todayD))
              weekIndexOf(d, todayD),
          ].whereType<int>().firstOrNull;
    final targetDay = fromTo == null
        ? null
        : [
            for (final d in parseDateRefs(fromTo.group(2)!, todayD))
              weekIndexOf(d, todayD),
          ].whereType<int>().firstOrNull;
    final b = sourceDay == null
        ? _findBlockThisWeek(blocks, t)
        : _findBlock(blocks, t, sourceDay);
    if (b != null && b.kind != Kind.lecture) {
      final target = targetDay ?? named ?? b.day;
      if (target < today) {
        return const Reply(
          'That date has passed. Choose today or a later day.',
        );
      }
      final wanted = _parseTime(fromTo?.group(2) ?? t);
      if (target == today && wanted != null && wanted < now) {
        return const Reply('That time has passed. Choose a later time today.');
      }
      final sameDay = target == b.day;
      final after =
          wanted ??
          (sameDay
              ? (b.end > left0 ? b.end : left0)
              : (target == today ? now : h(8)));
      var to = target;
      var slot = findSlot(blocks, to, b.length, after, ignoreId: b.id);
      if (slot == null && named == null && targetDay == null && to < 6) {
        to = to + 1;
        slot = findSlot(blocks, to, b.length, h(8), ignoreId: b.id);
      }
      if (slot == null) {
        return Reply(
          'There’s no ${duration(b.length)} slot left ${named == null ? 'today or tomorrow' : 'on ${whenLabel(target)}'} for ${b.title}.',
        );
      }
      return Reply(
        'The next free ${duration(b.length)} for ${b.title} is ${whenLabel(to)} ${range(slot.start, slot.end)}.',
        changes: [
          MoveChange(
            blockId: b.id,
            title: b.title,
            kind: b.kind,
            from: slotOf(b),
            to: Slot(to, slot.start, slot.end),
          ),
        ],
      );
    }
  }

  final due = _re(
    r"^(?:add\s+|tambah(?:kan)?\s+)?(.+?)[,\s]+(?:due|deadline|tenggat(?:nya)?|dikumpul(?:kan)?|kumpul|submit)\b[\s:]*(?:on|at|pada|di)?\s*(.*)$",
  ).firstMatch(text.trim());
  if (due != null) {
    final len = _parseLength(t) ?? 120;
    final title = _titleCase(due.group(1)!);
    final rest = due.group(2)!;
    final dueDate = parseDateRefs(rest, todayD).firstOrNull;
    final whenText = dueDate != null
        ? dueLabelFor(isoDate(dueDate), todayD)
        : _titleCase(rest.replaceAll(RegExp(r'[,.].*$'), ''));
    final existing = deadlines
        .where(
          (d) => !d.done && d.title.trim().toLowerCase() == title.toLowerCase(),
        )
        .firstOrNull;
    final deadline = Deadline(
      id: existing?.id ?? _newId('d'),
      title: title,
      course: existing?.course ?? 'Added in chat',
      estimate: len,
      due: dueDate != null
          ? isoDate(dueDate)
          : (whenText.isEmpty ? 'TBD' : whenText),
      urgent: false,
      planned: existing?.planned ?? 0,
    );
    final dueIdx = dueDate == null ? null : weekIndexOf(dueDate, todayD);
    final firstDay = dueIdx != null && dueIdx <= today ? today : today + 1;
    final lastDay = dueIdx ?? 6;
    final found = firstDay > 6
        ? null
        : _firstSlot(
            blocks,
            len > 90 ? 90 : len,
            firstDay,
            lastDay,
            afterOnFirst: firstDay == today ? now : h(8),
          );
    final label = whenText.isEmpty ? 'no date yet' : 'due $whenText';
    return Reply(
      'Added $title: $label, about ${duration(len)}. ${found != null ? 'I can start with ${duration(found.slot.length)} ${whenLabel(found.day)} at ${range(found.slot.start, found.slot.end)}.' : 'Tell me when you want to work on it.'}',
      deadline: deadline,
      deadlineId: deadline.id,
      changes: found == null
          ? const []
          : [
              AddChange(
                Block(
                  id: _newId('focus'),
                  day: found.day,
                  title: title,
                  kind: Kind.focus,
                  start: found.slot.start,
                  end: found.slot.end,
                  origin: Origin.added,
                  detail: 'Added by Chrono',
                ),
              ),
            ],
    );
  }

  final at = _parseTime(t);
  if (at != null) {
    if (at < 0 || at >= 1440) {
      return const Reply('Use a time between 00:00 and 23:59.');
    }
    if (refs.any((d) => d.isBefore(todayD))) {
      return const Reply(
        'That date has passed. Tell me a day from today onward.',
      );
    }
    if (day == today && at < now) {
      return const Reply('That time has passed. Choose a later time today.');
    }
    if (outside != null) {
      return Reply(
        'I can only plan this week (${dayLabelOf(0, todayD)} to ${dayLabelOf(6, todayD)}). ${outside.day} ${monthShortNames[outside.month - 1]} is further out. Tell me a day this week, or add it as a deadline.',
      );
    }
    return _addEvent(blocks, text, at, day);
  }

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
          for (final b in next)
            b.id == blockId
                ? b.copyWith(
                    day: to.day,
                    start: to.start,
                    end: to.end,
                    origin: Origin.moved,
                  )
                : b,
        ];
    }
  }
  return next;
}
