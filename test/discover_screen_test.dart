import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/screens/discover_screen.dart';
import 'package:sembast/sembast_memory.dart';

class _PagedSearchController extends AppController {
  _PagedSearchController(super.repository, super.engine);

  final pages = <int>[];
  final source = BookSource({
    'bookSourceUrl': 'https://source.example',
    'bookSourceName': '分页书源',
  });

  @override
  Future<List<SourceSearchGroup>> searchSources(
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    pages.add(page);
    return [
      SourceSearchGroup(source, [
        Book(
          id: 'remote-$page',
          title: '第 $page 页结果',
          author: '作者',
          description: '',
          category: '网络',
          coverStyle: page,
          sourceLabel: source.name,
          sourceId: source.id,
          url: 'https://source.example/book/$page',
          addedAt: DateTime.utc(2026),
        ),
      ]),
    ];
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
      Book(
        id: 'explore-$page',
        title: '发现第 $page 页',
        author: '作者',
        description: '',
        category: category.entry.title,
        coverStyle: page,
        sourceLabel: category.source.name,
        sourceId: category.source.id,
        url: 'https://source.example/explore/$page',
        addedAt: DateTime.utc(2026),
      ),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('discovery loads and merges the next source page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final database = await databaseFactoryMemory.openDatabase(
      'discover-${DateTime.now().microsecondsSinceEpoch}',
    );
    final controller = _PagedSearchController(
      AppRepository(database),
      SourceEngine(),
    );
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
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('discover-search')), '测试');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

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

  testWidgets('discovery opens and paginates a source explore category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final database = await databaseFactoryMemory.openDatabase(
      'explore-${DateTime.now().microsecondsSinceEpoch}',
    );
    final controller = _ExploreController(
      AppRepository(database),
      SourceEngine(),
    );
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
          ),
        ),
      ),
    );
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
}
