import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../domain/book.dart';
import '../domain/book_source.dart';
import 'source_importer.dart';
import 'source_runtime/content_normalizer.dart';
import 'source_runtime/content_replacement.dart';
import 'source_runtime/request_plan.dart';
import 'source_runtime/request_planner.dart';
import 'source_runtime/rule_interpreter.dart';
import 'source_runtime/script_runtime.dart';
import 'source_runtime/source_transport.dart';

class SourceException implements Exception {
  const SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SourceEngine {
  SourceEngine({
    http.Client? client,
    RequestPlanner? planner,
    RuleInterpreter? interpreter,
    SandboxedScriptRuntime? scriptRuntime,
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = 2 * 1024 * 1024,
  }) : _planner = planner ?? const RequestPlanner(),
       _interpreter = interpreter ?? const RuleInterpreter(),
       _scriptRuntime = scriptRuntime ?? const SandboxedScriptRuntime(),
       _transport = SourceTransport(
         client: client,
         timeout: timeout,
         maxResponseBytes: maxResponseBytes,
       );

  static const _maxChapters = 10000;
  static const _maxDomNodes = 50000;
  static const _maxTocPages = 10;
  static const _maxContentPages = 10;

  final RequestPlanner _planner;
  final RuleInterpreter _interpreter;
  final SandboxedScriptRuntime _scriptRuntime;
  final SourceTransport _transport;
  final Duration timeout;
  final int maxResponseBytes;

  void close() {
    _transport.close();
    unawaited(_scriptRuntime.close());
  }

  Future<List<Book>> search(
    BookSource source,
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    if (keyword.trim().isEmpty) return [];
    if (source.searchUrl.isEmpty) {
      throw const SourceException('缺少必填字段 searchUrl。');
    }
    final rules = source.searchRules;
    _requireRules(rules, 'ruleSearch', const ['bookList', 'name', 'bookUrl']);
    final response = await _fetch(
      source,
      source.searchUrl,
      variables: {'key': keyword.trim(), 'page': page},
      abortTrigger: abortTrigger,
    );
    return _parseBookList(
      source,
      response,
      rules,
      ruleSetName: 'ruleSearch',
      fallbackCategory: '网络',
    );
  }

  Future<List<Book>> explore(
    BookSource source,
    SourceExploreEntry entry, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    final rules = source.exploreRules;
    _requireRules(rules, 'ruleExplore', const ['bookList', 'name', 'bookUrl']);
    final response = await _fetch(
      source,
      entry.url,
      variables: {'page': page},
      abortTrigger: abortTrigger,
    );
    return _parseBookList(
      source,
      response,
      rules,
      ruleSetName: 'ruleExplore',
      fallbackCategory: entry.title,
    );
  }

  void _requireRules(
    Map<String, String> rules,
    String setName,
    List<String> fields,
  ) {
    for (final field in fields) {
      _requiredRule(rules, setName, field);
    }
  }

  String _requiredRule(
    Map<String, String> rules,
    String setName,
    String field,
  ) {
    final value = rules[field];
    if (value == null || value.trim().isEmpty) {
      throw SourceException('缺少必填规则 $setName.$field。');
    }
    return value;
  }

  List<Book> _parseBookList(
    BookSource source,
    _Page response,
    Map<String, String> rules, {
    required String ruleSetName,
    required String fallbackCategory,
  }) {
    final root = _ruleRoot(response.body, rules.values);
    final books = <String, Book>{};
    for (final element in _interpreter.select(
      root,
      _requiredRule(rules, ruleSetName, 'bookList'),
    )) {
      final title = _interpreter.extractFirst(element, rules['name']);
      final url = _link(
        response.url,
        _interpreter.extractFirst(element, rules['bookUrl']),
      );
      if (title.isEmpty || url == null) continue;
      final author = _interpreter.extractFirst(element, rules['author']);
      final category = _interpreter.extractFirst(element, rules['kind']);
      final id = '${source.id}::$url';
      books[id] = Book(
        id: id,
        title: title,
        author: author.isEmpty ? '作者未提供' : author,
        description: _interpreter.extract(element, rules['intro']),
        category: category.isEmpty ? fallbackCategory : category,
        coverStyle: books.length % 6,
        sourceLabel: source.name,
        sourceId: source.id,
        url: url.toString(),
        coverUrl: _link(
          response.url,
          _interpreter.extractFirst(element, rules['coverUrl']),
        )?.toString(),
        provenance: '来自你导入的书源 ${source.name}，请确认内容使用授权。',
        addedAt: DateTime.now(),
      );
    }
    return books.values.toList();
  }

  /// Refreshes descriptive fields without loading or replacing the chapter list.
  Future<Book> refreshBookInfo(BookSource source, Book result) async =>
      (await _loadBookInfo(source, result)).book;

  /// Loads a same-origin image through the source transport security policy.
  Future<Uint8List> loadCover(
    BookSource source,
    String coverUrl, {
    Future<void>? abortTrigger,
  }) async {
    final declared = Uri.tryParse(source.id);
    final requested = declared == null ? null : _link(declared, coverUrl);
    if (declared == null || requested == null) {
      throw const SourceException('封面地址必须是与书源同源的 HTTP(S) 链接。');
    }
    try {
      final response = await _transport.execute(
        _planner.plan(source, requested.toString()),
        policy: SourceNetworkPolicy(allowedOrigins: {declared.origin}),
        abortTrigger: abortTrigger,
        decodeText: false,
      );
      final mediaType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.bytes.isEmpty || mediaType?.startsWith('image/') != true) {
        throw const SourceException('书源封面响应不是有效的图片。');
      }
      return Uint8List.fromList(response.bytes);
    } on SourceException {
      rethrow;
    } on SourceRuntimeException catch (error) {
      throw SourceException(error.message);
    } on SourceTransportException catch (error) {
      throw SourceException(error.message);
    } on FormatException {
      throw const SourceException('封面请求地址或选项格式无效。');
    }
  }

