import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book_source.dart';

/// Minimal viable source JSON: only `bookSourceUrl`/`bookSourceName` are
/// required by SourceDefinition, which keeps these tests focused on
/// `exploreEntries` parsing alone.
Map<String, dynamic> _sourceJson({String? exploreUrl}) => {
  'bookSourceUrl': 'https://source.example',
  'bookSourceName': '测试书源',
  'exploreUrl': exploreUrl,
};

BookSource _source(String? exploreUrl) =>
    BookSource(_sourceJson(exploreUrl: exploreUrl));

void main() {
  group('BookSource.exploreEntries', () {
    test('parses the legacy title::url list', () {
      final entries = _source(
        '热门::/genre/{{page}}\n完结::/finished/{{page}}',
      ).exploreEntries;
      expect(entries.map((entry) => (entry.title, entry.url)), [
        ('热门', '/genre/{{page}}'),
        ('完结', '/finished/{{page}}'),
      ]);
    });

    test('splits legacy entries on && as well as newlines', () {
      final entries = _source('热门::/genre&&完结::/finished').exploreEntries;
      expect(entries.map((entry) => entry.title), ['热门', '完结']);
    });

    test('reuses the source name as title for untitled legacy lines', () {
      final entries = _source('热门::/genre\n/finished/{{page}}').exploreEntries;
      expect(entries.map((entry) => (entry.title, entry.url)), [
        ('热门', '/genre'),
        ('测试书源', '/finished/{{page}}'),
      ]);
    });

    test('decodes the compact JSON array form', () {
      const value =
          '[{"title":"玄幻","url":"/sort/1/{{page}}.html"},'
          '{"title":"都市","url":"https://source.example/sort/12/{{page}}.html"},'
          '{"title":"仅分组","url":""}]';
      final entries = _source(value).exploreEntries;
      expect(entries.map((entry) => (entry.title, entry.url)), [
        ('玄幻', '/sort/1/{{page}}.html'),
        ('都市', 'https://source.example/sort/12/{{page}}.html'),
      ]);
    });

    test('decodes the pretty-printed JSON array form', () {
      const value = '''
[
  {"title": "男生·全部", "url": ""},
  {"title": "玄幻", "url": "/xuanhuan/{{page}}"}
]''';
      final entries = _source(value).exploreEntries;
      expect(entries.map((entry) => (entry.title, entry.url)), [
        ('玄幻', '/xuanhuan/{{page}}'),
      ]);
    });

    test(
      'script-valued exploreUrl yields no entries (regression: MuMu crash)',
      () {
        // Real shape from the yckceo 1325 feed, source ⚡📂全本小说
        // (http://119.45.176.116:5006): a whole @js: program whose shredded
        // lines used to become duplicate `discover-explore-…::}` chips and
        // crash the discover Wrap with "Duplicate keys found".
        const value =
            '@js:\n'
            'var all = [];\n'
            '}\n'
            '});\n'
            '});\n'
            'java.put("all", all);\n'
            'String(all)\n'
            '}';
        expect(_source(value).exploreEntries, isEmpty);
        expect(_source('<js>String(all)</js>').exploreEntries, isEmpty);
        expect(_source('@webjs:location.href').exploreEntries, isEmpty);
        expect(_source('<webjs>history</webjs>').exploreEntries, isEmpty);
      },
    );

    test('junk fragments of shredded payloads are dropped', () {
      final entries = _source(
        '热门::/genre\n}\n});\n[\n{"title": "男生"}',
      ).exploreEntries;
      expect(entries.map((entry) => (entry.title, entry.url)), [
        ('热门', '/genre'),
      ]);
    });

    test(
      'duplicate pairs keep only the first entry (regression: MuMu crash)',
      () {
        final entries = _source(
          '热门::/genre\n热门::/genre\n完结::/finished',
        ).exploreEntries;
        expect(entries.map((entry) => (entry.url)), ['/genre', '/finished']);
      },
    );

    test('JSON array entries are deduped and capped like legacy entries', () {
      final many = [
        for (var index = 0; index < 260; index++)
          {'title': '分类$index', 'url': '/cat/$index'},
      ];
      final first = {'title': '重复', 'url': '/dup'};
      final entries = _source(
        jsonEncode([first, ...many, first]),
      ).exploreEntries;
      expect(entries.length, 200);
      expect(entries.first.title, '重复');
      expect(entries.where((entry) => entry.url == '/dup').length, 1);
      expect(entries.last.url, '/cat/198');
    });

    test('empty, whitespace and null exploreUrl yield no entries', () {
      expect(_source(null).exploreEntries, isEmpty);
      expect(_source('').exploreEntries, isEmpty);
      expect(_source('   \n  ').exploreEntries, isEmpty);
    });
  });
}
