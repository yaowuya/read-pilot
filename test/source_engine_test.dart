import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/source_capability.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/services/source_importer.dart';
import 'package:read_pilot/services/source_runtime/script_runtime.dart';

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
    'author': '@CSS:#info a@text',
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

class _EngineScriptRuntime extends SandboxedScriptRuntime {
  String? script;
  Map<String, Object?>? globals;
  Object? result;

  @override
  Future<Object?> evaluate(
    String script, {
    Map<String, Object?> globals = const {},
  }) async {
    this.script = script;
    this.globals = globals;
    return result;
  }
}

void main() {
  final importer = SourceImporter();

  test('accepts an empty review-rule array while preserving raw JSON', () {
    final raw = sourceJson()..['ruleReview'] = <dynamic>[];
    final source = importer.parse(jsonEncode(raw)).single;
    expect(source.toJson()['ruleReview'], isEmpty);
    expect(source.searchUrl, isNotEmpty);
    expect(
      () => importer.parse(jsonEncode(sourceJson()..['ruleReview'] = ['rule'])),
      throwsFormatException,
    );
  });

  test('imports JSON arrays and JSON-encoded nested rules', () {
    final raw = sourceJson();
    raw['ruleSearch'] = jsonEncode(raw['ruleSearch']);
    final sources = importer.parse(jsonEncode([raw]));
    expect(sources.single.name, '测试公版书源');
    expect(sources.single.searchRules['name'], '@CSS:a@text');
    expect(sources.single.enabled, isTrue);
  });

  test(
    'accepts executable fields as format and reports runtime requirements',
    () {
      final raw = sourceJson()..['jsLib'] = 'java.get("private")';
      final source = importer.parse(jsonEncode(raw)).single;

      expect(source.toJson()['jsLib'], raw['jsLib']);
      expect(
        source.requiredCapabilities,
        contains(SourceCapability.javascript),
      );
      expect(
        source
            .capabilitiesFor(SourceRuntimeProfile.nativeCore)
            .runtimeImplemented,
        isFalse,
      );
    },
  );

  test('accepts advanced rule syntax without claiming it is implemented', () {
    final cases = <(String, String, SourceCapability)>[
      ('@js:1+1', 'ruleSearch.name', SourceCapability.javascript),
      ('{{java.get()}}', 'ruleSearch.name', SourceCapability.javascript),
      ('@XPath://a', 'ruleSearch.name', SourceCapability.xpath),
      ('@Json:\$.books[*]', 'ruleSearch.name', SourceCapability.jsonPath),
      ('@CSS:a@text##x##y', 'ruleSearch.name', SourceCapability.regex),
    ];
    for (final (rule, path, capability) in cases) {
      final raw = sourceJson();
      (raw['ruleSearch'] as Map)['name'] = rule;
      final source = importer.parse(jsonEncode(raw)).single;
      expect(source.requiredCapabilities, contains(capability), reason: rule);
      expect(
        source
            .capabilitiesFor(SourceRuntimeProfile.nativeCore)
            .diagnostics
            .map((item) => item.path),
        contains(path),
        reason: rule,
      );
    }

    final raw = sourceJson()..['searchUrl'] = '/s?q={{key.toUpperCase()}}';
    final source = importer.parse(jsonEncode(raw)).single;
    expect(source.requiredCapabilities, contains(SourceCapability.javascript));
  });

  test('preserves advanced workflow fields and reports their capabilities', () {
    final raw = sourceJson();
    (raw['ruleContent'] as Map)
      ..['nextContentUrl'] = '@CSS:a@href'
      ..['webJs'] = 'document.body.innerHTML'
      ..['replaceRegex'] = '广告##';

    final source = importer.parse(jsonEncode(raw)).single;
    expect(
      source.requiredCapabilities,
      containsAll({
        SourceCapability.contentPagination,
        SourceCapability.javascript,
        SourceCapability.regex,
      }),
    );
    expect(
      (source.toJson()['ruleContent'] as Map)['nextContentUrl'],
      '@CSS:a@href',
    );
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
    for (final type in [-1, 5, '2']) {
      expect(
        () =>
            importer.parse(jsonEncode(sourceJson()..['bookSourceType'] = type)),
        throwsFormatException,
      );
    }
    final imageSource = importer
        .parse(jsonEncode(sourceJson()..['bookSourceType'] = 2))
        .single;
    expect(imageSource.requiredCapabilities, contains(SourceCapability.image));
    expect(() => importer.parse('{}'), throwsFormatException);
    expect(() => importer.parse('[]'), throwsFormatException);
  });

  test('reports missing required workflow rules before HTTP', () async {
    final searchRaw = sourceJson();
    (searchRaw['ruleSearch'] as Map).remove('bookList');
    final contentRaw = sourceJson()..['ruleContent'] = <String, dynamic>{};
    final searchSource = importer.parse(jsonEncode(searchRaw)).single;
    final contentSource = importer.parse(jsonEncode(contentRaw)).single;
    final engine = SourceEngine(
      client: MockClient((_) async => fail('must not request')),
    );
    addTearDown(engine.close);

    await expectLater(
      engine.search(searchSource, '测试'),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('ruleSearch.bookList'),
        ),
      ),
    );
    await expectLater(
      engine.loadChapter(
        contentSource,
        Chapter(
          id: 'c',
          title: 'Chapter',
          url: 'https://books.example/chapter/1',
        ),
      ),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('ruleContent.content'),
        ),
      ),
    );
  });

  test('preserves unknown descriptive metadata for export', () {
    final raw = sourceJson()..['bookSourceComment'] = '由用户授权使用的公版来源';
    expect(
      importer.parse(jsonEncode(raw)).single.toJson()['bookSourceComment'],
      raw['bookSourceComment'],
    );
  });

  test('evaluates a script-wrapped search request before planning', () async {
    late http.Request captured;
    final scripts = _EngineScriptRuntime()
      ..result = '/search,{"method":"POST","body":{"q":"测试词","page":"3"}}';
    final engine = SourceEngine(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '<div class="book"><a href="/book/1">脚本搜索结果</a></div>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
      scriptRuntime: scripts,
    );
    addTearDown(engine.close);
    final source = importer
        .parse(
          jsonEncode(
            sourceJson(
              searchUrl:
                  '<js>"/search?q=" + encodeURIComponent(key) + "&page=" + page</js>',
            ),
          ),
        )
        .single;

    final books = await engine.search(source, '测试词', page: 3);

    expect(books.single.title, '脚本搜索结果');
    expect(captured.method, 'POST');
    expect(captured.body, 'q=%E6%B5%8B%E8%AF%95%E8%AF%8D&page=3');
    expect(scripts.script, contains('encodeURIComponent(key)'));
    expect(scripts.globals, {'key': '测试词', 'page': 3, 'baseUrl': source.id});
  });

  test('post-processes content through bounded script globals', () async {
    final scripts = _EngineScriptRuntime()..result = '清理后的正文';
    final engine = SourceEngine(
      client: MockClient(
        (_) async => http.Response(
          '<article id="content">原始正文广告</article>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
      scriptRuntime: scripts,
    );
    addTearDown(engine.close);
    final raw = sourceJson()
      ..['ruleContent'] = {
        'content': '@CSS:#content@text@js:result.replace(/广告/g, "")',
      };
    final source = importer.parse(jsonEncode(raw)).single;

    final chapter = await engine.loadChapter(
      source,
      Chapter(
        id: 'chapter-1',
        title: '第一章',
        url: 'https://books.example/chapter/1',
      ),
    );

    expect(chapter.paragraphs, ['清理后的正文']);
    expect(scripts.globals, {
      'baseUrl': 'https://books.example',
      'result': '原始正文广告',
    });
  });

  test('normalizes chapter layout after content extraction', () async {
    final engine = SourceEngine(
      client: MockClient(
        (_) async => http.Response(
          '<article><p>第一章</p><p>正文&nbsp; 内容</p>'
          '<p>正文&nbsp; 内容</p><p>广告也是故事的一部分</p></article>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
    );
    addTearDown(engine.close);
    final source = importer.parse(jsonEncode(sourceJson())).single;

    final chapter = await engine.loadChapter(
      source,
      Chapter(
        id: 'chapter-normalized',
        title: '第一章',
        url: 'https://books.example/chapter/normalized',
      ),
    );

    expect(chapter.paragraphs, ['正文 内容', '广告也是故事的一部分']);
  });

  test('refreshes book info and loads a same-origin image cover', () async {
    final engine = SourceEngine(
      client: MockClient((request) async {
        if (request.url.path == '/cover.png') {
          return http.Response.bytes(
            const [0x89, 0x50, 0x4e, 0x47],
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        return http.Response(
          '<h1>刷新书名</h1><div id="info"><a>刷新作者</a></div>'
          '<p class="intro">刷新简介</p><img class="cover" src="/cover.png">',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    addTearDown(engine.close);
    final raw = sourceJson();
    (raw['ruleBookInfo'] as Map)['coverUrl'] = '@CSS:.cover@src';
    final source = importer.parse(jsonEncode(raw)).single;

    final refreshed = await engine.refreshBookInfo(source, bookResult());
    expect(refreshed.title, '刷新书名');
    expect(refreshed.coverUrl, 'https://books.example/cover.png');
    expect(await engine.loadCover(source, refreshed.coverUrl!), const [
      0x89,
      0x50,
      0x4e,
      0x47,
    ]);
  });

  test('rejects a non-image cover response', () async {
    final engine = SourceEngine(
      client: MockClient(
        (_) async => http.Response(
          '<html>not an image</html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
    );
    addTearDown(engine.close);
    final source = importer.parse(jsonEncode(sourceJson())).single;

    await expectLater(
      engine.loadCover(source, 'https://books.example/cover.png'),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('图片'),
        ),
      ),
    );
  });

  test(
    'applies a bounded content replacement before paragraph normalization',
    () async {
      final engine = SourceEngine(
        client: MockClient(
          (_) async => http.Response(
            '<article><p>第一章</p><p>正文 广告词</p><p>第二段</p></article>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
      addTearDown(engine.close);
      final raw = sourceJson()
        ..['ruleContent'] = {
          'content': '@CSS:article@html',
          'replaceRegex': r'广告词##',
        };
      final source = importer.parse(jsonEncode(raw)).single;

      final chapter = await engine.loadChapter(
        source,
        Chapter(
          id: 'chapter-replaced',
          title: '第一章',
          url: 'https://books.example/chapter/replaced',
        ),
      );

      expect(chapter.paragraphs, ['正文', '第二段']);
    },
  );

  test(
    'rejects an unsafe content replacement before writing a chapter',
    () async {
      final engine = SourceEngine(
        client: MockClient((_) async => http.Response('正文', 200)),
      );
      addTearDown(engine.close);
      final raw = sourceJson()
        ..['ruleContent'] = {
          'content': '@CSS:article@text',
          'replaceRegex': r'.*##',
        };
      final source = importer.parse(jsonEncode(raw)).single;

      await expectLater(
        engine.loadChapter(
          source,
          Chapter(
            id: 'chapter-unsafe-replacement',
            title: '第一章',
            url: 'https://books.example/chapter/unsafe-replacement',
          ),
        ),
        throwsA(
          isA<SourceException>().having(
            (error) => error.message,
            'message',
            contains('replaceRegex'),
          ),
        ),
      );
    },
  );

  test('parses explore categories and loads a selected page', () async {
    late Uri requested;
    final engine = SourceEngine(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          '<div class="item"><a href="/book/1">发现书籍</a></div>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    addTearDown(engine.close);
    final raw = sourceJson()
      ..['exploreUrl'] = '热门::/genre/{{page}}\n完结::/finished/{{page}}'
      ..['ruleExplore'] = {
        'bookList': '@CSS:.item',
        'name': '@CSS:a@text',
        'bookUrl': '@CSS:a@href',
      };
    final source = importer.parse(jsonEncode(raw)).single;

    final entries = source.exploreEntries;
    final books = await engine.explore(source, entries.first, page: 2);

    expect(entries.map((entry) => entry.title), ['热门', '完结']);
    expect(requested.path, '/genre/2');
    expect(books.single.title, '发现书籍');
  });

  test('searches, resolves detail and TOC links, and extracts paragraphs', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      final body = switch (request.url.path) {
        '/search' =>
          '<div class="book"><a href="/book/1">测试书</a><span class="author">作者</span></div>',
        '/book/1' =>
          '<h1>完整书名</h1><div id="info"><a>完整作者</a><a>最新章节</a></div><p class="intro">内容介绍</p><a class="toc" href="/toc/1">目录</a>',
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
    expect(book.author, '完整作者');
    expect(book.chapters, hasLength(2));
    expect(book.chapters.first.url, 'https://books.example/chapter/1');
    final chapter = await engine.loadChapter(source, book.chapters.first);
    expect(chapter.paragraphs, ['第一段。', '第二段。', '换行。']);
    expect(chapter.paragraphs.join(), isNot(contains('危险代码')));
    expect(chapter.paragraphs.join(), isNot(contains('隐藏样式')));
  });

  test('searches a JSON response with the safe JSONPath subset', () async {
    final engine = SourceEngine(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'books': [
              {'title': 'JSON 书籍', 'author': 'JSON 作者', 'url': '/book/json'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(engine.close);
    final raw = sourceJson()
      ..['ruleSearch'] = {
        'bookList': r'@Json:$.books[*]',
        'name': r'@Json:$.title',
        'author': r'@Json:$.author',
        'bookUrl': r'@Json:$.url',
      };
    final source = importer.parse(jsonEncode(raw)).single;

    final results = await engine.search(source, 'JSON');

    expect(results.single.title, 'JSON 书籍');
    expect(results.single.author, 'JSON 作者');
    expect(results.single.url, 'https://books.example/book/json');
  });

  test('runs the full reader workflow over JSONPath responses', () async {
    final requests = <Uri>[];
    final engine = SourceEngine(
      client: MockClient((request) async {
        requests.add(request.url);
        final payload = switch (request.url.path) {
          '/search' => {
            'books': [
              {'title': 'JSON 书籍', 'author': 'JSON 作者', 'url': '/book/json'},
            ],
          },
          '/book/json' => {
            'title': '完整 JSON 书名',
            'author': '完整作者',
            'intro': 'JSON 简介',
            'toc': '/toc/json',
          },
          '/toc/json' => {
            'chapters': [
              {'title': '第一章', 'url': '/chapter/1'},
            ],
          },
          '/chapter/1' => {'title': '第一章 · JSON', 'content': '第一段。\n第二段。'},
          _ => null,
        };
        return http.Response(
          payload == null ? '' : jsonEncode(payload),
          payload == null ? 404 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(engine.close);
    final raw = sourceJson()
      ..['ruleSearch'] = {
        'bookList': r'@Json:$.books[*]',
        'name': r'@Json:$.title',
        'author': r'@Json:$.author',
        'bookUrl': r'@Json:$.url',
      }
      ..['ruleBookInfo'] = {
        'name': r'@Json:$.title',
        'author': r'@Json:$.author',
        'intro': r'@Json:$.intro',
        'tocUrl': r'@Json:$.toc',
      }
      ..['ruleToc'] = {
        'chapterList': r'@Json:$.chapters[*]',
        'chapterName': r'@Json:$.title',
        'chapterUrl': r'@Json:$.url',
      }
      ..['ruleContent'] = {
        'title': r'@Json:$.title',
        'content': r'@Json:$.content',
      };
    final source = importer.parse(jsonEncode(raw)).single;

    final result = (await engine.search(source, 'JSON')).single;
    final book = await engine.loadBook(source, result);
    final chapter = await engine.loadChapter(source, book.chapters.single);

    expect(book.title, '完整 JSON 书名');
    expect(book.author, '完整作者');
    expect(book.description, 'JSON 简介');
    expect(chapter.title, '第一章 · JSON');
    expect(chapter.paragraphs, ['第一段。', '第二段。']);
    expect(requests.map((uri) => uri.path), [
      '/search',
      '/book/json',
      '/toc/json',
      '/chapter/1',
    ]);
  });

  test(
    'applies static headers and a default user-agent to every workflow',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final body = switch (request.url.path) {
          '/search' => '<div class="book"><a href="/book/1">测试书</a></div>',
          '/book/1' => '<h1>测试书</h1><a class="toc" href="/toc/1">目录</a>',
          '/toc/1' => '<div id="chapters"><a href="/chapter/1">第一章</a></div>',
          '/chapter/1' => '<article><p>正文。</p></article>',
          _ => '',
        };
        return http.Response(
          body,
          body.isEmpty ? 404 : 200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      final raw = sourceJson()
        ..['header'] = {
          'Referer': 'https://books.example/',
          'X-Reader': 'enabled',
        };
      final source = importer.parse(jsonEncode(raw)).single;
      final engine = SourceEngine(client: client);
      addTearDown(engine.close);

      final result = (await engine.search(source, '测试')).single;
      final book = await engine.loadBook(source, result);
      await engine.loadChapter(source, book.chapters.single);

      expect(requests, hasLength(4));
      for (final request in requests) {
        expect(request.headers['referer'], 'https://books.example/');
        expect(request.headers['x-reader'], 'enabled');
        expect(request.headers['user-agent'], isNotEmpty);
      }
    },
  );

  test('executes POST search options through the public workflow', () async {
    late http.Request captured;
    final engine = SourceEngine(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '<div class="book"><a href="/book/1">POST 结果</a></div>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    addTearDown(engine.close);
    final source = importer
        .parse(
          jsonEncode(
            sourceJson(
              searchUrl: '/search,{"method":"POST","body":{"q":"{{key}}"}}',
            ),
          ),
        )
        .single;

    final results = await engine.search(source, '月 下');

    expect(results.single.title, 'POST 结果');
    expect(captured.method, 'POST');
    expect(captured.body, 'q=%E6%9C%88+%E4%B8%8B');
  });

  test('follows bounded TOC pagination and stops cycles', () async {
    final requested = <Uri>[];
    final engine = SourceEngine(
      client: MockClient((request) async {
        requested.add(request.url);
        final body = switch (request.url.path) {
          '/book/1' => '<h1>分页目录书</h1><a class="toc" href="/toc/1">目录</a>',
          '/toc/1' =>
            '<div id="chapters"><a href="/chapter/1">第一章</a></div><a class="next" href="/toc/2">下一页</a>',
          '/toc/2' =>
            '<div id="chapters"><a href="/chapter/2">第二章</a></div><a class="next" href="/toc/1">上一页</a>',
          _ => '',
        };
        return http.Response(
          body,
          body.isEmpty ? 404 : 200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    addTearDown(engine.close);
    final raw = sourceJson();
    (raw['ruleToc'] as Map)['nextTocUrl'] = '@CSS:a.next@href';
    final source = importer.parse(jsonEncode(raw)).single;

    final book = await engine.loadBook(source, bookResult());

    expect(book.chapters.map((chapter) => chapter.title), ['第一章', '第二章']);
    expect(requested.map((uri) => uri.path), ['/book/1', '/toc/1', '/toc/2']);
  });

  test('follows bounded content pagination and stops cycles', () async {
    final requested = <Uri>[];
    final engine = SourceEngine(
      client: MockClient((request) async {
        requested.add(request.url);
        final body = switch (request.url.path) {
          '/chapter/1' =>
            '<article><p>第一页。</p></article><a class="next" href="/chapter/2">下一页</a>',
          '/chapter/2' =>
            '<article><p>第二页。</p></article><a class="next" href="/chapter/1">上一页</a>',
          _ => '',
        };
        return http.Response(
          body,
          body.isEmpty ? 404 : 200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    addTearDown(engine.close);
    final raw = sourceJson();
    (raw['ruleContent'] as Map)['nextContentUrl'] = '@CSS:a.next@href';
    final source = importer.parse(jsonEncode(raw)).single;

    final chapter = await engine.loadChapter(
      source,
      Chapter(
        id: 'chapter-1',
        title: '分页章',
        url: 'https://books.example/chapter/1',
      ),
    );

    expect(chapter.paragraphs, ['第一页。', '第二页。']);
    expect(requested.map((uri) => uri.path), ['/chapter/1', '/chapter/2']);
  });

  test('rejects content pagination beyond ten pages', () async {
    final requested = <Uri>[];
    final engine = SourceEngine(
      client: MockClient((request) async {
        requested.add(request.url);
        final page = int.parse(request.url.pathSegments.last);
        return http.Response(
          '<article><p>第 $page 页。</p></article>'
          '<a class="next" href="/chapter/${page + 1}">下一页</a>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    addTearDown(engine.close);
    final raw = sourceJson();
    (raw['ruleContent'] as Map)['nextContentUrl'] = '@CSS:a.next@href';
    final source = importer.parse(jsonEncode(raw)).single;

    await expectLater(
      engine.loadChapter(
        source,
        Chapter(
          id: 'chapter-1',
          title: '超长分页章',
          url: 'https://books.example/chapter/1',
        ),
      ),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('10'),
        ),
      ),
    );
    expect(requested, hasLength(10));
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

  test('accepts the measured 7365-chapter, 29k-node TOC shape', () async {
    final body =
        '<div id="chapters">${List.generate(7365, (i) => '<a href="/c/$i"><span><em>Chapter $i</em></span></a>').join()}</div>';
    expect(utf8.encode(body).length, lessThan(2 * 1024 * 1024));
    final source = importer.parse(jsonEncode(sourceJson())).single;
    final engine = SourceEngine(
      client: MockClient((_) async => http.Response(body, 200)),
    );
    addTearDown(engine.close);
    final book = await engine.loadBook(source, bookResult());
    expect(book.chapters, hasLength(7365));
    expect(book.chapters.last.url, 'https://books.example/c/7364');
  });

  test('rejects an oversized TOC instead of silently losing chapters', () async {
    final body =
        '<div id="chapters">${List.generate(10001, (i) => '<a href="/c/$i">Chapter $i</a>').join()}</div>';
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
          contains('10000'),
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

  test('cancels search even when the HTTP client ignores abort', () async {
    final source = importer.parse(jsonEncode(sourceJson())).single;
    final abort = Completer<void>();
    final engine = SourceEngine(
      client: MockClient((_) => Completer<http.Response>().future),
    );
    addTearDown(engine.close);

    final pending = engine.search(source, '书', abortTrigger: abort.future);
    abort.complete();

    await expectLater(
      pending.timeout(const Duration(milliseconds: 200)),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('取消'),
        ),
      ),
    );
  });

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
