import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:read_pilot/services/source_runtime/rule_interpreter.dart';
import 'package:read_pilot/services/source_runtime/rule_tokenizer.dart';
import 'package:read_pilot/services/source_runtime/script_runtime.dart';

class _RecordingScriptRuntime extends SandboxedScriptRuntime {
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
  test('tokenizer splits operators only at the top level', () {
    const tokenizer = RuleTokenizer();

    expect(
      tokenizer.splitTopLevel(
        '@CSS:a[href="x&&y"]@text&&@CSS:.author@text',
        '&&',
      ),
      ['@CSS:a[href="x&&y"]@text', '@CSS:.author@text'],
    );
    expect(
      tokenizer.splitTopLevel(
        r'@Json:$.books[?(@.name=="A||B")]||@Json:$.fallback',
        '||',
      ),
      [r'@Json:$.books[?(@.name=="A||B")]', r'@Json:$.fallback'],
    );
  });

  test('interpreter preserves existing CSS selection and accessors', () {
    final root = RuleNode.html(
      html.parse('''
            <main>
              <div class="book"><a href="/1">第一本</a><span>附注</span></div>
              <div class="book"><a href="/2">第二本<script>隐藏</script></a></div>
            </main>
          ''').documentElement!,
    );
    const interpreter = RuleInterpreter();

    final books = interpreter.select(root, '@CSS:.book');

    expect(books, hasLength(2));
    expect(interpreter.extract(books.first, '@CSS:a@text'), '第一本');
    expect(interpreter.extractFirst(root, '@CSS:.book a@text'), '第一本');
    expect(interpreter.extract(books.first, '@CSS:a@href'), '/1');
    expect(interpreter.extract(books.first, '@CSS:@ownText'), '');
    expect(interpreter.extract(books.last, '@CSS:a@text'), '第二本');
    expect(interpreter.extract(books.first, '@CSS:a@html'), contains('<a'));
  });

  test('interpreter uses the first non-empty fallback branch', () {
    final root = RuleNode.html(
      html.parse('<div><h1 class="title">月下读书</h1></div>').documentElement!,
    );
    const interpreter = RuleInterpreter();

    expect(
      interpreter.extract(root, '@CSS:.missing@text||@CSS:.title@text'),
      '月下读书',
    );
    expect(
      interpreter.select(root, '@CSS:.missing||@CSS:.title'),
      hasLength(1),
    );
  });

  test('interpreter translates common legacy selector chains', () {
    final root = RuleNode.html(
      html.parse('''
        <section id="catalog">
          <div class="book"><a href="/1">第一本</a></div>
          <div class="book"><a href="/2">第二本</a></div>
        </section>
      ''').documentElement!,
    );
    const interpreter = RuleInterpreter();

    expect(interpreter.select(root, 'id.catalog@tag.div'), hasLength(2));
    expect(interpreter.extract(root, 'class.book@tag.a@text'), '第一本\n第二本');
    expect(interpreter.extract(root, 'class.book@tag.a@href'), '/1\n/2');
  });

  test('interpreter handles bare accessors and exact-text legacy links', () {
    final root = RuleNode.html(
      html.parse('''
        <div id="list"><a href="/chapter/1">第一章</a></div>
        <nav><a href="/chapter/2">下一页</a></nav>
      ''').documentElement!,
    );
    const interpreter = RuleInterpreter();
    final chapter = interpreter.select(root, '@CSS:#list a').single;

    expect(interpreter.extract(chapter, 'text'), '第一章');
    expect(interpreter.extract(chapter, 'href'), '/chapter/1');
    expect(interpreter.extract(root, 'text.下一页@href'), '/chapter/2');
  });

