import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import '../domain/book.dart';
import 'local_book_id.dart';
import 'source_runtime/content_normalizer.dart';

/// Imports a bounded, local-only subset of EPUB 3/2 without loading resources.
class EpubImporter {
  static const maxBytes = 20 * 1024 * 1024;
  static const maxEntries = 2048;
  static const maxEntryBytes = 4 * 1024 * 1024;
  static const maxUncompressedBytes = 50 * 1024 * 1024;
  static const maxChapters = 2000;
  static const maxParagraphs = 100000;
  static const maxTextCharacters = 20 * 1024 * 1024;
  static const _maxMarkupNodes = 30000;
  static const _maxXmlNodes = 20000;
  static const _maxDepth = 64;

  Book parse(Uint8List bytes, String fileName) {
    if (bytes.isEmpty) throw const FormatException('EPUB 文件为空。');
    if (bytes.length > maxBytes) {
      throw const FormatException('EPUB 不能超过 20 MiB。');
    }
    if (!fileName.toLowerCase().endsWith('.epub')) {
      throw const FormatException('请选择扩展名为 .epub 的本地电子书。');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(
        bytes,
        verify: true,
        throwOnError: true,
      );
    } on Object {
      throw const FormatException('EPUB 压缩包已损坏或格式不受支持。');
    }
    if (archive.isEmpty || archive.length > maxEntries) {
      throw const FormatException('EPUB 条目数量无效或过多。');
    }
    final files = <String, ArchiveFile>{};
    var totalBytes = 0;
    for (final file in archive.files) {
      final path = _canonicalArchivePath(file.name);
      if (!file.isFile ||
          file.isSymbolicLink ||
          file.size < 0 ||
          file.size > maxEntryBytes ||
          files.containsKey(path)) {
        throw const FormatException('EPUB 包含不安全或过大的资源。');
      }
      totalBytes += file.size;
      if (totalBytes > maxUncompressedBytes) {
        throw const FormatException('EPUB 解压后的内容过大。');
      }
      files[path] = file;
    }
    final mimetype = files['mimetype'];
    if (mimetype == null ||
        mimetype.compression != CompressionType.none ||
        _text(mimetype, maxBytes: 64) != 'application/epub+zip') {
      throw const FormatException('不是标准的 EPUB 文件。');
    }
    if (files.containsKey('META-INF/encryption.xml')) {
      throw const FormatException('不支持加密或 DRM EPUB。');
    }
    final container = _xml(
      _text(_required(files, 'META-INF/container.xml'), maxBytes: 65536),
      'EPUB 容器',
    );
    final rootfile = _elements(container, 'rootfile').firstOrNull;
    final opfPath = rootfile == null
        ? null
        : _resolvePath('', rootfile.getAttribute('full-path') ?? '');
    if (opfPath == null ||
        rootfile!.getAttribute('media-type') !=
            'application/oebps-package+xml') {
      throw const FormatException('EPUB 缺少有效的书籍目录。');
    }
    final package = _xml(_text(_required(files, opfPath)), 'EPUB 目录');
    final title = _metadata(package, 'title') ?? _fallbackTitle(fileName);
    final author = _metadata(package, 'creator') ?? '本地 EPUB';
    final manifest = <String, String>{};
    final manifestTypes = <String, String>{};
    for (final item in _elements(package, 'item')) {
      final id = item.getAttribute('id')?.trim() ?? '';
      final href = item.getAttribute('href')?.trim() ?? '';
      final mediaType = item.getAttribute('media-type')?.trim() ?? '';
      final path = _resolvePath(opfPath, href);
      if (id.isEmpty || path == null || manifest.containsKey(id)) {
        throw const FormatException('EPUB 目录包含无效章节资源。');
      }
      manifest[id] = path;
      manifestTypes[id] = mediaType;
    }
    final spine = <String>[];
    for (final item in _elements(package, 'itemref')) {
      final id = item.getAttribute('idref')?.trim() ?? '';
      if (id.isEmpty || !manifest.containsKey(id)) {
        throw const FormatException('EPUB 阅读顺序引用无效。');
      }
      if (spine.length >= maxChapters) {
        throw const FormatException('EPUB 章节数量过多。');
      }
      final mediaType = manifestTypes[id]!;
      if (mediaType == 'application/xhtml+xml' || mediaType == 'text/html') {
        spine.add(id);
      }
    }
    if (spine.isEmpty) throw const FormatException('EPUB 没有可阅读的 XHTML 章节。');

    final bookId = LocalBookId.next();
    final chapters = <Chapter>[];
    var totalParagraphs = 0;
    var totalText = 0;
    for (var index = 0; index < spine.length; index++) {
      final page = _htmlPage(_text(_required(files, manifest[spine[index]]!)));
      final chapterTitle = _chapterTitle(page) ?? '第 ${index + 1} 章';
      final paragraphs = _paragraphs(page, chapterTitle);
      if (paragraphs.isEmpty) continue;
      totalParagraphs += paragraphs.length;
      totalText += paragraphs.fold<int>(0, (sum, text) => sum + text.length);
      if (totalParagraphs > maxParagraphs || totalText > maxTextCharacters) {
        throw const FormatException('EPUB 正文过大，已停止导入。');
      }
      chapters.add(
        Chapter(
          id: '$bookId-$index',
          title: chapterTitle,
          paragraphs: paragraphs,
        ),
      );
    }
    if (chapters.isEmpty) throw const FormatException('EPUB 中没有可阅读的正文。');
    return Book(
      id: bookId,
      title: title,
      author: author,
      description: '从 $fileName 导入的本地 EPUB。',
      category: '本地',
      coverStyle: 4,
      sourceLabel: '本地导入',
      provenance: '由你导入的本地 EPUB，未上传到任何服务器。',
      addedAt: DateTime.now(),
      chapters: chapters,
    );
  }

