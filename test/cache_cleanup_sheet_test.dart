import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/book_details.dart';
import 'package:sembast/sembast_memory.dart';

Book _remoteBook() => Book(
  id: 'cache-ui',
  title: '章节缓存管理',
  author: '作者',
  description: '',
  category: '文学',
  coverStyle: 0,
  sourceLabel: '远程书源',
  sourceId: 'https://source.example',
  url: 'https://source.example/book',
  addedAt: DateTime.utc(2026),
  position: const ReadingPosition(chapterIndex: 1),
  chapters: [
    for (var index = 0; index < 6; index++)
      Chapter(
        id: 'chapter-$index',
        title: '第${index + 1}章',
        url: 'https://source.example/chapter/$index',
        paragraphs: index == 4 ? const [] : ['正文 $index'],
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'cache-ui-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
    await controller.addBook(_remoteBook());
    await controller.addBookmark(
      Bookmark(
        id: 'chapter-note',
        bookId: 'cache-ui',
        chapterIndex: 3,
        paragraphIndex: 0,
        quote: '摘录',
        note: '不清理',
        createdAt: DateTime.utc(2026),
      ),
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> pumpDetails(WidgetTester tester, Book book) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookDetails(book: book, controller: controller, onRead: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'selection needs confirmation and protects current and noted chapters',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDetails(tester, controller.book('cache-ui')!);
      await tester.tap(find.byKey(const Key('book-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-manage-cache')));
      await tester.pumpAndSettle();

      expect(find.text('可清理 3 / 5 章已缓存'), findsOneWidget);
      expect(find.byKey(const Key('cache-clear-chapter-0')), findsOneWidget);
      expect(find.byKey(const Key('cache-clear-chapter-1')), findsNothing);
      expect(find.byKey(const Key('cache-clear-chapter-3')), findsNothing);
      await tester.tap(find.byKey(const Key('cache-clear-chapter-0')));
      await tester.tap(find.byKey(const Key('cache-clear-chapter-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cache-clear-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('将移除 2 章的本地正文'), findsOneWidget);
      expect(controller.book('cache-ui')!.chapters[0].isCached, isTrue);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(controller.book('cache-ui')!.chapters[0].isCached, isTrue);

      await tester.tap(find.byKey(const Key('cache-clear-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认移除'));
      await tester.pumpAndSettle();
      final saved = controller.book('cache-ui')!;
      expect(saved.chapters[0].isCached, isFalse);
      expect(saved.chapters[2].isCached, isFalse);
      expect(saved.chapters[1].isCached, isTrue);
      expect(saved.chapters[3].isCached, isTrue);
      expect(controller.bookmarks.single.chapterIndex, 3);
      expect(find.text('已清理 2 章'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a newly protected chapter is removed from the selection', (
    tester,
  ) async {
    await pumpDetails(tester, controller.book('cache-ui')!);
    await tester.tap(find.byKey(const Key('book-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-manage-cache')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cache-clear-chapter-0')));
    await tester.pumpAndSettle();
    expect(find.text('清理 1 章缓存'), findsOneWidget);

    await tester.runAsync(
      () => controller.addBookmark(
        Bookmark(
          id: 'new-bookmark',
          bookId: 'cache-ui',
          chapterIndex: 0,
          paragraphIndex: 0,
          quote: '新摘录',
          note: '',
          createdAt: DateTime.utc(2026),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cache-clear-chapter-0')), findsNothing);
    expect(find.text('清理 0 章缓存'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cache-clear-confirm')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('cache-clear-chapter-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cache-clear-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('将移除 1 章的本地正文'), findsOneWidget);
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();
    expect(controller.book('cache-ui')!.chapters[0].isCached, isTrue);
    expect(controller.book('cache-ui')!.chapters[2].isCached, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed selection during confirmation needs a new approval', (
    tester,
  ) async {
    await pumpDetails(tester, controller.book('cache-ui')!);
    await tester.tap(find.byKey(const Key('book-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-manage-cache')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cache-clear-chapter-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cache-clear-confirm')));
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => controller.addBookmark(
        Bookmark(
          id: 'during-confirmation',
          bookId: 'cache-ui',
          chapterIndex: 0,
          paragraphIndex: 0,
          quote: '保护正文',
          note: '',
          createdAt: DateTime.utc(2026),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();
    expect(controller.book('cache-ui')!.chapters[0].isCached, isTrue);
    expect(find.textContaining('选择已变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local book has no cache clearing action', (tester) async {
    final local = controller.books.firstWhere((book) => !book.isRemote);
    await pumpDetails(tester, local);
    await tester.tap(find.byKey(const Key('book-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-manage-cache')), findsNothing);
  });
}
