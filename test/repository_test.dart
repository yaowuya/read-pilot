import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/domain/source_switch_candidate.dart';
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

Book _sourceCandidateBook({required String id, required String sourceId}) =>
    Book(
      id: id,
      title: '候选书 $id',
      author: '候选作者',
      description: '候选简介',
      category: '测试',
      coverStyle: 2,
      sourceLabel: '候选源',
      sourceId: sourceId,
      url: '$sourceId/books/$id',
      coverUrl: '$sourceId/covers/$id.png',
      chapters: [
        Chapter(
          id: '$id-chapter',
          title: '候选章节',
          url: '$sourceId/chapters/$id',
          paragraphs: const ['候选缓存内容'],
        ),
      ],
      position: const ReadingPosition(chapterIndex: 0, paragraphIndex: 1),
      lastOpenedAt: DateTime.utc(2026, 1, 2),
      finished: true,
      addedAt: DateTime.utc(2026, 1, 1),
    );

Book _shelfBook(String id) => Book(
  id: id,
  title: '书架书 $id',
  author: '书架作者',
  description: '书架简介',
  category: '测试',
  coverStyle: 0,
  sourceLabel: '书架源',
  sourceId: 'https://shelf.example',
  url: 'https://shelf.example/books/$id',
  chapters: [Chapter(id: '$id-chapter', title: '第一章', url: '$id-chapter')],
  addedAt: DateTime.utc(2026, 1, 1),
);

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

  test(
    'sources sort by customOrder and treat a missing value as zero',
    () async {
      final importer = SourceImporter();
      final preview = SourceImportPreview(
        sources: importer.parse(
          jsonEncode([
            _sourceJson(origin: 'https://jia.example', name: '甲'),
            _sourceJson(origin: 'https://yi.example', name: '乙'),
            _sourceJson(origin: 'https://bing.example', name: '丙'),
          ]),
        ),
        provenance: const SourceImportProvenance(
          kind: SourceImportKind.text,
          responseBytes: 512,
        ),
      );
      await repository.commitSourceImport(preview);
      final initial = (await repository.sources())
          .map((source) => source.name)
          .toList();
      expect(initial, hasLength(3));

      // 导入的 JSON 没有 customOrder 键，所有书源都算 0；置顶写进去的 -1 必须排到
      // 最前面，而不是像 sembast 的 SortOrder 那样因为缺字段而落到末尾。
      await repository.moveSourceToTop('https://bing.example');
      final afterTop = (await repository.sources()).toList();
      expect(afterTop.first.name, '丙');
      expect(afterTop.first.customOrder, lessThan(0));
      expect(
        afterTop.skip(1).map((source) => source.name),
        initial.where((name) => name != '丙'),
        reason: '置顶不应该打乱其他书源的相对次序',
      );

      // 显式写更小的 customOrder 也排到更前面。
      final yi = afterTop.firstWhere(
        (source) => source.id == 'https://yi.example',
      );
      await repository.saveSources([yi.withCustomOrder(-5)]);
      expect((await repository.sources()).first.name, '乙');
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

  test('source candidate cache round-trips candidates and metadata', () async {
    final loadedAt = DateTime.utc(2026, 4, 3, 12, 34, 56);
    final candidate = _sourceCandidateBook(
      id: 'round-trip-candidate',
      sourceId: 'https://round-trip.example',
    );
    await repository.saveBook(_shelfBook('round-trip-book'));
    await repository.saveSourceCandidateCache(
      SourceCandidateCache(
        bookId: 'round-trip-book',
        originSourceId: 'https://round-trip-origin.example',
        targetChapterIndex: 2,
        targetChapterId: 'round-trip-origin-chapter',
        targetChapterTitle: '第三章',
        loadedAt: loadedAt,
        failedSources: 2,
        entries: [
          SourceCandidateCacheEntry(
            candidate: candidate,
            info: const SourceCandidateInfo(
              chapterCount: 87,
              mappedChapterIndex: 42,
              mappedChapterTitle: '第四十三章',
              wordCount: 54321,
              errorMessage: '目录读取失败',
            ),
          ),
        ],
      ),
    );

    final restored = await AppRepository(
      database,
    ).sourceCandidateCache('round-trip-book', now: loadedAt);

    expect(restored, isNotNull);
    final cache = restored!;
    expect(cache.bookId, 'round-trip-book');
    expect(cache.originSourceId, 'https://round-trip-origin.example');
    expect(cache.targetChapterIndex, 2);
    expect(cache.targetChapterId, 'round-trip-origin-chapter');
    expect(cache.targetChapterTitle, '第三章');
    expect(cache.loadedAt, loadedAt);
    expect(cache.failedSources, 2);
    final entry = cache.entries.single;
    expect(entry.candidate.toJson(), candidate.toJson());
    final info = entry.info;
    expect(info, isNotNull);
    expect(info!.chapterCount, 87);
    expect(info.mappedChapterIndex, 42);
    expect(info.mappedChapterTitle, '第四十三章');
    expect(info.wordCount, 54321);
    expect(info.errorMessage, '目录读取失败');
  });

  test(
    'source candidate cache is fresh at ten days and expires after',
    () async {
      final loadedAt = DateTime.utc(2026, 1, 1);
      const bookId = 'freshness-book';
      const targetTitle = '第一章';
      await repository.saveBook(_shelfBook(bookId));
      await repository.saveSourceCandidateCache(
        SourceCandidateCache(
          bookId: bookId,
          originSourceId: 'https://freshness-origin.example',
          targetChapterIndex: 0,
          targetChapterId: 'freshness-origin-chapter',
          targetChapterTitle: targetTitle,
          loadedAt: loadedAt,
          entries: [
            SourceCandidateCacheEntry(
              candidate: _sourceCandidateBook(
                id: 'freshness-candidate',
                sourceId: 'https://freshness.example',
              ),
            ),
          ],
        ),
      );

      final expiresAt = loadedAt.add(SourceCandidateCache.lifetime);
      expect(
        await repository.sourceCandidateCache(bookId, now: loadedAt),
        isNotNull,
      );
      expect(
        await repository.sourceCandidateCache(bookId, now: expiresAt),
        isNotNull,
      );
      expect(
        await repository.sourceCandidateCache(
          bookId,
          now: expiresAt.add(const Duration(microseconds: 1)),
        ),
        isNull,
      );
    },
  );

  test(
    'a partial snapshot only seeds a book that has no snapshot yet',
    () async {
      final loadedAt = DateTime.utc(2026, 1, 1);
      const bookId = 'partial-seed-book';
      await repository.saveBook(_shelfBook(bookId));
      SourceCandidateCache snapshot(String candidateId, DateTime at) =>
          SourceCandidateCache(
            bookId: bookId,
            originSourceId: 'https://partial-origin.example',
            targetChapterIndex: 0,
            targetChapterId: 'partial-origin-chapter',
            targetChapterTitle: '第一章',
            loadedAt: at,
            entries: [
              SourceCandidateCacheEntry(
                candidate: _sourceCandidateBook(
                  id: candidateId,
                  sourceId: 'https://partial.example',
                ),
              ),
            ],
          );

      // No snapshot exists yet: even an incomplete refresh must persist, or a
      // book whose candidate list always loses a few dead sources would rescan
      // on every opening.
      expect(
        await repository.saveSourceCandidateCache(
          snapshot('seeded-candidate', loadedAt),
          replaceFreshExisting: false,
          now: loadedAt,
        ),
        isTrue,
      );
      expect(
        (await repository.sourceCandidateCache(
          bookId,
          now: loadedAt,
        ))!.entries.single.candidate.id,
        'seeded-candidate',
      );

      // A later incomplete refresh keeps the seeded snapshot.
      expect(
        await repository.saveSourceCandidateCache(
          snapshot('partial-later', loadedAt.add(const Duration(hours: 1))),
          replaceFreshExisting: false,
          now: loadedAt.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
      expect(
        (await repository.sourceCandidateCache(
          bookId,
          now: loadedAt,
        ))!.entries.single.candidate.id,
        'seeded-candidate',
      );

      // The manual refresh is complete, so it replaces the seeded snapshot.
      final completeAt = loadedAt.add(const Duration(hours: 2));
      expect(
        await repository.saveSourceCandidateCache(
          snapshot('complete-refresh', completeAt),
          now: completeAt,
        ),
        isTrue,
      );
      expect(
        (await repository.sourceCandidateCache(
          bookId,
          now: completeAt,
        ))!.entries.single.candidate.id,
        'complete-refresh',
      );
    },
  );

  test('removing a book deletes only its source candidate caches', () async {
    final books = await repository.books();
    final removedBook = books[0];
    final retainedBook = books[1];
    final now = DateTime.utc(2026, 1, 1);
    await repository.saveSourceCandidateCache(
      SourceCandidateCache(
        bookId: removedBook.id,
        originSourceId: 'https://removed-book-origin.example',
        targetChapterIndex: 0,
        targetChapterId: removedBook.chapters.first.id,
        targetChapterTitle: removedBook.chapters.first.title,
        loadedAt: now,
        entries: [
          SourceCandidateCacheEntry(
            candidate: _sourceCandidateBook(
              id: 'removed-book-candidate',
              sourceId: 'https://removed-book.example',
            ),
          ),
        ],
      ),
    );
    await repository.saveSourceCandidateCache(
      SourceCandidateCache(
        bookId: retainedBook.id,
        originSourceId: 'https://retained-book-origin.example',
        targetChapterIndex: 0,
        targetChapterId: retainedBook.chapters.first.id,
        targetChapterTitle: retainedBook.chapters.first.title,
        loadedAt: now,
        entries: [
          SourceCandidateCacheEntry(
            candidate: _sourceCandidateBook(
              id: 'retained-book-candidate',
              sourceId: 'https://retained-book.example',
            ),
          ),
        ],
      ),
    );

    await repository.removeBook(removedBook.id);

    expect(
      await repository.sourceCandidateCache(removedBook.id, now: now),
      isNull,
    );
    final retained = await repository.sourceCandidateCache(
      retainedBook.id,
      now: now,
    );
    expect(retained?.entries.single.candidate.id, 'retained-book-candidate');
  });

  test(
    'deleting a source prunes matching candidates and empty caches',
    () async {
      const deletedSourceId = 'https://deleted-source.example';
      final now = DateTime.utc(2026, 1, 1);
      await repository.saveBooks([
        _shelfBook('mixed-cache-book'),
        _shelfBook('empty-cache-book'),
        _shelfBook('origin-deleted-cache-book'),
      ]);
      await repository.saveSourceCandidateCache(
        SourceCandidateCache(
          bookId: 'mixed-cache-book',
          originSourceId: 'https://mixed-origin.example',
          targetChapterIndex: 4,
          targetChapterId: 'mixed-origin-chapter',
          targetChapterTitle: '第五章',
          loadedAt: now,
          failedSources: 1,
          entries: [
            SourceCandidateCacheEntry(
              candidate: _sourceCandidateBook(
                id: 'deleted-source-candidate',
                sourceId: deletedSourceId,
              ),
            ),
            SourceCandidateCacheEntry(
              candidate: _sourceCandidateBook(
                id: 'retained-source-candidate',
                sourceId: 'https://retained-source.example',
              ),
              info: const SourceCandidateInfo(wordCount: 321),
            ),
          ],
        ),
      );
      await repository.saveSourceCandidateCache(
        SourceCandidateCache(
          bookId: 'empty-cache-book',
          originSourceId: 'https://empty-origin.example',
          targetChapterIndex: 1,
          targetChapterId: 'empty-origin-chapter',
          targetChapterTitle: '第二章',
          loadedAt: now,
          entries: [
            SourceCandidateCacheEntry(
              candidate: _sourceCandidateBook(
                id: 'only-deleted-source-candidate',
                sourceId: deletedSourceId,
              ),
            ),
          ],
        ),
      );
      await repository.saveSourceCandidateCache(
        SourceCandidateCache(
          bookId: 'origin-deleted-cache-book',
          originSourceId: deletedSourceId,
          targetChapterIndex: 0,
          targetChapterId: 'origin-deleted-chapter',
          targetChapterTitle: '第一章',
          loadedAt: now,
          entries: [
            SourceCandidateCacheEntry(
              candidate: _sourceCandidateBook(
                id: 'otherwise-retained-candidate',
                sourceId: 'https://retained-source.example',
              ),
            ),
          ],
        ),
      );

      await repository.deleteSource(deletedSourceId);

      final pruned = await repository.sourceCandidateCache(
        'mixed-cache-book',
        now: now,
      );
      expect(pruned, isNotNull);
      expect(pruned!.failedSources, 1);
      expect(pruned.entries, hasLength(1));
      expect(pruned.entries.single.candidate.id, 'retained-source-candidate');
      expect(pruned.entries.single.info?.wordCount, 321);
      expect(
        await repository.sourceCandidateCache('empty-cache-book', now: now),
        isNull,
      );
      // The snapshot belongs to the book, so deleting the source it was
      // measured from keeps the remaining candidates selectable.
      final originDeleted = await repository.sourceCandidateCache(
        'origin-deleted-cache-book',
        now: now,
      );
      expect(
        originDeleted?.entries.single.candidate.id,
        'otherwise-retained-candidate',
      );
    },
  );

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
    await repository.saveSourceCandidateCache(
      SourceCandidateCache(
        bookId: current.id,
        originSourceId: current.sourceId!,
        targetChapterIndex: 0,
        targetChapterId: current.chapters.first.id,
        targetChapterTitle: current.chapters.first.title,
        loadedAt: DateTime.utc(2026, 1, 1),
        entries: [
          SourceCandidateCacheEntry(
            candidate: _sourceCandidateBook(
              id: 'switch-candidate',
              sourceId: 'https://candidate.example',
            ),
          ),
        ],
      ),
    );

    await repository.replaceBookSource(replacement, [mappedNote]);
    // Reopening 换源 after the switch must still show the candidates the user
    // already loaded, so the snapshot outlives the source replacement.
    final retainedCache = await repository.sourceCandidateCache(
      current.id,
      now: DateTime.utc(2026, 1, 1),
    );
    expect(retainedCache, isNotNull);
    expect(retainedCache!.entries.single.candidate.id, 'switch-candidate');

    // A slow search started before a manual refresh must not overwrite the
    // newer snapshot.
    expect(
      await repository.saveSourceCandidateCache(
        SourceCandidateCache(
          bookId: current.id,
          originSourceId: 'https://new.example',
          targetChapterIndex: 0,
          targetChapterId: 'new-chapter',
          targetChapterTitle: '第一章',
          loadedAt: DateTime.utc(2025, 12, 31),
          entries: const [],
        ),
        now: DateTime.utc(2026, 1, 1),
      ),
      isFalse,
    );
    expect(
      (await repository.sourceCandidateCache(
        current.id,
        now: DateTime.utc(2026, 1, 1),
      ))!.entries.single.candidate.id,
      'switch-candidate',
    );

    // Clock precision can make two requests share the same start timestamp.
    // The first completed save stays authoritative instead of letting an older
    // request overwrite it on an equality tie.
    expect(
      await repository.saveSourceCandidateCache(
        SourceCandidateCache(
          bookId: current.id,
          originSourceId: 'https://equal.example',
          targetChapterIndex: 0,
          targetChapterId: 'equal-chapter',
          targetChapterTitle: '第一章',
          loadedAt: DateTime.utc(2026, 1, 1),
          entries: const [],
        ),
        now: DateTime.utc(2026, 1, 1),
      ),
      isFalse,
    );
    expect(
      (await repository.sourceCandidateCache(
        current.id,
        now: DateTime.utc(2026, 1, 1),
      ))!.entries.single.candidate.id,
      'switch-candidate',
    );

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

  test(
    'startup preserves existing paragraph boundaries and saved anchors',
    () async {
      final book = (await repository.books()).first;
      const paragraphs = ['原文里   保留的空格', '已经独立的第二段'];
      await repository.saveBook(
        book.copyWith(
          chapters: [
            Chapter(id: 'existing', title: '第一章', paragraphs: paragraphs),
            Chapter(
              id: 'single',
              title: '第二章',
              paragraphs: const ['独立正文   保留的间距'],
            ),
          ],
          position: const ReadingPosition(paragraphIndex: 1),
        ),
      );
      final note = Bookmark(
        id: 'structured-note',
        bookId: book.id,
        chapterIndex: 0,
        paragraphIndex: 1,
        quote: paragraphs[1],
        note: '保留锚点',
        createdAt: DateTime.utc(2026),
      );
      await repository.saveBookmark(note);
      await stringMapStoreFactory
          .store('meta')
          .record('contentSplit')
          .delete(database);

      await repository.initialize();

      final stored = (await repository.books()).firstWhere(
        (item) => item.id == book.id,
      );
      expect(stored.chapters.first.paragraphs, paragraphs);
      expect(stored.chapters.last.paragraphs, ['独立正文   保留的间距']);
      expect(stored.position.paragraphIndex, 1);
      expect((await repository.bookmarks()).single.paragraphIndex, 1);
    },
  );

  test('re-splits a stored blob chapter and rebases its saved anchor', () async {
    final book = (await repository.books()).first;
    // A chapter cached before gap-aware splitting: one paragraph, space gaps.
    final blob = '第一段。${' ' * 4}第二段。${' ' * 4}第三段。';
    await repository.saveBook(
      book.copyWith(
        chapters: [
          Chapter(id: 'c1', title: '第一章', paragraphs: [blob]),
        ],
        position: const ReadingPosition(chapterIndex: 0, paragraphIndex: 0),
      ),
    );
    // This test explicitly opts in; ordinary startup leaves cached text alone.
    await stringMapStoreFactory.store('meta').record('contentSplit').put(
      database,
      {'requested': true},
    );

    await repository.initialize();

    final migrated = (await repository.books()).firstWhere(
      (b) => b.id == book.id,
    );
    expect(migrated.chapters.single.paragraphs, ['第一段。', '第二段。', '第三段。']);
    expect(migrated.position.paragraphIndex, 0);

    // Re-running must be idempotent, not split the pieces again.
    await repository.initialize();
    final again = (await repository.books()).firstWhere((b) => b.id == book.id);
    expect(again.chapters.single.paragraphs, ['第一段。', '第二段。', '第三段。']);
  });

  test('migration moves a mid-blob bookmark onto its sub-paragraph', () async {
    final book = (await repository.books()).first;
    final blob = '甲。${' ' * 4}乙。${' ' * 4}丙。';
    await repository.saveBook(
      book.copyWith(
        chapters: [
          Chapter(id: 'c1', title: '第一章', paragraphs: [blob]),
        ],
      ),
    );
    final note = Bookmark(
      id: 'note-in-blob',
      bookId: book.id,
      chapterIndex: 0,
      paragraphIndex: 0,
      quote: blob,
      note: '',
      createdAt: DateTime.utc(2026),
    );
    await repository.saveBookmark(note);
    await stringMapStoreFactory.store('meta').record('contentSplit').put(
      database,
      {'requested': true},
    );

    await repository.initialize();

    final restored = (await repository.bookmarks()).firstWhere(
      (item) => item.id == note.id,
    );
    expect(restored.paragraphIndex, 0);
    expect(restored.quote, blob);
  });
}
