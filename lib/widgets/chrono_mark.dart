import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Chrono's mark: a clock face with the first quarter filled in.
class ChronoMark extends StatelessWidget {
  const ChronoMark({
    super.key,
    this.size = 24,
    this.rest = C.ink,
    this.fill = C.lime,
    this.hole = 0,
    this.holeColor = C.bg,
  });

  final double size;
  final Color rest;
  final Color fill;
  final double hole;
  final Color holeColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter(rest, fill, hole, holeColor)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.rest, this.fill, this.hole, this.holeColor);
  final Color rest;
  final Color fill;
  final double hole;
  final Color holeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = rest);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, -math.pi / 2, math.pi / 2, false)
        ..close(),
      Paint()..color = fill,
    );
    if (hole > 0) canvas.drawCircle(c, hole / 2, Paint()..color = holeColor);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.rest != rest || old.fill != fill || old.hole != hole || old.holeColor != holeColor;
}

/// The mark spinning, used while Chrono builds the week.
class SpinningMark extends StatefulWidget {
  const SpinningMark({super.key, this.size = 56});
  final double size;

  @override
  State<SpinningMark> createState() => _SpinningMarkState();
}

class _SpinningMarkState extends State<SpinningMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: CurvedAnimation(parent: _c, curve: easeOut),
      child: ChronoMark(size: widget.size, rest: C.surface2),
    );
  }
}
