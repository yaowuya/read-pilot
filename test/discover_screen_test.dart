import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/domain/explore_kind.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/screens/discover_screen.dart';
import 'package:read_pilot/ui/screens/search_screen.dart';
import 'package:sembast/sembast_memory.dart';

Book _book({
  required String id,
  required String title,
  required BookSource source,
  String author = '作者',
  String category = '网络',
}) => Book(
  id: id,
  title: title,
  author: author,
  description: '',
  category: category,
  coverStyle: 1,
  sourceLabel: source.name,
  addedAt: DateTime.utc(2026),
  sourceId: source.id,
  url: '${source.id}/book/$id',
);

BookSource _source(String url, String name, {String? group, String? explore}) =>
    BookSource({
      'bookSourceUrl': url,
      'bookSourceName': name,
      'bookSourceGroup': ?group,
      'exploreUrl': ?explore,
    });

/// 一条书源的发现规则覆盖了全部五种分类类型。
String _richExploreUrl() => const JsonEncoder().convert([
  {'title': '玄幻', 'url': '/genre/xuanhuan/{{page}}'},
  {'title': '榜单', 'url': '/rank/{{page}}'},
  {'title': '关键字', 'type': 'text'},
  {
    'title': '完结',
    'type': 'toggle',
    'chars': ['完结', '连载'],
  },
  {
    'title': '排序',
    'type': 'select',
    'chars': ['最热', '最新'],
    'default': '最热',
  },
  {'title': '登录', 'type': 'button', 'action': 'login()'},
]);

/// 发现页的测试替身：书源、分组、分类取值、搜索历史都在内存里，不发真实请求。
class _ExploreController extends AppController {
  _ExploreController(
    super.repository,
    super.engine, {
    List<BookSource>? installed,
  }) : _installed = installed ?? const [];

  final List<BookSource> _installed;

  final selections = <ExploreMainSelection>[];
  final savedInfo = <String, Map<String, String>>{};
  final explored = <({String source, String kind, int page})>[];
  final history = <String>[];
  Completer<void>? pendingExplore;

  BookSource sourceFor(String id) =>
      _installed.firstWhere((source) => source.id == id);

  @override
  List<BookSource> get sources => _installed;

  @override
  List<BookSource> get exploreSources => [
    for (final source in _installed)
      if (source.enabled && source.enabledExplore && source.hasExplore) source,
  ];

  @override
  List<String> get sourceGroups {
    final groups = <String>{};
    for (final source in exploreSources) {
      groups.addAll(source.groups);
    }
    return groups.toList()..sort();
  }

  @override
  List<BookSource> exploreSourcesInGroup(String? group) {
    final name = group?.trim() ?? '';
    if (name.isEmpty) return exploreSources;
    return [
      for (final source in exploreSources)
        if (source.groups.contains(name)) source,
    ];
  }

  @override
  Future<ExploreMainSelection> exploreSelection() async =>
      selections.isEmpty ? const ExploreMainSelection() : selections.last;

  @override
  Future<void> saveExploreSelection(ExploreMainSelection selection) async {
    selections.add(selection);
  }

  @override
  Future<Map<String, String>> sourceExploreInfo(String sourceId) async =>
      savedInfo[sourceId] ?? const {};

  @override
  Future<void> saveSourceExploreInfo(
    String sourceId,
    Map<String, String> values,
  ) async {
    savedInfo[sourceId] = values;
  }

  @override
  Future<List<String>> searchHistory() async => List.unmodifiable(history);

  @override
  Future<List<String>> rememberSearch(String keyword) async {
    history.removeWhere((item) => item.toLowerCase() == keyword.toLowerCase());
    history.insert(0, keyword);
    return List.unmodifiable(history);
  }

  @override
  Future<void> clearSearchHistory() async => history.clear();

  @override
  List<SourceExploreCategory> get exploreCategories => const [];

