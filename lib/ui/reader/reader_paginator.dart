import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'reader_paragraph.dart';

/// A source-text slice retaining its paragraph index across page boundaries.
@immutable
final class ReaderPageFragment {
  const ReaderPageFragment({
    required this.paragraphIndex,
    required this.text,
    required this.isContinuation,
    required this.indent,
    required this.endsParagraph,
    required this.trailingSpacing,
  });

  final int paragraphIndex;
  final String text;
  final bool isContinuation;

  /// 这一段的第一行是否需要两字缩进；由排版规则决定，渲染必须与测量一致。
  final bool indent;
  final bool endsParagraph;
  final double trailingSpacing;
}

/// A transient measured page; its anchors always refer to source paragraphs.
@immutable
final class ReaderPage {
  ReaderPage({
    required Iterable<ReaderPageFragment> fragments,
    required this.showsChapterHeader,
    required this.usedHeight,
  }) : fragments = List.unmodifiable(fragments);

  final List<ReaderPageFragment> fragments;
  final bool showsChapterHeader;
  final double usedHeight;

  int get anchorParagraphIndex =>
      fragments.isEmpty ? 0 : fragments.first.paragraphIndex;
}

/// Immutable layout generated from chapter text and the current viewport.
@immutable
final class ReaderPageLayout {
  ReaderPageLayout(Iterable<ReaderPage> pages)
    : pages = List.unmodifiable(pages);

  final List<ReaderPage> pages;

  /// Finds the first containing page, or the preceding page for skipped anchors.
  int pageForParagraph(int paragraphIndex) {
    final exact = pages.indexWhere(
      (page) => page.fragments.any(
        (fragment) => fragment.paragraphIndex == paragraphIndex,
      ),
    );
    if (exact >= 0) return exact;
    for (var index = pages.length - 1; index >= 0; index--) {
      if (pages[index].anchorParagraphIndex <= paragraphIndex) return index;
    }
    return 0;
  }

  /// Rejoins source fragments without adding display-only indentation or gaps.
  String textForParagraph(int paragraphIndex) => pages
      .expand((page) => page.fragments)
      .where((fragment) => fragment.paragraphIndex == paragraphIndex)
      .map((fragment) => fragment.text)
      .join();
}

