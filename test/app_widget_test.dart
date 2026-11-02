import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'widgets-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  testWidgets('bookshelf is usable on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('阅航'), findsNothing);
    expect(find.bySemanticsLabel('阅读标志'), findsOneWidget);
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(find.byTooltip('批量导入 TXT 或 EPUB'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a book and persists chapter navigation', (tester) async {
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('book-public-fusheng')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-public-fusheng')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-settings')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(controller.book('public-fusheng')!.position.chapterIndex, 1);
    await tester.tap(find.byKey(const Key('reader-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-fusheng')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('can create a reading note from the reader', (tester) async {
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('book-public-fusheng')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-public-fusheng')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-bookmark')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-input')), '这一段值得再读。');
    await tester.tap(find.text('保存书签'));
    await tester.pumpAndSettle();
    expect(controller.bookmarks.single.note, '这一段值得再读。');
    expect(tester.takeException(), isNull);
  });

  testWidgets('new chapter keeps its heading visible', (tester) async {
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始阅读  →'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('卷一 · 闺房记乐')).dy,
      greaterThanOrEqualTo(kToolbarHeight),
    );
    expect(controller.book('public-fusheng')!.position.paragraphIndex, 0);
  });

  testWidgets('night theme is applied and persisted from the reader', (
    tester,
  ) async {
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始阅读  →'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('夜间'));
    await tester.pumpAndSettle();
    expect(controller.settings.theme, ReaderTheme.dark);
    final saved = await tester.runAsync(controller.repository.settings);
    expect(saved!.theme, ReaderTheme.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold start restores a valid reader URL', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/read/public-fusheng';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown reader URL safely opens the shelf', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/read/missing-book';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('我的书架'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile opens bounded local reading history', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('阅读足迹'), findsOneWidget);
    await tester.tap(find.text('阅读足迹'));
    await tester.pumpAndSettle();
    expect(find.text('每一次翻页，都在这里'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library search filters actual books', (tester) async {
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shelf-search')), '人间');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-public-renjian')), findsOneWidget);
    expect(find.byKey(const Key('book-public-fusheng')), findsNothing);
  });
}
