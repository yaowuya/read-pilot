import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/book.dart';

/// Displays a safely loaded cover image with the existing generated fallback.
class BookCover extends StatefulWidget {
  const BookCover({
    super.key,
    required this.book,
    this.imageLoader,
    this.onMissingCover,
    this.width = 120,
    this.height = 164,
  });

  final Book book;
  final Future<Uint8List?> Function(Book book)? imageLoader;

  /// Called once when a remote book has no cover URL yet.
  final Future<void> Function(Book book)? onMissingCover;
  final double width;
  final double height;

  @override
  State<BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends State<BookCover> {
  Future<Uint8List?>? _image;

  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.book.coverUrl == null &&
        widget.book.isRemote &&
        widget.onMissingCover != null) {
      widget.onMissingCover!(widget.book);
    }
  }

  @override
  void didUpdateWidget(covariant BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book != widget.book ||
        oldWidget.book.coverUrl != widget.book.coverUrl ||
        oldWidget.book.sourceId != widget.book.sourceId ||
        oldWidget.imageLoader != widget.imageLoader) {
      _reload();
    }
  }

  void _reload() {
    _image = widget.book.coverUrl == null || widget.imageLoader == null
        ? null
        : widget.imageLoader!(widget.book);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    excludeSemantics: true,
    label: '${widget.book.title}封面',
    image: true,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: _image == null
            ? _generated()
            : FutureBuilder<Uint8List?>(
                future: _image,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (snapshot.connectionState == ConnectionState.done &&
                      bytes != null &&
                      bytes.isNotEmpty) {
                    return Image.memory(
                      bytes,
                      key: const Key('book-cover-image'),
                      width: widget.width,
                      height: widget.height,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _generated(),
                    );
                  }
                  return _generated();
                },
              ),
      ),
    ),
  );

  Widget _generated() => _GeneratedCover(
    key: const Key('book-cover-generated'),
    book: widget.book,
    width: widget.width,
    height: widget.height,
  );
}

class _GeneratedCover extends StatelessWidget {
  const _GeneratedCover({
    super.key,
    required this.book,
    required this.width,
    required this.height,
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
    return ColoredBox(
      color: _grounds[index],
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _CoverArt(index, _inks[index])),
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
