import 'package:flutter/material.dart';

/// Shares a measured two-em first-line indent between paged and scrolling text.
class ReaderParagraph extends StatelessWidget {
  const ReaderParagraph({
    super.key,
    required this.text,
    required this.style,
    this.isContinuation = false,
    this.selectable = false,
  });

  final String text;
  final TextStyle style;
  final bool isContinuation;
  final bool selectable;

  static double indentWidth(TextStyle style) => (style.fontSize ?? 14) * 2;

  static String withoutSourceIndent(String text) =>
      text.replaceFirst(RegExp(r'^[\s   -​  　﻿]+'), '');

  static TextSpan textSpan(
    String text,
    TextStyle style, {
    required bool indent,
  }) => TextSpan(
    style: style,
    children: [
      if (indent)
        WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: SizedBox(width: indentWidth(style), height: 0),
        ),
      TextSpan(text: indent ? withoutSourceIndent(text) : text),
    ],
  );

  /// The caller owns the painter and must dispose it after measuring.
  static TextPainter layout({
    required String text,
    required TextStyle style,
    required double width,
    required TextDirection direction,
    required bool indent,
  }) {
    final painter = TextPainter(
      text: textSpan(text, style, indent: indent),
      textAlign: TextAlign.justify,
      textDirection: direction,
      textScaler: TextScaler.noScaling,
    );
    if (indent) {
      painter.setPlaceholderDimensions([
        PlaceholderDimensions(
          size: Size(indentWidth(style), 0),
          alignment: PlaceholderAlignment.bottom,
        ),
      ]);
    }
    painter.layout(maxWidth: width);
    return painter;
  }

  @override
  Widget build(BuildContext context) {
    final paragraph = Text.rich(
      textSpan(text, style, indent: !isContinuation),
      style: style,
      textAlign: TextAlign.justify,
      textScaler: TextScaler.noScaling,
      semanticsLabel: isContinuation ? text : withoutSourceIndent(text),
    );
    return selectable ? SelectionArea(child: paragraph) : paragraph;
  }
}
