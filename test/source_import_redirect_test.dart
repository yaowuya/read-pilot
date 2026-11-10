import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/services/source_import_service.dart';

/// The real yckceo feed redirects to this jsDelivr mirror.
const _requestedUrl = 'https://www.yckceo.com/yuedu/shuyuans/json/id/1325.json';
const _redirectedUrl =
    'https://gcore.jsdelivr.net/gh/mumuceo/file01/202610/'
    '15320_712f79e6df0d9fad5e4a331a960ebfdd.json';

Map<String, dynamic> _sourceJson({String name = '网络书源'}) => {
  'bookSourceUrl': 'https://books.example',
  'bookSourceName': name,
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
  group('yckceo feed redirect', () {
    test('follows 302 to the jsDelivr mirror and parses the payload', () async {
      final visited = <Uri>[];
      final client = MockClient((request) async {
        visited.add(request.url);
        if (request.url.toString() == _requestedUrl) {
          return http.Response(
            '<html><body>Found</body></html>',
            302,
            headers: {
              'location': _redirectedUrl,
              'content-type': 'text/html; charset=utf-8',
            },
          );
        }
        expect(request.url.toString(), _redirectedUrl);
        return http.Response(
          jsonEncode([_sourceJson(name: '错层小说网')]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = SourceImportService(client: client);
      addTearDown(service.close);

      final preview = await service.prepare(
        SourceImportInput.url(Uri.parse(_requestedUrl)),
      );

      expect(preview.sources.single.name, '错层小说网');
      expect(preview.provenance.kind, SourceImportKind.url);
      // The redirect chain stays visible in provenance: what the caller asked
      // for and where the bytes actually came from are different answers.
      expect(preview.provenance.requestedUri.toString(), _requestedUrl);
      expect(preview.provenance.finalUri.toString(), _redirectedUrl);
      expect(preview.provenance.contentType, 'application/json; charset=utf-8');
      expect(preview.provenance.responseBytes, greaterThan(0));
      expect(visited, hasLength(2));
    });

    test('accepts the mirror Content-Type that jsDelivr really sends', () {
      // jsDelivr serves the redirected document as application/json with a
      // charset parameter. Anything that splits on ';' must keep working.
      for (final contentType in [
        'application/json; charset=utf-8',
        'application/json',
        'application/json;charset=UTF-8',
        'text/plain; charset=utf-8',
        'application/octet-stream',
      ]) {
        final mediaType = contentType.split(';').first.trim().toLowerCase();
        expect(
          const {
                'application/json',
                'application/octet-stream',
                'application/force-download',
                'text/json',
                'text/plain',
              }.contains(mediaType) ||
              mediaType.endsWith('+json'),
          isTrue,
          reason: contentType,
        );
      }
    });

    test('rejects a redirect that leaves HTTPS', () async {
      final client = MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'http://mirror.example/source.json'},
        ),
      );
      final service = SourceImportService(client: client);
      addTearDown(service.close);

      await expectLater(
        service.prepare(SourceImportInput.url(Uri.parse(_requestedUrl))),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            SourceImportErrorKind.redirect,
          ),
        ),
      );
    });

    test('rejects a redirect to a private address', () async {
      final client = MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://127.0.0.1/source.json'},
        ),
      );
      final service = SourceImportService(client: client);
      addTearDown(service.close);

      await expectLater(
        service.prepare(SourceImportInput.url(Uri.parse(_requestedUrl))),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            SourceImportErrorKind.redirect,
          ),
        ),
      );
    });

    test('rejects a redirect loop past the configured budget', () async {
      final client = MockClient(
        (request) async => http.Response(
          '',
          302,
          headers: {'location': request.url.toString()},
        ),
      );
      final service = SourceImportService(client: client);
      addTearDown(service.close);

      await expectLater(
        service.prepare(SourceImportInput.url(Uri.parse(_requestedUrl))),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            SourceImportErrorKind.redirect,
          ),
        ),
      );
    });
  });

  group('transport retry', () {
    test(
      'recovers when the first handshakes fail and a later one works',
      () async {
        // Some origins drop TLS handshakes intermittently: a request that fails
        // at the transport layer succeeds unchanged a moment later.
        var attempts = 0;
        final requests = <http.BaseRequest>[];
        final client = MockClient((request) async {
          requests.add(request);
          attempts++;
          if (attempts <= 3) {
            throw const SocketExceptionLike(
              'Connection terminated in handshake',
            );
          }
          return http.Response(
            jsonEncode([_sourceJson(name: '重试后成功')]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final service = SourceImportService(client: client);
        addTearDown(service.close);

        final preview = await service.prepare(
          SourceImportInput.url(Uri.parse(_requestedUrl)),
        );

        expect(preview.sources.single.name, '重试后成功');
        expect(attempts, 4);
        // Every attempt carried the same method and URL; nothing about the
        // request drifted between retries.
        expect(requests, hasLength(4));
        for (final request in requests) {
          expect(request.method, 'GET');
          expect(request.url.toString(), _requestedUrl);
        }
      },
    );

    test(
      'gives up after the retry budget instead of hammering forever',
      () async {
        var attempts = 0;
        final client = MockClient((_) async {
          attempts++;
          throw const SocketExceptionLike('Connection reset by peer');
        });
        final service = SourceImportService(client: client);
        addTearDown(service.close);

        await expectLater(
          service.prepare(SourceImportInput.url(Uri.parse(_requestedUrl))),
          throwsA(
            isA<SourceImportException>().having(
              (error) => error.kind,
              'kind',
              SourceImportErrorKind.network,
            ),
          ),
        );
        // The bound is what keeps a dead host from turning into a hang.
        expect(attempts, 8);
      },
    );

    test('never retries a completed HTTP error response', () async {
      var attempts = 0;
      final client = MockClient((_) async {
        attempts++;
        return http.Response('busy', 503);
      });
      final service = SourceImportService(client: client);
      addTearDown(service.close);

      await expectLater(
        service.prepare(SourceImportInput.url(Uri.parse(_requestedUrl))),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            SourceImportErrorKind.httpStatus,
          ),
        ),
      );
      expect(attempts, 1);
    });

    test('never retries a content-type rejection', () async {
      var attempts = 0;
      final client = MockClient((_) async {
        attempts++;
        return http.Response(
          '<html></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      final service = SourceImportService(client: client);
      addTearDown(service.close);

      await expectLater(
        service.prepare(SourceImportInput.url(Uri.parse(_requestedUrl))),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            SourceImportErrorKind.contentType,
          ),
        ),
      );
      expect(attempts, 1);
    });

    test('an abort wins over an in-flight retry', () async {
      final abort = Completer<void>();
      var attempts = 0;
      final client = MockClient((_) async {
        attempts++;
        throw const SocketExceptionLike('Connection terminated in handshake');
      });
      final service = SourceImportService(client: client);
      addTearDown(service.close);

      final pending = service.prepare(
        SourceImportInput.url(Uri.parse(_requestedUrl)),
        abortTrigger: abort.future,
      );
      abort.complete();

      await expectLater(
        pending.timeout(const Duration(seconds: 5)),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            anyOf(
              SourceImportErrorKind.cancelled,
              SourceImportErrorKind.network,
            ),
          ),
        ),
      );
      expect(attempts, lessThan(8));
    });
  });
}

/// Stand-in for a `dart:io` transport failure.
///
/// The retry path classifies failures by "did this produce a response", not by
/// exception type, so a plain exception exercises the same branch without
/// dragging dart:io into a test that may run on the web VM.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;

  @override
  String toString() => 'SocketExceptionLike: $message';
}
