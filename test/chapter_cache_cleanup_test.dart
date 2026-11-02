import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

Book _remoteBook({String sourceId = 'https://source.example'}) => Book(
  id: 'cleanup-book',
  title: '测试书',
  author: '作者',
  description: '',
  category: '文学',
  coverStyle: 0,
  sourceLabel: '书源',
  sourceId: sourceId,
  url: '$sourceId/book',
  addedAt: DateTime.utc(2026),
  position: const ReadingPosition(chapterIndex: 1, paragraphIndex: 0),
  chapters: [
    for (var index = 0; index < 6; index++)
      Chapter(
        id: 'chapter-$index',
        title: '第${index + 1}章',
        url: '$sourceId/chapter/$index',
        paragraphs: index == 4 ? const [] : ['正文 $index'],
      ),
  ],
);

class _PausedCleanupRepository extends AppRepository {
  _PausedCleanupRepository(super.database);

  final started = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<Book> clearCachedChapters(Book expectedBook, List<int> indices) async {
    started.complete();
    await resume.future;
    return super.clearCachedChapters(expectedBook, indices);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppRepository repository;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'cache-cleanup-${DateTime.now().microsecondsSinceEpoch}',
    );
    repository = AppRepository(database);
    controller = AppController(repository, SourceEngine());
    await controller.initialize();
    await controller.addBook(_remoteBook());
    await controller.addBookmark(
      Bookmark(
        id: 'protected-note',
        bookId: 'cleanup-book',
        chapterIndex: 3,
        paragraphIndex: 0,
        quote: '摘录',
        note: '保留',
        createdAt: DateTime.utc(2026),
      ),
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'selected remote caches clear without moving anchors or notes',
    () async {
      expect(controller.clearableCachedChapterIndices('cleanup-book'), [
        0,
        2,
        5,
      ]);
      final cleared = await controller.clearCachedChapters('cleanup-book', [
        0,
        2,
      ]);
      expect(cleared, 2);
      final book = controller.book('cleanup-book')!;
      expect(book.chapters[0].isCached, isFalse);
      expect(book.chapters[2].isCached, isFalse);
      expect(book.chapters[1].paragraphs, ['正文 1']);
      expect(book.chapters[3].paragraphs, ['正文 3']);
      expect(book.chapters[5].paragraphs, ['正文 5']);
      expect(book.position.chapterIndex, 1);
      expect(controller.bookmarks.single.chapterIndex, 3);
      final stored = (await repository.books()).firstWhere(
        (b) => b.id == book.id,
      );
      expect(stored.chapters[0].isCached, isFalse);
      expect(stored.chapters[2].isCached, isFalse);
      expect((await repository.bookmarks()).single.note, '保留');
    },
  );

  test(
    'protected or invalid selections never partly delete cached text',
    () async {
      for (final indices in <List<int>>[
        [0, 1],
        [0, 3],
        [0, 4],
      ]) {
        await expectLater(
          controller.clearCachedChapters('cleanup-book', indices),
          throwsStateError,
        );
        expect(controller.book('cleanup-book')!.chapters[0].isCached, isTrue);
      }
      for (final indices in <List<int>>[
        [],
        [0, 0],
        [0, 2, 3, 4, 5, 5],
        [-1],
        [6],
      ]) {
        await expectLater(
          controller.clearCachedChapters('cleanup-book', indices),
          throwsArgumentError,
        );
      }
      expect(
        (await repository.books())
            .firstWhere((b) => b.id == 'cleanup-book')
            .chapters[0]
            .isCached,
        isTrue,
      );
    },
  );

  test('local books cannot lose imported paragraphs', () async {
    final local = controller.books.firstWhere((book) => !book.isRemote);
    await expectLater(
      controller.clearCachedChapters(local.id, [0]),
      throwsA(isA<SourceException>()),
    );
    expect(controller.book(local.id)!.chapters[0].isCached, isTrue);
  });

