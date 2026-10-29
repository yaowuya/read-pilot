import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

const _bookId = 'recovery-fixture';
const _saveError = '阅读进度暂未保存，请检查本机存储空间。';

List<String> _paragraphs(String prefix) =>
    List.generate(15, (index) => '$prefix $index. ${'用于验证阅读锚点的正文。' * 15}');

class _FailingProgressRepository extends AppRepository {
  _FailingProgressRepository(super.database);
  bool failWrites = false;
  int failedWrites = 0;
  Completer<void>? pendingWrite;

  @override
  Future<void> savePosition(
    String id,
    ReadingPosition position, {
    bool? finished,
  }) async {
    if (failWrites) {
      failedWrites++;
      throw StateError('Storage write failed');
    }
    await pendingWrite?.future;
    await super.savePosition(id, position, finished: finished);
  }
}

class _RetrySourceEngine extends SourceEngine {
  _RetrySourceEngine()
    : super(
        client: MockClient(
          (_) async => throw StateError('Unexpected HTTP request'),
        ),
      );
  int requests = 0;

  @override
  Future<Chapter> loadChapter(BookSource source, Chapter chapter) async {
    if (requests++ == 0) throw const SourceException('临时网络错误');
    return chapter.withParagraphs(_paragraphs('Second chapter'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late _FailingProgressRepository repository;
  late AppController controller;
  late _RetrySourceEngine engine;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'recovery-${DateTime.now().microsecondsSinceEpoch}',
    );
    repository = _FailingProgressRepository(database);
    engine = _RetrySourceEngine();
    controller = AppController(repository, engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode({
        'bookSourceUrl': 'https://books.example',
        'bookSourceName': '恢复测试书源',
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
    await controller.addBook(
      Book(
        id: _bookId,
        title: '复现书',
        author: 'Test',
        description: '',
        category: 'Test',
        coverStyle: 0,
        sourceLabel: '恢复测试书源',
        sourceId: 'https://books.example',
        url: 'https://books.example/book/1',
        addedAt: DateTime.utc(2026),
        chapters: [
          Chapter(
            id: 'first',
            title: 'First chapter',
            url: 'https://books.example/c/1',
            paragraphs: _paragraphs('First chapter'),
          ),
          Chapter(
            id: 'second',
            title: 'Second chapter',
            url: 'https://books.example/c/2',
          ),
        ],
      ),
    );
    await controller.savePosition(
      _bookId,
      const ReadingPosition(chapterIndex: 0, paragraphIndex: 7),
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> openReader(WidgetTester tester) async {
    await tester.pumpWidget(
      ReadPilotApp(controller: controller, initialRoute: '/read/$_bookId'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> failLeaving(WidgetTester tester) async {
    await openReader(tester);
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('reader-back')));
    await tester.pumpAndSettle();
  }

  testWidgets('next chapter retry retains the requested start anchor', (
    tester,
  ) async {
    await openReader(tester);
    expect(controller.book(_bookId)!.position.paragraphIndex, 7);
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(find.text('临时网络错误'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(controller.book(_bookId)!.position.chapterIndex, 1);
    expect(controller.book(_bookId)!.position.paragraphIndex, 0);
    expect(engine.requests, 2);
  });

  testWidgets(
    'failed close-time progress save keeps the reader and allows retry',
    (tester) async {
      await failLeaving(tester);
      expect(repository.failedWrites, greaterThan(0));
      expect(controller.book(_bookId)!.position.paragraphIndex, 7);
      expect(find.text(_saveError), findsOneWidget);
      expect(find.byKey(const Key('reader-back')), findsOneWidget);
      repository.failWrites = false;
      await tester.tap(find.byKey(const Key('reader-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-back')), findsNothing);
      expect(controller.book(_bookId)!.position.paragraphIndex, greaterThan(7));
    },
  );

  testWidgets('save retry clears the error without leaving the reader', (
    tester,
  ) async {
    await failLeaving(tester);
    repository.failWrites = false;
    await tester.tap(find.byKey(const Key('reader-save-retry')));
    await tester.pumpAndSettle();
    expect(find.text(_saveError), findsNothing);
    expect(find.byKey(const Key('reader-back')), findsOneWidget);
    expect(controller.book(_bookId)!.position.paragraphIndex, greaterThan(7));
  });

  testWidgets('explicit discard exits without another progress write', (
    tester,
  ) async {
    await failLeaving(tester);
    final failedWrites = repository.failedWrites;
    await tester.tap(find.byKey(const Key('reader-discard-progress')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsNothing);
    expect(controller.book(_bookId)!.position.paragraphIndex, 7);
    expect(repository.failedWrites, failedWrites);
  });

  testWidgets('failed progress save prevents moving to another chapter', (
    tester,
  ) async {
    await openReader(tester);
    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(engine.requests, 0);
    expect(controller.book(_bookId)!.position.chapterIndex, 0);
    expect(find.text(_saveError), findsOneWidget);
  });

  testWidgets('failed final chapter loading cannot report completion', (
    tester,
  ) async {
    await openReader(tester);
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(find.text('临时网络错误'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('reader-next'))).onPressed,
      isNull,
    );
    expect(controller.book(_bookId)!.finished, isFalse);
    expect(find.text('又读完一本，下一本见。'), findsNothing);
  });

  testWidgets('save retry preserves a failed completion request', (
    tester,
  ) async {
    await tester.runAsync(() async {
      engine.requests = 1;
      await controller.chapter(_bookId, 1);
      await controller.savePosition(
        _bookId,
        const ReadingPosition(chapterIndex: 1),
      );
    });
    await openReader(tester);
    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(find.text(_saveError), findsOneWidget);
    repository.failWrites = false;
    await tester.tap(find.byKey(const Key('reader-save-retry')));
    await tester.pumpAndSettle();
    expect(find.text(_saveError), findsNothing);
    expect(controller.book(_bookId)!.finished, isTrue);
    await tester.runAsync(() async {
      final stored = (await repository.books()).singleWhere(
        (book) => book.id == _bookId,
      );
      expect(stored.finished, isTrue);
    });
  });

  testWidgets('discard during pending close retry pops the reader only once', (
    tester,
  ) async {
    await failLeaving(tester);
    repository.failWrites = false;
    final pending = Completer<void>();
    repository.pendingWrite = pending;
    await tester.tap(find.byKey(const Key('reader-back')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reader-discard-progress')));
    await tester.pump(const Duration(milliseconds: 10));
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('reader-back')), findsNothing);
    expect(find.text('我的书架'), findsOneWidget);
  });

  testWidgets('marking a book finished reports storage failure', (
    tester,
  ) async {
    await tester.runAsync(() async {
      engine.requests = 1;
      await controller.chapter(_bookId, 1);
      await controller.savePosition(
        _bookId,
        const ReadingPosition(chapterIndex: 1),
      );
    });
    await openReader(tester);
    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(controller.book(_bookId)!.finished, isFalse);
    expect(find.text(_saveError), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