/// Splits chapter paragraphs into measured pages without persisting page numbers.
abstract final class ReaderPaginator {
  static ReaderPageLayout paginate({
    required String title,
    required List<String> paragraphs,
    required double maxWidth,
    required double maxHeight,
    required TextStyle bodyStyle,
    required TextStyle titleStyle,
    required double firstPageChromeHeight,
    double paragraphSpacing = 20,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    if (maxWidth <= 0 || maxHeight <= 0) {
      throw ArgumentError('Reader viewport dimensions must be positive.');
    }

    final titleHeight = _measure(title, titleStyle, maxWidth, textDirection);
    final firstHeaderHeight = titleHeight + firstPageChromeHeight;
    final lineHeight = _measure('字', bodyStyle, maxWidth, textDirection);
    if (firstHeaderHeight + lineHeight > maxHeight || lineHeight > maxHeight) {
      throw ArgumentError('Reader viewport is too short for one line of text.');
    }

    final pages = <ReaderPage>[];
    var fragments = <ReaderPageFragment>[];
    var usedHeight = firstHeaderHeight;
    var showsHeader = true;

    void finishPage() {
      if (fragments.isEmpty && !showsHeader) return;
      // 页底不留段间距：段落间距只在同一页内的两段之间才有意义，
      // 留在页尾会变成正文与页脚之间的空白，让每页正文下沿忽高忽低。
      if (fragments.isNotEmpty) {
        final last = fragments.last;
        if (last.trailingSpacing != 0) {
          fragments[fragments.length - 1] = ReaderPageFragment(
            paragraphIndex: last.paragraphIndex,
            text: last.text,
            isContinuation: last.isContinuation,
            indent: last.indent,
            endsParagraph: last.endsParagraph,
            trailingSpacing: 0,
          );
          usedHeight -= last.trailingSpacing;
        }
      }
      pages.add(
        ReaderPage(
          fragments: fragments,
          showsChapterHeader: showsHeader,
          usedHeight: usedHeight,
        ),
      );
      fragments = <ReaderPageFragment>[];
      usedHeight = 0;
      showsHeader = false;
    }

    for (
      var paragraphIndex = 0;
      paragraphIndex < paragraphs.length;
      paragraphIndex++
    ) {
      final paragraph = paragraphs[paragraphIndex];
      if (ReaderParagraph.withoutSourceIndent(paragraph).isEmpty) continue;
      // 章节正文的第一段按设计稿不缩进（设计稿的 .first-paragraph），
      // 其余段落在首行缩进两字。
      final firstParagraph = paragraphIndex == 0;
      var offset = 0;
      while (offset < paragraph.length) {
        var available = maxHeight - usedHeight;
        if (available + 0.01 < lineHeight) {
          finishPage();
          available = maxHeight;
        }

        final remaining = paragraph.substring(offset);
        final remainingHeight = _measure(
          remaining,
          bodyStyle,
          maxWidth,
          textDirection,
          indent: offset == 0 && !firstParagraph,
        );
        if (remainingHeight <= available + 0.01) {
          final spacing = math.min(
            paragraphSpacing,
            maxHeight - usedHeight - remainingHeight,
          );
          fragments.add(
            ReaderPageFragment(
              paragraphIndex: paragraphIndex,
              text: remaining,
              isContinuation: offset > 0,
              indent: offset == 0 && !firstParagraph,
              endsParagraph: true,
              trailingSpacing: math.max(0, spacing),
            ),
          );
          usedHeight += remainingHeight;
          offset = paragraph.length;
          if (spacing > 0) usedHeight += spacing;
          continue;
        }

        final end = _largestFittingEnd(
          paragraph,
          offset,
          available,
          bodyStyle,
          maxWidth,
          textDirection,
          firstParagraph: firstParagraph,
        );
        if (end <= offset) {
          if (fragments.isNotEmpty || showsHeader) {
            finishPage();
            continue;
          }
          throw ArgumentError('Reader viewport is too short for chapter text.');
        }
        final text = paragraph.substring(offset, end);
        fragments.add(
          ReaderPageFragment(
            paragraphIndex: paragraphIndex,
            text: text,
            isContinuation: offset > 0,
            indent: offset == 0 && !firstParagraph,
            endsParagraph: false,
            trailingSpacing: 0,
          ),
        );
        usedHeight += _measure(
          text,
          bodyStyle,
          maxWidth,
          textDirection,
          indent: offset == 0 && !firstParagraph,
        );
        offset = end;
        finishPage();
      }
    }

    if (fragments.isNotEmpty || pages.isEmpty) finishPage();
    return ReaderPageLayout(pages);
  }

  static int _largestFittingEnd(
    String text,
    int start,
    double availableHeight,
    TextStyle style,
    double width,
    TextDirection direction, {
    required bool firstParagraph,
  }) {
    final remaining = text.substring(start);
    final indent = start == 0 && !firstParagraph;
    final removedIndent = indent
        ? remaining.length -
              ReaderParagraph.withoutSourceIndent(remaining).length
        : 0;
    final painter = ReaderParagraph.layout(
      text: remaining,
      style: style,
      width: width,
      direction: direction,
      indent: indent,
    );
    var best = start;
    for (final line in painter.computeLineMetrics()) {
      if (line.baseline + line.descent > availableHeight + 0.01) break;
      final position = painter.getPositionForOffset(
        Offset(line.left + line.width / 2, line.baseline),
      );
      // TextPainter counts the indent placeholder, but not source indentation.
      final end =
          start +
          painter.getLineBoundary(position).end +
          removedIndent -
          (indent ? 1 : 0);
      best = end.clamp(start, text.length);
    }
    painter.dispose();
    return best;
  }

  static double _measure(
    String text,
    TextStyle style,
    double width,
    TextDirection direction, {
    bool indent = false,
  }) {
    final painter = ReaderParagraph.layout(
      text: text,
      style: style,
      width: width,
      direction: direction,
      indent: indent,
    );
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
