import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

import 'support/reader_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'reader-auto-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  // 阅读页默认沉浸式，操作顶栏/底栏前需先点正文中部唤出工具栏。
  Future<void> showChrome(WidgetTester tester) async {
    if (find.byKey(const Key('reader-settings')).evaluate().isNotEmpty) return;
    final paged = find.byKey(const Key('reader-paged-view'));
    final body = paged.evaluate().isNotEmpty
        ? paged
        : find.byKey(const Key('reader-scrolling-view'));
    await tester.tapAt(tester.getRect(body).center);
    await tester.pumpAndSettle();
  }

  testWidgets('explicit auto read advances one paged reader and can stop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/public-fusheng',
      ),
    );
    await tester.pumpAndSettle();

    // 页码指示器只随工具栏显示，先唤出工具栏再读取当前页。
    await showChrome(tester);
    final indicator = find.byKey(const Key('reader-page-indicator'));
    expect(indicator, findsOneWidget);
    final before = tester.widget<Text>(indicator).data;

    await openReaderMoreSheet(tester);
    await tester.tap(find.byKey(const Key('reader-auto-read')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 秒 / 页'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.widget<Text>(indicator).data, isNot(before));
    await showChrome(tester);
    await openReaderMoreSheet(tester);
    await tester.tap(find.byKey(const Key('reader-auto-read')));
    await tester.pumpAndSettle();
    expect(find.text('停止自动翻页'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-auto-read-stop')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic page turns stop when the reader becomes inactive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/public-fusheng',
      ),
    );
    await tester.pumpAndSettle();
    await showChrome(tester);
    final indicator = find.byKey(const Key('reader-page-indicator'));
    final before = tester.widget<Text>(indicator).data;

    await openReaderMoreSheet(tester);
    await tester.tap(find.byKey(const Key('reader-auto-read')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 秒 / 页'));
    await tester.pump(const Duration(milliseconds: 300));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(tester.widget<Text>(indicator).data, before);
    expect(tester.takeException(), isNull);
  });
}
