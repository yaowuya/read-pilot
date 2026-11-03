import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/screens/sources_screen.dart';
import 'package:sembast/sembast_memory.dart';

Map<String, dynamic> _sourceJson() => {
  'bookSourceUrl': 'https://health-ui.example',
  'bookSourceName': '待检查书源',
  'searchUrl': '/search?q={{key}}',
  'ruleSearch': {
    'bookList': '@CSS:.book',
    'name': '@CSS:a@text',
    'bookUrl': '@CSS:a@href',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'source-health-screen-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
    await controller.importSources(jsonEncode([_sourceJson()]));
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  testWidgets('source health check stays user-triggered before network work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SourcesScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('检查书源'),
      180,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('检查书源'));
    await tester.pumpAndSettle();

    expect(find.text('书源健康检查'), findsOneWidget);
    expect(find.text('开始检查'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
