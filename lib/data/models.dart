// Models and calendar helpers.

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
  const DayInfo(this.short, this.long, this.date);
  final String short;
  final String long;
  final int date;
}


const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The current week, Monday first, with real dates.
List<DayInfo> get days {
  final clock = DateTime.now();
  final monday = clock.subtract(Duration(days: clock.weekday - 1));
  return [
    for (var i = 0; i < 7; i++)
      DayInfo(
        _dayNames[i].substring(0, 3).toUpperCase(),
        _dayNames[i],
        monday.add(Duration(days: i)).day,
      ),
  ];
}

/// Day index for right now: 0 = Monday … 6 = Sunday.
int get today => DateTime.now().weekday - 1;

/// Minutes since midnight for right now.
int get now {
  final clock = DateTime.now();
  return clock.hour * 60 + clock.minute;
}

const _monthNames = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// Short month name for right now, for the header labels.
String get monthLabel => _monthNames[DateTime.now().month - 1];

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