  @override
  Future<SourceSearchGroup> exploreKind(
    BookSource source,
    ExploreKind kind, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    explored.add((source: source.id, kind: kind.title, page: page));
    await pendingExplore?.future;
    return SourceSearchGroup(source, [
      _book(
        id: '${source.id}-${kind.title}-$page',
        title: '${kind.title} 第 $page 页',
        source: source,
        category: kind.title,
      ),
    ]);
  }

  @override
  Future<List<SourceSearchGroup>> searchSources(
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
    void Function(int processed, int total)? onProgress,
    FutureOr<void> Function(SourceSearchGroup group, int processed, int total)?
    onResult,
  }) async {
    final group = SourceSearchGroup(_installed.first, [
      _book(id: 'found-book', title: '搜到的书', source: _installed.first),
    ]);
    onResult?.call(group, 1, 1);
    return [group];
  }
}

Future<_ExploreController> _pumpDiscover(
  WidgetTester tester, {
  required List<BookSource> sources,
  Size size = const Size(800, 1200),
  VoidCallback? onBack,
  VoidCallback? onSources,
  VoidCallback? onImport,
  List<String> history = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  late final Database database;
  late final _ExploreController controller;
  await tester.runAsync(() async {
    database = await databaseFactoryMemory.openDatabase(
      'discover-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = _ExploreController(
      AppRepository(database),
      SourceEngine(),
      installed: sources,
    );
  });
  controller.history.addAll(history);
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
          onSources: onSources ?? () {},
          onBack: onBack,
          onImport: onImport,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// 根层点开一条书源，进入它的分类格子（书源层）。
Future<void> _openSourceLayer(WidgetTester tester, String sourceUrl) async {
  await tester.tap(find.byKey(ValueKey('discover-source-$sourceUrl')));
  await tester.pumpAndSettle();
}

void main() {
  final alpha = _source(
    'https://alpha.example',
    '阿尔法书源',
    group: '玄幻',
    explore: _richExploreUrl(),
  );
  final beta = _source(
    'https://beta.example',
    '贝塔书源',
    group: '都市',
    explore: '玄幻::/xuanhuan\\n都市::/dushi',
  );
  final gamma = _source('https://gamma.example', '伽马书源');

  testWidgets('browse mode lists one row per explore source', (tester) async {
    await _pumpDiscover(tester, sources: [alpha, beta, gamma]);

    expect(find.text('发现'), findsOneWidget);
    expect(find.text('阿尔法书源'), findsOneWidget);
    expect(find.text('贝塔书源'), findsOneWidget);
    // 伽马书源没有声明发现规则，不算发现书源。
    expect(find.text('伽马书源'), findsNothing);
    // 设计稿在「浏览书源」右侧标出已启用条数。
    expect(find.text('2 个已启用'), findsOneWidget);
    // 有分类的书源标「分类」，只有搜索能力的标「仅搜索」。
    expect(find.text('分类'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a source with only discover rules is search-only', (
    tester,
  ) async {
    await _pumpDiscover(
      tester,
      sources: [
        BookSource({
          'bookSourceUrl': 'https://partial.example',
          'bookSourceName': '只有规则的书源',
          'ruleExplore': {
            'bookList': '.list',
            'name': '.name',
            'bookUrl': 'a@href',
          },
        }),
      ],
    );

    expect(find.text('只有规则的书源'), findsOneWidget);
    // 没有 exploreUrl 就没有分类可逛，行上直接标成「仅搜索」。
    expect(find.text('仅搜索'), findsOneWidget);
    expect(find.text('支持按书名、作者搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a source shows its kind tiles', (tester) async {
    final controller = await _pumpDiscover(tester, sources: [alpha]);
    await _openSourceLayer(tester, 'https://alpha.example');

    // 分类格子用「书源 + 分类标题」组成 key，避免和分组名、书源分组标签同名。
    for (final title in ['玄幻', '榜单', '关键字', '登录']) {
      expect(
        find.byKey(ValueKey('explore-kind-https://alpha.example-$title')),
        findsOneWidget,
        reason: '缺少分类格子 $title',
      );
    }
    // 开关类格子把当前取值拼在标题旁边（legado ToggleTypeItem）。
    expect(find.text('完结完结'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('explore-kind-https://alpha.example-玄幻')),
    );
    await tester.pumpAndSettle();

    expect(controller.explored.last.kind, '玄幻');
    expect(
      find.byKey(const ValueKey('discover-book-https://alpha.example-玄幻-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a text kind saves what the user typed into the source info map',
    (tester) async {
      final controller = await _pumpDiscover(tester, sources: [alpha]);
      await _openSourceLayer(tester, 'https://alpha.example');

      final field = find.byKey(
        const ValueKey('explore-kind-input-https://alpha.example-关键字'),
      );
      await tester.enterText(field, '斗破');
      await tester.pump(const Duration(milliseconds: 700));

      expect(controller.savedInfo['https://alpha.example'], {'关键字': '斗破'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tapping a toggle cycles through its declared chars', (
    tester,
  ) async {
    final controller = await _pumpDiscover(tester, sources: [alpha]);
    await _openSourceLayer(tester, 'https://alpha.example');

    // 未保存过取值时显示首个候选值（legado `chars.first()`）。
    await tester.tap(find.text('完结完结'));
    await tester.pump();

    expect(controller.savedInfo['https://alpha.example'], {'完结': '连载'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('group filter narrows the visible sources', (tester) async {
    await _pumpDiscover(tester, sources: [alpha, beta]);

    await tester.tap(find.byKey(const ValueKey('discover-group-玄幻')));
    await tester.pumpAndSettle();
    expect(find.text('阿尔法书源'), findsOneWidget);
    expect(find.text('贝塔书源'), findsNothing);

    await tester.tap(find.byKey(const Key('discover-group-all')));
    await tester.pumpAndSettle();
    expect(find.text('贝塔书源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('content mode shows one source at a time and remembers it', (
    tester,
  ) async {
    final controller = await _pumpDiscover(tester, sources: [alpha, beta]);

    await tester.tap(find.byKey(const Key('discover-mode')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discover-source-select')), findsOneWidget);
    expect(controller.selections.last.showContent, isTrue);
    // 内容模式只列出当前书源的分类标签，不再铺开所有书源的行。
    expect(
      find.byKey(const ValueKey('discover-source-https://beta.example')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('content mode restores the saved source and kind', (
    tester,
  ) async {
    final controller = await _pumpDiscover(tester, sources: [alpha]);
    controller.selections.add(
      const ExploreMainSelection(
        sourceUrl: 'https://alpha.example',
        kindKeyBySource: {'https://alpha.example': '2:榜单:/rank/{{page}}'},
        showContent: true,
      ),
    );
    await tester.pumpWidget(const SizedBox());
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
    await tester.pumpAndSettle();

    expect(find.text('浏览“榜单”'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a category page paginates and can be closed', (tester) async {
    final controller = await _pumpDiscover(tester, sources: [alpha]);
    await _openSourceLayer(tester, 'https://alpha.example');

    await tester.tap(
      find.byKey(const ValueKey('explore-kind-https://alpha.example-玄幻')),
    );
    await tester.pumpAndSettle();
    expect(controller.explored.map((item) => item.page), [1]);

    await tester.tap(find.byKey(const Key('discover-page-more')));
    await tester.pumpAndSettle();
    expect(controller.explored.map((item) => item.page), [1, 2]);
    // 书名同时出现在书封和标题两处，用书籍行的 key 精确定位。
    expect(
      find.byKey(const ValueKey('discover-book-https://alpha.example-玄幻-2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('discover-page-back')));
    await tester.pumpAndSettle();
    // 关闭分类页回到书源层，标题是书源名。
    expect(find.text('阿尔法书源'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discover-detail-back')));
    await tester.pumpAndSettle();
    expect(find.text('浏览书源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('script-generated explore rules are reported as unsupported', (
    tester,
  ) async {
    await _pumpDiscover(
      tester,
      sources: [
        _source('https://alpha.example', '阿尔法书源', explore: '@js:buildKinds()'),
      ],
    );

    // 脚本分类不在本版本能力范围：行上说明原因，并归为「仅搜索」。
    expect(find.text('该书的发现分类由脚本生成，当前版本无法加载。'), findsOneWidget);
    expect(find.text('仅搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the search box opens the full search page with its keyword', (
    tester,
  ) async {
    await _pumpDiscover(tester, sources: [alpha]);

    await tester.enterText(
      find.byKey(const Key('discover-search-field')),
      '测试',
    );
    await tester.tap(find.byKey(const Key('discover-search-submit')));
    await tester.pumpAndSettle();

    // 设计稿：搜索是整页，不再在发现页内联出结果。
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byKey(const Key('search-submit')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-submit')));
    await tester.pumpAndSettle();

    // 设计稿的结果头是「N 本书 · 已搜索 X/Y 个源」，不是「找到 N 本」。
    expect(find.byKey(const Key('search-results-head')), findsOneWidget);
    expect(find.textContaining('本书'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('search-result-found-book')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search-only source opens the search page scoped to it', (
    tester,
  ) async {
    await _pumpDiscover(
      tester,
      sources: [
        BookSource({
          'bookSourceUrl': 'https://partial.example',
          'bookSourceName': '只有规则的书源',
          'ruleExplore': {'bookList': '.list'},
        }),
      ],
    );

    await tester.tap(
      find.byKey(const ValueKey('discover-source-https://partial.example')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
    // 设计稿把范围放在条件行：单源搜索时这里直接显示源名。
    expect(find.byKey(const Key('search-scope-trigger')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-scope-trigger')),
        matching: find.text('只有规则的书源'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent searches only render once there is history', (
    tester,
  ) async {
    final controller = await _pumpDiscover(
      tester,
      sources: [alpha],
      history: ['斗破', '遮天'],
    );

    expect(find.text('最近搜索'), findsOneWidget);
    expect(find.byKey(const ValueKey('discover-history-斗破')), findsOneWidget);

    // 点历史 chip 直接带着关键词进搜索页。
    await tester.tap(find.byKey(const ValueKey('discover-history-斗破')));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(controller.history, ['斗破', '遮天']);

    // 搜索页的返回键是设计稿的圆形按钮，不是系统返回箭头。
    await tester.tap(find.byKey(const Key('topbar-back')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('discover-history-clear')));
    await tester.pumpAndSettle();
    expect(find.text('最近搜索'), findsNothing);
    expect(controller.history, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the add source button reaches source management', (
    tester,
  ) async {
    var opens = 0;
    await _pumpDiscover(tester, sources: [alpha], onSources: () => opens++);

    await tester.tap(find.byKey(const Key('discover-add-source')));
    await tester.pump();

    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back button returns to the bookshelf', (tester) async {
    var backs = 0;
    await _pumpDiscover(tester, sources: [alpha], onBack: () => backs++);

    await tester.tap(find.byKey(const Key('discover-back')));
    await tester.pump();

    expect(backs, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no explore sources shows an empty state with a way forward', (
    tester,
  ) async {
    var imports = 0;
    await _pumpDiscover(tester, sources: const [], onImport: () => imports++);

    expect(find.text('添加书源，发现更多书'), findsOneWidget);
    expect(find.text('添加书源'), findsOneWidget);
    expect(find.text('可以先搜索书架与本地书籍'), findsOneWidget);

    await tester.tap(find.text('导入本地书籍'));
    await tester.pump();
    expect(imports, 1);
    expect(tester.takeException(), isNull);
  });
}
