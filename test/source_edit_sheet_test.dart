import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/source_edit_sheet.dart';
import 'package:sembast/sembast_memory.dart';

Map<String, dynamic> _sourceJson({
  String url = 'https://books.example',
  String name = '示例书源',
}) => {
  'bookSourceUrl': url,
  'bookSourceName': name,
  'bookSourceType': 0,
  'bookSourceGroup': '玄幻,都市',
  'bookSourceComment': '自己写的规则',
  'searchUrl': '/search?q={{key}}',
  'ruleSearch': {
    'bookList': '@CSS:.book',
    'name': '@CSS:a@text',
    'bookUrl': '@CSS:a@href',
  },
  'ruleToc': {'chapterList': '@CSS:a', 'chapterName': '@text'},
  'ruleContent': {'content': '@CSS:article@html'},
  // 本项目不认识的 legado 字段，保存后必须原样保留。
  'loginUrl': 'https://books.example/login',
  'variableComment': '保留我',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'source-edit-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
    await controller.importSources(jsonEncode([_sourceJson()]));
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  BookSource stored() => controller.sources.single;

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SourceEditSheet(
                  controller: controller,
                  source: controller.sources.single,
                ),
              ),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('source-edit-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('base fields are pre-filled from the stored source', (
    tester,
  ) async {
    await openSheet(tester);

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('source-edit-name')))
          .controller!
          .text,
      '示例书源',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('source-edit-url')))
          .controller!
          .text,
      'https://books.example',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('source-edit-group')))
          .controller!
          .text,
      '玄幻,都市',
    );
    expect(
      tester.widget<Switch>(find.byKey(const Key('source-edit-enabled'))).value,
      isTrue,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('source-edit-enabled-explore')))
          .value,
      isTrue,
    );
  });

  testWidgets('saving rewrites scalar fields and keeps unknown legado keys', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(find.byKey(const Key('source-edit-name')), '改过的书源');
    await tester.enterText(
      find.byKey(const Key('source-edit-comment')),
      '新的备注',
    );
    await tester.enterText(find.byKey(const Key('source-edit-group')), '都市;科幻');
    await tester.tap(find.byKey(const Key('source-edit-enabled-explore')));
    await tester.pumpAndSettle();
    await save(tester);

    final saved = controller.sources.single;
    expect(saved.name, '改过的书源');
    expect(saved.comment, '新的备注');
    expect(saved.groups, ['都市', '科幻']);
    expect(saved.enabledExplore, isFalse);
    expect(saved.toJson()['loginUrl'], 'https://books.example/login');
    expect(saved.toJson()['variableComment'], '保留我');

    final stored = await tester.runAsync(() => controller.repository.sources());
    expect(stored!.single.name, '改过的书源');
  });

  testWidgets('editing a rule field rewrites only that field', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('source-edit-section-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rule-ruleSearch-bookList')),
      '@CSS:.item',
    );
    await save(tester);

    final rules = controller.sources.single.searchRules;
    expect(rules['bookList'], '@CSS:.item');
    expect(rules['name'], '@CSS:a@text');
  });

  testWidgets('a rejected URL keeps the sheet open with the Chinese message', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(find.byKey(const Key('source-edit-url')), 'ftp://x');
    await save(tester);

    expect(find.byKey(const Key('source-edit-error')), findsOneWidget);
    expect(find.text('bookSourceUrl 必须是无账号密码的 HTTP(S) 地址。'), findsOneWidget);
    expect(find.byKey(const Key('source-edit-save')), findsOneWidget);
    expect(controller.sources.single.id, 'https://books.example');
  });

  testWidgets('an empty name is rejected before it reaches the store', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(find.byKey(const Key('source-edit-name')), '   ');
    await save(tester);

    expect(find.byKey(const Key('source-edit-error')), findsOneWidget);
    expect(controller.sources.single.name, '示例书源');
  });

  testWidgets('changing the URL moves the record to the new key', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(
      find.byKey(const Key('source-edit-url')),
      'https://moved.example',
    );
    await save(tester);

    final ids = [for (final item in controller.sources) item.id];
    expect(ids, ['https://moved.example']);
    final stored = await tester.runAsync(() => controller.repository.sources());
    expect([for (final item in stored!) item.id], ['https://moved.example']);
  });

  testWidgets('advanced JSON rejects broken input with a Chinese hint', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('source-edit-section-6')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-edit-json')),
      '{"oops"',
    );
    await save(tester);

    expect(find.text('书源 JSON 无法解析，请检查括号与引号。'), findsOneWidget);
    expect(controller.sources.single.name, '示例书源');
  });

  testWidgets('advanced JSON can rewrite the whole source', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('source-edit-section-6')));
    await tester.pumpAndSettle();
    final json = stored().toJson()..['customOrder'] = 7;
    await tester.enterText(
      find.byKey(const Key('source-edit-json')),
      jsonEncode(json),
    );
    await save(tester);

    expect(controller.sources.single.customOrder, 7);
  });

  testWidgets('cancelling leaves the stored source untouched', (tester) async {
    await openSheet(tester);

    await tester.enterText(find.byKey(const Key('source-edit-name')), '不保存');
    await tester.tap(find.byKey(const Key('source-edit-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-edit-name')), findsNothing);
    expect(controller.sources.single.name, '示例书源');
  });
}
