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
        flow: ReaderFlow.scrolling,
        fontSize: 26,
        lineHeight: 2,
      ),
    );
    final fresh = AppRepository(database);
    expect((await fresh.settings()).theme, ReaderTheme.dark);
    expect((await fresh.settings()).flow, ReaderFlow.scrolling);
    expect((await fresh.settings()).fontSize, 26);
  });

  test('typography and directory order survive a fresh repository', () async {
    await repository.saveSettings(
      ReaderSettings.fromJson({
        'paragraphSpacing': 32,
        'boldText': true,
        'tocDescending': true,
      }),
    );
    final stored = (await AppRepository(database).settings()).toJson();
    expect(stored['paragraphSpacing'], 32);
    expect(stored['boldText'], isTrue);
    expect(stored['tocDescending'], isTrue);
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

  test('source switch replaces a book and its bookmarks atomically', () async {
    final current = Book(
      id: 'switch-book',
      title: '测试书',
      author: '作者',
      description: '',
      category: '测试',
      coverStyle: 0,
      sourceLabel: '旧源',
      sourceId: 'https://old.example',
      url: 'https://old.example/book',
      chapters: [
        Chapter(
          id: 'old-chapter',
          title: '第一章',
          url: 'https://old.example/chapter',
          paragraphs: const ['旧正文'],
        ),
      ],
      addedAt: DateTime.utc(2026),
    );
    final originalNote = Bookmark(
      id: 'switch-note',
      bookId: current.id,
      chapterIndex: 0,
      paragraphIndex: 0,
      quote: '旧正文',
      note: '保留',
      createdAt: DateTime.utc(2026),
    );
    await repository.saveBook(current);
    await repository.saveBookmark(originalNote);
    final replacement = Book(
      id: current.id,
      title: current.title,
      author: current.author,
      description: current.description,
      category: current.category,
      coverStyle: current.coverStyle,
      sourceLabel: '新源',
      sourceId: 'https://new.example',
      url: 'https://new.example/book',
      chapters: [
        Chapter(
          id: 'new-chapter',
          title: '第一章',
          url: 'https://new.example/chapter',
        ),
      ],
      addedAt: current.addedAt,
    );
    final mappedNote = originalNote.copyWithPosition(
      chapterIndex: 0,
      paragraphIndex: 3,
    );

    await repository.replaceBookSource(replacement, [mappedNote]);

    final restored = (await repository.books()).firstWhere(
      (book) => book.id == current.id,
    );
    expect(restored.sourceId, 'https://new.example');
    expect(
      (await repository.bookmarks())
          .firstWhere((note) => note.id == mappedNote.id)
          .paragraphIndex,
      3,
    );

    Iterable<Bookmark> throwingBookmarks() sync* {
      yield originalNote;
      throw StateError('rollback');
    }

    await expectLater(
      repository.replaceBookSource(current, throwingBookmarks()),
      throwsStateError,
    );
    expect(
      (await repository.books())
          .firstWhere((book) => book.id == current.id)
          .sourceId,
      'https://new.example',
    );
    expect(
      (await repository.bookmarks())
          .firstWhere((note) => note.id == mappedNote.id)
          .paragraphIndex,
      3,
    );
  });

  test('chapter caching rejects a stale source binding', () async {
    final book = Book(
      id: 'cache-book',
      title: '测试书',
      author: '作者',
      description: '',
      category: '测试',
      coverStyle: 0,
      sourceLabel: '新源',
      sourceId: 'https://new.example',
      url: 'https://new.example/book',
      chapters: [
        Chapter(
          id: 'new-chapter',
          title: '第一章',
          url: 'https://new.example/chapter',
        ),
      ],
      addedAt: DateTime.utc(2026),
    );
    await repository.saveBook(book);

    final stale = await repository.cacheChapter(
      book.id,
      0,
      Chapter(
        id: 'old-chapter',
        title: '第一章',
        url: 'https://old.example/chapter',
        paragraphs: const ['旧正文'],
      ),
      expectedSourceId: 'https://old.example',
      expectedChapterId: 'old-chapter',
    );
    expect(stale, isFalse);
    expect(
      (await repository.books())
          .firstWhere((item) => item.id == book.id)
          .chapters
          .single
          .paragraphs,
      isEmpty,
    );

    final cached = await repository.cacheChapter(
      book.id,
      0,
      book.chapters.single.withParagraphs(const ['新正文']),
      expectedSourceId: 'https://new.example',
      expectedChapterId: 'new-chapter',
    );
    expect(cached, isTrue);
    expect(
      (await repository.books())
          .firstWhere((item) => item.id == book.id)
          .chapters
          .single
          .paragraphs,
      ['新正文'],
    );
  });

  test(
    'cover updates preserve progress and do not resurrect deleted books',
    () async {
      final original = (await repository.books()).first;
      await repository.savePosition(
        original.id,
        const ReadingPosition(chapterIndex: 1, paragraphIndex: 2),
      );
      final updated = await repository.updateBookCover(
        original.id,
        'https://books.example/new.png',
        expectedSourceId: original.sourceId,
      );
      expect(updated!.position.chapterIndex, 1);
      expect(updated.position.paragraphIndex, 2);
      expect(updated.coverUrl, 'https://books.example/new.png');
      await repository.removeBook(original.id);
      expect(
        await repository.updateBookCover(
          original.id,
          'https://books.example/late.png',
          expectedSourceId: original.sourceId,
        ),
        isNull,
      );
      await expectLater(
        repository.replaceBookSource(original, const []),
        throwsStateError,
      );
      expect(
        (await repository.books()).any((book) => book.id == original.id),
        isFalse,
      );
    },
  );

  test('source switching does not recreate a deleted bookmark', () async {
    final book = (await repository.books()).first;
    final deleted = Bookmark(
      id: 'deleted-during-switch',
      bookId: book.id,
      chapterIndex: 0,
      paragraphIndex: 0,
      quote: '文字',
      note: '已删除',
      createdAt: DateTime.utc(2026),
    );
    await repository.saveBookmark(deleted);
    await repository.deleteBookmark(deleted.id);
    await repository.replaceBookSource(book, [deleted]);
    expect(
      (await repository.bookmarks()).any((note) => note.id == deleted.id),
      isFalse,
    );
  });

  for (final changed in ['source', 'book URL', 'chapter']) {
    test('guarded progress rejects a changed $changed binding', () async {
      final original = (await repository.books()).first;
      final expected = Book.fromJson({
        ...original.toJson(),
        'sourceId': 'https://old.example',
        'url': 'https://old.example/book',
      });
      await repository.saveBook(expected);
      final changedJson = expected.toJson();
      switch (changed) {
        case 'source':
          changedJson['sourceId'] = 'https://new.example';
        case 'book URL':
          changedJson['url'] = 'https://old.example/another-book';
        case 'chapter':
          final chapters = [
            for (final chapter in expected.chapters) chapter.toJson(),
          ];
          chapters.first['id'] = 'replaced-chapter';
          changedJson['chapters'] = chapters;
      }
      final current = Book.fromJson(changedJson);
      await repository.saveBook(current);

      await expectLater(
        repository.savePosition(
          expected.id,
          const ReadingPosition(paragraphIndex: 2),
          finished: true,
          expectedBook: expected,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'binding failure',
            contains('阅读进度'),
          ),
        ),
      );

      final restored = (await repository.books()).firstWhere(
        (book) => book.id == expected.id,
      );
      expect(restored.toJson(), current.toJson());
    });
  }

  test(
    'guarded progress accepts an unchanged local binding with newer state',
    () async {
      final original = (await repository.books()).first;
      final refreshed = original.copyWith(
        chapters: [
          original.chapters.first.withParagraphs(const ['新缓存', '第二段', '第三段']),
          ...original.chapters.skip(1),
        ],
      );
      await repository.saveBook(refreshed);
      await repository.savePosition(
        original.id,
        const ReadingPosition(paragraphIndex: 2),
      );

      await repository.savePosition(
        original.id,
        const ReadingPosition(paragraphIndex: 1),
        expectedBook: original,
      );

      final restored = (await repository.books()).firstWhere(
        (book) => book.id == original.id,
      );
      expect(restored.position.paragraphIndex, 1);
      expect(restored.chapters.first.paragraphs, ['新缓存', '第二段', '第三段']);
    },
  );

  test(
    'guarded progress rejects deletion without resurrecting the book',
    () async {
      final original = (await repository.books()).first;
      await repository.removeBook(original.id);

      await expectLater(
        repository.savePosition(
          original.id,
          const ReadingPosition(),
          expectedBook: original,
        ),
        throwsStateError,
      );

      expect(
        (await repository.books()).any((book) => book.id == original.id),
        isFalse,
      );
    },
  );

  test('saving progress after deletion never resurrects the book', () async {
    final book = (await repository.books()).first;
    await repository.removeBook(book.id);
    await repository.savePosition(book.id, const ReadingPosition());
    expect((await repository.books()).any((b) => b.id == book.id), isFalse);
  });
}
