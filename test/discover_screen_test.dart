import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/screens/discover_screen.dart';
import 'package:sembast/sembast_memory.dart';

Book _book({
  required String id,
  required String title,
  required BookSource source,
  String author = '作者',
  String? category,
}) => Book(
  id: id,
  title: title,
  author: author,
  description: '',
  category: category ?? '网络',
  coverStyle: 1,
  sourceLabel: source.name,
  sourceId: source.id,
  url: 'https://source.example/book/$id',
  addedAt: DateTime.utc(2026),
);

class _PagedSearchController extends AppController {
  _PagedSearchController(super.repository, super.engine);

  final pages = <int>[];
  final progress = <({int processed, int total})>[];
  Completer<List<SourceSearchGroup>>? pending;
  int cancellations = 0;
  final source = BookSource({
    'bookSourceUrl': 'https://source.example',
    'bookSourceName': '分页书源',
  });

  @override
  Future<List<SourceSearchGroup>> searchSources(
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
    void Function(int processed, int total)? onProgress,
    void Function(SourceSearchGroup group, int processed, int total)? onResult,
  }) async {
    pages.add(page);
    progress.add((processed: 1, total: 1));
    onProgress?.call(1, 1);
    abortTrigger?.then((_) => cancellations++);
    if (pending != null) return pending!.future;
    final group = SourceSearchGroup(source, [
      _book(id: 'remote-$page', title: '第 $page 页结果', source: source),
    ]);
    onResult?.call(group, 1, 1);
    return [group];
  }
}

/// Two sources offering the same book, so the row must merge into one badge.
class _DualSourceController extends _PagedSearchController {
  _DualSourceController(super.repository, super.engine);

  final second = BookSource({
    'bookSourceUrl': 'https://mirror.example',
    'bookSourceName': '镜像书源',
  });

  @override
  Future<List<SourceSearchGroup>> searchSources(
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
    void Function(int processed, int total)? onProgress,
    void Function(SourceSearchGroup group, int processed, int total)? onResult,
  }) async {
    pages.add(page);
    final same = _book(id: 'same-book', title: '斩神', source: source);
    final groups = [
      SourceSearchGroup(source, [same]),
      SourceSearchGroup(second, [
        _book(id: 'same-book-mirror', title: '斩神', source: second),
        _book(id: 'only-mirror', title: '另一本书', source: second),
      ]),
    ];
    onResult?.call(groups[0], 1, 2);
    onProgress?.call(1, 2);
    onResult?.call(groups[1], 2, 2);
    onProgress?.call(2, 2);
    return groups;
  }
}

/// Two sources where the second one only finishes after a fake-time delay,
/// which is what makes the incremental rendering observable.
class _StreamingController extends AppController {
  _StreamingController(super.repository, super.engine);

  final first = BookSource({
    'bookSourceUrl': 'https://first.example',
    'bookSourceName': '先返回的书源',
  });
  final second = BookSource({
    'bookSourceUrl': 'https://second.example',
    'bookSourceName': '后返回的书源',
  });

  @override
  Future<List<SourceSearchGroup>> searchSources(
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
    void Function(int processed, int total)? onProgress,
    void Function(SourceSearchGroup group, int processed, int total)? onResult,
  }) async {
    final firstGroup = SourceSearchGroup(first, [
      _book(id: 'first-book', title: '先返回的书', source: first),
    ]);
    onResult?.call(firstGroup, 1, 2);
    onProgress?.call(1, 2);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final secondGroup = SourceSearchGroup(second, [
      _book(id: 'second-book', title: '后返回的书', source: second),
    ]);
    onResult?.call(secondGroup, 2, 2);
    onProgress?.call(2, 2);
    return [firstGroup, secondGroup];
  }
}

class _ExploreController extends AppController {
  _ExploreController(super.repository, super.engine);

  final source = BookSource({
    'bookSourceUrl': 'https://source.example',
    'bookSourceName': '发现书源',
  });
  final pages = <int>[];

  @override
  List<SourceExploreCategory> get exploreCategories => [
    SourceExploreCategory(
      source,
      const SourceExploreEntry(title: '热门', url: '/genre/{{page}}'),
    ),
  ];

  @override
  Future<SourceSearchGroup> exploreSource(
    SourceExploreCategory category, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    pages.add(page);
    return SourceSearchGroup(category.source, [
      _book(
        id: 'explore-$page',
        title: '发现第 $page 页',
        source: category.source,
        category: category.entry.title,
      ),
    ]);
  }
}

