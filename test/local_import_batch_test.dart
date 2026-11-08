import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/app_shell.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'local-import-batch-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'invalid batch input never persists an earlier valid local book',
    () async {
      final files = [
        (
          bytes: Uint8List.fromList(utf8.encode('不应入库的正文。')),
          fileName: '不应入库.txt',
        ),
        (bytes: Uint8List.fromList(const [1, 2, 3]), fileName: '不支持.pdf'),
      ];

      await expectLater(
        controller.importLocalFiles(files),
        throwsA(isA<FormatException>()),
      );

      expect(controller.books, hasLength(3));
      expect(await controller.repository.books(), hasLength(3));
    },
  );

  test(
    'batch import assigns distinct durable books to selected TXT files',
    () async {
      final books = await controller.importLocalFiles([
        (
          bytes: Uint8List.fromList(utf8.encode('第一本的正文。')),
          fileName: '第一本.txt',
        ),
        (
          bytes: Uint8List.fromList(utf8.encode('第二本的正文。')),
          fileName: '第二本.txt',
        ),
      ]);

      expect(books, hasLength(2));
      expect(books.map((book) => book.title), ['第一本', '第二本']);
      expect(books.map((book) => book.id).toSet(), hasLength(2));
      expect(await controller.repository.books(), hasLength(5));
    },
  );

  testWidgets('shelf imports an explicitly selected local batch together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          controller: controller,
          pickLocalFiles: () async => [
            (
              bytes: Uint8List.fromList(utf8.encode('第一本的正文。')),
              fileName: '第一本.txt',
            ),
            (
              bytes: Uint8List.fromList(utf8.encode('第二本的正文。')),
              fileName: '第二本.txt',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('批量导入 TXT 或 EPUB'));
    await tester.pumpAndSettle();
    // The shelf's import button now opens the draft's import page first.
    await tester.tap(find.byKey(const Key('import-pick-files')));
    await tester.pumpAndSettle();

    expect(controller.books, hasLength(5));
    expect(
      controller.books.map((book) => book.title),
      containsAll(['第一本', '第二本']),
    );
    expect(find.text('已导入 2 本书。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
