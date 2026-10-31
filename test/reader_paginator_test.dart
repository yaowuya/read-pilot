import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/ui/reader/reader_paginator.dart';
import 'package:read_pilot/ui/reader/reader_paragraph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bodyStyle = TextStyle(fontSize: 22, height: 1.9);
  const titleStyle = TextStyle(fontSize: 26, height: 1.6);

  test('splits long paragraphs without losing text or exceeding a page', () {
    final longParagraph = '尘世浊浪翻滚。' * 180;
    final layout = ReaderPaginator.paginate(
      title: '第一章',
      paragraphs: ['第一段。', longParagraph],
      maxWidth: 280,
      maxHeight: 420,
      bodyStyle: bodyStyle,
      titleStyle: titleStyle,
      firstPageChromeHeight: 72,
    );

    expect(layout.pages.length, greaterThan(2));
    expect(layout.textForParagraph(0), '第一段。');
    expect(layout.textForParagraph(1), longParagraph);
    expect(layout.pages.every((page) => page.usedHeight <= 420.01), isTrue);
    expect(layout.pages.first.showsChapterHeader, isTrue);
    expect(
      layout.pages.skip(1).every((page) => !page.showsChapterHeader),
      isTrue,
    );
  });

  test(
    'punctuation does not leave usable lines empty before a continuation',
    () {
      final input = '${'甲' * 8}。${'乙' * 31}' * 30;
      const width = 220.0;
      const height = 300.0;
      final layout = ReaderPaginator.paginate(
        title: '第一章',
        paragraphs: [input],
        maxWidth: width,
        maxHeight: height,
        bodyStyle: bodyStyle,
        titleStyle: titleStyle,
        firstPageChromeHeight: 20,
      );
      for (var index = 0; index < layout.pages.length - 1; index++) {
        final page = layout.pages[index];
        expect(page.fragments.last.endsParagraph, isFalse);
        expect(
          height - page.usedHeight,
          lessThan(bodyStyle.fontSize! * bodyStyle.height!),
          reason:
              'Page $index must fill its available lines before continuing.',
        );
      }
      expect(layout.textForParagraph(0), input);
    },
  );

  test(
    'page breaks follow measured lines rather than sentence punctuation',
    () {
      final input = '${'甲' * 8}。${'乙' * 31}' * 30;
      final layout = ReaderPaginator.paginate(
        title: '第一章',
        paragraphs: [input],
        maxWidth: 220,
        maxHeight: 300,
        bodyStyle: bodyStyle,
        titleStyle: titleStyle,
        firstPageChromeHeight: 20,
      );
      var offset = 0;
      for (final fragment in layout.pages.expand((page) => page.fragments)) {
        final indent = !fragment.isContinuation;
        final painter = ReaderParagraph.layout(
          text: input.substring(offset),
          style: bodyStyle,
          width: 220,
          direction: TextDirection.ltr,
          indent: indent,
        );
        final lineEnds = painter.computeLineMetrics().map((line) {
          final position = painter.getPositionForOffset(
            Offset(line.left + line.width / 2, line.baseline),
          );
          return painter.getLineBoundary(position).end - (indent ? 1 : 0);
        }).toSet();
        expect(
          lineEnds,
          contains(fragment.text.length),
          reason: 'A continued page must end on a real typeset line.',
        );
        painter.dispose();
        offset += fragment.text.length;
      }
      expect(offset, input.length);
    },
  );

  test(
    'continued pages preserve source indent, words and grapheme clusters',
    () {
      for (final input in [
        '﻿　 \t${'带有原始缩进的中文正文。' * 80}',
        'A sentence with several different word lengths. ' * 80,
        '👨‍👩‍👧‍👦🇨🇳é' * 80,
      ]) {
        final layout = ReaderPaginator.paginate(
          title: '排版',
          paragraphs: [input],
          maxWidth: 220,
          maxHeight: 300,
          bodyStyle: bodyStyle,
          titleStyle: titleStyle,
          firstPageChromeHeight: 20,
        );
        final fragments = layout.pages
            .expand((page) => page.fragments)
            .toList();
        expect(layout.textForParagraph(0), input);
        expect(fragments.first.isContinuation, isFalse);
        expect(fragments.skip(1).every((part) => part.isContinuation), isTrue);
        expect(fragments.last.endsParagraph, isTrue);
        final clusterEnds = <int>{};
        var clusterEnd = 0;
        for (final cluster in input.characters) {
          clusterEnd += cluster.length;
          clusterEnds.add(clusterEnd);
        }
        var offset = 0;
        for (final fragment in fragments) {
          offset += fragment.text.length;
          expect(clusterEnds, contains(offset));
          if (!fragment.endsParagraph) expect(fragment.trailingSpacing, 0);
        }
        if (input.startsWith('A sentence')) {
          expect(
            fragments
                .take(fragments.length - 1)
                .every((part) => RegExp(r'\s$').hasMatch(part.text)),
            isTrue,
          );
        }
      }
    },
  );

  test('bold and paragraph spacing combinations preserve measured text', () {
    final paragraphs = ['第一段。' * 20, '带有标点的长段正文。😀' * 100, '最后一段。' * 15];
    for (final spacing in [0.0, 40.0]) {
      for (final weight in [FontWeight.w400, FontWeight.bold]) {
        final layout = ReaderPaginator.paginate(
          title: '排版组合',
          paragraphs: paragraphs,
          maxWidth: 280,
          maxHeight: 420,
          bodyStyle: bodyStyle.copyWith(fontWeight: weight),
          titleStyle: titleStyle,
          firstPageChromeHeight: 20,
          paragraphSpacing: spacing,
        );
        expect(layout.pages.every((page) => page.usedHeight <= 420.01), isTrue);
        for (var index = 0; index < paragraphs.length; index++) {
          expect(layout.textForParagraph(index), paragraphs[index]);
        }
        for (final fragment in layout.pages.expand((page) => page.fragments)) {
          expect(fragment.trailingSpacing, inInclusiveRange(0, spacing));
          if (!fragment.endsParagraph) expect(fragment.trailingSpacing, 0);
        }
      }
    }
  });

  test('maps a paragraph anchor to a stable page', () {
    final layout = ReaderPaginator.paginate(
      title: '第二章',
      paragraphs: List.generate(24, (index) => '第 $index 段。' * 8),
      maxWidth: 320,
      maxHeight: 500,
      bodyStyle: bodyStyle,
      titleStyle: titleStyle,
      firstPageChromeHeight: 72,
    );

    final page = layout.pageForParagraph(12);
    expect(page, inInclusiveRange(0, layout.pages.length - 1));
    expect(
      layout.pages[page].fragments.any(
        (fragment) => fragment.paragraphIndex == 12,
      ),
      isTrue,
    );
  });

  test('emoji paragraphs terminate and preserve surrogate pairs', () {
    final input = '😀' * 180;
    final layout = ReaderPaginator.paginate(
      title: '表情',
      paragraphs: [input],
      maxWidth: 120,
      maxHeight: 180,
      bodyStyle: bodyStyle,
      titleStyle: titleStyle,
      firstPageChromeHeight: 20,
    );
    expect(layout.textForParagraph(0), input);
    for (final fragment in layout.pages.expand((page) => page.fragments)) {
      expect(fragment.text.runes.every((rune) => rune == 0x1f600), isTrue);
    }
  });

  test('narrower viewports produce at least as many pages', () {
    final paragraphs = List.generate(16, (index) => '排版测试第 $index 段。' * 10);
    ReaderPageLayout paginate(double width) => ReaderPaginator.paginate(
      title: '第三章',
      paragraphs: paragraphs,
      maxWidth: width,
      maxHeight: 560,
      bodyStyle: bodyStyle,
      titleStyle: titleStyle,
      firstPageChromeHeight: 72,
    );

    expect(paginate(260).pages.length, greaterThan(paginate(520).pages.length));
  });
}
