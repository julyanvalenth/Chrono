const dayLongNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const dayShortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthShortNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

DateTime mondayOf(DateTime d) => addDays(d, -(d.weekday - 1));

int daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

DateTime? _validDate(int y, int m, int d) {
  final dt = DateTime(y, m, d);
  return dt.year == y && dt.month == m && dt.day == d ? dt : null;
}

DateTime? parseIsoDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  return _validDate(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

int? weekIndexOf(DateTime d, DateTime today) {
  final i = daysBetween(mondayOf(today), d);
  return i >= 0 && i <= 6 ? i : null;
}

String dayLabelOf(int index, DateTime today) {
  final d = addDays(mondayOf(today), index);
  return '${dayShortNames[index]} ${d.day} ${monthShortNames[d.month - 1]}';
}

String dueLabelFor(String due, DateTime today, {bool done = false}) {
  final d = parseIsoDate(due);
  if (d == null) return due;
  final diff = daysBetween(dateOnly(today), d);
  if (diff < 0) return done ? 'Past' : 'Overdue';
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  final fromMonday = daysBetween(mondayOf(today), d);
  final short = dayShortNames[d.weekday - 1];
  if (fromMonday <= 6) return short;
  if (fromMonday <= 13) return 'Next $short';
  return '${d.day} ${monthShortNames[d.month - 1]}';
}

bool? dueWithinADay(String due, DateTime today) {
  final d = parseIsoDate(due);
  if (d == null) return null;
  return daysBetween(dateOnly(today), d) <= 1;
}

const _months = {
  'jan': 1,
  'januari': 1,
  'january': 1,
  'feb': 2,
  'februari': 2,
  'february': 2,
  'mar': 3,
  'maret': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'mei': 5,
  'may': 5,
  'jun': 6,
  'juni': 6,
  'june': 6,
  'jul': 7,
  'juli': 7,
  'july': 7,
  'agu': 8,
  'agt': 8,
  'agustus': 8,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'okt': 10,
  'oktober': 10,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'des': 12,
  'desember': 12,
  'dec': 12,
  'december': 12,
};

const _monthRe =
    'januari|january|jan|februari|february|feb|maret|march|mar|april|apr|mei|may|juni|june|jun|juli|july|jul|'
    'agustus|august|agu|agt|aug|september|sept|sep|oktober|october|okt|oct|november|nov|desember|december|des|dec';

const _weekdays = {
  'monday': 0,
  'mon': 0,
  'senin': 0,
  'tuesday': 1,
  'tues': 1,
  'tue': 1,
  'selasa': 1,
  'wednesday': 2,
  'wed': 2,
  'rabu': 2,
  'thursday': 3,
  'thurs': 3,
  'thur': 3,
  'thu': 3,
  'kamis': 3,
  'friday': 4,
  'fri': 4,
  'jumat': 4,
  "jum'at": 4,
  'saturday': 5,
  'sat': 5,
  'sabtu': 5,
  'sunday': 6,
  'sun': 6,
  'minggu': 6,
  'ahad': 6,
};

DateTime? _inferYear(int month, int day, DateTime today) {
  final t = dateOnly(today);
  final c = _validDate(t.year, month, day);
  if (c == null) return null;
  return daysBetween(c, t) > 180 ? _validDate(t.year + 1, month, day) : c;
}

List<DateTime> parseDateRefs(String text, DateTime today) {
  final t0 = dateOnly(today);
  var work = text.toLowerCase();
  final found = <(int, DateTime)>[];

  void mask(RegExpMatch m) {
    work = work.replaceRange(m.start, m.end, ' ' * (m.end - m.start));
  }

  void run(RegExp re, DateTime? Function(RegExpMatch m) toDate) {
    for (final m in re.allMatches(work).toList()) {
      final d = toDate(m);
      if (d == null) continue;
      found.add((m.start, d));
      mask(m);
    }
  }

  run(
    RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b'),
    (m) => _validDate(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    ),
  );

  run(RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b'), (m) {
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    if (m.group(3) != null) {
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      return _validDate(y, mo, d);
    }
    return _inferYear(mo, d, t0);
  });

  run(
    RegExp(
      '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?($_monthRe)\\b(?:,?\\s+(\\d{4}))?',
    ),
    (m) {
      final y = m.group(3) == null ? null : int.parse(m.group(3)!);
      final d = int.parse(m.group(1)!);
      final mo = _months[m.group(2)!]!;
      return y != null ? _validDate(y, mo, d) : _inferYear(mo, d, t0);
    },
  );

  run(
    RegExp(
      '\\b($_monthRe)\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?!:)(?:,?\\s+(\\d{4}))?',
    ),
    (m) {
      final y = m.group(3) == null ? null : int.parse(m.group(3)!);
      final d = int.parse(m.group(2)!);
      final mo = _months[m.group(1)!]!;
      return y != null ? _validDate(y, mo, d) : _inferYear(mo, d, t0);
    },
  );

  run(RegExp(r'\b(?:tanggal|tgl)\.?\s*(\d{1,2})(?!\d)'), (m) {
    final d = int.parse(m.group(1)!);
    final thisMonth = _validDate(t0.year, t0.month, d);
    if (thisMonth != null && !thisMonth.isBefore(t0)) return thisMonth;
    final next = DateTime(t0.year, t0.month + 1, 1);
    return _validDate(next.year, next.month, d);
  });

  run(RegExp(r'\b(?:day after tomorrow|lusa)\b'), (_) => addDays(t0, 2));
  run(RegExp(r'\b(?:tomorrow|tmrw|besok)\b'), (_) => addDays(t0, 1));
  run(RegExp(r'\b(?:yesterday|kemarin)\b'), (_) => addDays(t0, -1));
  run(RegExp(r'\b(?:today|tonight|hari ini|malam ini)\b'), (_) => t0);

  run(
    RegExp(
      r"\b(?:(next|depan)\s+)?(monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat|sunday|sun|senin|selasa|rabu|kamis|jum'?at|sabtu|minggu|ahad)\b(\s+(?:depan|next)\b)?",
    ),
    (m) {
      final key = m.group(2)!.replaceAll("'", '');
      if (key == 'minggu' &&
          (m.group(3) != null ||
              RegExp(
                r'^\s*(ini|lalu|kemarin|depan|ke-?\d|\d)',
              ).hasMatch(work.substring(m.end)))) {
        return null;
      }
      final idx = _weekdays[key]!;
      var date = addDays(mondayOf(t0), idx);
      if (m.group(1) != null || m.group(3) != null) {
        date = addDays(date, 7);
      } else if (date.isBefore(t0)) {
        date = addDays(date, 7);
      }
      return date;
    },
  );

  found.sort((a, b) => a.$1.compareTo(b.$1));
  final out = <DateTime>[];
  for (final (_, d) in found) {
    if (!out.any((o) => o == d)) out.add(d);
  }
  return out;
}
