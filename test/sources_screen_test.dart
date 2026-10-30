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

  @override
  Future<SourceImportPreview> prepareSourceImport(
    SourceImportInput input, {
    Future<void>? abortTrigger,
  }) async {
    preparedInput = input;
    return preview;
  }

  Set<String>? committedSourceIds;

  @override
  Future<SourceImportCommitResult> commitSourceImport(
    SourceImportPreview preview, {
    Set<String>? selectedSourceIds,
  }) async {
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

  testWidgets('import sheet previews before committing any source', (
    tester,
  ) async {
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
    await tester.tap(find.byKey(const Key('source-mode-url')));
    await tester.pump();
    expect(find.byKey(const Key('source-url')), findsOneWidget);
    await tester.tap(find.byKey(const Key('source-mode-text')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('source-json')), input);
    await tester.tap(find.byKey(const Key('source-prepare')));
    await tester.pumpAndSettle();

    expect(controller.preparedInput, isA<SourceTextImportInput>());
    expect(find.byKey(const Key('source-preview')), findsOneWidget);
    expect(
      find.textContaining('https://feed.example/source.json'),
      findsOneWidget,
    );
    expect(
      find.textContaining('https://cdn.example/source.json'),
      findsOneWidget,
    );
    expect(find.textContaining('最终地址来源已变化'), findsOneWidget);
    expect(find.textContaining('application/json'), findsOneWidget);
    expect(find.text('网络预览源'), findsOneWidget);
    expect(find.text('不导入的源'), findsOneWidget);
    expect(find.text('referer'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const Key('source-preview')),
        matching: find.textContaining('loginUrl'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('项能力需要后续实现'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('source-preview')),
        matching: find.textContaining('/private'),
      ),
      findsNothing,
    );
    expect(controller.committed, isFalse);

    final skippedSource = find.byKey(
      const Key('source-select-https://skip.example'),
    );
    await tester.ensureVisible(skippedSource);
    await tester.tap(skippedSource);
    await tester.pump();
    final commit = find.byKey(const Key('source-commit'));
    await tester.ensureVisible(commit);
    await tester.tap(commit);
    await tester.pumpAndSettle();

    expect(controller.committed, isTrue);
    expect(controller.committedSourceIds, {'https://books.example'});
    expect(find.byKey(const Key('source-preview')), findsNothing);
  });
}