  static ArchiveFile _required(Map<String, ArchiveFile> files, String path) {
    final file = files[path];
    if (file == null) throw const FormatException('EPUB 缺少必要文件。');
    return file;
  }

  static String _canonicalArchivePath(String value) {
    if (value.isEmpty ||
        value.length > 512 ||
        value.contains('\\') ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      throw const FormatException('EPUB 资源路径无效。');
    }
    final parts = value.split('/');
    if (parts.any(
      (part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.contains('\u0000'),
    )) {
      throw const FormatException('EPUB 资源路径无效。');
    }
    return value;
  }

  static String? _resolvePath(String basePath, String href) {
    if (href.isEmpty || href.contains('\\') || href.contains('?')) return null;
    final fragment = href.split('#').first;
    if (fragment.isEmpty ||
        RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(fragment)) {
      return null;
    }
    final result = <String>[];
    if (basePath.isNotEmpty) {
      result.addAll(basePath.split('/')..removeLast());
    }
    for (final part in fragment.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (result.isEmpty) return null;
        result.removeLast();
      } else if (part.contains('\u0000')) {
        return null;
      } else {
        result.add(part);
      }
    }
    if (result.isEmpty) return null;
    try {
      return _canonicalArchivePath(result.join('/'));
    } on FormatException {
      return null;
    }
  }

  static String _text(ArchiveFile file, {int? maxBytes}) {
    final limit = maxBytes ?? maxEntryBytes;
    if (file.size > limit) {
      throw const FormatException('EPUB 必要资源过大。');
    }
    try {
      final output = _BoundedOutput(limit);
      file.decompress(output);
      final content = output.bytes;
      if (content.length != file.size) {
        throw const FormatException('EPUB 资源大小无效。');
      }
      return utf8
          .decode(content, allowMalformed: false)
          .replaceFirst(RegExp('^﻿'), '');
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('EPUB 资源编码无效或已损坏。');
    }
  }

  static XmlDocument _xml(String content, String label) {
    if (content.length > maxEntryBytes ||
        RegExp(
          r'<!\s*(doctype|entity)',
          caseSensitive: false,
        ).hasMatch(content)) {
      throw FormatException('$label 含不支持的 XML 声明。');
    }
    try {
      final document = XmlDocument.parse(content);
      _checkXmlTree(document);
      return document;
    } on FormatException {
      rethrow;
    } on Object {
      throw FormatException('$label 格式无效。');
    }
  }

  static void _checkXmlTree(XmlNode root) {
    final pending = <({XmlNode node, int depth})>[(node: root, depth: 0)];
    var nodes = 0;
    while (pending.isNotEmpty) {
      final entry = pending.removeLast();
      if (++nodes > _maxXmlNodes || entry.depth > _maxDepth) {
        throw const FormatException('EPUB XML 结构过深或过大。');
      }
      for (final child in entry.node.children) {
        pending.add((node: child, depth: entry.depth + 1));
      }
    }
  }

