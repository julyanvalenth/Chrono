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
  const DayInfo(this.short, this.long, this.date);
  final String short;
  final String long;
  final int date;
}


const days = [
  DayInfo('MON', 'Monday', 12),
  DayInfo('TUE', 'Tuesday', 13),
  DayInfo('WED', 'Wednesday', 14),
  DayInfo('THU', 'Thursday', 15),
  DayInfo('FRI', 'Friday', 16),
  DayInfo('SAT', 'Saturday', 17),
  DayInfo('SUN', 'Sunday', 18),
];

/// Demo clock: Thursday 15 Oct, 10:40 — the "Happening now" state in the design.
const today = 3;
const now = 10 * 60 + 40;

const dayStart = 7 * 60;
const dayEnd = 23 * 60;

int h(int hh, [int mm = 0]) => hh * 60 + mm;

final seedCourses = [
  Course(id: 'ds', name: 'Data Structures', days: const [0, 3], start: h(8), end: h(9, 40), room: 'B-302'),
  Course(id: 'stats', name: 'Statistics', days: const [1, 3], start: h(10), end: h(11, 40), room: 'A-204'),
  Course(id: 'hci', name: 'Human–Computer Interaction', days: const [4], start: h(9), end: h(10, 40), room: 'Lab 3'),
  Course(id: 'se', name: 'Software Engineering', days: const [2, 4], start: h(13), end: h(14, 40), room: 'B-105'),
  Course(id: 'calc', name: 'Calculus II', days: const [0], start: h(13), end: h(14, 40), room: 'A-110'),
];

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

final seedFlexBlocks = [
  Block(id: 'routine-3', day: 3, title: 'Morning routine', kind: Kind.personal, start: h(7, 30), end: h(8)),
  Block(id: 'lunch-3', day: 3, title: 'Lunch', kind: Kind.breakTime, start: h(12), end: h(12, 45)),
  Block(id: 'quiz-3', day: 3, title: 'Algorithm quiz prep', kind: Kind.focus, start: h(13), end: h(14, 30)),
  Block(id: 'hci-essay-3', day: 3, title: 'HCI essay draft', kind: Kind.task, start: h(14, 45), end: h(15, 45)),
  Block(id: 'gym-3', day: 3, title: 'Gym', kind: Kind.personal, start: h(16), end: h(17)),
  Block(id: 'report-3', day: 3, title: 'Statistics report', kind: Kind.focus, start: h(19), end: h(20, 30)),
  Block(id: 'plan-3', day: 3, title: 'Plan tomorrow', kind: Kind.personal, start: h(21), end: h(21, 30)),
  Block(id: 'report-4', day: 4, title: 'Statistics report', kind: Kind.focus, start: h(15), end: h(16, 30)),
  Block(
    id: 'logo-4',
    day: 4,
    title: 'Logo revisions',
    kind: Kind.task,
    start: h(19),
    end: h(20, 30),
    detail: 'Freelance · client: Kopi Senja',
  ),
];

const seedDeadlines = [
  Deadline(id: 'd-quiz', title: 'Algorithm quiz prep', course: 'Data Structures', estimate: 180, due: 'Tomorrow', urgent: true, planned: 180),
  Deadline(id: 'd-logo', title: 'Logo revisions', course: 'Freelance', estimate: 90, due: 'Tomorrow', urgent: true, planned: 90),
  Deadline(id: 'd-hci', title: 'HCI essay draft', course: 'Human–Computer Interaction', estimate: 240, due: 'Sun', urgent: false, planned: 270),
  Deadline(id: 'd-report', title: 'Statistics report', course: 'Statistics', estimate: 300, due: 'Next Mon', urgent: false, planned: 270),
  Deadline(id: 'd-bem', title: 'BEM event proposal', course: 'Student organization', estimate: 120, due: 'Next Tue', urgent: false, planned: 0),
  Deadline(id: 'd-calc', title: 'Calculus problem set 4', course: 'Calculus II', estimate: 120, due: 'Past', urgent: false, planned: 120, done: true),
];
