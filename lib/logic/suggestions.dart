import '../data/models.dart';
import 'time_utils.dart';

/// Shortcut prompts built from what is actually on the user's calendar right
/// now, plus their saved preferences. Shared by Home and Chat so both pages
/// offer the same relevant actions instead of a fixed demo list.
List<String> suggestPrompts({
  required List<Block> blocks,
  required List<Deadline> deadlines,
  required String focusWindow,
  required String bedtime,
  required int day,
  required int now,
}) {
  final out = <String>[];
  final todays = dayBlocks(blocks, day);

  final classesLeft = todays
      .where((b) => b.kind == Kind.lecture && b.end > now)
      .toList();
  final flexible = todays
      .where((b) => b.kind.flexible && !b.done && b.end > now)
      .toList();
  final openDeadlines = deadlines.where((d) => !d.done).toList()
    ..sort((a, b) {
      if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
      return (a.estimate - a.plannedFor(blocks)).compareTo(
        b.estimate - b.plannedFor(blocks),
      );
    });

  final behind = openDeadlines
      .where((d) => d.plannedFor(blocks) < d.estimate)
      .toList();
  if (behind.isNotEmpty) out.add('Plan time for ${behind.first.title}');

  if (classesLeft.isNotEmpty) {
    final next = classesLeft.first;
    out.add('When is ${next.title}?');
  }

  if (flexible.isNotEmpty) {
    out.add('Skip ${flexible.first.title.toLowerCase()} today');
  }

  final freeNow = gaps(
    blocks,
    day,
    now > h(8) ? now : h(8),
    h(22),
  ).where((g) => g.length >= 60);
  if (freeNow.isNotEmpty) out.add('Find me a focus block today');

  // Preferences: nudge toward the chosen focus window / bedtime.
  if (focusWindow == 'morning' && now >= h(12)) {
    out.add('Move my focus work to tomorrow morning');
  } else if (focusWindow == 'night' && now < h(18)) {
    out.add('Plan my focus block for tonight');
  }
  if (now >= h(21)) out.add('Wrap up before $bedtime');

  if (out.isEmpty) {
    out.addAll(const [
      'How does my day look?',
      'Add a meeting tomorrow at 3pm for 1h',
    ]);
  }
  return out.take(4).toList();
}
