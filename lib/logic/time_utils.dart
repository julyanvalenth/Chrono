import '../data/models.dart';

class Span {
  const Span(this.start, this.end);
  final int start;
  final int end;
  int get length => end - start;
}

String pad(int n) => n.toString().padLeft(2, '0');

String clock(int m) => '${pad(m ~/ 60)}:${pad(m % 60)}';

String range(int a, int b) => '${clock(a)}–${clock(b)}';

String duration(int min) {
  final hh = min ~/ 60;
  final mm = min % 60;
  if (hh == 0) return '${mm}m';
  if (mm == 0) return '${hh}h';
  return '${hh}h ${mm}m';
}

bool overlaps(int aStart, int aEnd, int bStart, int bEnd) => aStart < bEnd && bStart < aEnd;

List<Block> dayBlocks(List<Block> blocks, int day) =>
    blocks.where((b) => b.day == day).toList()..sort((a, b) => a.start.compareTo(b.start));

/// Gaps between blocks inside [from, to].
List<Span> gaps(List<Block> blocks, int day, int from, int to) {
  final out = <Span>[];
  var cursor = from;
  for (final b in dayBlocks(blocks, day)) {
    if (b.start > cursor) out.add(Span(cursor, b.start < to ? b.start : to));
    if (b.end > cursor) cursor = b.end;
    if (cursor >= to) break;
  }
  if (cursor < to) out.add(Span(cursor, to));
  return out.where((g) => g.end > g.start).toList();
}

/// Open time shown in headers: gaps of 15 min or more between 08:00 and 22:40.
int freeMinutes(List<Block> blocks, int day) => gaps(blocks, day, h(8), h(22, 40))
    .map((g) => g.length)
    .where((m) => m >= 15)
    .fold(0, (s, m) => s + m);

/// Slots big enough to show as "Free · 2h" on the timeline.
List<Span> freeSlots(List<Block> blocks, int day) =>
    gaps(blocks, day, h(8), h(22)).where((g) => g.length >= 60).toList();

/// First slot of [len] minutes on [day], starting no earlier than [after], ending by 22:00.
Span? findSlot(List<Block> blocks, int day, int len, int after, {String? ignoreId}) {
  final list = dayBlocks(blocks, day).where((b) => b.id != ignoreId).toList();
  final candidates = <int>[after < h(8) ? h(8) : after, ...list.map((b) => b.end).where((e) => e >= after)]..sort();
  for (final start in candidates) {
    final end = start + len;
    if (end > h(22)) break;
    if (!list.any((b) => overlaps(b.start, b.end, start, end))) return Span(start, end);
  }
  return null;
}
