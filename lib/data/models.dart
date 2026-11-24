// Seed data and models taken from the CHRONO Figma file.

enum Kind { lecture, focus, task, personal, breakTime }

extension KindLabel on Kind {
  String get label => switch (this) {
        Kind.lecture => 'Class',
        Kind.focus => 'Focus',
        Kind.task => 'Task',
        Kind.personal => 'Personal',
        Kind.breakTime => 'Break',
      };

  bool get flexible => this == Kind.focus || this == Kind.task || this == Kind.personal;
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
  final int day; // 0 = Mon … 6 = Sun (week of 12–18 Oct)
  final String title;
  final Kind kind;
  final int start; // minutes from 00:00
  final int end;
  final String? detail;
  final Origin? origin;
  final bool done;
  final String? courseId;

  int get length => end - start;

  Block copyWith({int? day, int? start, int? end, Origin? origin, bool clearOrigin = false, bool? done}) {
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
  final String code; // course code from the timetable, e.g. COMP6048 ('' if unknown)

  Course toggled() =>
      Course(id: id, name: name, days: days, start: start, end: end, room: room, selected: !selected, code: code);
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
  final int planned; // minutes already on the calendar
  final bool done;

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
  const DayInfo(this.short, this.long, this.date, this.month);
  final String short;
  final String long;
  final int date; // day of the month
  final String month; // 'NOV'
}

const _dayNames = [
  ('MON', 'Monday'),
  ('TUE', 'Tuesday'),
  ('WED', 'Wednesday'),
  ('THU', 'Thursday'),
  ('FRI', 'Friday'),
  ('SAT', 'Saturday'),
  ('SUN', 'Sunday'),
];
const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

// ---- Real clock (device time) ----
// The schedule is a weekly template (day 0 = Monday … 6 = Sunday); these map it
// onto the current week. The backend works out "today" the same way from its own
// clock plus the device's UTC offset.

/// The current week, Monday first, with real dates.
List<DayInfo> get days {
  final n = DateTime.now();
  final monday = n.day - (n.weekday - 1);
  return [
    for (var i = 0; i < 7; i++)
      () {
        final d = DateTime(n.year, n.month, monday + i); // DateTime rolls over month ends
        return DayInfo(_dayNames[i].$1, _dayNames[i].$2, d.day, _months[d.month - 1]);
      }(),
  ];
}

/// Today's day index: 0 = Monday … 6 = Sunday.
int get today => DateTime.now().weekday - 1;

/// Tomorrow's day index. The week repeats, so after Sunday comes Monday.
int get tomorrow => (today + 1) % 7;

/// Minutes since midnight, device time.
int get now {
  final n = DateTime.now();
  return n.hour * 60 + n.minute;
}

/// "Good morning" / "Good afternoon" / "Good evening" for the current time.
String get greetingWord => now < h(12) ? 'morning' : now < h(18) ? 'afternoon' : 'evening';

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
            detail: c.room.isEmpty ? null : (c.room.startsWith('Lab') ? c.room : 'Room ${c.room}'),
            courseId: c.id,
          ),
    ];
