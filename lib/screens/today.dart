import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../logic/time_utils.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chrono_mark.dart';
import '../widgets/common.dart';

const double hourHeight = 75; // px per hour, from the Figma timeline
double yOf(int min) => (min - dayStart) / 60 * hourHeight;

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _scroll = ScrollController();
  int? _scrolledDay;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _afterBuild(AppState state, List<Block> blocks) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = state.scrollTo;
      if (target != null) {
        final b = state.blocks.where((x) => x.id == target).firstOrNull;
        state.scrolled();
        if (b != null) {
          final viewport = _scroll.position.viewportDimension;
          _scroll.animateTo(
            (yOf(b.start) - viewport / 3).clamp(0, _scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 450),
            curve: easeOut,
          );
        }
        _scrolledDay = state.selectedDay;
        return;
      }
      if (_scrolledDay == state.selectedDay) return;
      _scrolledDay = state.selectedDay;
      final isToday = state.selectedDay == today;
      final anchor = isToday ? yOf(now) - 24 : (blocks.isNotEmpty ? yOf(blocks.first.start) - 44 : yOf(h(8)));
      _scroll.jumpTo(anchor.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final day = state.selectedDay;
    final isToday = day == today;
    final blocks = dayBlocks(state.blocks, day);
    final current = isToday ? blocks.where((b) => b.start <= now && now < b.end).firstOrNull : null;
    final next = isToday ? blocks.where((b) => b.start >= now).firstOrNull : null;
    _afterBuild(state, blocks);

    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: MediaQuery.paddingOf(context).top + 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isToday ? 'Today' : days[day].long, style: poppins(30, weight: w600, lineHeight: 40, letterSpacing: -0.6)),
                Text(
                  '${days[day].long.toUpperCase()} · ${days[day].date} $monthLabel · ${blocks.length} BLOCKS · ${duration(freeMinutes(state.blocks, day))} FREE',
                  style: metaStyle,
                ),
              ]),
            ),
            const Avatar(),
          ]),
        ),
        const SizedBox(height: 16),
        _WeekStrip(state: state),
        if (current != null) _NowStrip(current: current, next: next),
        const SizedBox(height: 10),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: C.line(0.08)))),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(top: 12, bottom: 90),
              child: SizedBox(
                height: yOf(dayEnd) + 10,
                child: Stack(clipBehavior: Clip.none, children: [
                  for (var m = dayStart; m <= dayEnd; m += 60) _HourLine(minute: m),
                  for (final g in freeSlots(state.blocks, day))
                    Positioned(
                      top: yOf(g.start) + 4,
                      left: 58,
                      right: 14,
                      height: g.length / 60 * hourHeight - 12,
                      child: _FreeSlot(span: g, onTap: () => state.goTab(AppTab.chat)),
                    ),
                  for (final b in blocks)
                    Positioned(
                      top: yOf(b.start) - 1,
                      left: 58,
                      right: 14,
                      height: b.length / 60 * hourHeight - 3,
                      child: _TimelineBlock(
                        block: b,
                        past: day < today || (isToday && b.end <= now),
                        onTap: () => state.openSheet(b.id),
                      ),
                    ),
                  if (isToday)
                    Positioned(
                      top: yOf(now) - 1,
                      left: 46,
                      right: 0,
                      child: IgnorePointer(
                        child: Stack(clipBehavior: Clip.none, children: [
                          Container(height: 2, color: C.lime),
                          Positioned(
                            left: -5,
                            top: -4,
                            child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle)),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ]),
      if (state.toast == null)
        Positioned(
          right: 16,
          bottom: 16,
          child: Pressable(
            onTap: () => state.goTab(AppTab.chat),
            child: Container(
              height: 52,
              padding: const EdgeInsets.only(left: 13, right: 19),
              decoration: BoxDecoration(
                color: C.ink,
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 28, offset: Offset(0, 12))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const ChronoMark(size: 26, fill: C.bg, rest: Color(0xFFBDBAC6)),
                const SizedBox(width: 10),
                Text('Something changed?', style: poppins(14.5, weight: w600, color: C.bg)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _Day(index: i, state: state)),
        ],
      ]),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.index, required this.state});
  final int index;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final selected = index == state.selectedDay;
    final has = state.blocks.any((b) => b.day == index);
    final fg = selected ? C.bg : C.ink;
    final dot = selected
        ? C.bg
        : index == today
            ? C.lime
            : has
                ? kindStyle(Kind.breakTime).bar
                : Colors.transparent;
    return Pressable(
      onTap: () => state.selectDay(index),
      selected: selected,
      label: days[index].long,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 60,
        decoration: BoxDecoration(color: selected ? C.ink : Colors.transparent, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          const SizedBox(height: 4),
          Text(
            index == today ? 'TODAY' : days[index].short,
            style: poppins(10.5, weight: w500, color: fg.withValues(alpha: 0.7), lineHeight: 15),
          ),
          const SizedBox(height: 6),
          Text('${days[index].date}', style: poppins(16, weight: w600, color: fg, lineHeight: 23)),
          const SizedBox(height: 5),
          Container(width: 4, height: 4, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        ]),
      ),
    );
  }
}

