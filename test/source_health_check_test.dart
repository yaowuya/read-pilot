import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/domain/source_health.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

class _HealthSourceEngine extends SourceEngine {
  final calls = <String>[];
  Completer<List<Book>>? pendingSearch;
  Object? searchError;
  bool emptyCatalog = false;

  Book get _candidate => Book(
    id: 'health-book',
    title: '检查用书',
    author: '检查作者',
    description: '',
    category: '网络',
    coverStyle: 0,
    sourceLabel: '健康检查书源',
    sourceId: 'https://health.example',
    url: 'https://health.example/book',
    addedAt: DateTime.utc(2026),
  );

  @override
  Future<List<Book>> search(
    BookSource source,
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    calls.add('search');
    final pending = pendingSearch;
    if (pending != null) return pending.future;
    final error = searchError;
    if (error != null) throw error;
    return [_candidate];
  }

  @override
  Future<List<Book>> explore(
    BookSource source,
    SourceExploreEntry entry, {
    int page = 1,
    Map<String, String> exploreInfo = const {},
    Future<void>? abortTrigger,
  }) async {
    calls.add('explore');
    return [_candidate];
  }

  @override
  Future<Book> loadBook(
    BookSource source,
    Book result, {
    Future<void>? abortTrigger,
  }) async {
    calls.add('catalog');
    if (emptyCatalog) return result;
    return result.copyWith(
      chapters: [
        Chapter(
          id: 'health-chapter',
          title: '检查章节',
          url: 'https://health.example/chapter',
        ),
      ],
    );
  }

  @override
  Future<Chapter> loadChapter(
    BookSource source,
    Chapter chapter, {
    Future<void>? abortTrigger,
  }) async {
    calls.add('content');
    return chapter.withParagraphs(const ['检查正文。']);
  }
}

