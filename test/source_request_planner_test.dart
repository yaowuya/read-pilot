import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/services/source_runtime/request_plan.dart';
import 'package:read_pilot/services/source_runtime/request_planner.dart';

BookSource _source({dynamic header}) => BookSource({
  'bookSourceUrl': 'https://books.example/library/',
  'bookSourceName': 'Request planner',
  'header': ?header,
});

void main() {
  const planner = RequestPlanner();

  test('expands GET variables and applies request header overrides', () {
    final plan = planner.plan(
      _source(header: {'User-Agent': 'Source UA', 'X-Shared': 'source'}),
      '/search?q={{key}}&page={{page}},'
      '{"method":"GET","headers":{"X-Shared":"request","X-Page":"1"}}',
      variables: const {'key': '书 & 阅读', 'page': 2},
    );

    expect(plan.method, 'GET');
    expect(
      plan.uri.toString(),
      'https://books.example/search?q=%E4%B9%A6+%26+%E9%98%85%E8%AF%BB&page=2',
    );
    expect(plan.headers['user-agent'], 'Source UA');
    expect(plan.headers['x-shared'], 'request');
    expect(plan.headers['x-page'], '1');
    expect(plan.body, isNull);
  });

  test('compiles a POST object body as form data by default', () {
    final plan = planner.plan(
      _source(),
      '/search,{"method":"POST","body":{"q":"{{key}}","page":"{{page}}"}}',
      variables: const {'key': '月 下', 'page': 3},
    );

    expect(plan.method, 'POST');
    expect(
      plan.headers['content-type'],
      startsWith('application/x-www-form-urlencoded'),
    );
    expect(utf8.decode(plan.body!), 'q=%E6%9C%88+%E4%B8%8B&page=3');
  });

  test('preserves JSON bodies when content-type requests JSON', () {
    final plan = planner.plan(
      _source(),
      '/search,{"method":"POST","headers":{"Content-Type":"application/json"},'
      '"body":{"keyword":"{{key}}"}}',
      variables: const {'key': '测试'},
    );

    expect(plan.headers['content-type'], 'application/json');
    expect(jsonDecode(utf8.decode(plan.body!)), {'keyword': '测试'});
  });

  test('encodes GET variables and POST forms with declared GBK', () {
    final get = planner.plan(
      _source(),
      '/search?q={{key}},{"charset":"gbk"}',
      variables: const {'key': '中文'},
    );
    final post = planner.plan(
      _source(),
      '/search,{"method":"POST","charset":"gbk",'
      '"body":{"q":"{{key}}"}}',
      variables: const {'key': '中文'},
    );

    expect(get.uri.toString(), 'https://books.example/search?q=%D6%D0%CE%C4');
    expect(utf8.decode(post.body!), 'q=%D6%D0%CE%C4');
    expect(
      post.headers['content-type'],
      'application/x-www-form-urlencoded; charset=gbk',
    );
  });

  test('rejects request charsets outside the verified subset', () {
    expect(
      () => planner.plan(
        _source(),
        '/search?q={{key}},{"charset":"gb18030"}',
        variables: const {'key': '测试'},
      ),
      throwsA(
        isA<SourceRuntimeException>().having(
          (error) => error.kind,
          'kind',
          SourceRuntimeErrorKind.unsupportedCapability,
        ),
      ),
    );
  });

  test('rejects request bodies on GET and HEAD', () {
    for (final method in ['GET', 'HEAD']) {
      expect(
        () => planner.plan(
          _source(),
          '/search,{"method":"$method","body":{"q":"test"}}',
        ),
        throwsA(
          isA<SourceRuntimeException>().having(
            (error) => error.kind,
            'kind',
            SourceRuntimeErrorKind.invalidRequest,
          ),
        ),
        reason: method,
      );
    }
  });

  test('rejects unimplemented template expressions explicitly', () {
    expect(
      () => planner.plan(
        _source(),
        '/search?q={{key.toUpperCase()}}',
        variables: const {'key': 'test'},
      ),
      throwsA(
        isA<SourceRuntimeException>().having(
          (error) => error.kind,
          'kind',
          SourceRuntimeErrorKind.unsupportedCapability,
        ),
      ),
    );
  });
}
