import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/services/source_import_service.dart';
import 'package:sembast/sembast_memory.dart';

class _ConcurrencySourceEngine extends SourceEngine {
  int active = 0;
  int peak = 0;
  int started = 0;

  @override
  Future<List<Book>> search(
    BookSource source,
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    started++;
    active++;
    if (active > peak) peak = active;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    active--;
    return [];
  }
}

Map<String, dynamic> _searchSource(int index) => {
  'bookSourceUrl': 'https://source-$index.example',
  'bookSourceName': 'Source $index',
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
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'controller-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test('loads an offline shelf and a separate six-book catalogue', () {
    expect(controller.books, hasLength(3));
    expect(controller.catalog, hasLength(6));
    expect(controller.sources, isEmpty);
  });

  test('adding a catalogue book twice never resets progress', () async {
    final candidate = controller.catalog.last;
    await controller.addBook(candidate);
    await controller.savePosition(
      candidate.id,
      const ReadingPosition(chapterIndex: 1, paragraphIndex: 1),
    );
    await controller.addBook(candidate);
    expect(controller.books, hasLength(4));
    expect(controller.book(candidate.id)!.position.paragraphIndex, 1);
  });

  test('cached chapters can be read without any source or network', () async {
    final book = controller.books.first;
    expect((await controller.chapter(book.id, 0)).paragraphs, isNotEmpty);
  });

  test('TXT imports become durable shelf books', () async {
    final book = await controller.importText(
      Uint8List.fromList(utf8.encode('导入的正文。')),
      '我的书.txt',
    );
    expect(controller.book(book.id)!.title, '我的书');
    expect(await controller.repository.books(), hasLength(4));
  });

  test('URL import preview remains read-only until explicit commit', () async {
    controller.dispose();
    final service = SourceImportService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'bookSourceUrl': 'https://network.example',
            'bookSourceName': '网络导入源',
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
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    controller = AppController(
      AppRepository(database),
      SourceEngine(),
      sourceImportService: service,
    );
    await controller.initialize();

    final preview = await controller.prepareSourceImport(
      SourceImportInput.url(Uri.parse('https://feed.example/source.json')),
    );
    expect(preview.sources.single.name, '网络导入源');
    expect(controller.sources, isEmpty);
    expect(await controller.repository.sources(), isEmpty);

    final result = await controller.commitSourceImport(preview);
    expect(result.added, 1);
    expect(result.updated, 0);
    expect(controller.sources.single.name, '网络导入源');
    expect((await controller.repository.sources()).single.name, '网络导入源');
  });

  test('multi-source search runs at most four sources concurrently', () async {
    controller.dispose();
    final engine = _ConcurrencySourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([
        for (var index = 0; index < 7; index++) _searchSource(index),
      ]),
    );

    final groups = await controller.searchSources('测试');

    expect(groups, hasLength(7));
    expect(engine.peak, 4);
  });

  test('cancelling search prevents queued sources from starting', () async {
    controller.dispose();
    final engine = _ConcurrencySourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([
        for (var index = 0; index < 20; index++) _searchSource(index),
      ]),
    );
    final abort = Completer<void>();

    final pending = controller.searchSources('测试', abortTrigger: abort.future);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    abort.complete();
    final groups = await pending;

    expect(engine.started, 4);
    expect(groups, hasLength(4));
  });

  test('stale toggle does not resurrect a deleted source', () async {
    await controller.importSources(
      jsonEncode({
        'bookSourceUrl': 'https://fixture.example',
        'bookSourceName': 'Fixture',
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
      }),
    );
    final stale = controller.sources.single;
    await controller.deleteSource(stale.id);
    await controller.setSourceEnabled(stale, false);
    expect(controller.sources, isEmpty);
    expect(await controller.repository.sources(), isEmpty);
  });

  test('settings and bookmark actions update durable state', () async {
    await controller.updateSettings(
      const ReaderSettings(theme: ReaderTheme.dark, fontSize: 28),
    );
    expect(controller.settings.fontSize, 28);
    final book = controller.books.first;
    final note = Bookmark(
      id: 'note',
      bookId: book.id,
      chapterIndex: 0,
      paragraphIndex: 0,
      quote: '记下来',
      note: '一条笔记',
      createdAt: DateTime.now(),
    );
    await controller.addBookmark(note);
    expect(controller.bookmarks.single.note, '一条笔记');
    await controller.deleteBookmark('note');
    expect(controller.bookmarks, isEmpty);
  });
}
