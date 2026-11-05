import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/domain/source_switch_candidate.dart';
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

SourceCandidateInfo _readyInfo() => const SourceCandidateInfo(
  chapterCount: 1,
  mappedChapterIndex: 0,
  mappedChapterTitle: '第一章',
  wordCount: 4,
);

SourceCandidateSearchResult _withReadyInfo(
  SourceCandidateSearchResult result,
) => SourceCandidateSearchResult(
  result.candidates,
  failedSources: result.failedSources,
  unavailableCandidateSourceIds: result.unavailableCandidateSourceIds,
  candidateInfoById: {
    for (final candidate in result.candidates)
      candidate.id: result.infoFor(candidate) ?? _readyInfo(),
  },
  pendingMetadata: result.pendingMetadata,
  fromCache: result.fromCache,
  loadedAt: result.loadedAt,
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
  int cacheLookups = 0;
  int reloads = 0;
  int failedSources = 0;
  int cancellations = 0;
  Object? searchError;
  SourceCandidateSearchResult? cachedCandidates;
  Future<SourceCandidateSearchResult>? pendingSearch;
  Book? selected;
  int switches = 0;
  Future<Book>? pendingSwitch;
  Object? switchError;
  bool streamedCandidates = false;
  bool streamedCandidatesReady = false;
  int streamedProcessed = 1;
  int streamedTotal = 400;
  int streamedPendingMetadata = 0;
  Completer<void>? streamGate;
  bool persistReloads = false;

  @override
  Future<SourceCandidateSearchResult> findSourceCandidates(
    String bookId, {
    Future<void>? abortTrigger,
  }) async {
    searches++;
    abortTrigger?.then((_) => cancellations++);
    if (searchError != null) throw searchError!;
    final pending = pendingSearch;
    if (pending != null) return _withReadyInfo(await pending);
    return _withReadyInfo(
      SourceCandidateSearchResult(candidates, failedSources: failedSources),
    );
  }

  @override
  Future<SourceCandidateSearchResult?> sourceCandidateCacheFor(
    Book current,
  ) async {
    cacheLookups++;
    final cached = cachedCandidates;
    if (cached == null) return null;
    final ready = _withReadyInfo(cached);
    return SourceCandidateSearchResult(
      ready.candidates,
      failedSources: ready.failedSources,
      candidateInfoById: ready.candidateInfoById,
      fromCache: true,
      loadedAt: ready.loadedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  Future<SourceCandidateSearchResult> reloadSourceCandidatesFor(
    Book current, {
    Future<void>? abortTrigger,
    void Function(
      SourceCandidateSearchResult partial,
      int processed,
      int total,
    )?
    onUpdate,
  }) async {
    reloads++;
    final result = await findSourceCandidatesFor(
      current,
      abortTrigger: abortTrigger,
      onUpdate: onUpdate,
    );
    // Mirrors the repository write: a complete manual/initial load becomes the
    // snapshot the next opening restores.
    if (persistReloads && result.hasCompleteCandidateResults) {
      cachedCandidates = result;
    }
    return result;
  }

  @override
  Future<SourceCandidateSearchResult> findSourceCandidatesFor(
    Book current, {
    Future<void>? abortTrigger,
    void Function(
      SourceCandidateSearchResult partial,
      int processed,
      int total,
    )?
    onUpdate,
  }) async {
    searches++;
    abortTrigger?.then((_) => cancellations++);
    if (searchError != null) throw searchError!;
    if (streamedCandidates && pendingSearch == null) {
      // Simulate both the old premature update and a metadata-ready live row.
      final partial = SourceCandidateSearchResult([
        candidates.first,
      ], pendingMetadata: streamedPendingMetadata);
      onUpdate?.call(
        streamedCandidatesReady ? _withReadyInfo(partial) : partial,
        streamedProcessed,
        streamedTotal,
      );
      await (streamGate ?? Completer<void>()).future;
    }
    final pending = pendingSearch;
    if (pending != null) return _withReadyInfo(await pending);
    return _withReadyInfo(
      SourceCandidateSearchResult(candidates, failedSources: failedSources),
    );
  }

  @override
  Future<Book> switchBookSource(String bookId, Book candidate) async {
    switches++;
    selected = candidate;
    if (switchError != null) throw switchError!;
    return pendingSwitch ??
        current.rebindSource(candidate, position: current.position);
  }

  /// Installed sources offered by the reader page. Empty means "use the real
  /// repository", so tests that do not care about source actions are unaffected.
  List<BookSource> installedSources = const [];
  CandidateSourceAction? lastAction;
  String? lastActionSourceId;
  bool actionKeepsRow = true;

  @override
  List<BookSource> get sources =>
      installedSources.isEmpty ? super.sources : installedSources;

  @override
  Future<bool> applyCandidateSourceAction(
    String sourceId,
    CandidateSourceAction action,
  ) async {
    lastAction = action;
    lastActionSourceId = sourceId;
    return actionKeepsRow;
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

  testWidgets('source sheet covers about two thirds of the phone', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(SourceSwitchSheet));
    // 换源是半屏操作：上方留出正文，用户能一边看当前页一边挑书源。
    expect(sheet.height, lessThanOrEqualTo(812 * .7));
    expect(sheet.height, greaterThanOrEqualTo(812 * .6));
    expect(sheet.top, greaterThan(812 * .3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restores cached candidates before requesting a fresh source search',
    (tester) async {
      final cached = _book('cached', '缓存书源', '原作者');
      controller.cachedCandidates = SourceCandidateSearchResult([
        cached,
      ], fromCache: true);

      await openSheet(tester);
      await tester.pumpAndSettle();

      expect(controller.cacheLookups, 1);
      expect(controller.reloads, 0);
      expect(controller.searches, 0);
      expect(find.byKey(const Key('source-candidate-cached')), findsOneWidget);
      expect(
        find.byKey(const Key('source-switch-cache-status')),
        findsOneWidget,
      );
      expect(find.text('已恢复上次加载的书源，10 天内可直接选择。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual refresh clears cached candidates and keeps its status unobscured',
    (tester) async {
      final cached = _book('cached', '缓存书源', '原作者');
      controller.cachedCandidates = SourceCandidateSearchResult([
        cached,
      ], fromCache: true);
      await openSheet(tester);
      await tester.pumpAndSettle();
      final pending = Completer<SourceCandidateSearchResult>();
      controller.pendingSearch = pending.future;

      await tester.tap(find.byTooltip('刷新候选'));
      await tester.pump();

      final status = find.byKey(const Key('source-switch-status'));
      final loading = find.byKey(const Key('source-switch-loading'));
      expect(controller.reloads, 1);
      expect(controller.searches, 1);
      expect(find.byKey(const Key('source-candidate-cached')), findsNothing);
      expect(find.byKey(const Key('source-switch-cache-status')), findsNothing);
      expect(loading, findsOneWidget);
      expect(status, findsOneWidget);
      expect(find.text('正在重新加载书源…'), findsOneWidget);
      final sheetRect = tester.getRect(find.byType(SourceSwitchSheet));
      final statusRect = tester.getRect(status);
      final loadingRect = tester.getRect(loading);
      expect(sheetRect.contains(statusRect.topLeft), isTrue);
      expect(statusRect.bottom, lessThanOrEqualTo(loadingRect.top));
      expect(statusRect.overlaps(loadingRect), isFalse);
      expect(tester.takeException(), isNull);

      pending.complete(
        SourceCandidateSearchResult([_book('fresh', '新书源', '原作者')]),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source-candidate-cached')), findsNothing);
      expect(find.byKey(const Key('source-candidate-fresh')), findsOneWidget);
    },
  );

  testWidgets(
    'fresh streaming cards remain below the pinned manual reload status',
    (tester) async {
      final cached = _book('cached', '缓存书源', '原作者');
      controller
        ..cachedCandidates = SourceCandidateSearchResult([
          cached,
        ], fromCache: true)
        ..streamedCandidates = true
        ..streamedCandidatesReady = true
        ..streamGate = Completer<void>();
      await openSheet(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('刷新候选'));
      await tester.pump();

      final status = find.byKey(const Key('source-switch-status'));
      final freshRow = find.byKey(const Key('source-candidate-z-first'));
      expect(find.byKey(const Key('source-candidate-cached')), findsNothing);
      expect(freshRow, findsOneWidget);
      expect(find.text('正在重新加载书源…（1/400）'), findsOneWidget);
      final statusRect = tester.getRect(status);
      final freshRect = tester.getRect(freshRow);
      expect(statusRect.bottom, lessThanOrEqualTo(freshRect.top));
      expect(statusRect.overlaps(freshRect), isFalse);

      controller.streamGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an incomplete refresh clears cached candidates for fresh rows', (
    tester,
  ) async {
    final cached = _book('cached', '缓存书源', '原作者');
    controller.cachedCandidates = SourceCandidateSearchResult([
      cached,
    ], fromCache: true);
    await openSheet(tester);
    await tester.pumpAndSettle();
    final pending = Completer<SourceCandidateSearchResult>();
    controller.pendingSearch = pending.future;

    await tester.tap(find.byTooltip('刷新候选'));
    await tester.pump();
    expect(find.byKey(const Key('source-candidate-cached')), findsNothing);
    expect(find.byKey(const Key('source-switch-loading')), findsOneWidget);
    pending.complete(
      SourceCandidateSearchResult(
        [_book('partial', '部分书源', '原作者')],
        failedSources: 1,
        unavailableCandidateSourceIds: const {'https://unavailable.example'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-candidate-cached')), findsNothing);
    expect(find.byKey(const Key('source-candidate-partial')), findsOneWidget);
    expect(
      find.byKey(const Key('source-switch-partial-error')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a successful refresh replaces the cached source candidates', (
    tester,
  ) async {
    final cached = _book('cached', '缓存书源', '原作者');
    controller.cachedCandidates = SourceCandidateSearchResult([
      cached,
    ], fromCache: true);
    await openSheet(tester);
    await tester.pumpAndSettle();
    final pending = Completer<SourceCandidateSearchResult>();
    controller.pendingSearch = pending.future;

    await tester.tap(find.byTooltip('刷新候选'));
    await tester.pump();
    pending.complete(
      SourceCandidateSearchResult([_book('fresh', '新书源', '原作者')]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-candidate-cached')), findsNothing);
    expect(find.byKey(const Key('source-candidate-fresh')), findsOneWidget);
    expect(find.byKey(const Key('source-switch-cache-status')), findsNothing);
    expect(find.text('候选 1 · 1 个书源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows mapped chapter and word-count candidate metadata', (
    tester,
  ) async {
    final mapped = _book('mapped', '映射书源', '原作者');
    controller.cachedCandidates = SourceCandidateSearchResult(
      [mapped],
      fromCache: true,
      candidateInfoById: {
        mapped.id: const SourceCandidateInfo(
          chapterCount: 120,
          mappedChapterIndex: 41,
          mappedChapterTitle: '风雪归途',
          wordCount: 123456,
        ),
      },
    );

    await openSheet(tester);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('source-candidate-chapter-mapped')),
          )
          .data,
      '章节：第 42/120 章 · 风雪归途',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('source-candidate-word-count-mapped')),
          )
          .data,
      '字数：123456',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reopening after a completed switch restores the loaded candidates',
    (tester) async {
      // 用户报告：换源成功后再次点开换源，应当直接列出上次加载好的源，
      // 只有点刷新按钮才重新扫描全部书源。
      controller.persistReloads = true;
      // 换源面板只占约 2/3 屏，用高一点的视口让候选行都落在可见区域。
      await openSheet(tester, size: const Size(375, 1200));
      await tester.pumpAndSettle();
      expect(controller.reloads, 1);
      expect(controller.searches, 1);
      expect(
        find.byKey(const Key('source-candidate-a-second')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('source-candidate-a-second')));
      await tester.pumpAndSettle();
      expect(controller.switches, 1);
      expect(find.byType(SourceSwitchSheet), findsNothing);
      final switched = controller.selected!;
      controller.current = controller.current.rebindSource(
        switched,
        position: controller.current.position,
      );

      await tester.tap(find.text('打开换源'));
      await tester.pumpAndSettle();

      expect(controller.cacheLookups, 2);
      expect(controller.reloads, 1);
      expect(controller.searches, 1);
      expect(
        find.byKey(const Key('source-candidate-a-second')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('source-switch-cache-status')),
        findsOneWidget,
      );
      expect(find.text('已恢复上次加载的书源，10 天内可直接选择。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
      await openSheet(tester, size: const Size(800, 2000));
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
    'search options persist the author filter and refresh the candidates',
    (tester) async {
      await openSheet(tester, size: const Size(800, 2000));
      await tester.pumpAndSettle();
      final before = controller.reloads;

      await tester.tap(find.byKey(const Key('source-switch-options')));
      await tester.pumpAndSettle();
      expect(find.text('搜索选项'), findsOneWidget);

      await tester.tap(find.byKey(const Key('source-options-check-author')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source-options-sort-word-count')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('source-options-done')));
      await tester.pumpAndSettle();

      expect(controller.changeSourceSettings.checkAuthor, isTrue);
      expect(controller.changeSourceSettings.sortByWordCount, isTrue);
      // 作者过滤发生在收集候选时，所以改完必须重新搜一次而不是只重排列表。
      expect(controller.reloads, before + 1);
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

  testWidgets('lists a streamed candidate before its metadata arrives', (
    tester,
  ) async {
    // A source returning this title is already a switchable target: chapter
    // mapping and word count are decoration, so they stream in afterwards and
    // must never keep the row off screen.
    controller
      ..streamedCandidates = true
      ..streamGate = Completer<void>();
    await openSheet(tester);
    await tester.pump();

    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);
    expect(find.text('章节：正在加载信息…'), findsOneWidget);
    expect(find.text('字数：正在加载…'), findsOneWidget);
    expect(find.textContaining('正在查找其他同名书源'), findsOneWidget);

    controller.streamGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('source-candidate-chapter-z-first')),
          )
          .data,
      '章节：第 1/1 章 · 第一章',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('source-candidate-word-count-z-first')),
          )
          .data,
      '字数：4',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports pending metadata while listing found candidates', (
    tester,
  ) async {
    controller
      ..streamedCandidates = true
      ..streamedProcessed = 400
      ..streamedTotal = 400
      ..streamedPendingMetadata = 3
      ..streamGate = Completer<void>();
    await openSheet(tester);
    await tester.pump();

    // The found source is listed immediately; only its summary is pending.
    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);
    expect(find.text('正在加载候选章节与字数…（剩余 3）'), findsOneWidget);

    controller.streamGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('source-candidate-word-count-z-first')),
          )
          .data,
      '字数：4',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing while candidate metadata is pending ignores a late ready row',
    (tester) async {
      controller
        ..streamedCandidates = true
        ..streamGate = Completer<void>();
      await openSheet(tester);
      await tester.pump();
      expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);

      Navigator.of(tester.element(find.byType(SourceSwitchSheet))).pop();
      await tester.pumpAndSettle();
      controller.streamGate!.complete();
      await tester.pumpAndSettle();

      expect(controller.cancellations, 1);
      expect(find.byType(SourceSwitchSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing a manual refresh ignores its late completion', (
    tester,
  ) async {
    final cached = _book('cached', '缓存书源', '原作者');
    controller
      ..cachedCandidates = SourceCandidateSearchResult([
        cached,
      ], fromCache: true)
      ..streamedCandidates = true
      ..streamedCandidatesReady = true
      ..streamGate = Completer<void>();
    await openSheet(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('刷新候选'));
    await tester.pump();
    expect(find.byKey(const Key('source-candidate-cached')), findsNothing);
    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);

    Navigator.of(tester.element(find.byType(SourceSwitchSheet))).pop();
    await tester.pumpAndSettle();
    controller.streamGate!.complete();
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

  testWidgets(
    'manual refresh status remains above fresh cards with the keyboard open',
    (tester) async {
      final cached = _book('cached', '缓存书源', '原作者');
      controller
        ..cachedCandidates = SourceCandidateSearchResult([
          cached,
        ], fromCache: true)
        ..streamedCandidates = true
        ..streamedCandidatesReady = true
        ..streamGate = Completer<void>();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await openSheet(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('刷新候选'));
      await tester.pump();

      final sheet = find.byType(SourceSwitchSheet);
      final status = find.byKey(const Key('source-switch-status'));
      final freshRow = find.byKey(const Key('source-candidate-z-first'));
      expect(status, findsOneWidget);
      expect(freshRow, findsOneWidget);
      final sheetRect = tester.getRect(sheet);
      final statusRect = tester.getRect(status);
      final freshRect = tester.getRect(freshRow);
      expect(statusRect.left, greaterThanOrEqualTo(sheetRect.left));
      expect(statusRect.right, lessThanOrEqualTo(sheetRect.right));
      expect(statusRect.top, greaterThanOrEqualTo(sheetRect.top));
      expect(statusRect.bottom, lessThanOrEqualTo(sheetRect.bottom));
      expect(statusRect.bottom, lessThanOrEqualTo(freshRect.top));
      expect(statusRect.overlaps(freshRect), isFalse);

      controller.streamGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('candidate rows expose the source actions legado offers', (
    tester,
  ) async {
    controller.installedSources = [
      BookSource({
        'bookSourceUrl': 'https://zeta.example',
        'bookSourceName': 'Zeta',
      }),
    ];
    await openSheet(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('source-candidate-menu-z-first')));
    await tester.pumpAndSettle();
    expect(find.text('置顶书源'), findsOneWidget);
    expect(find.text('置底书源'), findsOneWidget);
    expect(find.text('停用书源'), findsOneWidget);
    expect(find.text('删除书源'), findsOneWidget);

    await tester.tap(find.text('置顶书源'));
    await tester.pumpAndSettle();
    expect(controller.lastAction, CandidateSourceAction.top);
    expect(controller.lastActionSourceId, 'https://zeta.example');
    // 置顶/置底只是改排序，候选行必须留在原处。
    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);
  });

  testWidgets('disabling a source from the candidate list drops its row', (
    tester,
  ) async {
    controller.installedSources = [
      BookSource({
        'bookSourceUrl': 'https://zeta.example',
        'bookSourceName': 'Zeta',
      }),
    ];
    controller.actionKeepsRow = true;
    await openSheet(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-candidate-menu-z-first')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('停用书源'));
    await tester.pumpAndSettle();

    expect(controller.lastAction, CandidateSourceAction.disable);
    // 停用的源不再参与换源：行必须立刻消失，否则用户会以为没生效。
    expect(find.byKey(const Key('source-candidate-z-first')), findsNothing);
    expect(find.text('已停用该书源。'), findsOneWidget);
  });

  testWidgets('deleting a source from the candidate list confirms first', (
    tester,
  ) async {
    controller.installedSources = [
      BookSource({
        'bookSourceUrl': 'https://zeta.example',
        'bookSourceName': 'Zeta',
      }),
    ];
    controller.actionKeepsRow = false;
    await openSheet(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('source-candidate-menu-z-first')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除书源'));
    await tester.pumpAndSettle();

    // 删除是破坏性操作，必须先确认。
    expect(find.text('确认移除'), findsOneWidget);
    expect(controller.lastAction, isNull);
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();

    expect(controller.lastAction, CandidateSourceAction.delete);
    expect(find.byKey(const Key('source-candidate-z-first')), findsNothing);
  });

  testWidgets('a candidate from an uninstalled source has no action menu', (
    tester,
  ) async {
    // installedSources 为空：候选仍会列出，但没有可操作的书源记录。
    await openSheet(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-candidate-z-first')), findsOneWidget);
    expect(
      find.byKey(const Key('source-candidate-menu-z-first')),
      findsNothing,
    );
  });
}
