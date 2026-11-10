import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/domain/source_health.dart';
import 'package:read_pilot/services/source_runtime/concurrent_rate_limiter.dart';

BookSource _source(Map<String, dynamic> extra) => BookSource({
  'bookSourceUrl': 'https://rate.example',
  'bookSourceName': '限速书源',
  ...extra,
});

void main() {
  group('ConcurrentRateLimiter.parse', () {
    test('unlimited forms parse to null', () {
      expect(ConcurrentRateLimiter.parse(null), isNull);
      expect(ConcurrentRateLimiter.parse(''), isNull);
      expect(ConcurrentRateLimiter.parse('   '), isNull);
      expect(ConcurrentRateLimiter.parse('0'), isNull);
      expect(ConcurrentRateLimiter.parse('abc'), isNull);
      expect(ConcurrentRateLimiter.parse('-1/1000'), isNull);
      expect(ConcurrentRateLimiter.parse('3/0'), isNull);
    });

    test('reads legado count/interval form', () {
      final limiter = ConcurrentRateLimiter.parse('3/1000')!;
      expect(limiter.accessLimit, 3);
      expect(limiter.interval, 1000);
    });

    test('a bare number means one request per that many milliseconds', () {
      final limiter = ConcurrentRateLimiter.parse('500')!;
      expect(limiter.accessLimit, 1);
      expect(limiter.interval, 500);
    });

    test('ignores surrounding whitespace and keeps the first slash pair', () {
      final limiter = ConcurrentRateLimiter.parse(' 2 / 300 ')!;
      expect(limiter.accessLimit, 2);
      expect(limiter.interval, 300);
    });
  });

  group('ConcurrentRateLimiter.acquire', () {
    test('lets the burst through and then waits for the next window', () async {
      final limiter = ConcurrentRateLimiter.parse('3/100')!;
      final watch = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        await limiter.acquire();
      }
      final burst = watch.elapsedMilliseconds;
      expect(burst, lessThan(90), reason: 'the first three go out together');
      await limiter.acquire();
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(90));
    });

    test('a single-request rate serialises calls', () async {
      final limiter = ConcurrentRateLimiter.parse('1/80')!;
      final watch = Stopwatch()..start();
      await limiter.acquire();
      await limiter.acquire();
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(70));
    });
  });

  group('ConcurrentRateLimiters', () {
    test(
      'keys the budget by source so one host cannot starve another',
      () async {
        final limiters = ConcurrentRateLimiters();
        final watch = Stopwatch()..start();
        await limiters.acquire('https://a.example', '1/200');
        await limiters.acquire('https://b.example', '1/200');
        expect(watch.elapsedMilliseconds, lessThan(150));
      },
    );

    test(
      're-reads the declaration instead of caching the old window',
      () async {
        final limiters = ConcurrentRateLimiters();
        await limiters.acquire('https://a.example', '1/200');
        // Raising the declared rate must take effect without a restart.
        final watch = Stopwatch()..start();
        await limiters.acquire('https://a.example', '5/1000');
        await limiters.acquire('https://a.example', '5/1000');
        expect(watch.elapsedMilliseconds, lessThan(150));
      },
    );

    test('an unlimited declaration never waits', () async {
      final limiters = ConcurrentRateLimiters();
      final watch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        await limiters.acquire('https://a.example', null);
      }
      expect(watch.elapsedMilliseconds, lessThan(100));
    });
  });

  group('SourceHealthTag', () {
    test('recognises every tag this build can write', () {
      for (final tag in SourceHealthTag.all) {
        expect(SourceHealthTag.isInvalid(tag), isTrue, reason: tag);
      }
    });

    test('recognises stale tags written by other clients', () {
      expect(SourceHealthTag.isInvalid('搜索目录失效'), isTrue);
      expect(SourceHealthTag.isInvalid('发现正文失效'), isTrue);
      expect(SourceHealthTag.isInvalid('校验超时'), isTrue);
      expect(SourceHealthTag.isInvalid('玄幻'), isFalse);
      expect(SourceHealthTag.isInvalid('都市'), isFalse);
    });
  });

  group('BookSource group and comment helpers', () {
    test('addGroups merges without duplicating', () {
      final source = _source({'bookSourceGroup': '玄幻,都市'});
      final updated = source.addGroups(['都市', '榜单']);
      expect(updated.groups, ['玄幻', '都市', '榜单']);
      expect(updated.toJson()['bookSourceGroup'], '玄幻,都市,榜单');
    });

    test('removeGroups drops only the named groups', () {
      final source = _source({'bookSourceGroup': '玄幻,搜索失效,都市'});
      expect(source.removeGroups(['搜索失效']).groups, ['玄幻', '都市']);
    });

    test('removeInvalidGroups keeps user groups', () {
      final source = _source({'bookSourceGroup': '玄幻,搜索失效,校验超时,都市'});
      expect(source.removeInvalidGroups().groups, ['玄幻', '都市']);
    });

    test('addErrorComment prepends a block above existing content', () {
      final source = _source({'bookSourceComment': '正常备注'});
      final updated = source.addErrorComment('站点返回了 502。');
      expect(updated.comment, '// Error: 站点返回了 502。\n\n正常备注');
      expect(updated.cleanComment, '正常备注');
    });

    test('addErrorComment on an empty comment has no trailing separator', () {
      final source = _source({});
      expect(source.addErrorComment('超时').comment, '// Error: 超时');
    });

    test('removeErrorComment keeps only real comments', () {
      final source = _source({
        'bookSourceComment': '// Error: 旧错误\n\n// Error: 又一个\n\n用户备注\n\n第二段',
      });
      expect(source.removeErrorComment().comment, '用户备注\n\n第二段');
      expect(source.removeErrorComment().cleanComment, '用户备注\n\n第二段');
    });

    test('respondTime round-trips through the raw json', () {
      final source = _source({}).withRespondTime(1234);
      expect(source.respondTime, 1234);
      expect(source.toJson()['respondTime'], 1234);
      expect(BookSource(source.toJson()).respondTime, 1234);
    });

    test('concurrentRate is kept as the declared string', () {
      final source = _source({'concurrentRate': '3/1000'});
      expect(source.concurrentRate, '3/1000');
      expect(_source({}).concurrentRate, '');
    });
  });
}