  /// Loads a book's catalog, cancelling in-flight source transport when asked.
  Future<Book> loadBook(
    BookSource source,
    Book result, {
    Future<void>? abortTrigger,
  }) async {
    final info = await _loadBookInfo(
      source,
      result,
      abortTrigger: abortTrigger,
    );
    final tocRules = source.tocRules;
    _requireRules(tocRules, 'ruleToc', const [
      'chapterList',
      'chapterName',
      'chapterUrl',
    ]);
    final tocLink = _interpreter.extractFirst(
      info.root,
      source.infoRules['tocUrl'],
    );
    final tocUri = tocLink.isEmpty
        ? info.detail.url
        : _link(info.detail.url, tocLink);
    if (tocUri == null) throw const SourceException('目录地址不是有效的 HTTP(S) 链接。');
    final chapters = <String, Chapter>{};
    final visitedTocPages = <String>{};
    var nextTocUri = tocUri;
    for (var page = 0; ; page++) {
      await _throwIfCancelled(abortTrigger);
      if (!visitedTocPages.add(nextTocUri.toString())) break;
      if (page >= _maxTocPages) {
        throw const SourceException('目录分页超过 $_maxTocPages 页，已停止读取。');
      }
      final toc = nextTocUri == info.detail.url
          ? info.detail
          : await _fetch(
              source,
              nextTocUri.toString(),
              abortTrigger: abortTrigger,
            );
      final tocRoot = _ruleRoot(toc.body, tocRules.values);
      for (final element in _interpreter.select(
        tocRoot,
        _requiredRule(tocRules, 'ruleToc', 'chapterList'),
      )) {
        final title = _interpreter.extractFirst(
          element,
          tocRules['chapterName'],
        );
        final url = _link(
          toc.url,
          _interpreter.extractFirst(element, tocRules['chapterUrl']),
        );
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
      final nextValue = _interpreter.extractFirst(
        tocRoot,
        tocRules['nextTocUrl'],
      );
      if (nextValue.isEmpty) break;
      final parsedNext = _link(toc.url, nextValue);
      if (parsedNext == null) {
        throw const SourceException('目录下一页地址不是有效的同源 HTTP(S) 链接。');
      }
      nextTocUri = parsedNext;
    }
    if (chapters.isEmpty) {
      throw const SourceException('没有解析到章节。请检查书源目录规则或网站是否需要登录。');
    }
    return info.book.copyWith(chapters: chapters.values.toList());
  }

  Future<({Book book, _Page detail, RuleNode root})> _loadBookInfo(
    BookSource source,
    Book result, {
    Future<void>? abortTrigger,
  }) async {
    if (result.url == null) throw const SourceException('这本书没有可用的详情地址。');
    final detail = await _fetch(
      source,
      result.url!,
      abortTrigger: abortTrigger,
    );
    final rules = source.infoRules;
    final root = _ruleRoot(detail.body, rules.values);
    final title = _interpreter.extractFirst(root, rules['name']);
    final author = _interpreter.extractFirst(root, rules['author']);
    final intro = _interpreter.extract(root, rules['intro']);
    final coverUrl = _link(
      detail.url,
      _interpreter.extractFirst(root, rules['coverUrl']),
    )?.toString();
    return (
      book: result.copyWith(
        title: title.isEmpty ? null : title,
        author: author.isEmpty ? null : author,
        description: intro.isEmpty ? null : intro,
        coverUrl: coverUrl,
      ),
      detail: detail,
      root: root,
    );
  }

  /// Loads chapter content, cancelling in-flight source transport when asked.
  Future<Chapter> loadChapter(
    BookSource source,
    Chapter chapter, {
    Future<void>? abortTrigger,
  }) async {
    if (chapter.url == null) throw const SourceException('章节没有正文地址。');
    final rules = source.contentRules;
    final contentRule = _requiredRule(rules, 'ruleContent', 'content');
    final replacement = rules['replaceRegex'];
    if (replacement != null &&
        replacement.trim().isNotEmpty &&
        !ContentReplacement.isSupported(replacement)) {
      throw const SourceException('replaceRegex 必须使用安全的“正则##替换文本”格式。');
    }
    final nextRule = rules['nextContentUrl'];
    final isHtml = contentRule.toLowerCase().endsWith('@html');
    final paragraphs = <String>[];
    final visited = <String>{};
    var nextUrl = chapter.url!;
    var resolvedTitle = '';

    for (var page = 0; ; page++) {
      await _throwIfCancelled(abortTrigger);
      if (!visited.add(nextUrl)) break;
      if (page >= _maxContentPages) {
        throw const SourceException('正文分页超过 $_maxContentPages 页，已停止读取。');
      }
      final response = await _fetch(
        source,
        nextUrl,
        abortTrigger: abortTrigger,
      );
      final root = _ruleRoot(response.body, rules.values);
      final extracted = await _extractRule(root, contentRule, source: source);
      paragraphs.addAll(
        isHtml
            ? _paragraphs(_fragment(extracted))
            : extracted
                  .split(RegExp(r'\n+'))
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty),
      );
      if (resolvedTitle.isEmpty) {
        resolvedTitle = await _extractRule(
          root,
          rules['title'],
          source: source,
          firstOnly: true,
        );
      }
      final nextValue = await _extractRule(
        root,
        nextRule,
        source: source,
        firstOnly: true,
      );
      if (nextValue.isEmpty) break;
      final nextUri = _link(response.url, nextValue);
      if (nextUri == null) {
        throw const SourceException('正文下一页地址不是有效的同源 HTTP(S) 链接。');
      }
      nextUrl = nextUri.toString();
    }

    final title = resolvedTitle.isEmpty ? chapter.title : resolvedTitle;
    final replacementRule = rules['replaceRegex'];
    final Iterable<String> replacementInput;
    try {
      replacementInput =
          replacementRule == null || replacementRule.trim().isEmpty
          ? paragraphs
          : [
              const ContentReplacement().apply(
                paragraphs.join('\n'),
                replacementRule,
              ),
            ];
    } on FormatException catch (error) {
      throw SourceException(error.message);
    }
    final normalized = const ContentNormalizer().normalize(
      replacementInput,
      chapterTitle: title,
    );
    if (normalized.isEmpty) {
      throw const SourceException('没有解析到正文。请检查规则；不支持需要脚本或付费解锁的章节。');
    }
    return Chapter(
      id: chapter.id,
      title: title,
      url: chapter.url,
      paragraphs: normalized,
    );
  }

