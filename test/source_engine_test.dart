import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/services/source_importer.dart';

Map<String, dynamic> sourceJson({
  String origin = 'https://books.example',
  String searchUrl = '/search?q={{key}}&page={{page}}',
}) => {
  'bookSourceUrl': origin,
  'bookSourceName': '测试公版书源',
  'bookSourceType': 0,
  'enabled': true,
  'searchUrl': searchUrl,
  'ruleSearch': {
    'bookList': '@CSS:.book',
    'name': '@CSS:a@text',
    'author': '@CSS:.author@text',
    'bookUrl': '@CSS:a@href',
  },
  'ruleBookInfo': {
    'name': '@CSS:h1@text',
    'intro': '@CSS:.intro@text',
    'tocUrl': '@CSS:.toc@href',
  },
  'ruleToc': {
    'chapterList': '@CSS:#chapters a',
    'chapterName': '@text',
    'chapterUrl': '@href',
  },
  'ruleContent': {'content': '@CSS:article@html'},
};

Book bookResult({String url = 'https://books.example/book/1'}) => Book(
  id: 'book-1',
  title: '测试书',
  author: '作者',
  description: '',
  category: '测试',
  coverStyle: 0,
  sourceLabel: '测试公版书源',
  sourceId: 'https://books.example',
  url: url,
  addedAt: DateTime.utc(2026),
);

