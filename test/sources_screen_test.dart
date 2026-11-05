import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/services/source_importer.dart';
import 'package:read_pilot/ui/components/source_import_sheet.dart';
import 'package:read_pilot/ui/screens/sources_screen.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;

class _ImportController extends AppController {
  _ImportController(super.repository, super.engine, this.preview);

  final SourceImportPreview preview;
  SourceImportInput? preparedInput;
  bool committed = false;
  Object? commitError;
  Completer<void>? pendingPreparation;
  Completer<void>? pendingCommit;
  final calls = <String>[];

  @override
  Future<SourceImportPreview> prepareSourceImport(
    SourceImportInput input, {
    Future<void>? abortTrigger,
  }) async {
    calls.add('prepare');
    preparedInput = input;
    await pendingPreparation?.future;
    return preview;
  }

  Set<String>? committedSourceIds;

  @override
  Future<SourceImportCommitResult> commitSourceImport(
    SourceImportPreview preview, {
    Set<String>? selectedSourceIds,
  }) async {
    calls.add('commit');
    await pendingCommit?.future;
    if (commitError != null) throw commitError!;
    committed = true;
    committedSourceIds = selectedSourceIds;
    final selected = preview.sources
        .where(
          (source) =>
              selectedSourceIds == null ||
              selectedSourceIds.contains(source.id),
        )
        .toList();
    return SourceImportCommitResult(
      added: selected.length,
      updated: 0,
      sourceIds: selected.map((source) => source.id),
    );
  }
}

Map<String, dynamic> _sourceJson({
  String origin = 'https://books.example',
  String name = '网络预览源',
}) => {
  'bookSourceUrl': origin,
  'bookSourceName': name,
  'header': {'Referer': '$origin/private'},
  'searchUrl': '/search?q={{key}}',
  'ruleSearch': {
    'bookList': '@CSS:.book',
    'name': '@CSS:a@text',
    'bookUrl': '@CSS:a@href',
  },
  'ruleToc': {
    'chapterList': '@CSS:a',
    'chapterName': '@text',
    'chapterUrl': '@href',
  },
  'ruleContent': {'content': '@CSS:article@html'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late _ImportController controller;
  late String input;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'source-ui-${DateTime.now().microsecondsSinceEpoch}',
    );
    input = jsonEncode([
      _sourceJson(),
      _sourceJson(origin: 'https://skip.example', name: '不导入的源')
        ..['loginUrl'] = 'https://skip.example/login',
    ]);
    controller = _ImportController(
      AppRepository(database),
      SourceEngine(),
      SourceImportPreview(
        sources: SourceImporter().parse(input),
        provenance: SourceImportProvenance(
          kind: SourceImportKind.url,
          requestedUri: Uri.parse('https://feed.example/source.json'),
          finalUri: Uri.parse('https://cdn.example/source.json'),
          responseBytes: utf8.encode(input).length,
          contentType: 'application/json; charset=utf-8',
        ),
      ),
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> openImportSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SourceImportSheet(controller: controller),
              ),
              child: const Text('打开导入'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('source-json')), input);
  }

  testWidgets('import sheet previews then commits only selected sources', (
    tester,
  ) async {
    await openImportSheet(tester);
    final sources = controller.preview.sources;

    expect(find.byKey(const Key('source-preview')), findsNothing);
    await tester.tap(find.byKey(const Key('source-import')));
    await tester.pumpAndSettle();

    expect(controller.calls, ['prepare']);
    expect(controller.committed, isFalse);
    expect(find.byKey(const Key('source-preview')), findsOneWidget);
    await tester.tap(
      find.byKey(Key('source-preview-select-${sources.last.id}')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-preview-import')));
    await tester.pumpAndSettle();

    expect(controller.calls, ['prepare', 'commit']);
    expect(controller.committed, isTrue);
    expect(controller.committedSourceIds, {sources.first.id});
    expect(find.byKey(const Key('source-json')), findsNothing);
  });

  testWidgets('atomic persistence disables cancellation after preparation', (
    tester,
  ) async {
    controller.pendingCommit = Completer<void>();
    await openImportSheet(tester);

    await tester.tap(find.byKey(const Key('source-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source-preview-import')));
    await tester.pump();

    expect(controller.calls, ['prepare', 'commit']);
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '取消'),
    );
    expect(cancel.onPressed, isNull);
    expect(find.text('正在保存书源…'), findsOneWidget);

    controller.pendingCommit!.complete();
    await tester.pumpAndSettle();
    expect(controller.committed, isTrue);
    expect(find.byKey(const Key('source-json')), findsNothing);
  });

  testWidgets('cancelling preparation never starts persistence', (
    tester,
  ) async {
    controller.pendingPreparation = Completer<void>();
    await openImportSheet(tester);

    await tester.tap(find.byKey(const Key('source-import')));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    controller.pendingPreparation!.complete();
    await tester.pumpAndSettle();

    expect(controller.calls, ['prepare']);
    expect(controller.committed, isFalse);
    expect(find.text('已取消导入书源。'), findsOneWidget);
    expect(find.byKey(const Key('source-import')), findsOneWidget);
  });

  testWidgets('commit failure keeps the import sheet and input visible', (
    tester,
  ) async {
    controller.commitError = StateError('保存失败');
    await openImportSheet(tester);

    await tester.tap(find.byKey(const Key('source-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source-preview-import')));
    await tester.pumpAndSettle();

    expect(controller.calls, ['prepare', 'commit']);
    expect(controller.committed, isFalse);
    expect(find.byKey(const Key('source-preview')), findsOneWidget);
    expect(find.byKey(const Key('source-error')), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
  });

  group('书源管理', _manageGroup);

  testWidgets('file import discloses the shared 100 MiB limit', (tester) async {
    await openImportSheet(tester);

    await tester.tap(find.byKey(const Key('source-mode-file')));
    await tester.pumpAndSettle();

    expect(find.text('最大 100 MiB，仅限 JSON。'), findsOneWidget);
  });
}

