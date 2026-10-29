import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../domain/book.dart';

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.width = 120,
    this.height = 164,
  });
  final Book book;
  final double width;
  final double height;

  static const _grounds = [
    Color(0xFFD9E5E0),
    Color(0xFFE9DDD0),
    Color(0xFFDDE6EF),
    Color(0xFFE3E6D1),
    Color(0xFF364C62),
    Color(0xFFDDD9D2),
  ];
  static const _inks = [
    Color(0xFF29483E),
    Color(0xFF6B4537),
    Color(0xFF314B65),
    Color(0xFF49543B),
    Color(0xFFF4EFE3),
    Color(0xFF414944),
  ];

  @override
  Widget build(BuildContext context) {
    final index = book.coverStyle % _grounds.length;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${book.title}封面',
      image: true,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(5),
          bottomRight: Radius.circular(5),
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: _grounds[index],
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _CoverArt(index, _inks[index])),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 5,
                  child: ColoredBox(color: _inks[index].withValues(alpha: .12)),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    width * .13,
                    height * .12,
                    width * .1,
                    height * .1,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: width * .16,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                          color: _inks[index],
                        ),
                      ),
                      SizedBox(height: height * .04),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: math.max(9, width * .065),
                          color: _inks[index].withValues(alpha: .9),
                        ),
                      ),
                      const Spacer(),
                      if (width >= 90)
                        Text(
                          book.isExcerpt ? '公版 · 节选' : '阅读',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            color: _inks[index].withValues(alpha: .8),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverArt extends CustomPainter {
  const _CoverArt(this.style, this.ink);
  final int style;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink.withValues(alpha: .15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cx = size.width * .74;
    final cy = size.height * .73;
    if (style.isEven) {
      for (var i = 0; i < 8; i++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, cy + i * 7),
            width: size.width * .9 + i * 13,
            height: size.height * .25 + i * 8,
          ),
          paint,
        );
      }
    } else {
      for (var i = 0; i < 7; i++) {
        final path = Path()
          ..moveTo(size.width * .22 + i * 8, size.height)
          ..quadraticBezierTo(
            size.width * .3 + i * 14,
            size.height * .6,
            size.width * 1.15,
            size.height * .48 + i * 10,
          );
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CoverArt oldDelegate) =>
      oldDelegate.style != style || oldDelegate.ink != ink;
}