Map<String, dynamic> _sourceJson({String? comment}) => {
  'bookSourceUrl': 'https://health.example',
  'bookSourceName': '健康检查书源',
  'bookSourceComment': ?comment,
  'searchUrl': '/search?q={{key}}',
  'exploreUrl': '发现::/discover',
  'ruleSearch': {
    'bookList': '@CSS:.book',
    'name': '@CSS:a@text',
    'bookUrl': '@CSS:a@href',
  },
  'ruleExplore': {
    'bookList': '@CSS:.book',
    'name': '@CSS:a@text',
    'bookUrl': '@CSS:a@href',
  },
  'ruleBookInfo': {'name': '@CSS:h1@text'},
  'ruleToc': {
    'chapterList': '@CSS:a',
    'chapterName': '@text',
    'chapterUrl': '@href',
  },
  'ruleContent': {'content': '@CSS:article@html'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late _HealthSourceEngine engine;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'source-health-${DateTime.now().microsecondsSinceEpoch}',
    );
    engine = _HealthSourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(jsonEncode([_sourceJson()]));
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'runs every configured stage and records the verdict on the source',
    () async {
      final report = await controller.checkSourceHealth(
        'https://health.example',
      );

      expect(report.sourceId, 'https://health.example');
      expect(report.results.map((result) => result.stage.name), [
        'search',
        'explore',
        'catalog',
        'content',
      ]);
      expect(
        report.results.map((result) => result.status.name),
        everyElement('passed'),
      );
      expect(engine.calls, ['search', 'explore', 'catalog', 'content']);
      expect(report.tags, isEmpty);
      expect(report.failureSummary, isNull);

      // Legado has no health table: the verdict lives on the source itself.
      final stored = (await controller.repository.sources()).single;
      expect(stored.respondTime, report.respondTimeMillis);
      expect(stored.respondTime, greaterThanOrEqualTo(0));
      expect(stored.invalidGroups, isEmpty);
      expect(stored.cleanComment, isEmpty);
    },
  );

  test(
    'a failing stage tags the source group and comments the error',
    () async {
      engine.searchError = const FormatException('站点返回了 502。');

      final report = await controller.checkSourceHealth(
        'https://health.example',
      );

      expect(report.results.first.status, SourceHealthStatus.failed);
      expect(report.results.first.tags, contains(SourceHealthTag.searchFailed));
      expect(report.results.first.tags, contains(SourceHealthTag.siteFailed));
      expect(report.results.skip(1).map((result) => result.status.name), [
        'skipped',
        'skipped',
        'skipped',
      ]);

      final stored = (await controller.repository.sources()).single;
      expect(stored.groups, contains(SourceHealthTag.searchFailed));
      expect(stored.groups, contains(SourceHealthTag.siteFailed));
      expect(stored.cleanComment, isEmpty);
      expect(stored.comment, startsWith('// Error:'));
      // 备注会显示在书源行的界面里，阶段名必须是界面上那个中文名字。
      expect(stored.comment, contains('（搜索）'));
      expect(stored.comment, isNot(contains('search')));
      expect(
        controller.sources.single.groups,
        contains(SourceHealthTag.searchFailed),
      );
    },
  );

  test(
    'a clean run clears tags and error comments left by an earlier check',
    () async {
      // The in-memory copy is what the check reads, so seed the stale verdict
      // through the controller instead of only writing the database record.
      await controller.updateSource(
        controller.sources.single
            .withGroups(['玄幻', SourceHealthTag.searchFailed])
            .withComment('// Error: 上一次失败了。\n\n正常备注'),
      );
      expect(
        controller.sources.single.groups,
        contains(SourceHealthTag.searchFailed),
      );

      final report = await controller.checkSourceHealth(
        'https://health.example',
      );

      expect(report.hasFailures, isFalse);
      final stored = (await controller.repository.sources()).single;
      expect(stored.groups, ['玄幻']);
      expect(stored.comment, '正常备注');
    },
  );

  test('a stage that parses nothing usable stops the later stages', () async {
    engine.emptyCatalog = true;

    final report = await controller.checkSourceHealth('https://health.example');

    expect(report.results.map((result) => result.status.name), [
      'passed',
      'passed',
      'failed',
      'skipped',
    ]);
    expect(
      report.results[2].tags,
      contains(SourceHealthTag.searchCatalogFailed),
    );
    expect(engine.calls, ['search', 'explore', 'catalog']);
    expect(
      (await controller.repository.sources()).single.groups,
      contains(SourceHealthTag.searchCatalogFailed),
    );
  });

  test(
    'a timed-out run stores timeout plus elapsed so the source sorts last',
    () async {
      await controller.updateSourceCheckSettings(
        controller.sourceCheckSettings.copyWith(
          timeout: const Duration(milliseconds: 80),
        ),
      );
      final pending = Completer<List<Book>>();
      engine.pendingSearch = pending;

      final report = await controller.checkSourceHealth(
        'https://health.example',
      );

      expect(report.results.first.status, SourceHealthStatus.timedOut);
      expect(report.results.first.tags, [SourceHealthTag.timeout]);
      expect(report.timedOutAt, isNotNull);
      expect(
        report.respondTimeMillis,
        greaterThanOrEqualTo(const Duration(milliseconds: 80).inMilliseconds),
      );

      final stored = (await controller.repository.sources()).single;
      expect(stored.groups, contains(SourceHealthTag.timeout));
      expect(stored.groups, everyElement(isNot(SourceHealthTag.searchFailed)));
      pending.complete(const []);
    },
  );

  test('cancelling source health checks prevents queued stages', () async {
    final pendingSearch = Completer<List<Book>>();
    engine.pendingSearch = pendingSearch;
    final abort = Completer<void>();

    final pending = controller.checkSourceHealth(
      'https://health.example',
      abortTrigger: abort.future,
    );
    await Future<void>.delayed(Duration.zero);
    abort.complete();
    final report = await pending;
    pendingSearch.complete(const []);

    expect(report.results.map((result) => result.status), [
      SourceHealthStatus.cancelled,
      SourceHealthStatus.skipped,
      SourceHealthStatus.skipped,
      SourceHealthStatus.skipped,
    ]);
    expect(engine.calls, ['search']);
    // A cancelled run says nothing about the source, so it must not be recorded.
    final stored = (await controller.repository.sources()).single;
    expect(stored.respondTime, 0);
    expect(stored.groups, isEmpty);
    expect(stored.comment, isEmpty);
  });

  test('settings decide which stages run and are persisted', () async {
    await controller.updateSourceCheckSettings(
      controller.sourceCheckSettings.copyWith(
        checkSearch: false,
        checkExplore: true,
        checkInfo: false,
        checkCatalog: true,
        checkContent: false,
        timeout: const Duration(seconds: 60),
      ),
    );

    final report = await controller.checkSourceHealth('https://health.example');

    expect(report.results.map((result) => result.status.name), [
      'skipped',
      'passed',
      'passed',
      'skipped',
    ]);
    expect(engine.calls, ['explore', 'catalog']);

    final restored = await controller.repository.sourceCheckSettings();
    expect(restored.checkSearch, isFalse);
    expect(restored.timeout, const Duration(seconds: 60));
  });

  test('both public entry points may not be disabled at once', () async {
    expect(
      () => controller.updateSourceCheckSettings(
        controller.sourceCheckSettings.copyWith(
          checkSearch: false,
          checkExplore: false,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
