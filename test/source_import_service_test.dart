import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/services/source_import_service.dart';

Map<String, dynamic> _sourceJson({String name = '网络书源'}) => {
  'bookSourceUrl': 'https://books.example',
  'bookSourceName': name,
  'header': {'X-Source-Secret': 'must-not-reach-feed'},
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

void main() {
  test(
    'prepares a URL import without forwarding embedded source headers',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode([_sourceJson()]),
          200,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'content-disposition': 'attachment; filename="source.json"',
          },
        );
      });
      final service = SourceImportService(client: client);
      addTearDown(service.close);

      final preview = await service.prepare(
        SourceImportInput.url(Uri.parse('https://feed.example/source.json')),
      );

      expect(preview.sources.single.name, '网络书源');
      expect(preview.provenance.kind, SourceImportKind.url);
      expect(
        preview.provenance.requestedUri.toString(),
        'https://feed.example/source.json',
      );
      expect(preview.provenance.finalUri, preview.provenance.requestedUri);
      expect(preview.provenance.responseBytes, greaterThan(0));
      expect(requests, hasLength(1));
      expect(requests.single.headers, isNot(contains('x-source-secret')));
      expect(requests.single.headers, isNot(contains('cookie')));
    },
  );

  test(
    'text input reuses the same bounded parser without network work',
    () async {
      var requested = false;
      final service = SourceImportService(
        client: MockClient((_) async {
          requested = true;
          return http.Response('', 500);
        }),
      );
      addTearDown(service.close);

      final preview = await service.prepare(
        SourceImportInput.text(jsonEncode(_sourceJson(name: '粘贴源'))),
      );

      expect(preview.sources.single.name, '粘贴源');
      expect(preview.provenance.kind, SourceImportKind.text);
      expect(requested, isFalse);
    },
  );

  test(
    'rejects an HTML error page instead of parsing it as a source',
    () async {
      final service = SourceImportService(
        client: MockClient(
          (_) async => http.Response(
            '<html><title>503</title></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
      addTearDown(service.close);

      await expectLater(
        service.prepare(
          SourceImportInput.url(Uri.parse('https://feed.example/source.json')),
        ),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            SourceImportErrorKind.contentType,
          ),
        ),
      );
    },
  );

  test(
    'stops streaming a URL import above the configured byte limit',
    () async {
      final service = SourceImportService(
        client: MockClient((_) async => http.Response('x' * 1025, 200)),
        maxResponseBytes: 1024,
      );
      addTearDown(service.close);

      await expectLater(
        service.prepare(
          SourceImportInput.url(Uri.parse('https://feed.example/source.json')),
        ),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            SourceImportErrorKind.tooLarge,
          ),
        ),
      );
    },
  );

  test('rejects URL credentials and unsupported schemes before HTTP', () async {
    final service = SourceImportService(
      client: MockClient((_) async => fail('must not request')),
    );
    addTearDown(service.close);

    for (final value in [
      'file:///tmp/source.json',
      'https://user:secret@feed.example/source.json',
      'javascript:alert(1)',
    ]) {
      await expectLater(
        service.prepare(SourceImportInput.url(Uri.parse(value))),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            SourceImportErrorKind.invalidUrl,
          ),
        ),
      );
    }
  });

  test('enforces its timeout when the HTTP client ignores abort', () async {
    final service = SourceImportService(
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(service.close);

    await expectLater(
      service
          .prepare(
            SourceImportInput.url(
              Uri.parse('https://feed.example/source.json'),
            ),
          )
          .timeout(const Duration(milliseconds: 200)),
      throwsA(
        isA<SourceImportException>().having(
          (error) => error.kind,
          'kind',
          SourceImportErrorKind.timeout,
        ),
      ),
    );
  });

  test('cancels a URL import when the HTTP client ignores abort', () async {
    final abort = Completer<void>();
    final service = SourceImportService(
      client: MockClient((_) => Completer<http.Response>().future),
    );
    addTearDown(service.close);

    final pending = service.prepare(
      SourceImportInput.url(Uri.parse('https://feed.example/source.json')),
      abortTrigger: abort.future,
    );
    abort.complete();

    await expectLater(
      pending.timeout(const Duration(milliseconds: 200)),
      throwsA(
        isA<SourceImportException>().having(
          (error) => error.kind,
          'kind',
          SourceImportErrorKind.cancelled,
        ),
      ),
    );
  });
}
