import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/source_capability.dart';
import 'package:read_pilot/domain/source_definition.dart';

Map<String, dynamic> _source({dynamic header, dynamic ruleSearch}) => {
  'bookSourceUrl': 'https://books.example/library/',
  'bookSourceName': '兼容测试源',
  'bookSourceType': 0,
  'enabled': true,
  'header': ?header,
  'ruleSearch':
      ruleSearch ??
      {
        'bookList': '@CSS:.book',
        'name': '@CSS:a@text',
        'bookUrl': '@CSS:a@href',
      },
  'ruleBookInfo': {'name': '@CSS:h1@text', 'tocUrl': '@CSS:.toc@href'},
  'ruleToc': {
    'chapterList': '@CSS:a',
    'chapterName': '@text',
    'chapterUrl': '@href',
  },
  'ruleContent': {'content': '@CSS:article@html'},
  'searchUrl': '/search?q={{key}}',
  'unknownMetadata': {'owner': 'user'},
};

void main() {
  test(
    'normalizes object headers while preserving the original JSON shape',
    () {
      final raw = _source(
        header: {
          'User-Agent': 'ReadPilot/1.0',
          'Referer': 'https://books.example/',
        },
      );
      final definition = SourceDefinition.fromJson(raw);

      expect(definition.id, 'https://books.example/library/');
      expect(definition.type, 0);
      expect(definition.staticHeaders, {
        'user-agent': 'ReadPilot/1.0',
        'referer': 'https://books.example/',
      });
      expect(
        definition.requiredCapabilities,
        contains(SourceCapability.staticHeaders),
      );
      expect(definition.toJson()['header'], raw['header']);
      expect(definition.toJson()['unknownMetadata'], raw['unknownMetadata']);

      (raw['header'] as Map<String, dynamic>)['Referer'] =
          'https://evil.example/';
      (raw['unknownMetadata'] as Map<String, dynamic>)['owner'] = 'changed';
      expect(definition.staticHeaders['referer'], 'https://books.example/');
      expect((definition.toJson()['unknownMetadata'] as Map)['owner'], 'user');
    },
  );

  test('accepts JSON-string headers and nested rule objects', () {
    final definition = SourceDefinition.fromJson(
      _source(
        header: jsonEncode({'X-Reader': 'enabled'}),
        ruleSearch: jsonEncode({
          'bookList': '@CSS:.book',
          'name': '@CSS:a@text',
          'bookUrl': '@CSS:a@href',
        }),
      ),
    );

    expect(definition.staticHeaders, {'x-reader': 'enabled'});
    expect(definition.rules('ruleSearch')['name'], '@CSS:a@text');
    expect(definition.toJson()['header'], isA<String>());
    expect(definition.toJson()['ruleSearch'], isA<String>());
  });

  test(
    'accepts executable fields as format but reports runtime requirements',
    () {
      final raw = _source(header: '@js:({"X-Token":"secret"})')
        ..['jsLib'] = 'function helper() { return 1; }'
        ..['loginUrl'] = 'https://books.example/login'
        ..['ruleContent'] = {
          'content': '@XPath://article',
          'nextContentUrl': r'@Json:$.next',
        };
      final definition = SourceDefinition.fromJson(raw);
      final report = definition.capabilitiesFor(
        SourceRuntimeProfile.nativeCore,
      );

      expect(report.formatAccepted, isTrue);
      expect(
        definition.requiredCapabilities,
        containsAll({
          SourceCapability.javascript,
          SourceCapability.login,
          SourceCapability.xpath,
          SourceCapability.jsonPath,
          SourceCapability.contentPagination,
        }),
      );
      expect(report.runtimeImplemented, isFalse);
      expect(
        report.diagnostics.map((item) => item.path),
        containsAll(['header', 'jsLib', 'loginUrl', 'ruleContent.content']),
      );
      expect(definition.toJson()['jsLib'], raw['jsLib']);
    },
  );

  test('reports safe JSONPath and pagination as implemented core features', () {
    final raw =
        _source(
            ruleSearch: {
              'bookList': r'@Json:$.books[?@.score >= 8]',
              'name': r'@Json:$.name',
              'bookUrl': r'@Json:$.url',
            },
          )
          ..['ruleContent'] = {
            'content': r'@Json:$.content',
            'nextContentUrl': r'@Json:$.next',
          };
    final definition = SourceDefinition.fromJson(raw);

    for (final profile in [
      SourceRuntimeProfile.nativeCore,
      SourceRuntimeProfile.webCore,
    ]) {
      final report = definition.capabilitiesFor(profile);
      expect(report.runtimeImplemented, isTrue, reason: profile.name);
      expect(report.platformPermitted, isTrue, reason: profile.name);
    }
  });

  test('keeps JSONPath regex functions blocked by the regex capability', () {
    final definition = SourceDefinition.fromJson(
      _source(
        ruleSearch: {
          'bookList': r'@Json:$.books[?match(@.name, "a+")]',
          'name': r'@Json:$.name',
          'bookUrl': r'@Json:$.url',
        },
      ),
    );

    expect(
      definition.requiredCapabilities,
      containsAll({SourceCapability.jsonPath, SourceCapability.regex}),
    );
    expect(
      definition
          .capabilitiesFor(SourceRuntimeProfile.nativeCore)
          .runtimeImplemented,
      isFalse,
    );
  });

  test('reports declarative explore as an implemented core feature', () {
    final definition = SourceDefinition.fromJson(
      _source()
        ..['exploreUrl'] = '热门::/genre/{{page}}'
        ..['ruleExplore'] = {
          'bookList': '@CSS:.book',
          'name': '@CSS:a@text',
          'bookUrl': '@CSS:a@href',
        },
    );

    for (final profile in [
      SourceRuntimeProfile.nativeCore,
      SourceRuntimeProfile.webCore,
    ]) {
      final report = definition.capabilitiesFor(profile);
      expect(report.runtimeImplemented, isTrue, reason: profile.name);
      expect(report.platformPermitted, isTrue, reason: profile.name);
    }
  });

  test('reports script-wrapped search URLs as JavaScript requirements', () {
    final definition = SourceDefinition.fromJson(
      _source()
        ..['searchUrl'] =
            '<js>var op={method:"POST"};baseUrl+","+JSON.stringify(op)</js>',
    );
    final diagnostic = definition
        .capabilitiesFor(SourceRuntimeProfile.nativeCore)
        .diagnostics
        .singleWhere((item) => item.path == 'searchUrl');

    expect(diagnostic.capability, SourceCapability.javascript);
    expect(diagnostic.runtimeImplemented, isFalse);
  });

  test('reports only the proven XPath and regex subsets as implemented', () {
    final safe = SourceDefinition.fromJson(
      _source(
        ruleSearch: {
          'bookList': '@CSS:.book',
          'name': '@XPath://h1/text()',
          'intro': r'@CSS:.intro@text##\s+## ',
          'bookUrl': '@CSS:a@href',
        },
      ),
    );
    final unsafeXPath = SourceDefinition.fromJson(
      _source(
        ruleSearch: {
          'bookList': '@CSS:.book',
          'name': '@XPath://h1[starts-with(text(),"A")]',
          'bookUrl': '@CSS:a@href',
        },
      ),
    );
    final unsafeRegex = SourceDefinition.fromJson(
      _source(
        ruleSearch: {
          'bookList': '@CSS:.book',
          'name': r'@CSS:h1@text##x?##y',
          'bookUrl': '@CSS:a@href',
        },
      ),
    );

    for (final profile in [
      SourceRuntimeProfile.nativeCore,
      SourceRuntimeProfile.androidCore,
      SourceRuntimeProfile.webCore,
    ]) {
      expect(
        safe.capabilitiesFor(profile).runtimeImplemented,
        isTrue,
        reason: profile.name,
      );
      expect(
        unsafeXPath.capabilitiesFor(profile).runtimeImplemented,
        isFalse,
        reason: profile.name,
      );
      expect(
        unsafeRegex.capabilitiesFor(profile).runtimeImplemented,
        isFalse,
        reason: profile.name,
      );
    }
  });

  test('classifies XPath positions and fallback branches exactly', () {
    final fallback = SourceDefinition.fromJson(
      _source(
        ruleSearch: {
          'bookList': '@CSS:.book',
          'name': '@CSS:h1@text||@XPath://h1/text()',
          'bookUrl': '@CSS:a@href',
        },
      ),
    );
    expect(
      fallback
          .capabilitiesFor(SourceRuntimeProfile.nativeCore)
          .runtimeImplemented,
      isTrue,
    );
    final bareFallback = SourceDefinition.fromJson(
      _source(
        ruleSearch: {
          'bookList': '@CSS:.book',
          'name': '@CSS:.missing@text||//h1/text()',
          'bookUrl': '@CSS:a@href',
        },
      ),
    );
    expect(bareFallback.requiredCapabilities, contains(SourceCapability.xpath));
    expect(
      bareFallback
          .capabilitiesFor(SourceRuntimeProfile.nativeCore)
          .runtimeImplemented,
      isTrue,
    );

    for (final rule in [
      '@XPath://li[0]/text()',
      '@XPath://li[-1]/text()',
      '@XPath://li[1][2]/text()',
      '@CSS:.missing@text||//h1[starts-with(text(),"A")]',
    ]) {
      final definition = SourceDefinition.fromJson(
        _source(
          ruleSearch: {
            'bookList': '@CSS:.book',
            'name': rule,
            'bookUrl': '@CSS:a@href',
          },
        ),
      );
      expect(
        definition
            .capabilitiesFor(SourceRuntimeProfile.nativeCore)
            .runtimeImplemented,
        isFalse,
        reason: rule,
      );
    }
    final unsafeRegexFallback = SourceDefinition.fromJson(
      _source(
        ruleSearch: {
          'bookList': '@CSS:.book',
          'name': r'@CSS:.missing@text##\s+## ||@CSS:h1@text##(a+)+$##x',
          'bookUrl': '@CSS:a@href',
        },
      ),
    );
    expect(
      unsafeRegexFallback
          .capabilitiesFor(SourceRuntimeProfile.nativeCore)
          .runtimeImplemented,
      isFalse,
    );
  });

  test('classifies XPath before its regex post-processing suffix', () {
    final definition = SourceDefinition.fromJson(
      _source(
        ruleSearch: {
          'bookList': '@CSS:.book',
          'name': r'@XPath://h1/text()##\s+## ',
          'bookUrl': '@CSS:a@href',
        },
      ),
    );

    expect(
      definition.requiredCapabilities,
      containsAll({SourceCapability.xpath, SourceCapability.regex}),
    );
    expect(
      definition
          .capabilitiesFor(SourceRuntimeProfile.nativeCore)
          .runtimeImplemented,
      isTrue,
    );
  });

  test('recognizes safe content replacement rules as executable', () {
    final replacement = SourceDefinition.fromJson(
      _source()
        ..['ruleContent'] = {
          'content': '@CSS:article@text',
          'replaceRegex': r'广告词##',
        },
    );
    final diagnostic = replacement
        .capabilitiesFor(SourceRuntimeProfile.nativeCore)
        .diagnostics
        .singleWhere(
          (item) =>
              item.path == 'ruleContent.replaceRegex' &&
              item.capability == SourceCapability.regex,
        );

    expect(diagnostic.runtimeImplemented, isTrue);
  });

  test('keeps regex blocked outside extraction fields', () {
    final selection = SourceDefinition.fromJson(
      _source(
        ruleSearch: {
          'bookList': r'@CSS:.book##\s+## ',
          'name': '@CSS:h1@text',
          'bookUrl': '@CSS:a@href',
        },
      ),
    );
    final unconsumed = SourceDefinition.fromJson(
      _source()
        ..['ruleContent'] = {
          'content': '@CSS:article@text',
          'replaceRegex': r'.*##b',
        },
    );

    for (final (definition, path) in [
      (selection, 'ruleSearch.bookList'),
      (unconsumed, 'ruleContent.replaceRegex'),
    ]) {
      final diagnostic = definition
          .capabilitiesFor(SourceRuntimeProfile.nativeCore)
          .diagnostics
          .singleWhere(
            (item) =>
                item.path == path && item.capability == SourceCapability.regex,
          );
      expect(diagnostic.runtimeImplemented, isFalse, reason: path);
    }
  });

  test(
    'reports sandboxed JavaScript only for the verified Android profile',
    () {
      final definition = SourceDefinition.fromJson(
        _source()
          ..['searchUrl'] = '<js>baseUrl + "/search"</js>'
          ..['ruleContent'] = {'content': '@CSS:article@text@js:result.trim()'},
      );

      expect(
        definition
            .capabilitiesFor(SourceRuntimeProfile.androidCore)
            .runtimeImplemented,
        isTrue,
      );
      expect(
        definition
            .capabilitiesFor(SourceRuntimeProfile.nativeCore)
            .runtimeImplemented,
        isFalse,
      );
      expect(
        definition
            .capabilitiesFor(SourceRuntimeProfile.webCore)
            .runtimeImplemented,
        isFalse,
      );
    },
  );

  test('keeps unrestricted JavaScript blocked on the Android profile', () {
    final definition = SourceDefinition.fromJson(
      _source()..['jsLib'] = 'function unrestricted() { return 1; }',
    );

    expect(
      definition
          .capabilitiesFor(SourceRuntimeProfile.androidCore)
          .runtimeImplemented,
      isFalse,
    );
  });

  test('accepts non-text source types without claiming reader support', () {
    final definition = SourceDefinition.fromJson(
      _source()..['bookSourceType'] = 4,
    );
    final report = definition.capabilitiesFor(SourceRuntimeProfile.nativeCore);

    expect(definition.type, 4);
    expect(definition.requiredCapabilities, contains(SourceCapability.video));
    expect(report.formatAccepted, isTrue);
    expect(report.runtimeImplemented, isFalse);
  });

  test('rejects non-string values for known rule fields', () {
    for (final (setName, field) in [
      ('ruleSearch', 'bookList'),
      ('ruleExplore', 'bookUrl'),
      ('ruleBookInfo', 'tocUrl'),
      ('ruleToc', 'chapterName'),
      ('ruleContent', 'content'),
    ]) {
      final raw = _source();
      final current = raw[setName];
      raw[setName] = {if (current is Map) ...current, field: 123};
      expect(
        () => SourceDefinition.fromJson(raw),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('$setName.$field'),
          ),
        ),
      );
    }
  });

  test('rejects unsafe header names and values before any network work', () {
    for (final header in [
      {'X-Test\r\nInjected': 'value'},
      {'X-Test': 'value\r\nInjected: yes'},
      {'Connection': 'keep-alive'},
    ]) {
      expect(
        () => SourceDefinition.fromJson(_source(header: header)),
        throwsFormatException,
        reason: '$header',
      );
    }
  });
}