// ------------------------------------------------------------ 书源管理

Map<String, dynamic> _manageJson({
  required String url,
  required String name,
  String? group,
  bool? enabled,
  String? comment,
  String? explore,
}) => {
  'bookSourceUrl': url,
  'bookSourceName': name,
  'bookSourceGroup': ?group,
  'enabled': ?enabled,
  'bookSourceComment': ?comment,
  'exploreUrl': ?explore,
  'searchUrl': '/search?q={{key}}',
  'ruleSearch': {'bookList': '@CSS:.book', 'name': '@CSS:a@text'},
};

/// 真实控制器 + 内存库，用来测列表本身的行为（不替换任何方法）。
Future<AppController> _pumpManage(
  WidgetTester tester, {
  required List<Map<String, dynamic>> sources,
  Size size = const Size(1200, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  late final Database database;
  late final AppController manage;
  await tester.runAsync(() async {
    database = await databaseFactoryMemory.openDatabase(
      'manage-${DateTime.now().microsecondsSinceEpoch}',
    );
    manage = AppController(AppRepository(database), SourceEngine());
    await manage.initialize();
    await manage.importSources(jsonEncode(sources));
  });
  addTearDown(() async {
    manage.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SourcesScreen(controller: manage)),
    ),
  );
  await tester.pumpAndSettle();
  return manage;
}

Finder _name(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.data == name &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('source-name-'),
);

double _top(WidgetTester tester, String name) =>
    tester.getTopLeft(_name(name)).dy;

void _manageGroup() {
  testWidgets('a row shows its name, groups, status and address', (
    tester,
  ) async {
    await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://a.example', name: '甲书源', group: '玄幻,都市'),
        _manageJson(
          url: 'https://b.example',
          name: '乙书源',
          enabled: false,
          comment: '备用',
        ),
      ],
    );

    expect(_name('甲书源'), findsOneWidget);
    expect(find.text('https://a.example'), findsOneWidget);
    expect(find.text('玄幻'), findsOneWidget);
    expect(find.text('都市'), findsOneWidget);
    expect(find.text('已启用 · 无发现规则'), findsOneWidget);
    expect(find.text('已停用 · 不参与搜索与换源'), findsOneWidget);
    expect(find.text('备用'), findsOneWidget);
    expect(find.text('2 个'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search matches name, address and group, then clears', (
    tester,
  ) async {
    await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://alpha.example', name: '阿尔法', group: '玄幻'),
        _manageJson(url: 'https://beta.example', name: '贝塔', group: '都市'),
      ],
    );

    await tester.tap(find.byKey(const Key('source-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('source-search')), '贝塔');
    await tester.pumpAndSettle();
    expect(_name('贝塔'), findsOneWidget);
    expect(_name('阿尔法'), findsNothing);

    await tester.enterText(find.byKey(const Key('source-search')), 'alpha');
    await tester.pumpAndSettle();
    expect(_name('阿尔法'), findsOneWidget);
    expect(_name('贝塔'), findsNothing);

    await tester.enterText(find.byKey(const Key('source-search')), '都市');
    await tester.pumpAndSettle();
    expect(_name('贝塔'), findsOneWidget);
    expect(_name('阿尔法'), findsNothing);

    await tester.enterText(find.byKey(const Key('source-search')), '找不到');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的书源'), findsOneWidget);
    await tester.tap(find.byKey(const Key('source-clear-filter')));
    await tester.pumpAndSettle();
    expect(_name('阿尔法'), findsOneWidget);
    expect(_name('贝塔'), findsOneWidget);

    // 收起搜索框后不应再留下筛选条件。
    await tester.tap(find.byKey(const Key('source-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-search')), findsNothing);
    expect(_name('阿尔法'), findsOneWidget);
    expect(_name('贝塔'), findsOneWidget);
  });

  testWidgets('the group filter narrows the list and 全部 restores it', (
    tester,
  ) async {
    await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://a.example', name: '甲书源', group: '玄幻'),
        _manageJson(url: 'https://b.example', name: '乙书源', group: '都市'),
      ],
    );

    // 分组筛选是顶栏按钮 + 面板（legado 的 showGroupFilterSheet），不是平铺 chips。
    await tester.tap(find.byKey(const Key('source-group-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source-group-都市')));
    await tester.pumpAndSettle();
    expect(_name('乙书源'), findsOneWidget);
    expect(_name('甲书源'), findsNothing);
    expect(find.text('1 / 2 个'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-group-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source-group-all')));
    await tester.pumpAndSettle();
    expect(_name('甲书源'), findsOneWidget);
    expect(_name('乙书源'), findsOneWidget);
    expect(find.text('2 个'), findsOneWidget);
  });

  testWidgets('health tags never become group filters', (tester) async {
    // 校验结论写进 bookSourceGroup（legado 也这么做），但它们不是用户选的分组：
    // 让它们出现在筛选行里，等于允许用户按「坏掉了」浏览。
    await _pumpManage(
      tester,
      sources: [
        _manageJson(
          url: 'https://a.example',
          name: '甲书源',
          group: '玄幻,搜索链接规则为空,校验超时',
        ),
        _manageJson(url: 'https://b.example', name: '乙书源', group: '都市,搜索失效'),
      ],
    );

    await tester.tap(find.byKey(const Key('source-group-filter')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-group-玄幻')), findsOneWidget);
    expect(find.byKey(const Key('source-group-都市')), findsOneWidget);
    expect(find.byKey(const Key('source-group-搜索链接规则为空')), findsNothing);
    expect(find.byKey(const Key('source-group-校验超时')), findsNothing);
    expect(find.byKey(const Key('source-group-搜索失效')), findsNothing);
  });

  testWidgets('置顶 moves the chosen source above the others', (tester) async {
    final manage = await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://a.example', name: '甲书源'),
        _manageJson(url: 'https://b.example', name: '乙书源'),
        _manageJson(url: 'https://c.example', name: '丙书源'),
      ],
    );
    expect(_top(tester, '丙书源'), greaterThan(_top(tester, '甲书源')));

    await tester.tap(find.byKey(const Key('source-menu-https://c.example')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();

    final moved = manage.sources.firstWhere(
      (source) => source.id == 'https://c.example',
    );
    expect(moved.customOrder, lessThan(0));
    expect(_top(tester, '丙书源'), lessThan(_top(tester, '甲书源')));
    expect(_top(tester, '丙书源'), lessThan(_top(tester, '乙书源')));
    final stored = await tester.runAsync(() => manage.repository.sources());
    expect(
      stored!
          .firstWhere((source) => source.id == 'https://c.example')
          .customOrder,
      moved.customOrder,
    );
  });

  testWidgets('the discover switch in the row menu flips enabledExplore', (
    tester,
  ) async {
    final manage = await _pumpManage(
      tester,
      sources: [
        _manageJson(
          url: 'https://a.example',
          name: '甲书源',
          explore: '玄幻::/xuanhuan',
        ),
      ],
    );
    expect(manage.sources.single.enabledExplore, isTrue);

    await tester.tap(find.byKey(const Key('source-menu-https://a.example')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭发现'));
    await tester.pumpAndSettle();

    expect(manage.sources.single.enabledExplore, isFalse);
    expect(find.text('已启用 · 不参与发现'), findsOneWidget);
  });

  testWidgets('batch delete removes exactly the selected sources', (
    tester,
  ) async {
    final manage = await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://a.example', name: '甲书源'),
        _manageJson(url: 'https://b.example', name: '乙书源'),
        _manageJson(url: 'https://c.example', name: '丙书源'),
      ],
    );

    await tester.tap(find.byKey(const Key('source-select-mode')));
    await tester.pumpAndSettle();
    await tester.tap(_name('甲书源'));
    await tester.pumpAndSettle();
    await tester.tap(_name('丙书源'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 个书源'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-batch-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();

    expect([for (final source in manage.sources) source.name], ['乙书源']);
    expect(_name('甲书源'), findsNothing);
    expect(_name('丙书源'), findsNothing);
    expect(_name('乙书源'), findsOneWidget);
    final stored = await tester.runAsync(() => manage.repository.sources());
    expect([for (final source in stored!) source.name], ['乙书源']);
  });

  testWidgets('long-press enters multi-select and 反选 inverts it', (
    tester,
  ) async {
    await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://a.example', name: '甲书源'),
        _manageJson(url: 'https://b.example', name: '乙书源'),
      ],
    );

    await tester.longPress(_name('甲书源'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 个书源'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-select-invert')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 个书源'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 个书源'), findsOneWidget);
  });

  testWidgets('batch enable and disable update every selected source', (
    tester,
  ) async {
    final manage = await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://a.example', name: '甲书源'),
        _manageJson(url: 'https://b.example', name: '乙书源'),
      ],
    );

    await tester.tap(find.byKey(const Key('source-select-mode')));
    await tester.pumpAndSettle();
    await tester.tap(_name('甲书源'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source-batch-disable')));
    await tester.pumpAndSettle();

    expect(manage.sources.every((source) => !source.enabled), isFalse);
    expect(manage.sources.where((source) => !source.enabled).length, 1);
    expect(find.text('已停用 · 不参与搜索与换源'), findsOneWidget);
  });

  testWidgets('export copies a JSON array holding every source', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://a.example', name: '甲书源', group: '玄幻'),
        _manageJson(url: 'https://b.example', name: '乙书源'),
      ],
    );

    await tester.tap(find.byKey(const Key('source-export')));
    await tester.pumpAndSettle();

    final decoded = jsonDecode(copied!) as List;
    expect(decoded, hasLength(2));
    expect(
      [for (final entry in decoded) (entry as Map)['bookSourceName']],
      ['甲书源', '乙书源'],
    );
    expect(find.text('已复制 2 个书源的 JSON，可粘贴到其他阅读客户端。'), findsOneWidget);
  });

  testWidgets('editing from a row renames it in place', (tester) async {
    final manage = await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://a.example', name: '甲书源'),
        _manageJson(url: 'https://b.example', name: '乙书源'),
      ],
    );

    await tester.tap(find.byKey(const Key('source-edit-https://a.example')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('source-edit-name')), '甲书源改名');
    await tester.tap(find.byKey(const Key('source-edit-save')));
    await tester.pumpAndSettle();

    expect(_name('甲书源改名'), findsOneWidget);
    expect(_name('甲书源'), findsNothing);
    expect(manage.sources.first.name, '甲书源改名');
    final stored = await tester.runAsync(() => manage.repository.sources());
    expect(stored!.map((source) => source.name), contains('甲书源改名'));
  });

  testWidgets('a rejected address keeps the sheet open and the row unchanged', (
    tester,
  ) async {
    await _pumpManage(
      tester,
      sources: [_manageJson(url: 'https://a.example', name: '甲书源')],
    );

    await tester.tap(find.byKey(const Key('source-edit-https://a.example')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-edit-url')),
      'not-a-url',
    );
    await tester.tap(find.byKey(const Key('source-edit-save')));
    await tester.pumpAndSettle();

    expect(find.text('bookSourceUrl 必须是无账号密码的 HTTP(S) 地址。'), findsOneWidget);
    expect(find.byKey(const Key('source-edit-save')), findsOneWidget);
  });

  testWidgets('删除 asks first and then drops the source', (tester) async {
    final manage = await _pumpManage(
      tester,
      sources: [
        _manageJson(url: 'https://a.example', name: '甲书源'),
        _manageJson(url: 'https://b.example', name: '乙书源'),
      ],
    );

    await tester.tap(find.byKey(const Key('source-menu-https://a.example')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(manage.sources, hasLength(2));

    await tester.tap(find.byKey(const Key('source-menu-https://a.example')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();

    expect([for (final source in manage.sources) source.name], ['乙书源']);
  });

  testWidgets('a phone-width layout still lists and reaches 检查书源', (
    tester,
  ) async {
    await _pumpManage(
      tester,
      sources: [_manageJson(url: 'https://a.example', name: '甲书源')],
      size: const Size(390, 844),
    );

    await tester.scrollUntilVisible(
      find.text('检查书源'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('检查书源'));
    await tester.pumpAndSettle();

    expect(find.text('书源健康检查'), findsOneWidget);
    expect(find.text('开始检查'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
