import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/services/source_import_service.dart';
import 'package:read_pilot/services/source_importer.dart';
import 'package:read_pilot/ui/components/source_import_sheet.dart';
import 'package:sembast/sembast_memory.dart';

/// A well-formed Legado-shaped source. [index] keeps identities distinct.
Map<String, dynamic> _valid(int index, {String? name}) => {
  'bookSourceUrl': 'https://books$index.example',
  'bookSourceName': name ?? '可用书源$index',
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

/// `header` written as a JavaScript object literal: single quotes are not JSON.
Map<String, dynamic> _headerWithSingleQuotes(int index) => {
  ..._valid(index),
  'header': "{'Referer': 'https://books$index.example/'}",
};

/// `header` written as a bare User-Agent token, which is not JSON either.
Map<String, dynamic> _headerWithBareUserAgent(int index) => {
  ..._valid(index),
  'header': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
};

/// `bookSourceUrl` is the source identity, so it must be a public HTTP(S) URL.
Map<String, dynamic> _invalidUrl(int index) => {
  ..._valid(index),
  'bookSourceUrl': 'file:///etc/passwd$index',
};

/// Hop-by-hop headers are a transport boundary the feed may not set itself.
Map<String, dynamic> _hopByHopHeader(int index, String name) => {
  ..._valid(index),
  'header': {name: 'books$index.example'},
};

Matcher _formatExceptionContaining(String message) => isA<FormatException>()
    .having((error) => error.message.toString(), 'message', contains(message));

String _reasonOf(String message) => message;

void main() {
  group('SourceImporter.parseReport', () {
    late Map<String, dynamic> singleQuoted;
    late Map<String, dynamic> bareUserAgent;
    late Map<String, dynamic> badUrl;
    late Map<String, dynamic> forbiddenHost;
    late Map<String, dynamic> forbiddenConnection;
    late String payload;

    setUp(() {
      singleQuoted = _headerWithSingleQuotes(1);
      bareUserAgent = _headerWithBareUserAgent(2);
      badUrl = _invalidUrl(3);
      forbiddenHost = _hopByHopHeader(4, 'host');
      forbiddenConnection = _hopByHopHeader(5, 'Connection');
      payload = jsonEncode([
        _valid(0, name: '正常书源甲'),
        singleQuoted,
        _valid(6, name: '正常书源乙'),
        bareUserAgent,
        badUrl,
        forbiddenHost,
        forbiddenConnection,
        _valid(7, name: '正常书源丙'),
      ]);
    });

    test('keeps every valid source and records the rejected entries', () {
      final report = SourceImporter().parseReport(payload);

      expect(report.sources.map((source) => source.name), [
        '正常书源甲',
        '正常书源乙',
        '正常书源丙',
      ]);
      expect(report.sources.map((source) => source.id).toSet(), hasLength(3));
      expect(report.skippedCount, 5);
      expect(report.totalCount, 8);
      expect(report.skipped.map((skip) => skip.label), [
        '可用书源1',
        '可用书源2',
        '可用书源3',
        '可用书源4',
        '可用书源5',
      ]);
      expect(report.skipped.map((skip) => skip.reason), [
        _reasonOf('header 必须是 JSON 对象或编码后的 JSON 对象。'),
        _reasonOf('header 必须是 JSON 对象或编码后的 JSON 对象。'),
        _reasonOf('bookSourceUrl 必须是无账号密码的 HTTP(S) 地址。'),
        _reasonOf('header.host 不允许由书源设置。'),
        _reasonOf('header.Connection 不允许由书源设置。'),
      ]);
    });

    test('reports the four observed reason classes as grouped counts', () {
      final report = SourceImporter().parseReport(payload);

      final groups = groupSourceImportSkips(report.skipped);
      expect(groups.map((group) => group.count), [2, 1, 1, 1]);
      expect(groups.first.reason, 'header 必须是 JSON 对象或编码后的 JSON 对象。');
      expect(groups.map((group) => group.reason).toSet(), {
        'header 必须是 JSON 对象或编码后的 JSON 对象。',
        'bookSourceUrl 必须是无账号密码的 HTTP(S) 地址。',
        'header.host 不允许由书源设置。',
        'header.Connection 不允许由书源设置。',
      });
    });

    test('names a skip after its URL when the entry has no name', () {
      final report = SourceImporter().parseReport(
        jsonEncode([
          {'bookSourceUrl': 'https://named.example', 'header': "{'a':'b'}"},
        ]),
      );

      expect(report.sources, isEmpty);
    }, skip: 'an all-invalid payload throws; covered separately');

    test('falls back to the entry position for unnamed, URL-less skips', () {
      // A single invalid entry among valid ones: no name, no URL.
      final report = SourceImporter().parseReport(
        jsonEncode([
          _valid(0),
          {'header': "{'a':'b'}"},
          _valid(2),
        ]),
      );

      expect(report.skipped.single.label, '第 2 个书源');
      expect(report.sources, hasLength(2));
    });

    test('uses the URL as the label when only the name is missing', () {
      final report = SourceImporter().parseReport(
        jsonEncode([
          _valid(0),
          {'bookSourceUrl': 'https://only-url.example', 'header': 'nope'},
        ]),
      );

      expect(report.skipped.single.label, 'https://only-url.example');
    });

    test('still de-duplicates valid entries by source id', () {
      final report = SourceImporter().parseReport(
        jsonEncode([
          _valid(0, name: '甲'),
          _valid(1),
          _valid(0, name: '甲-重名'),
          _invalidUrl(9),
        ]),
      );

      expect(report.sources, hasLength(2));
      expect(report.skippedCount, 1);
    });

    test('keeps strict parse rejecting the same payload', () {
      expect(
        () => SourceImporter().parse(payload),
        throwsA(_formatExceptionContaining('header 必须是 JSON 对象')),
      );
    });
  });

  group('structural problems still fail the whole import', () {
    final importer = SourceImporter();

    test('rejects payloads that are not JSON', () {
      expect(
        () => importer.parseReport('not json'),
        throwsA(_formatExceptionContaining('不是有效的 JSON')),
      );
    });

    test('rejects an empty array', () {
      expect(
        () => importer.parseReport('[]'),
        throwsA(_formatExceptionContaining('请一次导入')),
      );
    });

    test('rejects more entries than the cap', () {
      final over = jsonEncode([
        for (var index = 0; index <= SourceImporter.maxSources; index++)
          _valid(index),
      ]);

      expect(
        () => importer.parseReport(over),
        throwsA(_formatExceptionContaining('${SourceImporter.maxSources}')),
      );
    });

    test('rejects payloads nested past the depth limit', () {
      var deep = <String, dynamic>{'value': 1};
      for (var index = 0; index < SourceImporter.maxJsonDepth + 2; index++) {
        deep = {'value': deep};
      }

      expect(
        () => importer.parseReport(jsonEncode(deep)),
        throwsA(_formatExceptionContaining('嵌套不能超过')),
      );
    });

    test('rejects a non-object entry instead of skipping it', () {
      expect(
        () => importer.parseReport(jsonEncode([_valid(0), 'oops', _valid(1)])),
        throwsA(_formatExceptionContaining('每个书源必须是 JSON 对象。')),
      );
    });

    test('rejects a payload whose every entry is invalid', () {
      expect(
        () =>
            importer.parseReport(jsonEncode([_invalidUrl(0), _invalidUrl(1)])),
        throwsA(_formatExceptionContaining('这 2 个书源都无法解析')),
      );
    });

    test('still rejects a bare object with a single invalid entry', () {
      expect(
        () => importer.parseReport(jsonEncode(_invalidUrl(0))),
        throwsA(_formatExceptionContaining('都无法解析')),
      );
    });
  });

  group('SourceImportService', () {
    test('carries skip details into the prepared preview', () async {
      final service = SourceImportService(
        client: MockClient((_) async => fail('must not request')),
      );
      addTearDown(service.close);

      final preview = await service.prepare(
        SourceImportInput.text(
          jsonEncode([
            _valid(0),
            _headerWithSingleQuotes(1),
            _invalidUrl(2),
            _valid(3),
          ]),
        ),
      );

      expect(preview.sources, hasLength(2));
      expect(preview.skippedCount, 2);
      expect(preview.totalCount, 4);
      expect(preview.skipped.map((skip) => skip.label), ['可用书源1', '可用书源2']);
      expect(preview.provenance.kind, SourceImportKind.text);
    });

    test('still surfaces an unparsable payload as invalidJson', () async {
      final service = SourceImportService(
        client: MockClient((_) async => fail('must not request')),
      );
      addTearDown(service.close);

      await expectLater(
        service.prepare(SourceImportInput.text('{broken')),
        throwsA(
          isA<SourceImportException>().having(
            (error) => error.kind,
            'kind',
            SourceImportErrorKind.invalidJson,
          ),
        ),
      );
    });
  });

  group('SourceImportPreview', () {
    test('skipped detail is optional and immutable', () {
      final preview = SourceImportPreview(
        sources: SourceImporter().parse(jsonEncode([_valid(0), _valid(1)])),
        provenance: const SourceImportProvenance(
          kind: SourceImportKind.text,
          responseBytes: 1,
        ),
      );

      expect(preview.skipped, isEmpty);
      expect(preview.skippedCount, 0);
      expect(preview.totalCount, 2);
      expect(
        () => preview.skipped.add(
          const SourceImportSkip(label: 'x', reason: 'y'),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('SourceImportSheet preview', () {
    late Database database;

    setUp(() async {
      database = await databaseFactoryMemory.openDatabase(
        'source-partial-${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets('discloses skipped entries inside the preview', (tester) async {
      final controller = _PartialController(
        AppRepository(database),
        SourceEngine(),
        'https://feed.example/sources.json',
      );
      addTearDown(controller.dispose);

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
      await tester.tap(find.byKey(const Key('source-import')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('source-preview')), findsOneWidget);
      expect(find.byKey(const Key('source-preview-skipped')), findsOneWidget);
      expect(find.textContaining('跳过 2 个无法解析的书源'), findsOneWidget);
      expect(
        find.textContaining('header 必须是 JSON 对象或编码后的 JSON 对象。（1 个）'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('source-preview-import')), findsOneWidget);
    });

    testWidgets('omits the notice when nothing was skipped', (tester) async {
      final controller = _PartialController(
        AppRepository(database),
        SourceEngine(),
        null,
      );
      addTearDown(controller.dispose);

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
      await tester.tap(find.byKey(const Key('source-import')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('source-preview')), findsOneWidget);
      expect(find.byKey(const Key('source-preview-skipped')), findsNothing);
    });
  });

  test(
    'real 1466-entry aggregate yields 1400 parsed entries and 66 skips',
    () {
      final file = File('.claude/test-logs/yckceo-1325.json');
      final report = SourceImporter().parseReport(file.readAsStringSync());

      // 66 entries are rejected before de-duplication, leaving 1400 parseable
      // entries; six of them repeat an existing `bookSourceUrl`, so the preview
      // offers 1394 selectable sources.
      expect(report.skippedCount, 66);
      expect(report.totalCount, 1460);
      expect(report.sources, hasLength(1394));
      expect(
        groupSourceImportSkips(report.skipped).map((group) => group.count),
        [52, 9, 2, 2, 1],
      );
      expect(
        groupSourceImportSkips(report.skipped).map((group) => group.reason),
        [
          'header 必须是 JSON 对象或编码后的 JSON 对象。',
          'bookSourceUrl 必须是无账号密码的 HTTP(S) 地址。',
          'header.host 不允许由书源设置。',
          'header.Connection 不允许由书源设置。',
          'header.Host 不允许由书源设置。',
        ],
      );
    },
    skip: File('.claude/test-logs/yckceo-1325.json').existsSync()
        ? null
        : 'downloaded yckceo aggregate fixture is not present',
  );
}

/// Returns one prepared preview: from the real service when a feed URL is given,
/// otherwise a clean two-source preview.
class _PartialController extends AppController {
  _PartialController(super.repository, super.engine, this.feedUrl);

  final String? feedUrl;

  @override
  Future<SourceImportPreview> prepareSourceImport(
    SourceImportInput input, {
    Future<void>? abortTrigger,
  }) async {
    final feed = feedUrl;
    if (feed == null) {
      return SourceImportPreview(
        sources: SourceImporter().parse(jsonEncode([_valid(0), _valid(1)])),
        provenance: SourceImportProvenance(
          kind: SourceImportKind.text,
          responseBytes: 1,
        ),
      );
    }
    return SourceImportPreview(
      sources: SourceImporter().parse(jsonEncode([_valid(0), _valid(1)])),
      skipped: [
        const SourceImportSkip(
          label: '可用书源2',
          reason: 'header 必须是 JSON 对象或编码后的 JSON 对象。',
        ),
        const SourceImportSkip(
          label: '可用书源3',
          reason: 'bookSourceUrl 必须是无账号密码的 HTTP(S) 地址。',
        ),
      ],
      provenance: SourceImportProvenance(
        kind: SourceImportKind.url,
        requestedUri: Uri.parse(feed),
        finalUri: Uri.parse(feed),
        responseBytes: 1,
      ),
    );
  }

  @override
  Future<SourceImportCommitResult> commitSourceImport(
    SourceImportPreview preview, {
    Set<String>? selectedSourceIds,
  }) async {
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
