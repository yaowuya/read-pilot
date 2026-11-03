import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/services/txt_importer.dart';

void main() {
  final importer = TxtImporter();

  test('imports Chinese chapter headings and derives filename title', () {
    final book = importer.parse(
      Uint8List.fromList(utf8.encode('第一章 起风\n\n正文。\n\n第二章 归来\n\n新一章。')),
      '旅行.txt',
    );
    expect(book.title, '旅行');
    expect(book.chapters.length, 2);
    expect(book.chapters.first.title, '第一章 起风');
    expect(book.chapters.last.title, '第二章 归来');
    expect(book.chapters.last.paragraphs.single, '新一章。');
    expect(book.sourceLabel, '本地导入');
  });

  test('retains an introduction before the first chapter', () {
    final book = importer.parse(
      Uint8List.fromList(utf8.encode('引言文字。\n\n第一章 开始\n正文。')),
      '小书.txt',
    );
    expect(book.chapters.length, 2);
    expect(book.chapters.first.paragraphs, ['引言文字。']);
  });

  test('accepts UTF-8 BOM and normalizes Windows newlines', () {
    final book = importer.parse(
      Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode('一段。\r\n\r\n二段。')]),
      '文本.TXT',
    );
    expect(book.title, '文本');
    expect(book.chapters.single.paragraphs, ['一段。', '二段。']);
  });

  test('accepts UTF-16 LE with a BOM', () {
    final bytes = <int>[0xff, 0xfe];
    for (final unit in '中文阅读。'.codeUnits) {
      bytes.addAll([unit & 0xff, unit >> 8]);
    }
    final book = importer.parse(Uint8List.fromList(bytes), '中文.txt');
    expect(book.chapters.single.paragraphs.single, '中文阅读。');
  });

  for (final littleEndian in [true, false]) {
    Uint8List utf16Bytes(List<int> units) => Uint8List.fromList([
      if (littleEndian) ...[0xff, 0xfe] else ...[0xfe, 0xff],
      for (final unit in units)
        if (littleEndian) ...[
          unit & 0xff,
          unit >> 8,
        ] else ...[
          unit >> 8,
          unit & 0xff,
        ],
    ]);

    test('accepts UTF-16 surrogate pairs, littleEndian=$littleEndian', () {
      final book = importer.parse(utf16Bytes('正文𠮷🌙。'.codeUnits), '完整.txt');
      expect(book.chapters.single.paragraphs.single, '正文𠮷🌙。');
    });

    for (final units in [
      [0xd800],
      [0xdc00],
      [0xd800, 0x0041],
      [0xd800, 0xd800],
    ]) {
      test('rejects unpaired UTF-16 $units, littleEndian=$littleEndian', () {
        expect(
          () => importer.parse(utf16Bytes(units), '坏.txt'),
          throwsFormatException,
        );
      });
    }
  }

  test('rejects unsupported invalid encodings instead of corrupting text', () {
    expect(
      () => importer.parse(Uint8List.fromList([0xff, 0xff, 0x80]), '坏.txt'),
      throwsFormatException,
    );
  });

  test('rejects empty and oversized files', () {
    expect(() => importer.parse(Uint8List(0), '空.txt'), throwsFormatException);
    expect(
      () => importer.parse(Uint8List(2 * 1024 * 1024 + 1), '大.txt'),
      throwsFormatException,
    );
    expect(
      () => importer.parse(Uint8List.fromList(utf8.encode(' \n\t')), '空.txt'),
      throwsFormatException,
    );
  });

  test('chunks long unheaded text without losing any paragraphs', () {
    final paragraphs = List.generate(100, (i) => '第 $i 段：${'文字' * 80}。');
    final book = importer.parse(
      Uint8List.fromList(utf8.encode(paragraphs.join('\n\n'))),
      '长文.txt',
    );
    expect(book.chapters.length, greaterThan(1));
    expect(book.chapters.expand((c) => c.paragraphs).toList(), paragraphs);
  });
}
