import 'dart:convert';
import 'dart:typed_data';

import '../domain/book.dart';

class TxtImporter {
  static const maxBytes = 2 * 1024 * 1024;
  static final _heading = RegExp(
    r'^(第[零〇一二三四五六七八九十百千万两0-9]{1,12}[章节卷回部集篇].{0,45}|(?:序言|前言|后记|尾声|楔子)(?:\s.*)?)$',
  );

  Book parse(Uint8List bytes, String fileName) {
    if (bytes.isEmpty) throw const FormatException('文件为空，请选择有正文的 TXT。');
    if (bytes.length > maxBytes) {
      throw const FormatException('TXT 不能超过 2 MiB，请拆分后导入。');
    }
    final text = _decode(bytes).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.trim().isEmpty) throw const FormatException('文件中没有可阅读的正文。');
    if (text.contains('\u0000')) {
      throw const FormatException('文件编码不受支持，请转换为 UTF-8。');
    }
    final title = fileName
        .split(RegExp(r'[/\\]'))
        .last
        .replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '')
        .trim();
    final id = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final chapters = <Chapter>[];
    var chapterTitle = '正文';
    var paragraphs = <String>[];
    var length = 0;
    final lines = text.split('\n').map((line) => line.trim()).toList();
    final hasHeadings = lines.any((line) => _heading.hasMatch(line));

    void flush() {
      if (paragraphs.isEmpty) return;
      chapters.add(
        Chapter(
          id: '$id-${chapters.length}',
          title: chapterTitle,
          paragraphs: List.unmodifiable(paragraphs),
        ),
      );
      paragraphs = [];
      length = 0;
    }

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (_heading.hasMatch(line)) {
        if (chapters.isEmpty && paragraphs.isNotEmpty && chapterTitle == '正文') {
          chapterTitle = '引言';
        }
        flush();
        chapterTitle = line;
      } else {
        if (!hasHeadings && length >= 6000) {
          flush();
          chapterTitle = '正文 · ${chapters.length + 1}';
        }
        paragraphs.add(line);
        length += line.length;
      }
    }
    flush();
    if (chapters.isEmpty) {
      throw const FormatException('只找到章节标题，没有正文内容。');
    }
    return Book(
      id: id,
      title: title.isEmpty ? '未命名书籍' : title,
      author: '本地文件',
      description: '从 $fileName 导入的本地文字。',
      category: '本地',
      coverStyle: 5,
      sourceLabel: '本地导入',
      provenance: '由你导入的本地 TXT，未上传到任何服务器。',
      addedAt: DateTime.now(),
      chapters: List.unmodifiable(chapters),
    );
  }

  String _decode(Uint8List bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) {
        throw const FormatException('UTF-16 文件不完整，请重新导出。');
      }
      final littleEndian = bytes[0] == 0xff;
      final units = <int>[];
      for (var i = 2; i < bytes.length; i += 2) {
        units.add(
          littleEndian
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1],
        );
      }
      // Dart 字符串允许孤立代理项，但 UTF-16 文件必须包含完整的 Unicode 字符。
      for (var i = 0; i < units.length; i++) {
        final unit = units[i];
        if (unit >= 0xd800 && unit <= 0xdbff) {
          if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
            throw const FormatException('UTF-16 文件包含不完整的字符，请重新导出。');
          }
        } else if (unit >= 0xdc00 && unit <= 0xdfff) {
          throw const FormatException('UTF-16 文件包含不完整的字符，请重新导出。');
        }
      }
      return String.fromCharCodes(units);
    }
    try {
      return utf8.decode(bytes).replaceFirst(RegExp('^﻿'), '');
    } on FormatException {
      throw const FormatException('文件不是 UTF-8 或带 BOM 的 UTF-16，请转换编码后重试。');
    }
  }
}
