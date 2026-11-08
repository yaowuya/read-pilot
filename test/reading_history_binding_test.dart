import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reading_activity.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

Book _book({String? sourceId, String? url}) => Book(
  id: 'bound-history',
  title: '绑定测试书',
  author: '作者',
  description: '',
  category: '本地',
  coverStyle: 0,
  sourceLabel: sourceId == null ? '本地导入' : '新书源',
  sourceId: sourceId,
  url: url,
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(id: 'chapter-one', title: '第一章', paragraphs: const ['正文']),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'history-binding-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  testWidgets('stale history never opens a rebound source chapter', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.addBook(_book());
      await controller.recordReadingActivity(
        'bound-history',
        0,
        kind: ReadingActivityKind.opened,
      );
      await AppRepository(database).saveBook(
        _book(sourceId: 'https://new.example', url: 'https://new.example/book'),
      );
      await controller.initialize();
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ReadPilotApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reading-history-item-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('书籍来源或章节已变化'), findsOneWidget);
    expect(find.byKey(const Key('reader-back')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