  Future<String> _extractRule(
    RuleNode input,
    String? rule, {
    required BookSource source,
    bool firstOnly = false,
  }) async {
    try {
      return await _interpreter.extractWithScripts(
        input,
        rule,
        scriptRuntime: _scriptRuntime,
        globals: {'baseUrl': source.id},
        firstOnly: firstOnly,
      );
    } on SourceScriptException catch (error) {
      throw SourceException(error.message);
    } on FormatException catch (error) {
      throw SourceException(error.message);
    }
  }

  Future<void> _throwIfCancelled(Future<void>? abortTrigger) async {
    if (abortTrigger == null) return;
    final cancelled = await Future.any<bool>([
      abortTrigger.then((_) => true, onError: (_) => true),
      Future<bool>.delayed(Duration.zero, () => false),
    ]);
    if (cancelled) {
      throw const SourceTransportException(
        SourceTransportErrorKind.cancelled,
        '书源请求已取消。',
      );
    }
  }

  Future<String> _resolveRequestTemplate(
    BookSource source,
    String template,
    Map<String, Object?> variables,
  ) async {
    final match = RegExp(
      r'^\s*<js>([\s\S]*)</js>\s*$',
      caseSensitive: false,
    ).firstMatch(template);
    if (match == null) return template;
    final result = await _scriptRuntime.evaluate(
      match[1]!,
      globals: {...variables, 'baseUrl': source.id},
    );
    if (result is! String || result.trim().isEmpty) {
      throw const SourceScriptException(
        SourceScriptErrorKind.evaluation,
        '书源请求脚本没有返回 URL。',
      );
    }
    return result.trim();
  }

