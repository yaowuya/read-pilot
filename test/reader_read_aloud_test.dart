import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/services/read_aloud.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/screens/reader_screen.dart';
import 'package:sembast/sembast_memory.dart';

class _ReaderFakeEngine implements ReadAloudEngine {
  final started = Completer<void>();
  final completed = Completer<void>();
  var stops = 0;

  @override
  Future<void> speak(String text) {
    if (!started.isCompleted) started.complete();
    return completed.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'reader-read-aloud-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  testWidgets('reader starts and stops explicit device read aloud', (
    tester,
  ) async {
    final engine = _ReaderFakeEngine();
    final readAloud = ReadAloudController(engine: engine, supported: true);
    addTearDown(readAloud.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          controller: controller,
          bookId: 'public-fusheng',
          readAloud: readAloud,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-read-aloud')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-read-aloud-start')));
    await tester.pump();
    await engine.started.future;
    expect(readAloud.state, ReadAloudState.speaking);

    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-read-aloud')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-read-aloud-stop')));
    await tester.pump();

    expect(readAloud.state, ReadAloudState.idle);
    expect(engine.stops, 1);
    engine.completed.complete();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reader identifies unsupported read aloud before starting', (
    tester,
  ) async {
    final readAloud = ReadAloudController(supported: false);
    addTearDown(readAloud.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          controller: controller,
          bookId: 'public-fusheng',
          readAloud: readAloud,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-read-aloud')));
    await tester.pumpAndSettle();

    expect(find.text('当前平台不支持本机朗读。'), findsOneWidget);
    expect(find.byKey(const Key('reader-read-aloud-start')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