void main() {
  final importer = SourceImporter();

  test('imports JSON arrays and JSON-encoded nested rules', () {
    final raw = sourceJson();
    raw['ruleSearch'] = jsonEncode(raw['ruleSearch']);
    final sources = importer.parse(jsonEncode([raw]));
    expect(sources.single.name, '测试公版书源');
    expect(sources.single.searchRules['name'], '@CSS:a@text');
    expect(sources.single.enabled, isTrue);
  });

  test('rejects unsupported executable fields with a field name', () {
    final raw = sourceJson()..['jsLib'] = 'java.get("private")';
    expect(
      () => importer.parse(jsonEncode(raw)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'field',
          contains('jsLib'),
        ),
      ),
    );
  });

  test('rejects JavaScript, arbitrary templates, XPath and regex rules', () {
    for (final rule in [
      '@js:1+1',
      '{{java.get()}}',
      '@XPath://a',
      '@CSS:a@text##x##y',
    ]) {
      final raw = sourceJson();
      (raw['ruleSearch'] as Map)['name'] = rule;
      expect(
        () => importer.parse(jsonEncode(raw)),
        throwsFormatException,
        reason: rule,
      );
    }
    final raw = sourceJson()..['searchUrl'] = '/s?q={{key.toUpperCase()}}';
    expect(() => importer.parse(jsonEncode(raw)), throwsFormatException);
  });

  test('rejects advanced behavior instead of silently ignoring it', () {
    for (final field in ['nextContentUrl', 'webJs', 'replaceRegex']) {
      final raw = sourceJson();
      (raw['ruleContent'] as Map)[field] = '@CSS:a@href';
      expect(() => importer.parse(jsonEncode(raw)), throwsFormatException);
    }
  });

  test('rejects invalid source types and unsafe URL schemes', () {
    for (final origin in [
      'file:///etc/passwd',
      'javascript:alert(1)',
      'data:text/plain,test',
    ]) {
      final raw = sourceJson()..['bookSourceUrl'] = origin;
      expect(() => importer.parse(jsonEncode(raw)), throwsFormatException);
    }
    expect(
      () => importer.parse(jsonEncode(sourceJson()..['bookSourceType'] = 2)),
      throwsFormatException,
    );
    expect(() => importer.parse('{}'), throwsFormatException);
    expect(() => importer.parse('[]'), throwsFormatException);
  });

  test('preserves unknown descriptive metadata for export', () {
    final raw = sourceJson()..['bookSourceComment'] = '由用户授权使用的公版来源';
    expect(
      importer.parse(jsonEncode(raw)).single.toJson()['bookSourceComment'],
      raw['bookSourceComment'],
    );
  });

  test('searches, resolves detail and TOC links, and extracts paragraphs', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      final body = switch (request.url.path) {
        '/search' =>
          '<div class="book"><a href="/book/1">测试书</a><span class="author">作者</span></div>',
        '/book/1' =>
          '<h1>完整书名</h1><p class="intro">内容介绍</p><a class="toc" href="/toc/1">目录</a>',
        '/toc/1' =>
          '<div id="chapters"><a href="../chapter/1">第一章</a><a href="/chapter/2">第二章</a></div>',
        '/chapter/1' =>
          '<article><p>第一段。</p><p>第二段。<br>换行。</p><script>危险代码</script><style>隐藏样式</style></article>',
        _ => '',
      };
      return http.Response(
        body,
        body.isEmpty ? 404 : 200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    final engine = SourceEngine(client: client);
    final source = importer.parse(jsonEncode(sourceJson())).single;
    final results = await engine.search(source, '书 & 阅读');
    expect(results.single.title, '测试书');
    expect(requests.first.queryParameters['q'], '书 & 阅读');
    expect(requests.first.queryParameters['page'], '1');
    final book = await engine.loadBook(source, results.single);
    expect(book.title, '完整书名');
    expect(book.chapters, hasLength(2));
    expect(book.chapters.first.url, 'https://books.example/chapter/1');
    final chapter = await engine.loadChapter(source, book.chapters.first);
    expect(chapter.paragraphs, ['第一段。', '第二段。', '换行。']);
    expect(chapter.paragraphs.join(), isNot(contains('危险代码')));
    expect(chapter.paragraphs.join(), isNot(contains('隐藏样式')));
  });

  test('does not promote javascript links into navigable books', () async {
    final client = MockClient(
      (_) async => http.Response(
        '<div class="book"><a href="javascript:alert(1)">坏链接</a></div>',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      ),
    );
    final source = importer.parse(jsonEncode(sourceJson())).single;
    expect(await SourceEngine(client: client).search(source, '书'), isEmpty);
  });

  test('reports HTTP failures and limits response bytes', () async {
    final source = importer.parse(jsonEncode(sourceJson())).single;
    final missing = SourceEngine(
      client: MockClient((_) async => http.Response('missing', 404)),
    );
    await expectLater(
      missing.search(source, '书'),
      throwsA(isA<SourceException>()),
    );
    final oversized = SourceEngine(
      client: MockClient((_) async => http.Response('x' * 2048, 200)),
      maxResponseBytes: 1024,
    );
    await expectLater(
      oversized.search(source, '书'),
      throwsA(isA<SourceException>()),
    );
  });

  test('redirects cannot escape the configured source origin', () async {
    final requested = <Uri>[];
    final engine = SourceEngine(
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://127.0.0.1:8080/private'},
        );
      }),
    );
    final source = importer.parse(jsonEncode(sourceJson())).single;
    await expectLater(
      engine.search(source, '书'),
      throwsA(isA<SourceException>()),
    );
    expect(requested, hasLength(1));
    expect(requested.single.host, 'books.example');
  });

  test('rejects excessive HTML nesting with a readable source error', () async {
    final body = '<article>${'<div>' * 1000}正文${'</div>' * 1000}</article>';
    final engine = SourceEngine(
      client: MockClient(
        (_) async => http.Response(
          body,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
    );
    final source = importer.parse(jsonEncode(sourceJson())).single;
    await expectLater(
      engine.loadChapter(
        source,
        Chapter(id: '1', title: '一', url: 'https://books.example/chapter/1'),
      ),
      throwsA(isA<SourceException>()),
    );
  });

  test(
    'expanded search URLs cannot leave the declared source origin',
    () async {
      final source = importer
          .parse(
            jsonEncode(
              sourceJson(origin: 'http://test', searchUrl: 'http://{{key}}/'),
            ),
          )
          .single;
      final requests = <Uri>[];
      final engine = SourceEngine(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response('<html></html>', 200);
        }),
      );
      addTearDown(engine.close);
      await expectLater(
        engine.search(source, '127.0.0.1'),
        throwsA(isA<SourceException>()),
      );
      expect(requests, isEmpty);
    },
  );

  test(
    'book details are bound to the declared source origin before HTTP',
    () async {
      final source = importer.parse(jsonEncode(sourceJson())).single;
      final requests = <Uri>[];
      final engine = SourceEngine(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response('<html></html>', 200);
        }),
      );
      addTearDown(engine.close);
      await expectLater(
        engine.loadBook(
          source,
          bookResult(url: 'https://other.example/book/1'),
        ),
        throwsA(isA<SourceException>()),
      );
      expect(requests, isEmpty);
    },
  );

  for (final url in [
    'https://other.example/chapter/1',
    'http://books.example/chapter/1',
    'https://books.example:8443/chapter/1',
  ]) {
    test('chapter origin is checked before HTTP: $url', () async {
      final source = importer.parse(jsonEncode(sourceJson())).single;
      final requests = <Uri>[];
      final engine = SourceEngine(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response('<article><p>Content</p></article>', 200);
        }),
      );
      addTearDown(engine.close);
      await expectLater(
        engine.loadChapter(
          source,
          Chapter(id: 'c', title: 'Chapter', url: url),
        ),
        throwsA(isA<SourceException>()),
      );
      expect(requests, isEmpty);
    });
  }

  test('same-origin redirects remain supported', () async {
    final source = importer.parse(jsonEncode(sourceJson())).single;
    final requests = <Uri>[];
    final engine = SourceEngine(
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/search') {
          return http.Response('', 302, headers: {'location': '/results'});
        }
        return http.Response(
          '<div class="book"><a href="/book/1">Book</a></div>',
          200,
        );
      }),
    );
    addTearDown(engine.close);
    expect((await engine.search(source, 'Book')).single.title, 'Book');
    expect(requests.map((url) => url.path), ['/search', '/results']);
  });

  test('source base paths do not block same-origin chapters', () async {
    final source = importer
        .parse(jsonEncode(sourceJson(origin: 'https://books.example/library/')))
        .single;
    final engine = SourceEngine(
      client: MockClient(
        (_) async => http.Response('<article><p>Content</p></article>', 200),
      ),
    );
    addTearDown(engine.close);
    final chapter = await engine.loadChapter(
      source,
      Chapter(
        id: 'c',
        title: 'Chapter',
        url: 'https://books.example/chapter/1',
      ),
    );
    expect(chapter.paragraphs, ['Content']);
  });

  test(
    'accepts a complete 5000-chapter TOC at the documented boundary',
    () async {
      final body =
          '<div id="chapters">${List.generate(5000, (i) => '<a href="/c/$i">Chapter $i</a>').join()}</div>';
      final source = importer.parse(jsonEncode(sourceJson())).single;
      final engine = SourceEngine(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      addTearDown(engine.close);
      final book = await engine.loadBook(source, bookResult());
      expect(book.chapters, hasLength(5000));
      expect(book.chapters.last.url, 'https://books.example/c/4999');
    },
  );

  test('rejects an oversized TOC instead of silently losing chapters', () async {
    final body =
        '<div id="chapters">${List.generate(5001, (i) => '<a href="/c/$i">Chapter $i</a>').join()}</div>';
    expect(utf8.encode(body).length, lessThan(2 * 1024 * 1024));
    final source = importer.parse(jsonEncode(sourceJson())).single;
    final engine = SourceEngine(
      client: MockClient((_) async => http.Response(body, 200)),
    );
    addTearDown(engine.close);
    await expectLater(
      engine.loadBook(source, bookResult()),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'limit',
          contains('5000'),
        ),
      ),
    );
  });

  test('enabled accepts booleans and defaults only when omitted', () {
    final omitted = sourceJson()..remove('enabled');
    expect(importer.parse(jsonEncode(omitted)).single.enabled, isTrue);
    expect(
      importer
          .parse(jsonEncode(sourceJson()..['enabled'] = true))
          .single
          .enabled,
      isTrue,
    );
    expect(
      importer
          .parse(jsonEncode(sourceJson()..['enabled'] = false))
          .single
          .enabled,
      isFalse,
    );
  });

  for (final invalid in <Object?>['false', 'true', 0, 1, null, [], {}]) {
    test('rejects non-boolean enabled: ${jsonEncode(invalid)}', () {
      final raw = sourceJson()..['enabled'] = invalid;
      expect(
        () => importer.parse(jsonEncode(raw)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'field',
            contains('enabled'),
          ),
        ),
      );
    });
  }

  test('times out rather than leaving search busy indefinitely', () async {
    final source = importer.parse(jsonEncode(sourceJson())).single;
    final engine = SourceEngine(
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      engine.search(source, '书'),
      throwsA(isA<SourceException>()),
    );
  });
}