class _NowStrip extends StatelessWidget {
  const _NowStrip({required this.current, this.next});
  final Block current;
  final Block? next;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
      decoration: panelBox(radius: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('NOW', style: poppins(10.8, weight: w600, color: C.lime, letterSpacing: 0.8)),
          const SizedBox(width: 8),
          Expanded(child: Text(current.title, style: poppins(15, weight: w600))),
          Text('${current.end - now} min left', style: poppins(11, weight: w500, color: C.ink2)),
        ]),
        const SizedBox(height: 8),
        ProgressBar(value: (now - current.start) / current.length, track: C.surface3, height: 4),
        if (next != null) ...[
          const SizedBox(height: 9),
          Text('Next · ${next!.title} at ${clock(next!.start)}', style: poppins(12, color: C.ink2)),
        ],
      ]),
    );
  }
}

class _HourLine extends StatelessWidget {
  const _HourLine({required this.minute});
  final int minute;
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: yOf(minute) - 8,
      left: 0,
      right: 0,
      height: 16,
      child: Row(children: [
        SizedBox(
          width: 45,
          child: Text(
            '${pad(minute ~/ 60)}:00',
            textAlign: TextAlign.right,
            style: poppins(10.5, weight: w500, color: C.ink3, lineHeight: 16),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(child: Container(height: 1, color: C.line(0.07))),
      ]),
    );
  }
}

class _TimelineBlock extends StatelessWidget {
  const _TimelineBlock({required this.block, required this.past, required this.onTap});
  final Block block;
  final bool past;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = block;
    final style = b.origin == Origin.added ? addedStyle : kindStyle(b.kind);
    final height = b.length / 60 * hourHeight - 3;
    final compact = height < 45;
    final title = Text(
      b.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: poppins(13.5, weight: w600, color: style.ink, lineHeight: 16.88, decoration: b.done ? TextDecoration.lineThrough : null),
    );
    final time = Text(range(b.start, b.end), style: poppins(10.5, weight: w500, color: style.ink.withValues(alpha: 0.75)));

    return Opacity(
      opacity: b.done ? 0.45 : (past ? 0.6 : 1),
      child: Pressable(
        onTap: onTap,
        label: '${b.title}, ${range(b.start, b.end)}',
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: style.bg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: b.origin != null
                ? [
                    const BoxShadow(color: C.lime, spreadRadius: 2),
                    BoxShadow(color: C.lime.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 10)),
                  ]
                : null,
          ),
          child: Stack(children: [
            Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: style.bar)),
            Padding(
              padding: EdgeInsets.fromLTRB(14, compact ? 0 : 8, 14, 0),
              child: compact
                  ? Row(children: [Expanded(child: title), time])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      title,
                      const SizedBox(height: 3),
                      time,
                      if (b.detail != null && height >= 70) ...[
                        const SizedBox(height: 4),
                        Text(
                          b.detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: poppins(11.5, color: style.ink.withValues(alpha: 0.75), lineHeight: 14.95),
                        ),
                      ],
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FreeSlot extends StatelessWidget {
  const _FreeSlot({required this.span, required this.onTap});
  final Span span;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      label: 'Free ${duration(span.length)} from ${range(span.start, span.end)}. Ask Chrono to fill it.',
      child: CustomPaint(
        painter: _DashedBorder(color: C.line(0.16), radius: 12),
        child: Center(child: Text('Free · ${duration(span.length)}', style: poppins(11.5, weight: w500, color: C.ink3))),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.5));
    for (final PathMetric m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 3), paint);
        d += 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
