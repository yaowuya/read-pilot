import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

/// The draft shelf is one 3-col grid: group folders + ungrouped books + add.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'bookshelf-layout-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> pumpShelf(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets('without groups the shelf stays a flat book grid', (
    tester,
  ) async {
    await pumpShelf(tester);
    expect(controller.shelfGroups, isEmpty);
    expect(find.byKey(const Key('shelf-title')), findsOneWidget);
    expect(find.byKey(const Key('shelf-group-all')), findsNothing);
    expect(find.byKey(const Key('shelf-group-new-card')), findsNothing);
    expect(find.byKey(const Key('shelf-search')), findsNothing);
    expect(find.byKey(const Key('shelf-search-action')), findsOneWidget);
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(find.byKey(const Key('book-public-zhaohua')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a group shares the root grid and drills into its books', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final group = await controller.createShelfGroup('散文');
      await controller.setShelfGroupMembership(
        group.id,
        'public-fusheng',
        true,
      );
    });
    await pumpShelf(tester);
    final group = controller.shelfGroups.single;

    // Folder + remaining ungrouped books sit in one grid; no 全部书籍 card.
    expect(find.byKey(const Key('shelf-group-all')), findsNothing);
    expect(find.byKey(Key('shelf-group-${group.id}')), findsOneWidget);
    expect(find.byKey(const Key('shelf-group-new-card')), findsNothing);
    expect(find.byKey(const Key('book-public-fusheng')), findsNothing);
    expect(find.byKey(const Key('book-public-zhaohua')), findsOneWidget);
    expect(find.text('散文'), findsOneWidget);

    await tester.tap(find.byKey(Key('shelf-group-${group.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(find.byKey(const Key('book-public-zhaohua')), findsNothing);
    expect(find.byKey(const Key('shelf-scope-back')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shelf-scope-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('shelf-group-${group.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root continue card stays visible when groups exist', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.savePosition(
        'public-fusheng',
        const ReadingPosition(chapterIndex: 1),
      );
      final group = await controller.createShelfGroup('散文');
      await controller.setShelfGroupMembership(
        group.id,
        'public-zhaohua',
        true,
      );
    });
    await pumpShelf(tester);

    expect(find.text('接着上次，继续读'), findsOneWidget);
    expect(find.byKey(const Key('shelf-group-all')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search opens from the circle button, not an inline pill', (
    tester,
  ) async {
    await pumpShelf(tester);
    expect(find.byKey(const Key('shelf-search')), findsNothing);
    await tester.tap(find.byKey(const Key('shelf-search-action')));
    await tester.pumpAndSettle();
    expect(find.text('搜索'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a grouped book can leave its group without leaving the shelf', (
    tester,
  ) async {
    final group = (await tester.runAsync(() async {
      final created = await controller.createShelfGroup('散文');
      await controller.setShelfGroupMembership(
        created.id,
        'public-fusheng',
        true,
      );
      return created;
    }))!;
    await pumpShelf(tester);
    await tester.tap(find.byKey(Key('shelf-group-${group.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);

    await tester.tap(find.byTooltip('浮生六记的更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('移出分组'), findsOneWidget);
    await tester.tap(find.text('移出分组'));
    await tester.pumpAndSettle();

    expect(
      controller.shelfGroups.single.containsBook('public-fusheng'),
      isFalse,
    );
    expect(controller.books.map((book) => book.id), contains('public-fusheng'));
    expect(find.byKey(const Key('book-public-fusheng')), findsNothing);
    expect(find.text('这个分组还没有书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the filter line narrows the shelf by reading status', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.savePosition(
        'public-fusheng',
        const ReadingPosition(chapterIndex: 1),
        finished: true,
      );
      await controller.savePosition(
        'public-zhaohua',
        const ReadingPosition(chapterIndex: 0),
      );
    });
    await pumpShelf(tester);

    expect(find.byKey(const Key('shelf-status-filter')), findsOneWidget);
    expect(find.byKey(const Key('shelf-count')), findsOneWidget);
    expect(find.byKey(const Key('shelf-sort-title')), findsNothing);

    await tester.tap(find.byKey(const Key('shelf-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-status-reading')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-zhaohua')), findsOneWidget);
    expect(find.byKey(const Key('book-public-fusheng')), findsNothing);

    await tester.tap(find.byKey(const Key('shelf-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-status-finished')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(find.byKey(const Key('book-public-zhaohua')), findsNothing);

    await tester.tap(find.byKey(const Key('shelf-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-status-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-zhaohua')), findsOneWidget);
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty status filter offers a way back', (tester) async {
    await pumpShelf(tester);
    await tester.tap(find.byKey(const Key('shelf-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-status-finished')));
    await tester.pumpAndSettle();

    expect(find.text('暂时没有已读的书'), findsOneWidget);
    await tester.tap(find.text('查看全部状态'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按 a book opens 整理书架 and the batch bar', (tester) async {
    await pumpShelf(tester);
    await tester.longPress(find.byKey(const Key('book-public-fusheng')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shelf-selection-title')), findsOneWidget);
    expect(find.text('已选 1 本'), findsOneWidget);
    expect(find.byKey(const Key('shelf-batch-remove')), findsOneWidget);
    expect(find.byKey(const Key('shelf-batch-group')), findsOneWidget);
    expect(
      find.byKey(const Key('shelf-select-public-fusheng')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('shelf-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shelf-select-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-selection-title')), findsNothing);
    expect(find.byKey(const Key('shelf-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整理书架 groups the picked books through the batch bar', (
    tester,
  ) async {
    await tester.runAsync(() => controller.createShelfGroup('散文'));
    await pumpShelf(tester);

    await tester.tap(find.byKey(const Key('shelf-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-public-fusheng')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 本'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shelf-batch-group')));
    await tester.pumpAndSettle();
    final group = controller.shelfGroups.single;
    await tester.tap(find.byKey(Key('shelf-group-target-${group.id}')));
    await tester.pumpAndSettle();

    expect(
      controller.shelfGroups.single.containsBook('public-fusheng'),
      isTrue,
    );
    expect(find.byKey(const Key('shelf-selection-title')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the trailing card opens the add sheet and the group picker', (
    tester,
  ) async {
    await pumpShelf(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('shelf-add-card')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-add-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-add-import')), findsOneWidget);
    expect(find.byKey(const Key('shelf-add-groups')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final group = (await tester.runAsync(
      () => controller.createShelfGroup('散文'),
    ))!;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('shelf-group-${group.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-group-add-books')), findsOneWidget);
    expect(find.byKey(const Key('shelf-add-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shelf footer explains how to tidy it', (tester) async {
    await pumpShelf(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('shelf-foot')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('长按书籍或分组，即可整理书架'), findsOneWidget);

    final group = (await tester.runAsync(
      () => controller.createShelfGroup('散文'),
    ))!;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('shelf-group-${group.id}')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('shelf-foot')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('0 本书 · 散文'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
