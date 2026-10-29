import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    image: true,
    label: '阅读标志',
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: const _BrandPainter()),
      ),
    ),
  );
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter();

  static const _paper = Color(0xFFF2E8D5);
  static const _ink = Color(0xFF28302C);
  static const _cinnabar = Color(0xFFA54636);

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final paper = Paint()..color = _paper;
    final cinnabar = Paint()..color = _cinnabar;
    final ink = Paint()..color = _ink;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(shortest * .17),
      ),
      paper,
    );

    final borderInset = shortest * .115;
    final borderWidth = shortest < 20 ? 1.0 : shortest * .052;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          borderInset,
          borderInset,
          size.width - borderInset * 2,
          size.height - borderInset * 2,
        ),
        Radius.circular(shortest * .075),
      ),
      Paint()
        ..color = _cinnabar
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    canvas.drawCircle(
      Offset(size.width * .69, size.height * .285),
      shortest * .078,
      cinnabar,
    );

    final leftPage = Path()
      ..moveTo(size.width * .49, size.height * .79)
      ..cubicTo(
        size.width * .41,
        size.height * .69,
        size.width * .29,
        size.height * .67,
        size.width * .19,
        size.height * .72,
      )
      ..lineTo(size.width * .19, size.height * .42)
      ..cubicTo(
        size.width * .30,
        size.height * .36,
        size.width * .43,
        size.height * .39,
        size.width * .49,
        size.height * .48,
      )
      ..close();
    final rightPage = Path()
      ..moveTo(size.width * .51, size.height * .79)
      ..cubicTo(
        size.width * .59,
        size.height * .69,
        size.width * .71,
        size.height * .67,
        size.width * .81,
        size.height * .72,
      )
      ..lineTo(size.width * .81, size.height * .42)
      ..cubicTo(
        size.width * .70,
        size.height * .36,
        size.width * .57,
        size.height * .39,
        size.width * .51,
        size.height * .48,
      )
      ..close();
    canvas.drawPath(leftPage, ink);
    canvas.drawPath(rightPage, ink);

    canvas.drawLine(
      Offset(size.width * .50, size.height * .49),
      Offset(size.width * .50, size.height * .785),
      Paint()
        ..color = _paper
        ..strokeWidth = shortest < 20 ? 1 : shortest * .027,
    );

    if (shortest >= 28) {
      final line = Paint()
        ..color = _paper
        ..strokeWidth = shortest * .012;
      for (final y in [.53, .59]) {
        canvas.drawLine(
          Offset(size.width * .25, size.height * y),
          Offset(size.width * .43, size.height * (y + .015)),
          line,
        );
        canvas.drawLine(
          Offset(size.width * .57, size.height * (y + .015)),
          Offset(size.width * .75, size.height * y),
          line,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BrandPainter oldDelegate) => false;
}
