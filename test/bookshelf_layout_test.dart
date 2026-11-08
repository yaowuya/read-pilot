import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

/// The shelf follows wechat reading: a card layer when the reader has groups,
/// and the flat book grid when there are none.
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
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(find.byKey(const Key('book-public-zhaohua')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a group turns the shelf into cards and drills into its books', (
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

    // The card layer replaces the book grid entirely.
    expect(find.byKey(const Key('shelf-group-all')), findsOneWidget);
    expect(find.byKey(Key('shelf-group-${group.id}')), findsOneWidget);
    expect(find.byKey(const Key('shelf-group-new-card')), findsOneWidget);
    expect(find.byKey(const Key('book-public-fusheng')), findsNothing);
    expect(find.text('散文'), findsOneWidget);
    expect(find.text('1 本'), findsOneWidget);

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

  testWidgets('the 全部书籍 card opens every book and its 在读 count', (
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

    // One book is being read, so the 全部书籍 card carries the count badge.
    expect(find.text('在读 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shelf-group-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(find.byKey(const Key('book-public-zhaohua')), findsOneWidget);
    expect(find.text('全部书籍'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searching a grouped shelf shows books, not cards', (
    tester,
  ) async {
    await tester.runAsync(() => controller.createShelfGroup('散文'));
    await pumpShelf(tester);
    expect(find.byKey(const Key('shelf-group-new-card')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('shelf-search')), '人间');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-renjian')), findsOneWidget);
    expect(find.byKey(const Key('book-public-fusheng')), findsNothing);
    expect(find.byKey(const Key('shelf-group-new-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sort tabs reorder books and 进度 puts reading first', (
    tester,
  ) async {
    await tester.runAsync(
      () => controller.savePosition(
        'public-fusheng',
        const ReadingPosition(chapterIndex: 1),
      ),
    );
    await pumpShelf(tester);

    // The grid fills left to right, so (row, column) orders the books exactly.
    int rankOf(String id) {
      final topLeft = tester.getTopLeft(find.byKey(Key('book-$id')));
      return topLeft.dy.round() * 1000 + topLeft.dx.round();
    }

    // 默认 keeps the recently opened book first.
    expect(rankOf('public-fusheng'), lessThan(rankOf('public-zhaohua')));

    // 书名 orders by title: 人间词话 < 朝花夕拾 < 浮生六记.
    await tester.tap(find.byKey(const Key('shelf-sort-title')));
    await tester.pumpAndSettle();
    expect(rankOf('public-renjian'), lessThan(rankOf('public-zhaohua')));
    expect(rankOf('public-zhaohua'), lessThan(rankOf('public-fusheng')));

    // 分类 groups by stored category: 思想 (人间词话) before 文学.
    await tester.tap(find.byKey(const Key('shelf-sort-category')));
    await tester.pumpAndSettle();
    expect(rankOf('public-renjian'), lessThan(rankOf('public-fusheng')));

    // 进度 lifts the book being read above the untouched ones.
    await tester.tap(find.byKey(const Key('shelf-sort-progress')));
    await tester.pumpAndSettle();
    expect(rankOf('public-fusheng'), lessThan(rankOf('public-renjian')));
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
    // Inside a group the menu offers 移出分组 next to 移出书架: the first only
    // drops the membership, the second deletes the book.
    expect(find.text('移出分组'), findsOneWidget);
    await tester.tap(find.text('移出分组'));
    await tester.pumpAndSettle();

    expect(
      controller.shelfGroups.single.containsBook('public-fusheng'),
      isFalse,
    );
    // The book is still on the shelf, just no longer inside the group.
    expect(controller.books.map((book) => book.id), contains('public-fusheng'));
    expect(find.byKey(const Key('book-public-fusheng')), findsNothing);
    expect(find.text('分组里还没有书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shelf pill centres its hint and has no 书城 action', (
    tester,
  ) async {
    await pumpShelf(tester);
    final field = tester.getRect(find.byKey(const Key('shelf-search')));
    final hint = tester.getRect(find.text('搜索书名或作者'));
    // isCollapsed left the hint 6.5px above the centre of the 38px pill.
    expect((hint.center.dy - field.center.dy).abs(), lessThan(1));
    expect(find.byKey(const Key('shelf-discover')), findsNothing);
    expect(find.text('书城'), findsNothing);
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

    // Nothing on this shelf has been finished, and the draft says so plainly.
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
    // A picked book shows its check mark, the others keep an empty dot.
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
    // Grouping leaves 整理书架 and shows the result on the root shelf.
    expect(find.byKey(const Key('shelf-selection-title')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the trailing card opens the add sheet and the group picker', (
    tester,
  ) async {
    await pumpShelf(tester);
    // The add card sits after the last book, so bring it into the viewport
    // before tapping: an off-screen sliver child has no hit test point.
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

    // Inside a group the same slot adds books from the shelf instead.
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
    expect(find.text('每一本书，都有自己的位置'), findsOneWidget);

    final group = (await tester.runAsync(
      () => controller.createShelfGroup('散文'),
    ))!;
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('shelf-foot')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('长按书籍或分组，即可整理书架'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(Key('shelf-group-${group.id}')),
      -160,
      scrollable: find.byType(Scrollable).first,
    );
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
