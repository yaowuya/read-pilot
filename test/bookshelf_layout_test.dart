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
}
