import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/services/source_runtime/content_normalizer.dart';

void main() {
  test('normalizes whitespace without keyword-based deletion', () {
    final result = const ContentNormalizer().normalize([
      ' 第一章 ',
      '  正文  内容  ',
      '',
      '广告也是故事的一部分',
    ], chapterTitle: '第一章');

    expect(result, ['正文  内容', '广告也是故事的一部分']);
  });

  test('splits embedded blank lines and removes adjacent duplicates', () {
    final result = const ContentNormalizer().normalize([
      '第一段\r\n\r\n第二段',
      '第二段',
      '第三\t段',
    ], chapterTitle: '章名');

    expect(result, ['第一段', '第二段', '第三 段']);
  });

  test(
    'normalizes lightweight HTML boundaries without collapsing inner text',
    () {
      final result = const ContentNormalizer().normalize([
        '﻿　第一章',
        '<br>　甲&nbsp; 乙<br/>',
        '　丙 &amp; 丁',
        '甲  乙',
      ], chapterTitle: '第一章');

      expect(result, ['甲  乙', '丙 & 丁', '甲  乙']);
    },
  );

  test('removes an exact leading chapter title containing punctuation', () {
    final result = const ContentNormalizer().normalize([
      '第一章：起源',
      '正文',
    ], chapterTitle: '第一章：起源');

    expect(result, ['正文']);
  });

  test('keeps leading text that differs from the title in punctuation', () {
    final result = const ContentNormalizer().normalize([
      '为什么',
      '正文',
    ], chapterTitle: '为什么？');

    expect(result, ['为什么', '正文']);
  });

  test('does not remove a later paragraph that equals the chapter title', () {
    final result = const ContentNormalizer().normalize([
      '正文',
      '第一章',
    ], chapterTitle: '第一章');

    expect(result, ['正文', '第一章']);
  });
}
