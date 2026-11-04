import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:read_pilot/services/source_runtime/request_plan.dart';
import 'package:read_pilot/services/source_runtime/source_transport.dart';

void main() {
  test(
    'executes a request plan and returns a typed response envelope',
    () async {
      final requests = <http.Request>[];
      final transport = SourceTransport(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(
            utf8.encode('正文'),
            200,
            headers: {'content-type': 'text/plain; charset=utf-8'},
          );
        }),
      );
      addTearDown(transport.close);

      final envelope = await transport.execute(
        RequestPlan(
          uri: Uri.parse('https://books.example/search'),
          method: 'POST',
          headers: {'content-type': 'application/json', 'x-reader': 'enabled'},
          body: utf8.encode('{"q":"test"}'),
        ),
        policy: SourceNetworkPolicy(allowedOrigins: {'https://books.example'}),
      );

      expect(requests.single.method, 'POST');
      expect(requests.single.headers['x-reader'], 'enabled');
      expect(requests.single.body, '{"q":"test"}');
      expect(envelope.requestUri.toString(), 'https://books.example/search');
      expect(envelope.finalUri, envelope.requestUri);
      expect(envelope.statusCode, 200);
      expect(envelope.text, '正文');
      expect(envelope.redirects, isEmpty);
    },
  );

  test('returns binary bytes without applying charset decoding', () async {
    final transport = SourceTransport(
      client: MockClient(
        (_) async => http.Response.bytes(
          const [0x89, 0x50, 0x4e, 0x47, 0xff],
          200,
          headers: {'content-type': 'image/png'},
        ),
      ),
    );
    addTearDown(transport.close);

    final response = await transport.execute(
      RequestPlan(
        uri: Uri.parse('https://books.example/cover.png'),
        method: 'GET',
        headers: const {},
      ),
      policy: SourceNetworkPolicy(allowedOrigins: {'https://books.example'}),
      decodeText: false,
    );

    expect(response.bytes, const [0x89, 0x50, 0x4e, 0x47, 0xff]);
    expect(response.text, isEmpty);
  });

  test(
    'converts POST to GET and strips secrets on a granted 302 redirect',
    () async {
      final requests = <http.Request>[];
      final transport = SourceTransport(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.host == 'books.example') {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://cdn.example/result'},
            );
          }
          return http.Response('ok', 200);
        }),
      );
      addTearDown(transport.close);

      final envelope = await transport.execute(
        RequestPlan(
          uri: Uri.parse('https://books.example/search'),
          method: 'POST',
          headers: {
            'authorization': 'Bearer secret',
            'cookie': 'session=secret',
            'content-type': 'application/json',
            'user-agent': 'Test UA',
            'x-reader': 'safe',
          },
          body: utf8.encode('{}'),
        ),
        policy: SourceNetworkPolicy(
          allowedOrigins: {'https://books.example', 'https://cdn.example'},
        ),
      );

      expect(requests, hasLength(2));
      expect(requests.first.method, 'POST');
      expect(requests.last.method, 'GET');
      expect(requests.last.bodyBytes, isEmpty);
      expect(requests.last.headers, isNot(contains('authorization')));
      expect(requests.last.headers, isNot(contains('cookie')));
      expect(requests.last.headers, isNot(contains('content-type')));
      expect(requests.last.headers, isNot(contains('x-reader')));
      expect(requests.last.headers['user-agent'], 'Test UA');
      expect(envelope.redirects.map((uri) => uri.host), ['cdn.example']);
    },
  );

  test('rejects HTTPS downgrade even when both origins are granted', () async {
    final requests = <http.Request>[];
    final transport = SourceTransport(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://cdn.example/result'},
        );
      }),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.execute(
        RequestPlan(
          uri: Uri.parse('https://books.example/search'),
          method: 'GET',
          headers: const {},
        ),
        policy: SourceNetworkPolicy(
          allowedOrigins: {'https://books.example', 'http://cdn.example'},
        ),
      ),
      throwsA(
        isA<SourceTransportException>().having(
          (error) => error.kind,
          'kind',
          SourceTransportErrorKind.redirect,
        ),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('rejects a cross-origin 307 body replay', () async {
    final requests = <http.Request>[];
    final transport = SourceTransport(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '',
          307,
          headers: {'location': 'https://cdn.example/result'},
        );
      }),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.execute(
        RequestPlan(
          uri: Uri.parse('https://books.example/search'),
          method: 'POST',
          headers: {'content-type': 'application/json'},
          body: utf8.encode('{}'),
        ),
        policy: SourceNetworkPolicy(
          allowedOrigins: {'https://books.example', 'https://cdn.example'},
        ),
      ),
      throwsA(
        isA<SourceTransportException>().having(
          (error) => error.kind,
          'kind',
          SourceTransportErrorKind.redirect,
        ),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('blocks an origin that was not granted before sending HTTP', () async {
    var requested = false;
    final transport = SourceTransport(
      client: MockClient((_) async {
        requested = true;
        return http.Response('unexpected', 200);
      }),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.execute(
        RequestPlan(
          uri: Uri.parse('https://other.example/private'),
          method: 'GET',
          headers: const {},
        ),
        policy: SourceNetworkPolicy(allowedOrigins: {'https://books.example'}),
      ),
      throwsA(
        isA<SourceTransportException>().having(
          (error) => error.kind,
          'kind',
          SourceTransportErrorKind.originDenied,
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test('stops reading a response above the configured byte limit', () async {
    final transport = SourceTransport(
      client: MockClient((_) async => http.Response('x' * 1025, 200)),
      maxResponseBytes: 1024,
    );
    addTearDown(transport.close);

    await expectLater(
      transport.execute(
        RequestPlan(
          uri: Uri.parse('https://books.example/large'),
          method: 'GET',
          headers: const {},
        ),
        policy: SourceNetworkPolicy(allowedOrigins: {'https://books.example'}),
      ),
      throwsA(
        isA<SourceTransportException>().having(
          (error) => error.kind,
          'kind',
          SourceTransportErrorKind.tooLarge,
        ),
      ),
    );
  });

  test('decodes a whole-buffer GBK response from its charset', () async {
    final transport = SourceTransport(
      client: MockClient(
        (_) async => http.Response.bytes(
          const [0xD6, 0xD0, 0xCE, 0xC4],
          200,
          headers: {'content-type': 'text/plain; charset=gbk'},
        ),
      ),
    );
    addTearDown(transport.close);

    final response = await transport.execute(
      RequestPlan(
        uri: Uri.parse('https://books.example/gbk'),
        method: 'GET',
        headers: const {},
      ),
      policy: SourceNetworkPolicy(allowedOrigins: {'https://books.example'}),
    );

    expect(response.text, '中文');
  });

  test(
    'falls back to GBK when the response header omits the charset',
    () async {
      // 中文站常见：正文是 GBK，但 Content-Type 里不带 charset，
      // 以前会整章失败并提示「书源返回的正文不是 UTF-8」。
      final transport = SourceTransport(
        client: MockClient(
          (_) async => http.Response.bytes(
            const [0xD6, 0xD0, 0xCE, 0xC4],
            200,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );
      addTearDown(transport.close);

      final response = await transport.execute(
        RequestPlan(
          uri: Uri.parse('https://books.example/gbk-plain'),
          method: 'GET',
          headers: const {},
        ),
        policy: SourceNetworkPolicy(allowedOrigins: {'https://books.example'}),
      );

      expect(response.text, '中文');
    },
  );

  test('honours a GBK charset declared only in the page meta', () async {
    final body = <int>[
      ...latin1.encode('<html><head><meta charset="gb2312"></head><body>'),
      0xD6,
      0xD0,
      0xCE,
      0xC4,
      ...latin1.encode('</body></html>'),
    ];
    final transport = SourceTransport(
      client: MockClient(
        (_) async => http.Response.bytes(
          body,
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
    );
    addTearDown(transport.close);

    final response = await transport.execute(
      RequestPlan(
        uri: Uri.parse('https://books.example/gbk-meta'),
        method: 'GET',
        headers: const {},
      ),
      policy: SourceNetworkPolicy(allowedOrigins: {'https://books.example'}),
    );

    expect(response.text, contains('中文'));
  });

  test('rejects an unknown response charset explicitly', () async {
    final transport = SourceTransport(
      client: MockClient(
        (_) async => http.Response.bytes(
          const [0x74, 0x65, 0x78, 0x74],
          200,
          headers: {'content-type': 'text/plain; charset=x-unknown'},
        ),
      ),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.execute(
        RequestPlan(
          uri: Uri.parse('https://books.example/unknown'),
          method: 'GET',
          headers: const {},
        ),
        policy: SourceNetworkPolicy(allowedOrigins: {'https://books.example'}),
      ),
      throwsA(
        isA<SourceTransportException>().having(
          (error) => error.kind,
          'kind',
          SourceTransportErrorKind.invalidEncoding,
        ),
      ),
    );
  });

  test('enforces its timeout when the HTTP client ignores abort', () async {
    final transport = SourceTransport(
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(transport.close);

    await expectLater(
      transport
          .execute(
            RequestPlan(
              uri: Uri.parse('https://books.example/slow'),
              method: 'GET',
              headers: const {},
            ),
            policy: SourceNetworkPolicy(
              allowedOrigins: {'https://books.example'},
            ),
          )
          .timeout(const Duration(milliseconds: 200)),
      throwsA(
        isA<SourceTransportException>().having(
          (error) => error.kind,
          'kind',
          SourceTransportErrorKind.timeout,
        ),
      ),
    );
  });
}
