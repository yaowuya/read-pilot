import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reading_activity.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/screens/reading_history_screen.dart';
import 'package:sembast/sembast_memory.dart';

Book _book() => Book(
  id: 'history-ui',
  title: '足迹书籍',
  author: '作者',
  description: '',
  category: '本地',
  coverStyle: 0,
  sourceLabel: '本地导入',
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(id: 'one', title: '第一章', paragraphs: const ['正文']),
    Chapter(id: 'two', title: '第二章', paragraphs: const ['正文']),
  ],
);

Book _otherBook() => Book(
  id: 'history-other',
  title: '另一部足迹书',
  author: '另一位作者',
  description: '',
  category: '本地',
  coverStyle: 1,
  sourceLabel: '本地导入',
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(id: 'other-one', title: '另一章', paragraphs: const ['正文']),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'history-ui-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
    await controller.addBook(_book());
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> pumpHistory(
    WidgetTester tester, {
    ValueChanged<ReadingActivity>? onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingHistoryScreen(
          controller: controller,
          onOpen: onOpen ?? (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty timeline explains local-only retention', (tester) async {
    await pumpHistory(tester);
    expect(find.text('阅读记录'), findsOneWidget);
    expect(find.textContaining('当前设备'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history opens its chapter and clears only activities', (
    tester,
  ) async {
    await tester.runAsync(
      () => controller.recordReadingActivity(
        'history-ui',
        1,
        kind: ReadingActivityKind.chapter,
      ),
    );
    ReadingActivity? opened;
    await pumpHistory(tester, onOpen: (activity) => opened = activity);
    // 设计稿把统计放在页首，足迹时间线在下方，需要先滚下去。
    await tester.scrollUntilVisible(
      find.byKey(const Key('reading-history-item-0')),
      220,
    );
    await tester.pumpAndSettle();
    expect(find.text('足迹书籍'), findsWidgets);
    expect(find.text('第二章 · 阅读章节'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reading-history-item-0')));
    expect(opened?.chapterIndex, 1);

    await tester.tap(find.byKey(const Key('reading-history-clear')));
    await tester.pumpAndSettle();
    expect(controller.readingActivities, hasLength(1));
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();
    expect(controller.readingActivities, isEmpty);
    expect(controller.book('history-ui'), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history filters stay local to kind and selected book', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.recordReadingActivity(
        'history-ui',
        0,
        kind: ReadingActivityKind.opened,
      );
      await controller.addBook(_otherBook());
      await controller.recordReadingActivity(
        'history-other',
        0,
        kind: ReadingActivityKind.finished,
      );
    });
    await pumpHistory(tester);
    // 页首的「最近在读」也会显示书名，所以要滚到时间线里的具体行。
    await tester.scrollUntilVisible(
      find.byKey(const Key('reading-history-item-1')),
      220,
    );
    await tester.pumpAndSettle();
    expect(find.text('足迹书籍'), findsWidgets);
    expect(find.text('另一部足迹书'), findsWidgets);

    await tester.tap(find.byKey(const Key('history-kind-finished')));
    await tester.pumpAndSettle();
    expect(find.text('足迹书籍'), findsNothing);
    expect(find.text('另一部足迹书'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-kind-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-book-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-book-option-history-ui')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('reading-history-item-0')),
      220,
    );
    await tester.pumpAndSettle();
    expect(find.text('足迹书籍'), findsWidgets);
    expect(find.text('另一部足迹书'), findsNothing);
    expect(controller.readingActivities, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
