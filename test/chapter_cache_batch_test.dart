import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

class _BatchEngine extends SourceEngine {
  final requests = <String>[];
  final failures = <String>{};
  Completer<Chapter>? heldFirst;
  Completer<void>? started;

  @override
  Future<Chapter> loadChapter(
    BookSource source,
    Chapter chapter, {
    Future<void>? abortTrigger,
  }) {
    requests.add(chapter.id);
    if (failures.contains(chapter.id)) {
      return Future.error(const SourceException('章节暂时不可用'));
    }
    if (requests.length == 1 && heldFirst != null) {
      started?.complete();
      return heldFirst!.future;
    }
    return Future.value(chapter.withParagraphs(['正文 ${chapter.id}']));
  }
}

Book _remoteBook() => Book(
  id: 'cache-batch',
  title: '测试书',
  author: '作者',
  description: '',
  category: '文学',
  coverStyle: 0,
  sourceLabel: '已授权书源',
  sourceId: 'https://source.example',
  url: 'https://source.example/book',
  addedAt: DateTime.utc(2026),
  chapters: [
    for (var index = 0; index < 7; index++)
      Chapter(
        id: 'chapter-$index',
        title: '第${index + 1}章',
        url: 'https://source.example/chapter/$index',
        paragraphs: index == 1 ? const ['已缓存'] : const [],
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;
  late _BatchEngine engine;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'chapter-batch-${DateTime.now().microsecondsSinceEpoch}',
    );
    engine = _BatchEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode({
        'bookSourceUrl': 'https://source.example',
        'bookSourceName': '已授权书源',
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
      }),
    );
    await controller.addBook(_remoteBook());
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'downloads only five selected chapters serially and preserves progress',
    () async {
      final progress = <int>[];
      final result = await controller.cacheChapterRange(
        'cache-batch',
        startIndex: 0,
        count: 5,
        onProgress: (completed, total) {
          expect(total, 5);
          progress.add(completed);
        },
      );

      expect(result.requested, 5);
      expect(result.completed, 5);
      expect(result.downloaded, 4);
      expect(result.skippedCached, 1);
      expect(result.failedIndices, isEmpty);
      expect(result.cancelled, isFalse);
      expect(progress, [1, 2, 3, 4, 5]);
      expect(engine.requests, [
        'chapter-0',
        'chapter-2',
        'chapter-3',
        'chapter-4',
      ]);
      final saved = (await controller.repository.books()).firstWhere(
        (item) => item.id == 'cache-batch',
      );
      expect(
        saved.chapters.take(5).every((chapter) => chapter.isCached),
        isTrue,
      );
      expect(saved.chapters[5].isCached, isFalse);
      expect(saved.position.chapterIndex, 0);
      expect(saved.position.paragraphIndex, 0);
    },
  );

  test(
    'failed chapters remain uncached while later chapters continue',
    () async {
      engine.failures.add('chapter-2');
      final result = await controller.cacheChapterRange(
        'cache-batch',
        startIndex: 1,
        count: 3,
      );
      expect(result.completed, 3);
      expect(result.downloaded, 1);
      expect(result.skippedCached, 1);
      expect(result.failedIndices, [2]);
      expect(result.cancelled, isFalse);
      expect(engine.requests, ['chapter-2', 'chapter-3']);
      final stored = controller.book('cache-batch')!;
      expect(stored.chapters[2].isCached, isFalse);
      expect(stored.chapters[3].isCached, isTrue);
    },
  );

  test('invalid ranges reject before starting any chapter request', () async {
    for (final (start, count) in [(0, 0), (0, 6), (6, 2), (-1, 1)]) {
      await expectLater(
        controller.cacheChapterRange(
          'cache-batch',
          startIndex: start,
          count: count,
        ),
        throwsArgumentError,
      );
    }
    expect(engine.requests, isEmpty);
  });

  test('stop never starts another chapter after the current request', () async {
    final abort = Completer<void>();
    engine.heldFirst = Completer<Chapter>();
    engine.started = Completer<void>();
    final work = controller.cacheChapterRange(
      'cache-batch',
      startIndex: 0,
      count: 5,
      abortTrigger: abort.future,
    );
    await engine.started!.future;
    abort.complete();
    engine.heldFirst!.complete(
      _remoteBook().chapters.first.withParagraphs(['首章已缓存']),
    );
    final result = await work;
    expect(result.completed, 1);
    expect(result.downloaded, 1);
    expect(result.cancelled, isTrue);
    expect(engine.requests, ['chapter-0']);
  });

  test('already stopped batch starts no chapter request', () async {
    final abort = Completer<void>()..complete();
    final result = await controller.cacheChapterRange(
      'cache-batch',
      startIndex: 0,
      count: 1,
      abortTrigger: abort.future,
    );

    expect(result.cancelled, isTrue);
    expect(result.completed, 0);
    expect(engine.requests, isEmpty);
    expect(controller.book('cache-batch')!.chapters.first.isCached, isFalse);
  });

  test('stop from progress callback prevents the next request', () async {
    final abort = Completer<void>();
    final result = await controller.cacheChapterRange(
      'cache-batch',
      startIndex: 0,
      count: 3,
      abortTrigger: abort.future,
      onProgress: (completed, _) {
        if (completed == 1) abort.complete();
      },
    );

    expect(result.cancelled, isTrue);
    expect(result.completed, 1);
    expect(engine.requests, ['chapter-0']);
  });

  test(
    'deleting the book mid-download cannot revive it or continue the queue',
    () async {
      engine.heldFirst = Completer<Chapter>();
      engine.started = Completer<void>();
      final work = controller.cacheChapterRange(
        'cache-batch',
        startIndex: 0,
        count: 5,
      );
      await engine.started!.future;
      await controller.removeBook('cache-batch');
      engine.heldFirst!.complete(
        _remoteBook().chapters.first.withParagraphs(['过期正文']),
      );
      await expectLater(work, throwsA(isA<SourceException>()));
      expect(engine.requests, ['chapter-0']);
      expect(
        (await controller.repository.books()).any(
          (book) => book.id == 'cache-batch',
        ),
        isFalse,
      );
    },
  );
}
