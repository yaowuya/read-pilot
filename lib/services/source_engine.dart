import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../domain/book.dart';
import '../domain/book_source.dart';
import 'source_importer.dart';

class SourceException implements Exception {
  const SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SourceEngine {
  SourceEngine({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = 2 * 1024 * 1024,
  }) : _client = client ?? http.Client();

  static const _maxChapters = 5000;

  final http.Client _client;
  final Duration timeout;
  final int maxResponseBytes;

  void close() => _client.close();

  Future<List<Book>> search(
    BookSource source,
    String keyword, {
    int page = 1,
  }) async {
    if (keyword.trim().isEmpty) return [];
    final template = source.searchUrl
        .replaceAll('{{key}}', Uri.encodeComponent(keyword.trim()))
        .replaceAll('{{page}}', '$page')
        .replaceAll('{{baseUrl}}', source.id);
    final response = await _fetch(
      source,
      Uri.parse(source.id).resolve(template),
    );
    final root = _document(response.body).documentElement!;
    final rules = source.searchRules;
    final books = <String, Book>{};
    for (final element in _elements(root, rules['bookList']!)) {
      final title = _value(element, rules['name']);
      final url = _link(response.url, _value(element, rules['bookUrl']));
      if (title.isEmpty || url == null) continue;
      final author = _value(element, rules['author']);
      final id = '${source.id}::$url';
      books[id] = Book(
        id: id,
        title: title,
        author: author.isEmpty ? '作者未提供' : author,
        description: _value(element, rules['intro']),
        category: '网络',
        coverStyle: books.length % 6,
        sourceLabel: source.name,
        sourceId: source.id,
        url: url.toString(),
        coverUrl: _link(
          response.url,
          _value(element, rules['coverUrl']),
        )?.toString(),
        provenance: '来自你导入的书源 ${source.name}，请确认内容使用授权。',
        addedAt: DateTime.now(),
      );
    }
    return books.values.toList();
  }

  Future<Book> loadBook(BookSource source, Book result) async {
    if (result.url == null) throw const SourceException('这本书没有可用的详情地址。');
    final detail = await _fetch(source, Uri.parse(result.url!));
    final root = _document(detail.body).documentElement!;
    final info = source.infoRules;
    final tocLink = _value(root, info['tocUrl']);
    final tocUri = tocLink.isEmpty ? detail.url : _link(detail.url, tocLink);
    if (tocUri == null) throw const SourceException('目录地址不是有效的 HTTP(S) 链接。');
    final toc = tocUri == detail.url ? detail : await _fetch(source, tocUri);
    final tocRoot = _document(toc.body).documentElement!;
    final chapters = <String, Chapter>{};
    final tocRules = source.tocRules;
    for (final element in _elements(tocRoot, tocRules['chapterList']!)) {
      final title = _value(element, tocRules['chapterName']);
      final url = _link(toc.url, _value(element, tocRules['chapterUrl']));
      if (title.isEmpty || url == null) continue;
      chapters[url.toString()] = Chapter(
        id: url.toString(),
        title: title,
        url: url.toString(),
      );
      if (chapters.length > _maxChapters) {
        throw const SourceException('目录超过 $_maxChapters 章，已停止导入，未保存截断结果。');
      }
    }
    if (chapters.isEmpty) {
      throw const SourceException('没有解析到章节。请检查书源目录规则或网站是否需要登录。');
    }
    final title = _value(root, info['name']);
    final author = _value(root, info['author']);
    final intro = _value(root, info['intro']);
    return result.copyWith(
      title: title.isEmpty ? null : title,
      author: author.isEmpty ? null : author,
      description: intro.isEmpty ? null : intro,
      coverUrl: _link(detail.url, _value(root, info['coverUrl']))?.toString(),
      chapters: chapters.values.toList(),
    );
  }

  Future<Chapter> loadChapter(BookSource source, Chapter chapter) async {
    if (chapter.url == null) throw const SourceException('章节没有正文地址。');
    final response = await _fetch(source, Uri.parse(chapter.url!));
    final root = _document(response.body).documentElement!;
    final rule = source.contentRules['content']!;
    final extracted = _value(root, rule);
    final isHtml = rule.toLowerCase().endsWith('@html');
    final paragraphs = isHtml
        ? _paragraphs(_fragment(extracted))
        : extracted
              .split(RegExp(r'\n+'))
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();
    if (paragraphs.isEmpty) {
      throw const SourceException('没有解析到正文。请检查规则；不支持需要脚本或付费解锁的章节。');
    }
    final title = _value(root, source.contentRules['title']);
    return Chapter(
      id: chapter.id,
      title: title.isEmpty ? chapter.title : title,
      url: chapter.url,
      paragraphs: paragraphs,
    );
  }

  Future<_Page> _fetch(BookSource source, Uri url) async {
    final declared = Uri.tryParse(source.id);
    if (declared == null ||
        !SourceImporter.isHttpUrl(declared) ||
        declared.userInfo.isNotEmpty) {
      throw const SourceException('书源声明的地址必须是无账号密码的 HTTP(S) 地址。');
    }
    final abort = Completer<void>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      return await _request(
        url,
        declared.origin,
        abort.future,
      ).timeout(timeout);
    } on SourceException {
      rethrow;
    } on TimeoutException {
      throw const SourceException('书源响应超时，请稍后重试。离线书籍仍可阅读。');
    } on http.RequestAbortedException {
      throw const SourceException('书源响应超时，请稍后重试。');
    } on FormatException {
      throw const SourceException('书源返回的正文不是 UTF-8，请更换来源。');
    } catch (_) {
      throw const SourceException('无法连接书源。请检查网络；Web 版还需要来源允许跨域访问（CORS）。');
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<_Page> _request(
    Uri url,
    String declaredOrigin,
    Future<void> abort,
  ) async {
    for (var redirects = 0; redirects <= 4; redirects++) {
      if (!SourceImporter.isHttpUrl(url) || url.userInfo.isNotEmpty) {
        throw const SourceException('只允许无账号密码的 HTTP(S) 地址。');
      }
      if (url.origin != declaredOrigin) {
        throw const SourceException('书源请求超出声明的来源，已阻止跨源访问。');
      }
      final request = http.AbortableRequest('GET', url, abortTrigger: abort)
        ..followRedirects = false;
      final response = await _client.send(request);
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null || redirects == 4) {
          throw const SourceException('书源重定向无效或次数过多。');
        }
        url = url.resolve(location);
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.listen((_) {}).cancel();
        throw SourceException('书源返回 HTTP ${response.statusCode}，请检查地址或稍后重试。');
      }
      final charset = RegExp(r'charset\s*=\s*([^;\s]+)', caseSensitive: false)
          .firstMatch(response.headers['content-type'] ?? '')?[1]
          ?.replaceAll('"', '')
          .toLowerCase();
      if (charset != null && !{'utf-8', 'utf8', 'us-ascii'}.contains(charset)) {
        await response.stream.listen((_) {}).cancel();
        throw SourceException('首版仅支持 UTF-8，书源使用了 $charset。');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const SourceException('书源响应超过 2 MiB 限制，已停止下载。');
        }
        bytes.add(chunk);
      }
      return _Page(url, utf8.decode(bytes.takeBytes()));
    }
    throw const SourceException('书源重定向次数过多。');
  }

  dom.Document _document(String content) {
    _checkMarkup(content);
    final document = html.parse(content);
    _checkTree(document);
    return document;
  }

  dom.DocumentFragment _fragment(String content) {
    _checkMarkup(content);
    final fragment = html.parseFragment(content);
    _checkTree(fragment);
    return fragment;
  }

  void _checkMarkup(String content) {
    if (content.length > maxResponseBytes ||
        RegExp(r'<[a-zA-Z]').allMatches(content).take(25001).length > 25000) {
      throw const SourceException('书源页面结构过大，已停止解析。');
    }
  }

  void _checkTree(dom.Node root) {
    final pending = <(dom.Node, int)>[(root, 0)];
    var visited = 0;
    while (pending.isNotEmpty) {
      final (node, depth) = pending.removeLast();
      if (++visited > 25000 || depth > 128) {
        throw const SourceException('书源页面结构过深或节点过多，已停止解析。');
      }
      for (final child in node.nodes) {
        pending.add((child, depth + 1));
      }
    }
  }

  List<dom.Element> _elements(dom.Element root, String rule) {
    final selector = rule
        .replaceFirst(RegExp(r'^@css:', caseSensitive: false), '')
        .trim();
    return selector.isEmpty ? [root] : root.querySelectorAll(selector);
  }

  String _value(dom.Element root, String? rule) {
    if (rule == null || rule.isEmpty) return '';
    var selector = rule.replaceFirst(
      RegExp(r'^@css:', caseSensitive: false),
      '',
    );
    final index = selector.lastIndexOf('@');
    final accessor = index < 0 ? 'text' : selector.substring(index + 1);
    if (index >= 0) selector = selector.substring(0, index);
    final elements = selector.trim().isEmpty
        ? [root]
        : root.querySelectorAll(selector);
    final values = elements
        .map((element) {
          final clean = element.clone(true);
          for (final node in clean.querySelectorAll('script, style')) {
            node.remove();
          }
          return switch (accessor) {
            'text' => clean.text.trim(),
            'ownText' =>
              clean.nodes
                  .whereType<dom.Text>()
                  .map((node) => node.data)
                  .join(' ')
                  .trim(),
            'textNodes' =>
              clean.nodes
                  .whereType<dom.Text>()
                  .map((node) => node.data.trim())
                  .where((s) => s.isNotEmpty)
                  .join('\n'),
            'html' => clean.outerHtml,
            _ => clean.attributes[accessor]?.trim() ?? '',
          };
        })
        .where((value) => value.isNotEmpty);
    final output = StringBuffer();
    for (final value in values) {
      if (output.length + value.length > maxResponseBytes) {
        throw const SourceException('规则提取出的内容过大，请缩小 CSS 选择范围。');
      }
      if (output.isNotEmpty) output.writeln();
      output.write(value);
    }
    return output.toString();
  }

  Uri? _link(Uri base, String value) {
    if (value.trim().isEmpty) return null;
    try {
      final uri = base.resolve(value.trim());
      return SourceImporter.isHttpUrl(uri) &&
              uri.userInfo.isEmpty &&
              uri.origin == base.origin
          ? uri
          : null;
    } on FormatException {
      return null;
    }
  }

  List<String> _paragraphs(dom.Node root) {
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
    void visit(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.data);
        return;
      }
      if (node is dom.Element && {'script', 'style'}.contains(node.localName)) {
        return;
      }
      final isBlock = node is dom.Element && blocks.contains(node.localName);
      if (isBlock) buffer.writeln();
      for (final child in node.nodes) {
        visit(child);
      }
      if (isBlock) buffer.writeln();
    }

    visit(root);
    return buffer
        .toString()
        .split(RegExp(r'\n+'))
        .map((text) => text.replaceAll(RegExp(r'[\t  ]+'), ' ').trim())
        .where((text) => text.isNotEmpty)
        .toList();
  }
}

class _Page {
  const _Page(this.url, this.body);
  final Uri url;
  final String body;
}
