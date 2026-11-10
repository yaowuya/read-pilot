import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/reader_cache_sheet.dart';
import 'package:sembast/sembast_memory.dart';

Book _book({
  String sourceId = 'https://old.example',
  int chapters = 7,
  int chapterIndex = 2,
}) => Book(
  id: 'book',
  title: '测试书',
  author: '作者',
  description: '',
  category: '文学',
  coverStyle: 0,
  sourceLabel: '已授权书源',
  sourceId: sourceId,
  url: '$sourceId/book',
  position: ReadingPosition(chapterIndex: chapterIndex),
  addedAt: DateTime.utc(2026),
  chapters: [
    for (var index = 0; index < chapters; index++)
      Chapter(id: 'chapter-$index', title: '第${index + 1}章'),
  ],
);

class _CacheController extends AppController {
  _CacheController(super.repository, super.engine, this.current);

  Book current;
  int calls = 0;
  int? startIndex;
  int? count;
  bool stopped = false;
  Completer<ChapterCacheBatchResult>? pending;

  @override
  Book? book(String id) => current.id == id ? current : null;

  @override
  Future<ChapterCacheBatchResult> cacheChapterRange(
    String bookId, {
    required int startIndex,
    required int count,
    Future<void>? abortTrigger,
    void Function(int completed, int total)? onProgress,
  }) async {
    calls++;
    this.startIndex = startIndex;
    this.count = count;
    abortTrigger?.then((_) => stopped = true);
    onProgress?.call(1, count);
    return pending?.future ??
        ChapterCacheBatchResult(
          requested: count,
          completed: count,
          downloaded: count,
          skippedCached: 0,
          failedIndices: const [],
          cancelled: false,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late _CacheController controller;
  late Book initial;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'cache-sheet-${DateTime.now().microsecondsSinceEpoch}',
    );
    initial = _book();
    controller = _CacheController(
      AppRepository(database),
      SourceEngine(),
      initial,
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    ReaderCacheSheet(controller: controller, book: initial),
              ),
              child: const Text('打开缓存'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开缓存'));
    await tester.pumpAndSettle();
  }

  testWidgets('a five-chapter range can stop after its current download', (
    tester,
  ) async {
    controller.pending = Completer<ChapterCacheBatchResult>();
    await openSheet(tester);
    expect(find.text('全部章节'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('reader-cache-count')),
          )
          .value,
      5,
    );
    expect(find.text('第3章 — 第7章'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-cache-confirm')));
    await tester.pump();
    expect(controller.calls, 1);
    expect(controller.startIndex, 2);
    expect(controller.count, 5);
    expect(find.text('1 / 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-cache-stop')));
    await tester.pump();
    expect(controller.stopped, isTrue);
    controller.pending!.complete(
      ChapterCacheBatchResult(
        requested: 5,
        completed: 1,
        downloaded: 1,
        skippedCached: 0,
        failedIndices: const [],
        cancelled: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已停止'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default batch is 10 chapters, with 20, 50, and the rest', (
    tester,
  ) async {
    initial = _book(chapters: 80, chapterIndex: 0);
    controller.current = initial;
    await openSheet(tester);
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const Key('reader-cache-count')),
          )
          .value,
      10,
    );
    expect(find.text('第1章 — 第10章'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-cache-count')));
    await tester.pumpAndSettle();
    expect(find.text('20 章'), findsOneWidget);
    expect(find.text('50 章'), findsOneWidget);
    expect(find.text('全部章节'), findsOneWidget);

    await tester.tap(find.text('50 章').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-cache-confirm')));
    await tester.pumpAndSettle();
    expect(controller.startIndex, 0);
    expect(controller.count, 50);

    await tester.tap(find.byKey(const Key('reader-cache-count')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部章节').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-cache-confirm')));
    await tester.pumpAndSettle();
    expect(controller.count, 80);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a source change disables stale cache actions', (tester) async {
    await openSheet(tester);
    controller.current = _book(sourceId: 'https://new.example');
    await tester.tap(find.byKey(const Key('reader-cache-confirm')));
    await tester.pumpAndSettle();
    expect(controller.calls, 0);
    expect(find.byKey(const Key('reader-cache-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