  static Iterable<XmlElement> _elements(XmlNode root, String localName) => root
      .descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == localName);

  static String? _metadata(XmlDocument document, String name) {
    final value = _elements(
      document,
      name,
    ).map((element) => element.innerText.trim()).firstOrNull;
    if (value == null || value.isEmpty) return null;
    return value.length > 256 ? value.substring(0, 256) : value;
  }

  static String _fallbackTitle(String name) {
    final title = name
        .split(RegExp(r'[/\\]'))
        .last
        .replaceFirst(RegExp(r'\.epub$', caseSensitive: false), '')
        .trim();
    return title.isEmpty ? '未命名 EPUB' : title;
  }

  static dom.Document _htmlPage(String content) {
    if (content.length > maxEntryBytes ||
        RegExp(
              r'<[A-Za-z]',
            ).allMatches(content).take(_maxMarkupNodes + 1).length >
            _maxMarkupNodes) {
      throw const FormatException('EPUB XHTML 结构过大。');
    }
    final page = html.parse(content);
    final pending = <({dom.Node node, int depth})>[(node: page, depth: 0)];
    var nodes = 0;
    while (pending.isNotEmpty) {
      final entry = pending.removeLast();
      if (++nodes > _maxMarkupNodes || entry.depth > _maxDepth) {
        throw const FormatException('EPUB XHTML 结构过深或过大。');
      }
      for (final child in entry.node.nodes) {
        pending.add((node: child, depth: entry.depth + 1));
      }
    }
    return page;
  }

  static String? _chapterTitle(dom.Document page) {
    final heading = page.body?.querySelector('h1, h2, h3')?.text.trim();
    if (heading == null || heading.isEmpty) return null;
    return heading.length > 256 ? heading.substring(0, 256) : heading;
  }

  static List<String> _paragraphs(dom.Document page, String chapterTitle) {
    final buffer = StringBuffer();
    const blocks = {
      'p',
      'div',
      'br',
      'li',
      'h1',
      'h2',
      'h3',
      'section',
      'article',
      'blockquote',
    };
    const ignored = {
      'script',
      'style',
      'noscript',
      'iframe',
      'object',
      'svg',
      'math',
    };
    void visit(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.data);
        return;
      }
      if (node is dom.Element && ignored.contains(node.localName)) return;
      final block = node is dom.Element && blocks.contains(node.localName);
      if (block) buffer.writeln();
      for (final child in node.nodes) {
        visit(child);
      }
      if (block) buffer.writeln();
    }

    final body = page.body;
    if (body == null) return const [];
    visit(body);
    return const ContentNormalizer().normalize(
      buffer.toString().split(RegExp(r'\n+')),
      chapterTitle: chapterTitle,
    );
  }
}

class _BoundedOutput extends OutputStream {
  _BoundedOutput(this.maxBytes) : super(byteOrder: ByteOrder.littleEndian);

  final int maxBytes;
  final _bytes = <int>[];

  @override
  int get length => _bytes.length;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  void _reserve(int count) {
    if (count < 0 || _bytes.length + count > maxBytes) {
      throw const FormatException('EPUB 解压后的单个资源过大。');
    }
  }

  @override
  void clear() => _bytes.clear();

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _reserve(1);
    _bytes.add(value & 0xff);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (count < 0 || count > bytes.length) {
      throw const FormatException('EPUB 压缩资源无效。');
    }
    _reserve(count);
    _bytes.addAll(bytes.take(count));
  }

  @override
  void writeStream(InputStream stream) {
    final position = stream.position;
    try {
      while (!stream.isEOS) {
        writeByte(stream.readByte());
      }
    } finally {
      stream.setPosition(position);
    }
  }

  @override
  Uint8List subset(int start, [int? end]) {
    var offset = start < 0 ? _bytes.length + start : start;
    var finish = end;
    if (finish == null) {
      finish = _bytes.length;
    } else if (finish < 0) {
      finish = _bytes.length + finish;
    }
    if (offset < 0 || finish < offset || finish > _bytes.length) {
      throw const FormatException('EPUB 压缩资源无效。');
    }
    return Uint8List.fromList(_bytes.sublist(offset, finish));
  }
}
