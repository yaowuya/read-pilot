import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reading_activity.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

Book _book({String id = 'history-book', String? sourceId, String? url}) => Book(
  id: id,
  title: '时间线测试书',
  author: '作者',
  description: '',
  category: '本地',
  coverStyle: 0,
  sourceLabel: sourceId == null ? '本地导入' : '书源',
  sourceId: sourceId,
  url: url,
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(id: 'one', title: '第一章', paragraphs: const ['第一章正文']),
    Chapter(id: 'two', title: '第二章', paragraphs: const ['第二章正文']),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'reading-history-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
    await controller.addBook(_book());
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test('records local chapter milestones in newest-first order', () async {
    await controller.recordReadingActivity(
      'history-book',
      0,
      kind: ReadingActivityKind.opened,
    );
    await controller.recordReadingActivity(
      'history-book',
      1,
      kind: ReadingActivityKind.chapter,
    );
    await controller.recordReadingActivity(
      'history-book',
      1,
      kind: ReadingActivityKind.finished,
    );

    expect(controller.readingActivities, hasLength(3));
    expect(
      controller.readingActivities.first.kind,
      ReadingActivityKind.finished,
    );
    expect(controller.readingActivities.first.chapterTitle, '第二章');
    expect(controller.readingActivities.last.kind, ReadingActivityKind.opened);
    expect(
      (await AppRepository(
        database,
      ).readingActivities()).map((item) => item.kind),
      [
        ReadingActivityKind.finished,
        ReadingActivityKind.chapter,
        ReadingActivityKind.opened,
      ],
    );
  });

  test(
    'deduplicates immediate matching activity and bounds retained history',
    () async {
      await controller.recordReadingActivity(
        'history-book',
        0,
        kind: ReadingActivityKind.opened,
      );
      await controller.recordReadingActivity(
        'history-book',
        0,
        kind: ReadingActivityKind.opened,
      );
      expect(controller.readingActivities, hasLength(1));

      for (var index = 0; index < 205; index++) {
        await controller.recordReadingActivity(
          'history-book',
          index.isEven ? 0 : 1,
          kind: index.isEven
              ? ReadingActivityKind.chapter
              : ReadingActivityKind.finished,
        );
      }
      expect(
        controller.readingActivities,
        hasLength(ReadingActivity.maxEntries),
      );
      expect(
        (await AppRepository(database).readingActivities()),
        hasLength(ReadingActivity.maxEntries),
      );
    },
  );

  test(
    'stale bindings reject events and removing a book removes its activity',
    () async {
      final book = controller.book('history-book')!;
      await controller.recordReadingActivity(
        book.id,
        0,
        kind: ReadingActivityKind.opened,
      );
      await AppRepository(database).saveBook(
        _book(sourceId: 'https://new.example', url: 'https://new.example/book'),
      );
      await expectLater(
        controller.recordReadingActivity(
          book.id,
          0,
          kind: ReadingActivityKind.chapter,
        ),
        throwsStateError,
      );
      await controller.removeBook(book.id);
      expect(controller.readingActivities, isEmpty);
      expect(await AppRepository(database).readingActivities(), isEmpty);
    },
  );

  test('clear history keeps books, notes, settings and text rules', () async {
    await controller.addBookmark(
      Bookmark(
        id: 'note',
        bookId: 'history-book',
        chapterIndex: 0,
        paragraphIndex: 0,
        quote: '正文',
        note: '笔记',
        createdAt: DateTime.utc(2026),
      ),
    );
    await controller.addTextRule('history-book', '正文', '显示');
    await controller.recordReadingActivity(
      'history-book',
      0,
      kind: ReadingActivityKind.opened,
    );
    await controller.clearReadingActivities();
    expect(controller.readingActivities, isEmpty);
    expect(controller.book('history-book'), isNotNull);
    expect(controller.bookmarks.single.id, 'note');
    expect(controller.textRules('history-book'), hasLength(1));
  });
}