/// Opens a discovery screen with a controller built from [create].
Future<T> _pumpDiscover<T extends AppController>(
  WidgetTester tester,
  T Function(AppRepository repository, SourceEngine engine) create, {
  Size size = const Size(800, 1200),
  VoidCallback? onBack,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  // Opening the in-memory database and loading the bundled catalog both need
  // the real event loop; inside the widget test's fake-async zone they would
  // hang forever, so they run through runAsync.
  late final Database database;
  late final T controller;
  await tester.runAsync(() async {
    database = await databaseFactoryMemory.openDatabase(
      'discover-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = create(AppRepository(database), SourceEngine());
    await controller.initialize();
  });
  addTearDown(() async {
    controller.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DiscoverScreen(
          controller: controller,
          onDetails: (_) {},
          onSources: () {},
          onBack: onBack,
        ),
      ),
    ),
  );
  return controller;
}

/// Types into the pill field and submits with the keyboard search action.
Future<void> _submit(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byKey(const Key('discover-search')), keyword);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('discovery loads and merges the next source page', (
    tester,
  ) async {
    final controller = await _pumpDiscover(tester, _PagedSearchController.new);

    await _submit(tester, '测试');

    expect(controller.pages, [1]);
    expect(find.text('第 1 页结果'), findsWidgets);
    final more = find.byKey(const Key('discover-load-more'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(find.text('第 1 页结果'), findsWidgets);
    expect(find.text('第 2 页结果'), findsWidgets);
    expect(controller.pages, [1, 2]);
  });

  testWidgets('search reports result count and query progress in one chip', (
    tester,
  ) async {
    final controller = await _pumpDiscover(
      tester,
      _PagedSearchController.new,
      size: const Size(375, 812),
    );

    await _submit(tester, '测试');

    expect(controller.progress, [(processed: 1, total: 1)]);
    expect(find.text('结果 1 · 进度 1/1'), findsOneWidget);
    expect(tester.getTopLeft(find.text('第 1 页结果').last).dy, lessThan(812 * .6));
    final more = find.byKey(const Key('discover-load-more'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(find.text('结果 2 · 进度 1/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('results appear as each source finishes instead of at the end', (
    tester,
  ) async {
    await _pumpDiscover(
      tester,
      _StreamingController.new,
      size: const Size(375, 812),
    );

    await tester.enterText(find.byKey(const Key('discover-search')), '斩神');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    // 第一个书源已返回，第二个还在等待：列表应该已经能看到第一行。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const Key('result-source-count-first-book')), findsOne);
    expect(find.text('结果 1 · 进度 1/2'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('result-source-count-second-book')), findsOne);
    expect(find.text('结果 2 · 进度 2/2'), findsOneWidget);
  });

  testWidgets('duplicate books merge into one row with a source-count badge', (
    tester,
  ) async {
    await _pumpDiscover(tester, _DualSourceController.new);

    await _submit(tester, '斩神');

    // 斩神 exists in both sources → one row, badge 2. The duplicate's own id
    // never gets a badge, which is what proves the rows were merged.
    final badge = find.byKey(const Key('result-source-count-same-book'));
    expect(badge, findsOneWidget);
    expect(
      find.byKey(const Key('result-source-count-same-book-mirror')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(find.descendant(of: badge, matching: find.byType(Text)))
          .data,
      '2',
    );
    // The mirror-only book stays a separate row with its own badge of 1.
    // Its title appears twice (generated cover + row), so match loosely.
    expect(find.text('另一本书'), findsWidgets);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('result-source-count-only-mirror')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '1',
    );
    expect(find.text('结果 2 · 进度 2/2'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing search cancels load-more and ignores its late result', (
    tester,
  ) async {
    final controller = await _pumpDiscover(
      tester,
      _PagedSearchController.new,
      size: const Size(375, 812),
    );
    final search = find.byKey(const Key('discover-search'));
    await _submit(tester, '测试');
    final more = find.byKey(const Key('discover-load-more'));
    controller.pending = Completer<List<SourceSearchGroup>>();
    await tester.tap(more);
    await tester.pump();
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.byKey(const Key('discover-result-count')), findsNothing);
    controller.pending!.complete([SourceSearchGroup(controller.source, [])]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discover-result-count')), findsNothing);
    expect(controller.cancellations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a fresh search does not claim sources are disabled', (
    tester,
  ) async {
    final controller = await _pumpDiscover(
      tester,
      _PagedSearchController.new,
      size: const Size(375, 812),
    );
    controller.pending = Completer<List<SourceSearchGroup>>();
    await tester.enterText(find.byKey(const Key('discover-search')), '测试');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.tap(find.byKey(const Key('discover-cancel')));
    await tester.pumpAndSettle();

    expect(find.text('已取消搜索。'), findsOneWidget);
    expect(find.text('还没有启用的网络书源'), findsNothing);
    controller.pending!.complete([SourceSearchGroup(controller.source, [])]);
    await tester.pumpAndSettle();
    expect(find.text('已取消搜索。'), findsOneWidget);
    expect(controller.cancellations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery opens and paginates a source explore category', (
    tester,
  ) async {
    final controller = await _pumpDiscover(tester, _ExploreController.new);

    await tester.tap(find.text('热门'));
    await tester.pumpAndSettle();

    expect(find.text('发现第 1 页'), findsWidgets);
    final more = find.byKey(const Key('discover-load-more'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(find.text('发现第 1 页'), findsWidgets);
    expect(find.text('发现第 2 页'), findsWidgets);
    expect(controller.pages, [1, 2]);
  });

  testWidgets('back button returns to the bookshelf', (tester) async {
    var backs = 0;
    await _pumpDiscover(
      tester,
      _PagedSearchController.new,
      onBack: () => backs++,
    );

    await tester.tap(find.byKey(const Key('discover-back')));
    await tester.pump();

    expect(backs, 1);
    expect(find.byTooltip('管理书源'), findsWidgets);
    expect(find.byTooltip('筛选'), findsOneWidget);
  });

  testWidgets('filter sheet narrows the local catalog', (tester) async {
    final controller = await _pumpDiscover(tester, _PagedSearchController.new);

    await tester.tap(find.byKey(const Key('discover-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discover-filter-诗词')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discover-filter-done')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('discover-filter-诗词')), findsNothing);
    final poetry = controller.catalog.where((book) => book.category == '诗词');
    final others = controller.catalog.where(
      (book) => book.category != '诗词' && book.category != '全部',
    );
    expect(poetry, isNotEmpty);
    // Each row draws its title twice (generated cover + row label), so the
    // count is loose; the point is that only poetry survives the filter.
    expect(find.text(poetry.first.title), findsWidgets);
    expect(find.text(others.first.title), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
