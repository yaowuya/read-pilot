import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/source_check_settings.dart';
import 'package:read_pilot/domain/source_health.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/source_health_sheet.dart';
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

/// A real controller whose two sheet-facing calls are canned.
///
/// The sheet's own wiring is what these tests cover: which switches exist, that
/// a toggle writes a preference instead of sheet-local state, and how a finished
/// report renders. Reaching the network or sembast inside a `testWidgets` body
/// would hang, because widget tests run under a fake clock where only
/// `tester.runAsync` lets real I/O complete.
class _StubHealthController extends AppController {
  _StubHealthController(super.repository, super.engine);

  SourceHealthReport? report;
  SourceCheckSettings? savedSettings;

  @override
  Future<SourceHealthReport> checkSourceHealth(
    String sourceId, {
    Future<void>? abortTrigger,
  }) async => report!;

  @override
  Future<void> updateSourceCheckSettings(SourceCheckSettings settings) async {
    savedSettings = settings;
  }
}

SourceHealthReport _failingReport() => SourceHealthReport(
  sourceId: 'https://health-ui.example',
  sourceName: '待检查书源',
  duration: const Duration(milliseconds: 1400),
  results: const [
    SourceHealthResult(
      stage: SourceHealthStage.search,
      status: SourceHealthStatus.failed,
      summary: '站点返回了 502。',
      tags: [SourceHealthTag.searchFailed, SourceHealthTag.siteFailed],
    ),
    SourceHealthResult(
      stage: SourceHealthStage.explore,
      status: SourceHealthStatus.skipped,
      summary: '检查已停止，已跳过。',
    ),
    SourceHealthResult(
      stage: SourceHealthStage.catalog,
      status: SourceHealthStatus.skipped,
      summary: '检查已停止，已跳过。',
    ),
    SourceHealthResult(
      stage: SourceHealthStage.content,
      status: SourceHealthStatus.skipped,
      summary: '检查已停止，已跳过。',
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late _StubHealthController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'source-health-screen-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = _StubHealthController(AppRepository(database), SourceEngine());
    await controller.initialize();
    await controller.importSources(jsonEncode([_sourceJson()]));
    controller.report = _failingReport();
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

  testWidgets('the sheet says the verdict is written back to the source', (
    tester,
  ) async {
    await _pumpSheet(tester, controller);

    expect(
      find.textContaining('结论会写回书源'),
      findsOneWidget,
      reason: 'the old copy promised 结果不保存, which is no longer true',
    );
    expect(find.textContaining('每阶段最长 8 秒'), findsNothing);
  });

  testWidgets('stage switches persist without leaving the sheet', (
    tester,
  ) async {
    await _pumpSheet(tester, controller);

    expect(find.byKey(const Key('source-check-search')), findsNothing);
    await tester.tap(find.byKey(const Key('source-health-settings-toggle')));
    await tester.pump();

    expect(find.byKey(const Key('source-check-search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('source-check-explore')));
    await tester.pump();

    expect(
      controller.savedSettings?.checkExplore,
      isFalse,
      reason: 'the switch is a stored preference, not sheet-local state',
    );
    expect(
      find.byKey(const Key('source-check-explore')),
      findsOneWidget,
      reason: 'toggling must not close the options block',
    );
  });

  testWidgets('the timeout chips rewrite the shared budget', (tester) async {
    await _pumpSheet(tester, controller);
    await tester.tap(find.byKey(const Key('source-health-settings-toggle')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('source-check-timeout-60')));
    await tester.pump();

    expect(controller.savedSettings?.timeout, const Duration(seconds: 60));
    expect(find.textContaining('超时上限 60 秒'), findsOneWidget);
  });

  testWidgets('a finished check renders tags and the elapsed time', (
    tester,
  ) async {
    await _pumpSheet(tester, controller);
    await tester.tap(find.byKey(const Key('source-health-start')));
    await tester.pumpAndSettle();

    expect(find.textContaining('有 1 个阶段没通过'), findsOneWidget);
    expect(find.byKey(const Key('source-health-tags')), findsOneWidget);
    expect(find.text('已标记：搜索失效、网站失效'), findsOneWidget);
    expect(find.text('搜索 · 搜索失效、网站失效'), findsOneWidget);
    expect(find.text('站点返回了 502。'), findsOneWidget);
  });
}

Future<void> _pumpSheet(WidgetTester tester, AppController controller) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SourceHealthSheet(
          controller: controller,
          source: controller.sources.single,
        ),
      ),
    ),
  );
  await tester.pump();
}