  test(
    'repository refuses stale source and directory before any deletion',
    () async {
      final expected = controller.book('cleanup-book')!;
      await repository.saveBook(_remoteBook(sourceId: 'https://new.example'));
      await expectLater(
        repository.clearCachedChapters(expected, [0, 2]),
        throwsStateError,
      );
      final fresh = (await repository.books()).firstWhere(
        (b) => b.id == expected.id,
      );
      expect(fresh.sourceId, 'https://new.example');
      expect(fresh.chapters[0].isCached, isTrue);
      expect(fresh.chapters[2].isCached, isTrue);
    },
  );

  test(
    'latest stored reading position protects a newly opened chapter',
    () async {
      await repository.savePosition(
        'cleanup-book',
        const ReadingPosition(chapterIndex: 0),
      );
      await expectLater(
        controller.clearCachedChapters('cleanup-book', [0]),
        throwsStateError,
      );
      final fresh = (await repository.books()).firstWhere(
        (b) => b.id == 'cleanup-book',
      );
      expect(fresh.position.chapterIndex, 0);
      expect(fresh.chapters[0].isCached, isTrue);
    },
  );

  test(
    'notes added after the chooser opened still protect the chapter',
    () async {
      await repository.saveBookmark(
        Bookmark(
          id: 'late-note',
          bookId: 'cleanup-book',
          chapterIndex: 2,
          paragraphIndex: 0,
          quote: '另一处',
          note: '',
          createdAt: DateTime.utc(2026),
        ),
      );
      await expectLater(
        controller.clearCachedChapters('cleanup-book', [0, 2]),
        throwsStateError,
      );
      final fresh = (await repository.books()).firstWhere(
        (b) => b.id == 'cleanup-book',
      );
      expect(fresh.chapters[0].isCached, isTrue);
      expect(fresh.chapters[2].isCached, isTrue);
    },
  );

  test('a stale chooser cannot clear a replacement source', () async {
    final original = controller.book('cleanup-book')!;
    await repository.saveBook(
      _remoteBook(sourceId: 'https://replacement.example'),
    );
    await controller.initialize();

    await expectLater(
      controller.clearCachedChapters('cleanup-book', [
        0,
      ], expectedBook: original),
      throwsStateError,
    );
    final fresh = (await repository.books()).firstWhere(
      (b) => b.id == original.id,
    );
    expect(fresh.sourceId, 'https://replacement.example');
    expect(fresh.chapters[0].isCached, isTrue);
  });

  test(
    'reading a chapter being cleared waits instead of reviving it',
    () async {
      final paused = _PausedCleanupRepository(database);
      final reader = AppController(paused, SourceEngine());
      addTearDown(reader.dispose);
      await reader.initialize();
      final work = reader.clearCachedChapters('cleanup-book', [0]);
      await paused.started.future;
      try {
        await expectLater(
          reader.chapter('cleanup-book', 0),
          throwsA(isA<SourceException>()),
        );
      } finally {
        paused.resume.complete();
      }
      expect(await work, 1);
      expect(reader.book('cleanup-book')!.chapters[0].isCached, isFalse);
    },
  );

  test('a pending clear cannot acquire a new reading or note anchor', () async {
    final paused = _PausedCleanupRepository(database);
    final reader = AppController(paused, SourceEngine());
    addTearDown(reader.dispose);
    await reader.initialize();
    final work = reader.clearCachedChapters('cleanup-book', [0]);
    await paused.started.future;
    try {
      await expectLater(
        reader.savePosition(
          'cleanup-book',
          const ReadingPosition(chapterIndex: 0),
        ),
        throwsStateError,
      );
      await expectLater(
        reader.addBookmark(
          Bookmark(
            id: 'new-note',
            bookId: 'cleanup-book',
            chapterIndex: 0,
            paragraphIndex: 0,
            quote: '清理中',
            note: '',
            createdAt: DateTime.utc(2026),
          ),
        ),
        throwsStateError,
      );
    } finally {
      paused.resume.complete();
    }
    expect(await work, 1);
    final fresh = (await repository.books()).firstWhere(
      (b) => b.id == 'cleanup-book',
    );
    expect(fresh.position.chapterIndex, 1);
    expect(
      (await repository.bookmarks()).any((note) => note.id == 'new-note'),
      isFalse,
    );
  });
}
