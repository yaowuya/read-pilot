import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/shelf_group_sheets.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'shelf-groups-ui-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  testWidgets('a book joins a custom group without replacing reading filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();

    // 管理分组 moved behind the 添加 sheet on the root shelf; the group row
    // keeps its own entry once a group is open.
    await tester.tap(find.byKey(const Key('shelf-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-add-groups')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-group-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shelf-group-name')), '闲时读');
    await tester.tap(find.byKey(const Key('shelf-group-save')));
    await tester.pumpAndSettle();
    final group = controller.shelfGroups.single;
    await tester.tap(find.byKey(const Key('shelf-group-close')));
    await tester.pumpAndSettle();

    // Folder shares the root grid with ungrouped books; no 全部书籍 card / sort tabs.
    expect(find.byKey(Key('shelf-group-${group.id}')), findsOneWidget);
    expect(find.byKey(const Key('shelf-group-all')), findsNothing);
    expect(find.text('默认'), findsNothing);
    expect(find.byKey(const Key('shelf-sort-title')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('book-public-fusheng')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);

    await tester.tap(find.byKey(Key('shelf-group-${group.id}')));
    await tester.pumpAndSettle();
    expect(find.text('这个分组还没有书'), findsOneWidget);
    expect(find.byKey(const Key('book-public-fusheng')), findsNothing);

    await tester.tap(find.byKey(const Key('shelf-scope-back')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('book-public-fusheng')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('浮生六记的更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('shelf-group-member-${group.id}')));
    await tester.pumpAndSettle();
    expect(
      controller.shelfGroups.single.containsBook('public-fusheng'),
      isTrue,
    );
    await tester.tap(find.byKey(const Key('shelf-group-membership-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('shelf-group-${group.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(find.byKey(const Key('book-public-renjian')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deleting an active group returns to all books without deleting any',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final group = (await tester.runAsync(() async {
        final created = await controller.createShelfGroup('待重读');
        await controller.setShelfGroupMembership(
          created.id,
          'public-fusheng',
          true,
        );
        return created;
      }))!;
      await tester.pumpWidget(ReadPilotApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('shelf-group-${group.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);

      await tester.tap(find.byKey(const Key('shelf-group-manage')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('shelf-group-rename-${group.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('shelf-group-name')), '重读');
      await tester.tap(find.byKey(const Key('shelf-group-save')));
      await tester.pumpAndSettle();
      expect(controller.shelfGroups.single.name, '重读');

      await tester.tap(find.byKey(Key('shelf-group-delete-${group.id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('书籍、阅读进度与笔记仍保留'), findsOneWidget);
      await tester.tap(find.text('确认移除'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shelf-group-close')));
      await tester.pumpAndSettle();
      expect(controller.shelfGroups, isEmpty);
      expect(controller.books, hasLength(3));
      // Deleting the group empties the card layer, so the shelf falls back to
      // the flat book grid without a group card in sight.
      expect(find.byKey(const Key('shelf-group-all')), findsNothing);
      expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('group manager handles a small viewport with a tall keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ShelfGroupManagerSheet(controller: controller),
              ),
              child: const Text('打开分组'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-group-add')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 500);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('管理分组'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