  test('interpreter evaluates the safe HTML XPath subset', () {
    final root = RuleNode.html(
      html.parse('''
        <main>
          <h1>目录</h1>
          <div class="book featured"><a href="/1">第一本</a></div>
          <div class="book"><a href="/2">第二本</a></div>
          <ul><li>A1</li><li>A2</li></ul>
          <ul><li>B1</li><li>B2</li></ul>
          <section id="axes"><a id="direct">直系</a><div><a id="nested">后代</a></div></section>
          <div class="outer"><div class="inner"><a id="shared">共享后代</a></div></div>
        </main>
      ''').documentElement!,
    );
    const interpreter = RuleInterpreter();

    final books = interpreter.select(
      root,
      r'@XPath://div[contains(@class,"book")]',
    );

    expect(books, hasLength(2));
    expect(interpreter.extract(root, r'@XPath://h1/text()'), '目录');
    expect(interpreter.extract(books.first, r'@XPath:.//a/@href'), '/1');
    expect(
      interpreter.extract(root, r'@XPath://div[@class="book"][1]//a/text()'),
      '第二本',
    );
    expect(interpreter.extract(root, r'@XPath://ul/li[1]/text()'), 'A1\nB1');
    expect(
      interpreter.extract(root, r'@XPath://section[@id="axes"]/a/@id'),
      'direct',
    );
    expect(
      interpreter.extract(root, r'@XPath://section[@id="axes"]//a/@id'),
      'direct\nnested',
    );
    expect(
      interpreter.extract(root, r'@XPath:/html/body/main/h1/text()'),
      '目录',
    );
    expect(
      interpreter.extract(root, r'@XPath://html/body/main/h1/text()'),
      '目录',
    );
    expect(
      interpreter.extract(root, r'@XPath://div//a[@id="shared"]/@id'),
      'shared',
    );
    expect(
      () => interpreter.select(root, r'@XPath://div[starts-with(@class,"b")]'),
      throwsFormatException,
    );
  });

  test('interpreter selects JSONPath fields, indices and wildcards', () {
    final root = RuleNode.json(
      jsonDecode('''
        {
          "books": [
            {"name": "第一本", "tags": ["古典", "短篇"]},
            {"name": "第二本", "tags": ["现代"]}
          ]
        }
      '''),
    );
    const interpreter = RuleInterpreter();

    final books = interpreter.select(root, r'@Json:$.books[*]');

    expect(books, hasLength(2));
    expect(interpreter.extract(books.first, r'@Json:$.name'), '第一本');
    expect(interpreter.extract(root, r'@Json:$.books[1].name'), '第二本');
    expect(interpreter.extract(root, r'@Json:$.books[0].tags[*]'), '古典\n短篇');
  });

  test('interpreter supports RFC JSONPath filter selectors', () {
    final root = RuleNode.json(
      jsonDecode('''
        {
          "books": [
            {"name": "短篇", "score": 7},
            {"name": "长篇", "score": 9},
            {"name": "经典", "score": 10}
          ]
        }
      '''),
    );
    const interpreter = RuleInterpreter();

    expect(
      interpreter.extract(root, r'@Json:$.books[?@.score >= 8].name'),
      '长篇\n经典',
    );
  });

  test(
    'interpreter sends only extracted result to post-processing JS',
    () async {
      final root = RuleNode.html(
        html.parse('<article id="content">正文广告</article>').documentElement!,
      );
      final runtime = _RecordingScriptRuntime()..result = '正文';
      const interpreter = RuleInterpreter();

      final value = await interpreter.extractWithScripts(
        root,
        '@CSS:#content@text@js:result.replace(/广告/g, "")',
        scriptRuntime: runtime,
      );

      expect(value, '正文');
      expect(runtime.script, 'result.replace(/广告/g, "")');
      expect(runtime.globals, {'result': '正文广告'});
    },
  );

  test('interpreter applies bounded regex replacement rules', () {
    final root = RuleNode.html(
      html.parse('<h1 class="title">月   下 阅读</h1>').documentElement!,
    );
    const interpreter = RuleInterpreter();

    expect(interpreter.extract(root, r'@CSS:.title@text##\s+## '), '月 下 阅读');
    expect(
      () => interpreter.extract(root, r'@CSS:.title@text##(a+)+$##'),
      throwsFormatException,
    );
    expect(
      () => interpreter.extract(root, r'@CSS:.title@text##x?##y'),
      throwsFormatException,
    );
    expect(
      () => interpreter.extract(root, '@CSS:.title@text##月##${'y' * 4097}'),
      throwsFormatException,
    );
    final ambiguous =
        '^${List.filled(80, 'a?').join()}'
        '${List.filled(80, 'a').join()}b\$';
    expect(
      () => interpreter.extract(
        RuleNode.html(html.parse('<h1>${'a' * 80}</h1>').documentElement!),
        '@CSS:h1@text##$ambiguous##x',
      ),
      throwsFormatException,
    );
  });
}
