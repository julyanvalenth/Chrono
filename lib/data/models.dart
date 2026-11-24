// Models and calendar helpers.

import '../logic/dates.dart';

enum Kind { lecture, focus, task, personal, breakTime }

extension KindLabel on Kind {
  String get label => switch (this) {
    Kind.lecture => 'Class',
    Kind.focus => 'Focus',
    Kind.task => 'Task',
    Kind.personal => 'Personal',
    Kind.breakTime => 'Break',
  };

  bool get flexible =>
      this == Kind.focus || this == Kind.task || this == Kind.personal;
}

enum Origin { added, moved }

class Block {
  const Block({
    required this.id,
    required this.day,
    required this.title,
    required this.kind,
    required this.start,
    required this.end,
    this.detail,
    this.origin,
    this.done = false,
    this.courseId,
  });

  final String id;
  final int day; // 0 = Mon … 6 = Sun
  final String title;
  final Kind kind;
  final int start; // minutes from 00:00
  final int end;
  final String? detail;
  final Origin? origin;
  final bool done;
  final String? courseId;

  int get length => end - start;

  Block copyWith({
    int? day,
    int? start,
    int? end,
    Origin? origin,
    bool clearOrigin = false,
    bool? done,
  }) {
    return Block(
      id: id,
      day: day ?? this.day,
      title: title,
      kind: kind,
      start: start ?? this.start,
      end: end ?? this.end,
      detail: detail,
      origin: clearOrigin ? null : (origin ?? this.origin),
      done: done ?? this.done,
      courseId: courseId,
    );
  }
}

class Course {
  const Course({
    required this.id,
    required this.name,
    required this.days,
    required this.start,
    required this.end,
    required this.room,
    this.selected = true,
    this.code = '',
  });

  final String id;
  final String name;
  final List<int> days;
  final int start;
  final int end;
  final String room;
  final bool selected;
  final String
  code; // course code from the timetable, e.g. COMP6048 ('' if unknown)

  Course toggled() => Course(
    id: id,
    name: name,
    days: days,
    start: start,
    end: end,
    room: room,
    selected: !selected,
    code: code,
  );
}

class Deadline {
  const Deadline({
    required this.id,
    required this.title,
    required this.course,
    required this.estimate,
    required this.due,
    required this.urgent,
    required this.planned,
    this.done = false,
  });

  final String id;
  final String title;
  final String course;
  final int estimate; // minutes
  final String due;
  final bool urgent;
  final int
  planned; // server snapshot, screens derive live progress from blocks
  final bool done;

  DateTime? get dueDate => parseIsoDate(due);

  String get dueLabel => dueLabelFor(due, todayDate, done: done);

  bool get isUrgent => !done && (dueWithinADay(due, todayDate) ?? urgent);

  int plannedFor(List<Block> blocks) {
    final key = title.trim().toLowerCase();
    if (key.isEmpty) return 0;
    var sum = 0;
    for (final b in blocks) {
      if (b.kind == Kind.lecture) continue;
      final title = b.title.trim().toLowerCase();
      if (title == key) sum += b.length;
    }
    return sum;
  }

  Deadline copyWith({int? planned, bool? done}) => Deadline(
    id: id,
    title: title,
    course: course,
    estimate: estimate,
    due: due,
    urgent: urgent,
    planned: planned ?? this.planned,
    done: done ?? this.done,
  );
}

class DayInfo {
  const DayInfo(this.index, this.day);
  final int index;
  final DateTime day;

  String get short => dayShortNames[index].toUpperCase();
  String get long => dayLongNames[index];
  int get date => day.day;
  String get month => monthShortNames[day.month - 1].toUpperCase();
}

DateTime Function() appClock = DateTime.now;

List<DayInfo> get days {
  final monday = mondayOf(appClock());
  return [for (var i = 0; i < 7; i++) DayInfo(i, addDays(monday, i))];
}

DateTime get todayDate => dateOnly(appClock());

int get today => appClock().weekday - 1;

int get now {
  final clock = appClock();
  return clock.hour * 60 + clock.minute;
}

String get monthLabel => monthShortNames[appClock().month - 1].toUpperCase();

const dayStart = 7 * 60;
const dayEnd = 23 * 60;

int h(int hh, [int mm = 0]) => hh * 60 + mm;

List<Block> classBlocks(List<Course> courses) => [
  for (final c in courses.where((c) => c.selected))
    for (final d in c.days)
      Block(
        id: '${c.id}-$d',
        day: d,
        title: c.name,
        kind: Kind.lecture,
        start: c.start,
        end: c.end,
        detail: c.room.isEmpty
            ? null
            : (c.room.startsWith('Lab') ? c.room : 'Room ${c.room}'),
        courseId: c.id,
      ),
];
