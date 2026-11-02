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
    return [_candidate];
  }

  @override
  Future<List<Book>> explore(
    BookSource source,
    SourceExploreEntry entry, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    calls.add('explore');
    return [_candidate];
  }

  @override
  Future<Book> loadBook(BookSource source, Book result) async {
    calls.add('catalog');
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
  Future<Chapter> loadChapter(BookSource source, Chapter chapter) async {
    calls.add('content');
    return chapter.withParagraphs(const ['检查正文。']);
  }
}

Map<String, dynamic> _sourceJson() => {
  'bookSourceUrl': 'https://health.example',
  'bookSourceName': '健康检查书源',
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
    'runs finite source health stages without persisting diagnostics',
    () async {
      final SourceHealthReport report = await controller.checkSourceHealth(
        'https://health.example',
      );
      final results = report.results;

      expect(report.sourceId, 'https://health.example');
      expect(results.map((result) => result.stage.name), [
        'search',
        'explore',
        'catalog',
        'content',
      ]);
      expect(
        results.map((result) => result.status.name),
        everyElement('passed'),
      );
      expect(engine.calls, ['search', 'explore', 'catalog', 'content']);
      expect((await controller.repository.sources()).single.name, '健康检查书源');
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
  });
}
