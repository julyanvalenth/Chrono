// Tab icons traced from the vector networks in the Figma file (24×24, 1.8 stroke).
import 'package:flutter/material.dart';

enum TabGlyph { home, today, deadlines }

class TabIcon extends StatelessWidget {
  const TabIcon(this.glyph, {super.key, required this.color});
  final TabGlyph glyph;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: 24, child: CustomPaint(painter: _IconPainter(glyph, color)));
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.glyph, this.color);
  final TabGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case TabGlyph.home:
        canvas.drawPath(
          Path()
            ..moveTo(4, 10.5)
            ..lineTo(12, 4)
            ..lineTo(20, 10.5)
            ..lineTo(20, 19)
            ..arcToPoint(const Offset(18.5, 20.5), radius: const Radius.circular(1.5))
            ..lineTo(15, 20.5)
            ..lineTo(15, 14.5)
            ..lineTo(9, 14.5)
            ..lineTo(9, 20.5)
            ..lineTo(5.5, 20.5)
            ..arcToPoint(const Offset(4, 19), radius: const Radius.circular(1.5))
            ..close(),
          p,
        );
      case TabGlyph.today:
        p.strokeJoin = StrokeJoin.miter;
        canvas.drawRRect(RRect.fromLTRBR(3.5, 5, 20.5, 20, const Radius.circular(3)), p);
        canvas.drawPath(
          Path()
            ..moveTo(3.5, 10)
            ..lineTo(20.5, 10)
            ..moveTo(8, 3)
            ..lineTo(8, 7)
            ..moveTo(16, 3)
            ..lineTo(16, 7),
          p,
        );
      case TabGlyph.deadlines:
        final path = Path();
        for (final y in [6.0, 12.0, 18.0]) {
          path
            ..moveTo(10, y)
            ..lineTo(20, y)
            ..moveTo(3.5, y)
            ..lineTo(5, y + 1.5)
            ..lineTo(7.5, y - 1.5);
        }
        canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.glyph != glyph || old.color != color;
}
