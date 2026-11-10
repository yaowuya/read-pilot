import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/services/source_importer.dart';

/// One valid Legado-shaped source. `bookSourceUrl` is the identity of a source,
/// so [index] is what makes each entry distinct after de-duplication.
Map<String, dynamic> _sourceJson(int index) => {
  'bookSourceUrl': 'https://books$index.example',
  'bookSourceName': '网络书源$index',
  'searchUrl': '/search?q={{key}}',
  'ruleSearch': {
    'bookList': '@CSS:.book',
    'name': '@CSS:a@text',
    'bookUrl': '@CSS:a@href',
  },
  'ruleToc': {
    'chapterList': '@CSS:a',
    'chapterName': '@text',
    'chapterUrl': '@href',
  },
  'ruleContent': {'content': '@CSS:article@html'},
};

String _payload(int count) => jsonEncode([
  for (var index = 0; index < count; index++) _sourceJson(index),
]);

Matcher _formatExceptionContaining(String message) => isA<FormatException>()
    .having((error) => error.message.toString(), 'message', contains(message));

void main() {
  test('parses a 1466-source aggregate above the former 500 cap', () {
    // Mirrors https://www.yckceo.com/yuedu/shuyuans/json/id/1325.json, which is
    // an 11,248,248-byte array of 1466 sources.
    final parsed = SourceImporter().parse(_payload(1466));

    expect(parsed, hasLength(1466));
    expect(parsed, everyElement(isA<BookSource>()));
    expect(parsed.first.id, 'https://books0.example');
    expect(parsed.last.id, 'https://books1465.example');
    expect(parsed.map((source) => source.id).toSet(), hasLength(1466));
  });

  test('accepts exactly the maximum number of sources', () {
    final parsed = SourceImporter().parse(_payload(SourceImporter.maxSources));

    expect(parsed, hasLength(SourceImporter.maxSources));
  });

  test(
    'rejects one source over the cap with the enforced limit in the message',
    () {
      expect(
        () => SourceImporter().parse(_payload(SourceImporter.maxSources + 1)),
        throwsA(_formatExceptionContaining('${SourceImporter.maxSources}')),
      );
    },
  );

  test('error message is derived from the cap rather than hardcoded', () {
    final overCap = SourceImporter.maxSources + 1;

    expect(
      () => SourceImporter().parse(_payload(overCap)),
      throwsA(
        _formatExceptionContaining('请一次导入 1–${SourceImporter.maxSources} 个书源。'),
      ),
    );
    expect(SourceImporter.maxSourcesLabel, '${SourceImporter.maxSources}');
  });

  test('rejects an empty array', () {
    expect(
      () => SourceImporter().parse('[]'),
      throwsA(_formatExceptionContaining('请一次导入')),
    );
  });
}
