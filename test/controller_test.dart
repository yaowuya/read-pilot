import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

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
