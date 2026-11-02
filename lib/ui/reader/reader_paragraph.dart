import 'package:flutter/material.dart';

final class ReaderTextHighlight {
  const ReaderTextHighlight({required this.text, required this.color});

  final String text;
  final Color color;
}

/// Shares a measured two-em first-line indent between paged and scrolling text.
class ReaderParagraph extends StatelessWidget {
  const ReaderParagraph({
    super.key,
    required this.text,
    required this.style,
    this.isContinuation = false,
    this.selectable = false,
    this.highlights = const [],
    this.onSelectionChanged,
  });

  final String text;
  final TextStyle style;
  final bool isContinuation;
  final bool selectable;
  final List<ReaderTextHighlight> highlights;
  final ValueChanged<String?>? onSelectionChanged;

  static double indentWidth(TextStyle style) => (style.fontSize ?? 14) * 2;

  static String withoutSourceIndent(String text) =>
      text.replaceFirst(RegExp(r'^[\s   -​  　﻿]+'), '');

  static TextSpan textSpan(
    String text,
    TextStyle style, {
    required bool indent,
    Iterable<ReaderTextHighlight> highlights = const [],
  }) {
    final visibleText = indent ? withoutSourceIndent(text) : text;
    return TextSpan(
      style: style,
      children: [
        if (indent)
          WidgetSpan(
            alignment: PlaceholderAlignment.bottom,
            child: SizedBox(width: indentWidth(style), height: 0),
          ),
        ..._highlightedTextSpans(visibleText, style, highlights),
      ],
    );
  }

  static List<InlineSpan> _highlightedTextSpans(
    String text,
    TextStyle style,
    Iterable<ReaderTextHighlight> highlights,
  ) {
    final ranges = <({int start, int end, Color color})>[];
    for (final highlight in highlights) {
      if (highlight.text.isEmpty) continue;
      final start = text.indexOf(highlight.text);
      if (start < 0 || text.indexOf(highlight.text, start + 1) >= 0) continue;
      ranges.add((
        start: start,
        end: start + highlight.text.length,
        color: highlight.color,
      ));
    }
    ranges.sort((left, right) => left.start.compareTo(right.start));

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.start < cursor) continue;
      if (range.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, range.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: style.copyWith(
            backgroundColor: range.color.withValues(alpha: .45),
          ),
        ),
      );
      cursor = range.end;
    }
    if (cursor < text.length || spans.isEmpty) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

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
      textSpan(text, style, indent: !isContinuation, highlights: highlights),
      style: style,
      textAlign: TextAlign.justify,
      textScaler: TextScaler.noScaling,
      semanticsLabel: isContinuation ? text : withoutSourceIndent(text),
    );
    return selectable
        ? SelectionArea(
            onSelectionChanged: (content) =>
                onSelectionChanged?.call(content?.plainText),
            child: paragraph,
          )
        : paragraph;
  }
}
