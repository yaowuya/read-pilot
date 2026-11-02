import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_mark.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/reader_marks_sheet.dart';
import 'package:sembast/sembast_memory.dart';

Book _book() => Book(
  id: 'managed-book',
  title: '标注管理测试书',
  author: '作者',
  description: '',
  category: '本地',
  coverStyle: 0,
  sourceLabel: '本地导入',
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(
      id: 'managed-chapter',
      title: '第一章',
      paragraphs: const ['春风又绿江南岸。'],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'reader-marks-sheet-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
    await controller.addBook(_book());
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  testWidgets('manager opens an existing valid paragraph mark', (tester) async {
    final mark = await tester.runAsync(
      () => controller.addReaderMark(
        'managed-book',
        0,
        0,
        color: ReaderMarkColor.mint,
        note: '返回这里。',
      ),
    );
    expect(mark, isNotNull);
    ReaderMarkLocation? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderMarksSheet(
            controller: controller,
            bookId: 'managed-book',
            onOpen: (location) => opened = location,
          ),
        ),
      ),
    );

    expect(find.text('段落标注管理'), findsOneWidget);
    expect(find.text('备注：返回这里。'), findsOneWidget);
    await tester.tap(find.byKey(Key('reader-mark-manager-open-${mark!.id}')));
    await tester.pump();

    expect(opened, isNotNull);
    expect(opened!.chapterIndex, 0);
    expect(opened!.paragraphIndex, 0);
    expect(opened!.paragraph, '春风又绿江南岸。');
  });
  testWidgets('manager filters and removes a stale local mark', (tester) async {
    final mark = await tester.runAsync(
      () => controller.addReaderMark(
        'managed-book',
        0,
        0,
        color: ReaderMarkColor.amber,
        note: '',
        selectedText: '江南',
      ),
    );
    expect(mark, isNotNull);
    await tester.runAsync(() async {
      await controller.repository.saveBook(
        _book().copyWith(
          chapters: [
            Chapter(
              id: 'managed-chapter',
              title: '第一章',
              paragraphs: const ['江南岸的正文已变化。'],
            ),
          ],
        ),
      );
      await controller.initialize();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderMarksSheet(
            controller: controller,
            bookId: 'managed-book',
            onOpen: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('reader-mark-manager-filter-stale')));
    await tester.pump();
    expect(find.text('已失效的段落标注'), findsOneWidget);
    expect(find.text('选区标注'), findsOneWidget);
    expect(
      find.byKey(Key('reader-mark-manager-open-${mark!.id}')),
      findsNothing,
    );

    await tester.tap(find.byKey(Key('reader-mark-manager-delete-${mark.id}')));
    await tester.pumpAndSettle();
    expect(find.text('删除这条段落标注？'), findsOneWidget);
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();

    expect(controller.readerMarks('managed-book'), isEmpty);
  });

  testWidgets('manager identifies selected text annotations', (tester) async {
    final mark = await tester.runAsync(
      () => controller.addReaderMark(
        'managed-book',
        0,
        0,
        color: ReaderMarkColor.blue,
        note: '',
        selectedText: '江南',
      ),
    );
    expect(mark, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderMarksSheet(
            controller: controller,
            bookId: 'managed-book',
            onOpen: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('选区标注'), findsOneWidget);
    expect(find.text('江南'), findsOneWidget);
  });
}