  Future<_Page> _fetch(
    BookSource source,
    String template, {
    Map<String, Object?> variables = const {},
    Future<void>? abortTrigger,
  }) async {
    final declared = Uri.tryParse(source.id);
    if (declared == null ||
        !SourceImporter.isHttpUrl(declared) ||
        declared.userInfo.isNotEmpty) {
      throw const SourceException('书源声明的地址必须是无账号密码的 HTTP(S) 地址。');
    }
    try {
      await _throwIfCancelled(abortTrigger);
      final resolvedTemplate = await _resolveRequestTemplate(
        source,
        template,
        variables,
      );
      final plan = _planner.plan(
        source,
        resolvedTemplate,
        variables: variables,
      );
      final response = await _transport.execute(
        plan,
        policy: SourceNetworkPolicy(allowedOrigins: {declared.origin}),
        abortTrigger: abortTrigger,
      );
      return _Page(response.finalUri, response.text);
    } on SourceScriptException catch (error) {
      throw SourceException(error.message);
    } on SourceRuntimeException catch (error) {
      throw SourceException(error.message);
    } on SourceTransportException catch (error) {
      throw SourceException(switch (error.kind) {
        SourceTransportErrorKind.timeout => '书源响应超时，请稍后重试。离线书籍仍可阅读。',
        SourceTransportErrorKind.invalidEncoding => '书源返回的正文不是 UTF-8，请更换来源。',
        SourceTransportErrorKind.network =>
          '无法连接书源。请检查网络；Web 版还需要来源允许跨域访问（CORS）。',
        _ => error.message,
      });
    } on FormatException {
      throw const SourceException('书源请求地址或选项格式无效。');
    }
  }

  RuleNode _ruleRoot(String content, Iterable<String> rules) {
    if (rules.any(_interpreter.isJsonRule)) {
      try {
        final decoded = jsonDecode(content);
        _checkJsonTree(decoded);
        return RuleNode.json(decoded);
      } on FormatException {
        throw const SourceException('书源返回的内容不是有效的 JSON。');
      }
    }
    return RuleNode.html(_document(content).documentElement!);
  }

  void _checkJsonTree(Object? root) {
    final pending = <(Object?, int)>[(root, 0)];
    var visited = 0;
    while (pending.isNotEmpty) {
      final (value, depth) = pending.removeLast();
      if (++visited > 25000 || depth > 128) {
        throw const FormatException('JSON 结构过深或节点过多。');
      }
      if (value is Map) {
        for (final child in value.values) {
          pending.add((child, depth + 1));
        }
      } else if (value is List) {
        for (final child in value) {
          pending.add((child, depth + 1));
        }
      }
    }
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
        RegExp(r'<[a-zA-Z]').allMatches(content).take(_maxDomNodes + 1).length >
            _maxDomNodes) {
      throw const SourceException('书源页面结构过大，已停止解析。');
    }
  }

  void _checkTree(dom.Node root) {
    final pending = <(dom.Node, int)>[(root, 0)];
    var visited = 0;
    while (pending.isNotEmpty) {
      final (node, depth) = pending.removeLast();
      if (++visited > _maxDomNodes || depth > 128) {
        throw const SourceException('书源页面结构过深或节点过多，已停止解析。');
      }
      for (final child in node.nodes) {
        pending.add((child, depth + 1));
      }
    }
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
