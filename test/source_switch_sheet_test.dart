import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/source_switch_sheet.dart';
import 'package:read_pilot/ui/theme.dart';
import 'package:sembast/sembast_memory.dart';

Book _book(String id, String source, String author) => Book(
  id: id,
  title: '同名小说',
  author: author,
  description: '',
  category: '文学',
  coverStyle: 0,
  sourceLabel: source,
  sourceId: 'https://${source.toLowerCase()}.example',
  url: 'https://${source.toLowerCase()}.example/$id',
  addedAt: DateTime.utc(2026),
);

class _SwitchController extends AppController {
  _SwitchController(super.repository, super.engine);

  Book current = _book('current', '旧源', '原作者');
  List<Book> candidates = [
    _book('z-first', 'Zeta', '原作者'),
    _book('a-second', 'Alpha', '原作者'),
    _book('a-third', 'Alpha', '另一作者'),
  ];
  int searches = 0;
  int failedSources = 0;
  int cancellations = 0;
  Object? searchError;
  Future<SourceCandidateSearchResult>? pendingSearch;
  Book? selected;
  int switches = 0;
  Future<Book>? pendingSwitch;
  Object? switchError;

  @override
  Future<SourceCandidateSearchResult> findSourceCandidates(
    String bookId, {
    Future<void>? abortTrigger,
  }) async {
    searches++;
    abortTrigger?.then((_) => cancellations++);
    if (searchError != null) throw searchError!;
    return pendingSearch ??
        SourceCandidateSearchResult(candidates, failedSources: failedSources);
  }

