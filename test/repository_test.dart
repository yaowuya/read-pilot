import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/services/source_importer.dart';
import 'package:sembast/sembast_memory.dart';

Map<String, dynamic> _sourceJson({
  String origin = 'https://source.example',
  String name = '导入源',
}) => {
  'bookSourceUrl': origin,
  'bookSourceName': name,
  'enabled': true,
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
  late AppRepository repository;
  late Database database;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'test-${DateTime.now().microsecondsSinceEpoch}',
    );
    repository = AppRepository(database);
    await repository.initialize();
  });

  tearDown(() => database.close());

  test('first run seeds three books exactly once', () async {
    expect(await repository.books(), hasLength(3));
    await repository.initialize();
    expect(await repository.books(), hasLength(3));
  });

  test('removing all books does not reseed on next initialization', () async {
    for (final book in await repository.books()) {
      await repository.removeBook(book.id);
    }
    await repository.initialize();
    expect(await repository.books(), isEmpty);
  });

  test(
    'reading position is durable without replacing cached chapters',
    () async {
      final book = (await repository.books()).first;
      await repository.savePosition(
        book.id,
        const ReadingPosition(chapterIndex: 1, paragraphIndex: 2),
      );
      final restored = (await repository.books()).firstWhere(
        (b) => b.id == book.id,
      );
      expect(restored.position.chapterIndex, 1);
      expect(restored.position.paragraphIndex, 2);
      expect(
        restored.chapters.first.paragraphs,
        book.chapters.first.paragraphs,
      );
      expect(restored.lastOpenedAt, isNotNull);
    },
  );

  test('preferences survive a fresh repository instance', () async {
    await repository.saveSettings(
      const ReaderSettings(
        theme: ReaderTheme.dark,
        fontSize: 26,
        lineHeight: 2,
      ),
    );
    final fresh = AppRepository(database);
    expect((await fresh.settings()).theme, ReaderTheme.dark);
    expect((await fresh.settings()).fontSize, 26);
  });

  test('notes are stored with anchors and removed with their book', () async {
    final book = (await repository.books()).first;
    await repository.saveBookmark(
      Bookmark(
        id: 'bookmark-1',
        bookId: book.id,
        chapterIndex: 0,
        paragraphIndex: 1,
        quote: '公版文字',
        note: '我的笔记',
        createdAt: DateTime.now(),
      ),
    );
    expect((await repository.bookmarks()).single.note, '我的笔记');
    await repository.removeBook(book.id);
    expect(await repository.bookmarks(), isEmpty);
  });

  test(
    'source import commit is atomic and preserves a disabled source',
    () async {
      final importer = SourceImporter();
      final first = SourceImportPreview(
        sources: importer.parse(jsonEncode(_sourceJson())),
        provenance: SourceImportProvenance(
          kind: SourceImportKind.url,
          requestedUri: Uri.parse('https://feed.example/sources.json'),
          finalUri: Uri.parse('https://cdn.example/sources.json'),
          responseBytes: 512,
          contentType: 'application/json',
        ),
      );

      final added = await repository.commitSourceImport(first);
      expect(added.added, 1);
      expect(added.updated, 0);
      expect((await repository.sources()).single.name, '导入源');
      final state = await repository.sourceState('https://source.example');
      expect(state, isNotNull);
      expect(state!.kind, SourceImportKind.url);
      expect(state.requestedUri, first.provenance.requestedUri);
      expect(state.finalUri, first.provenance.finalUri);

      await repository.setSourceEnabled('https://source.example', false);
      final second = SourceImportPreview(
        sources: importer.parse(jsonEncode(_sourceJson(name: '更新后的源'))),
        provenance: const SourceImportProvenance(
          kind: SourceImportKind.text,
          responseBytes: 256,
        ),
      );
      final updated = await repository.commitSourceImport(second);

      expect(updated.added, 0);
      expect(updated.updated, 1);
      final restored = (await repository.sources()).single;
      expect(restored.name, '更新后的源');
      expect(restored.enabled, isFalse);
    },
  );

  test('source import selection controls records and sidecar state', () async {
    final importer = SourceImporter();
    final preview = SourceImportPreview(
      sources: importer.parse(
        jsonEncode([
          _sourceJson(origin: 'https://first.example', name: '第一个源'),
          _sourceJson(origin: 'https://second.example', name: '第二个源'),
        ]),
      ),
      provenance: const SourceImportProvenance(
        kind: SourceImportKind.file,
        label: 'sources.json',
        responseBytes: 1024,
      ),
    );

    final result = await repository.commitSourceImport(
      preview,
      selectedSourceIds: {'https://second.example'},
    );

    expect(result.total, 1);
    expect(result.sourceIds, ['https://second.example']);
    expect((await repository.sources()).single.name, '第二个源');
    expect(await repository.sourceState('https://first.example'), isNull);
    expect(await repository.sourceState('https://second.example'), isNotNull);

    await repository.deleteSource('https://second.example');
    expect(await repository.sources(), isEmpty);
    expect(await repository.sourceState('https://second.example'), isNull);
  });

  test('saving progress after deletion never resurrects the book', () async {
    final book = (await repository.books()).first;
    await repository.removeBook(book.id);
    await repository.savePosition(book.id, const ReadingPosition());
    expect((await repository.books()).any((b) => b.id == book.id), isFalse);
  });
}
