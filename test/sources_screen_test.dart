import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/services/source_importer.dart';
import 'package:read_pilot/ui/components/source_import_sheet.dart';
import 'package:sembast/sembast_memory.dart';

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

  testWidgets('import sheet prepares and commits all sources in one action', (
    tester,
  ) async {
    await openImportSheet(tester);

    expect(find.byKey(const Key('source-preview')), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byKey(const Key('source-import')));
    await tester.pumpAndSettle();

    expect(controller.calls, ['prepare', 'commit']);
    expect(controller.preparedInput, isA<SourceTextImportInput>());
    expect(controller.committed, isTrue);
    expect(controller.committedSourceIds, isNull);
    expect(find.byKey(const Key('source-json')), findsNothing);
  });

  testWidgets('atomic persistence disables cancellation after preparation', (
    tester,
  ) async {
    controller.pendingCommit = Completer<void>();
    await openImportSheet(tester);

    await tester.tap(find.byKey(const Key('source-import')));
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

    expect(controller.calls, ['prepare', 'commit']);
    expect(controller.committed, isFalse);
    expect(find.byKey(const Key('source-json')), findsOneWidget);
    expect(find.byKey(const Key('source-error')), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
  });
}