  @override
  Future<Book> switchBookSource(String bookId, Book candidate) async {
    switches++;
    selected = candidate;
    if (switchError != null) throw switchError!;
    return pendingSwitch ??
        current.rebindSource(candidate, position: current.position);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late _SwitchController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'source-sheet-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = _SwitchController(AppRepository(database), SourceEngine());
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> openSheet(
    WidgetTester tester, {
    Size size = const Size(375, 812),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<Book>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => SourceSwitchSheet(
                  controller: controller,
                  book: controller.current,
                ),
              ),
              child: const Text('打开换源'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开换源'));
    await tester.pump();
  }

  testWidgets('source sheet fills the phone below a small top margin', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(SourceSwitchSheet));
    expect(sheet.height, greaterThanOrEqualTo(812 * .85));
    expect(sheet.top, lessThan(812 * .15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters actual source and author locally with current context', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.pumpAndSettle();

    expect(find.text('换源'), findsOneWidget);
    expect(find.text('当前书源：旧源'), findsOneWidget);
    expect(find.text('候选 3 · 2 个书源'), findsOneWidget);
    final filter = find.byKey(const Key('source-switch-filter'));
    await tester.enterText(filter, 'zETA');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);
    expect(find.byKey(const Key('source-candidate-a-second')), findsNothing);
    expect(find.text('匹配 1 / 3 · 1 个书源'), findsOneWidget);
    await tester.enterText(filter, '另一作者');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-candidate-a-third')), findsOneWidget);
    expect(find.byKey(const Key('source-candidate-z-first')), findsNothing);
    await tester.enterText(filter, '同名小说');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-switch-filter-empty')), findsOneWidget);
    expect(find.text('匹配 0 / 3 · 0 个书源'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '清除筛选'));
    await tester.pumpAndSettle();
    expect(find.text('候选 3 · 2 个书源'), findsOneWidget);
    expect(controller.searches, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'source-name sort is stable and relevance restores controller order',
    (tester) async {
      await openSheet(tester, size: const Size(800, 1000));
      await tester.pumpAndSettle();
      final first = find.byKey(const Key('source-candidate-z-first'));
      final second = find.byKey(const Key('source-candidate-a-second'));
      final third = find.byKey(const Key('source-candidate-a-third'));
      expect(
        tester.getTopLeft(first).dy,
        lessThan(tester.getTopLeft(second).dy),
      );

      await tester.tap(find.byKey(const Key('source-switch-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<bool>, '书源名称'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(second).dy,
        lessThan(tester.getTopLeft(third).dy),
      );
      expect(
        tester.getTopLeft(third).dy,
        lessThan(tester.getTopLeft(first).dy),
      );
      await tester.tap(find.byKey(const Key('source-switch-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<bool>, '相关度'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(first).dy,
        lessThan(tester.getTopLeft(second).dy),
      );
      expect(controller.candidates.map((book) => book.id), [
        'z-first',
        'a-second',
        'a-third',
      ]);
      expect(controller.searches, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh requests new candidates and reports partial results honestly',
    (tester) async {
      await openSheet(tester);
      await tester.pumpAndSettle();
      final pending = Completer<SourceCandidateSearchResult>();
      controller.pendingSearch = pending.future;
      await tester.tap(find.byTooltip('刷新候选'));
      await tester.pump();

      expect(controller.searches, 2);
      expect(find.byKey(const Key('source-switch-loading')), findsOneWidget);
      expect(find.byKey(const Key('source-candidate-z-first')), findsNothing);
      pending.complete(
        SourceCandidateSearchResult([
          _book('fresh', '新源', '原作者'),
        ], failedSources: 2),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('source-candidate-fresh')), findsOneWidget);
      expect(find.text('候选 1 · 1 个书源'), findsOneWidget);
      expect(
        find.byKey(const Key('source-switch-partial-error')),
        findsOneWidget,
      );
      expect(find.textContaining('搜索结果可能不完整'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale refresh completions never replace the latest candidates', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.pumpAndSettle();
    final stale = Completer<SourceCandidateSearchResult>();
    final latest = Completer<SourceCandidateSearchResult>();
    final refresh = find.byTooltip('刷新候选');
    controller.pendingSearch = stale.future;
    await tester.tap(refresh);
    controller.pendingSearch = latest.future;
    await tester.tap(refresh);
    await tester.pump();
    latest.complete(
      SourceCandidateSearchResult([_book('latest', '新源', '原作者')]),
    );
    await tester.pumpAndSettle();
    stale.complete(SourceCandidateSearchResult([_book('stale', '过期源', '原作者')]));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-candidate-latest')), findsOneWidget);
    expect(find.byKey(const Key('source-candidate-stale')), findsNothing);
    expect(controller.cancellations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty partial and failed searches remain distinct and retryable',
    (tester) async {
      controller.candidates = [];
      controller.failedSources = 2;
      await openSheet(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source-switch-empty')), findsOneWidget);
      expect(
        find.byKey(const Key('source-switch-partial-error')),
        findsOneWidget,
      );
      expect(find.text('候选 0 · 0 个书源'), findsOneWidget);
      expect(find.textContaining('已显示其他候选'), findsNothing);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      controller.searchError = StateError('候选请求失败');
      await tester.tap(find.text('打开换源'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source-switch-error')), findsOneWidget);
      expect(find.textContaining('候选请求失败'), findsOneWidget);
      expect(find.byKey(const Key('source-switch-empty')), findsNothing);
      controller.searchError = null;
      controller.failedSources = 0;
      controller.candidates = [_book('retry', '重试源', '原作者')];
      await tester.tap(find.widgetWithText(TextButton, '重试'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source-candidate-retry')), findsOneWidget);
      expect(find.byKey(const Key('source-switch-error')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing the sheet cancels its in-flight candidate search', (
    tester,
  ) async {
    final pending = Completer<SourceCandidateSearchResult>();
    controller.pendingSearch = pending.future;
    await openSheet(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('source-switch-loading')), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    pending.complete(SourceCandidateSearchResult(controller.candidates));
    await tester.pumpAndSettle();
    expect(controller.cancellations, 1);
    expect(find.byType(SourceSwitchSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed lower candidate stays visibly explained after scrolling',
    (tester) async {
      controller.candidates = [
        for (var index = 0; index < 18; index++)
          _book('candidate-$index', '来源$index', '作者'),
      ];
      controller.switchError = StateError('换源失败');
      await openSheet(tester);
      await tester.pumpAndSettle();
      final lower = find.byKey(const Key('source-candidate-candidate-15'));
      await tester.scrollUntilVisible(
        lower,
        140,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(lower);
      await tester.pumpAndSettle();

      final error = find.byKey(const Key('source-switch-error'));
      expect(error, findsOneWidget);
      expect(tester.getRect(error).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(error).bottom, lessThanOrEqualTo(812));
      expect(find.textContaining('换源失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching blocks duplicate actions and a failure keeps candidates usable',
    (tester) async {
      final pending = Completer<Book>();
      controller.pendingSwitch = pending.future;
      await openSheet(tester, size: const Size(800, 1000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source-candidate-z-first')));
      await tester.tap(find.byKey(const Key('source-candidate-a-second')));
      await tester.pump();
      expect(controller.switches, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('source-switch-filter')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close))
            .onPressed,
        isNull,
      );
      pending.completeError(StateError('切换失败'));
      await tester.pumpAndSettle();
      expect(find.textContaining('切换失败'), findsOneWidget);
      expect(controller.current.sourceLabel, '旧源');
      controller.pendingSwitch = null;
      await tester.tap(find.byKey(const Key('source-candidate-a-second')));
      await tester.pumpAndSettle();
      expect(controller.selected!.id, 'a-second');
      expect(find.byType(SourceSwitchSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('short phone keyboard still exposes filter and candidates', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await openSheet(tester, size: const Size(375, 520));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final filter = find.byKey(const Key('source-switch-filter'));
    await tester.ensureVisible(filter);
    await tester.enterText(filter, 'Zeta');
    await tester.pumpAndSettle();
    expect(find.text('匹配 1 / 3 · 1 个书源'), findsOneWidget);
    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone keyboard and long metadata leave source controls usable', (
    tester,
  ) async {
    controller.current = _book(
      'current',
      '当前书源名称很长需要截断显示',
      '原作者',
    ).copyWith(title: '一本书名非常长但仍然应该能够筛选并且切换书源的小说');
    controller.candidates = [_book('long', '很长的候选书源名称仍然可以显示', '原作者')];
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await openSheet(tester);
    await tester.pumpAndSettle();
    final filter = find.byKey(const Key('source-switch-filter'));
    await tester.enterText(filter, '原作者');
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(filter).dy, lessThanOrEqualTo(512));
    expect(find.text('匹配 1 / 1 · 1 个书源'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新候选'));
    await tester.pumpAndSettle();
    expect(controller.searches, 2);
    expect(tester.takeException(), isNull);
  });
}
