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

class _SwitchSourceEngine extends SourceEngine {
  final results = <String, List<Book>>{};
  Book? loadedBook;
  Chapter? loadedChapter;
  Book? refreshedBook;
  Uint8List coverBytes = Uint8List.fromList(const [1, 2, 3]);
  Object? failure;
  String? delayedSourceId;
  Completer<Chapter>? delayedChapter;
  Completer<void>? chapterStarted;
  final chapterRequests = <String>[];

  @override
  Future<List<Book>> search(
    BookSource source,
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async => results[source.id] ?? const [];

  @override
  Future<Book> loadBook(BookSource source, Book result) async {
    if (failure != null) throw failure!;
    return loadedBook ?? result;
  }

  @override
  Future<Chapter> loadChapter(BookSource source, Chapter chapter) async {
    chapterRequests.add(chapter.id);
    if (chapterStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    if (source.id == delayedSourceId && delayedChapter != null) {
      return delayedChapter!.future;
    }
    return loadedChapter ?? chapter.withParagraphs(const ['新正文']);
  }

  @override
  Future<Book> refreshBookInfo(BookSource source, Book result) async =>
      refreshedBook ?? result;

  @override
  Future<Uint8List> loadCover(
    BookSource source,
    String coverUrl, {
    Future<void>? abortTrigger,
  }) async {
    if (failure != null) throw failure!;
    return coverBytes;
  }
}

class _PausedProgressRepository extends AppRepository {
  _PausedProgressRepository(super.database, {required this.afterWrite});

  final bool afterWrite;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> savePosition(
    String id,
    ReadingPosition position, {
    bool? finished,
    Book? expectedBook,
  }) async {
    if (afterWrite) {
      await super.savePosition(
        id,
        position,
        finished: finished,
        expectedBook: expectedBook,
      );
    }
    started.complete();
    await release.future;
    if (!afterWrite) {
      await super.savePosition(
        id,
        position,
        finished: finished,
        expectedBook: expectedBook,
      );
    }
  }
}

class _PausedCacheRepository extends AppRepository {
  _PausedCacheRepository(super.database);

  final cached = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> cacheChapter(
    String bookId,
    int index,
    Chapter chapter, {
    required String expectedSourceId,
    required String expectedChapterId,
  }) async {
    final saved = await super.cacheChapter(
      bookId,
      index,
      chapter,
      expectedSourceId: expectedSourceId,
      expectedChapterId: expectedChapterId,
    );
    cached.complete();
    await release.future;
    return saved;
  }
}

class _FailingSwitchRepository extends AppRepository {
  _FailingSwitchRepository(super.database);

  @override
  Future<void> replaceBookSource(
    Book book,
    Iterable<Bookmark> bookmarks, {
    String? expectedSourceId,
    ReadingPosition? expectedPosition,
  }) async => throw StateError('persist failed');
}

Book _remoteBook({
  required String id,
  required String sourceId,
  required String sourceLabel,
  String title = '测试书',
  String author = '作者',
  List<Chapter>? chapters,
  ReadingPosition position = const ReadingPosition(),
  String? coverUrl,
}) => Book(
  id: id,
  title: title,
  author: author,
  description: '',
  category: '测试',
  coverStyle: 0,
  sourceLabel: sourceLabel,
  sourceId: sourceId,
  url: '$sourceId/book',
  coverUrl: coverUrl,
  chapters:
      chapters ??
      [
        Chapter(
          id: '$sourceId/chapter',
          title: '第一章',
          url: '$sourceId/chapter',
        ),
      ],
  position: position,
  addedAt: DateTime.utc(2026),
);

Map<String, dynamic> _searchSource(int index) => {
  'bookSourceUrl': 'https://source-$index.example',
  'bookSourceName': 'Source $index',
  'searchUrl': '/search?q={{key}}',
  'ruleSearch': {
    'bookList': '@CSS:.book',
    'name': '@CSS:a@text',
    'author': '@CSS:.author@text',
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

  test(
    'finds ranked candidates, switches durably, and refreshes cover',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([
          for (var index = 0; index < 3; index++) _searchSource(index),
        ]),
      );
      final oldSource = 'https://source-0.example';
      final exactSource = 'https://source-1.example';
      final otherSource = 'https://source-2.example';
      final current = _remoteBook(
        id: 'shelf-book',
        sourceId: oldSource,
        sourceLabel: 'Source 0',
        position: const ReadingPosition(paragraphIndex: 1),
        chapters: [
          Chapter(
            id: '$oldSource/chapter',
            title: '第一章',
            url: '$oldSource/chapter',
            paragraphs: const ['旧段', '目标段落'],
          ),
        ],
      );
      await controller.addBook(current);
      await controller.addBookmark(
        Bookmark(
          id: 'switch-note',
          bookId: current.id,
          chapterIndex: 0,
          paragraphIndex: 1,
          quote: '目标段落',
          note: '',
          createdAt: DateTime.utc(2026),
        ),
      );
      final exact = _remoteBook(
        id: 'exact-result',
        sourceId: exactSource,
        sourceLabel: 'Source 1',
        title: '测 试书',
      );
      final otherAuthor = _remoteBook(
        id: 'other-result',
        sourceId: otherSource,
        sourceLabel: 'Source 2',
        author: '另一作者',
      );
      engine.results
        ..[oldSource] = [
          _remoteBook(
            id: 'current-result',
            sourceId: oldSource,
            sourceLabel: 'Source 0',
          ),
        ]
        ..[exactSource] = [exact]
        ..[otherSource] = [
          _remoteBook(
            id: 'wrong-title',
            sourceId: otherSource,
            sourceLabel: 'Source 2',
            title: '另一本书',
          ),
          otherAuthor,
        ];

      final candidates = await controller.findSourceCandidates(current.id);
      expect(candidates.candidates.map((book) => book.id), [
        'exact-result',
        'other-result',
      ]);

      engine.loadedBook = _remoteBook(
        id: exact.id,
        sourceId: exactSource,
        sourceLabel: 'Source 1',
        chapters: [
          Chapter(
            id: '$exactSource/chapter',
            title: '第一章',
            url: '$exactSource/chapter',
          ),
        ],
      );
      engine.loadedChapter = Chapter(
        id: '$exactSource/chapter',
        title: '第一章',
        url: '$exactSource/chapter',
        paragraphs: const ['新段', '目标段落'],
      );

      final switched = await controller.switchBookSource(current.id, exact);
      expect(switched.id, current.id);
      expect(switched.sourceId, exactSource);
      expect(switched.position.paragraphIndex, 1);
      expect(controller.bookmarks.single.paragraphIndex, 1);
      expect(
        (await controller.repository.books())
            .firstWhere((book) => book.id == current.id)
            .sourceId,
        exactSource,
      );

      engine.refreshedBook = switched.copyWith(
        coverUrl: '$exactSource/new-cover.png',
      );
      final refreshed = await controller.refreshBookCover(current.id);
      expect(refreshed.coverUrl, '$exactSource/new-cover.png');
      expect(await controller.loadBookCover(refreshed), [1, 2, 3]);
    },
  );

  test(
    'failed source-switch persistence never publishes replacement state',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(_FailingSwitchRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1)]),
      );
      final current = _remoteBook(
        id: 'rollback-book',
        sourceId: 'https://source-0.example',
        sourceLabel: 'Source 0',
        chapters: [
          Chapter(
            id: 'old-chapter',
            title: '第一章',
            url: 'https://source-0.example/chapter',
            paragraphs: const ['旧正文'],
          ),
        ],
      );
      await controller.addBook(current);
      final candidate = _remoteBook(
        id: 'replacement',
        sourceId: 'https://source-1.example',
        sourceLabel: 'Source 1',
      );
      engine.loadedBook = candidate;
      engine.loadedChapter = candidate.chapters.single.withParagraphs(const [
        '新正文',
      ]);

      await expectLater(
        controller.switchBookSource(current.id, candidate),
        throwsStateError,
      );

      expect(controller.book(current.id)!.sourceId, current.sourceId);
    },
  );

  test(
    'source switch rejects an unvalidated destination after progress moves',
    () async {
      controller.dispose();
      const oldSource = 'https://source-0.example';
      const newSource = 'https://source-1.example';
      final engine = _SwitchSourceEngine()
        ..delayedSourceId = newSource
        ..delayedChapter = Completer<Chapter>()
        ..chapterStarted = Completer<void>();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1)]),
      );
      final current = _remoteBook(
        id: 'moving-book',
        sourceId: oldSource,
        sourceLabel: 'Source 0',
        chapters: [
          for (var index = 0; index < 2; index++)
            Chapter(
              id: '$oldSource/chapter-$index',
              title: '第${index + 1}章 内容$index',
              url: '$oldSource/chapter-$index',
              paragraphs: const ['首段', '目标段落'],
            ),
        ],
      );
      await controller.addBook(current);
      final candidate = _remoteBook(
        id: 'replacement',
        sourceId: newSource,
        sourceLabel: 'Source 1',
        chapters: [
          for (var index = 0; index < 2; index++)
            Chapter(
              id: '$newSource/chapter-$index',
              title: '第${index + 1}章 内容$index',
              url: '$newSource/chapter-$index',
            ),
        ],
      );
      engine.loadedBook = candidate;
      final rejected = expectLater(
        controller.switchBookSource(current.id, candidate),
        throwsA(
          isA<SourceException>().having(
            (error) => error.toString(),
            'retry message',
            contains('重试'),
          ),
        ),
      );
      await engine.chapterStarted!.future;
      await controller.savePosition(
        current.id,
        const ReadingPosition(chapterIndex: 1, paragraphIndex: 1),
      );
      engine.delayedChapter!.complete(
        candidate.chapters.first.withParagraphs(const ['新正文']),
      );
      await rejected;

      final unchanged = controller.book(current.id)!;
      expect(unchanged.sourceId, oldSource);
      expect(unchanged.position.chapterIndex, 1);
      expect(unchanged.position.paragraphIndex, 1);
      final stored = (await controller.repository.books()).firstWhere(
        (book) => book.id == current.id,
      );
      expect(stored.sourceId, oldSource);
      expect(stored.position.chapterIndex, 1);
      expect(stored.position.paragraphIndex, 1);
      expect(engine.chapterRequests, [candidate.chapters.first.id]);
    },
  );

  test(
    'chapter result is rejected if binding changes after cache commit',
    () async {
      controller.dispose();
      final repository = _PausedCacheRepository(database);
      final engine = _SwitchSourceEngine();
      controller = AppController(repository, engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1)]),
      );
      final current = _remoteBook(
        id: 'cached-before-switch',
        sourceId: 'https://source-0.example',
        sourceLabel: 'Source 0',
      );
      await controller.addBook(current);
      final pendingOldChapter = controller.chapter(current.id, 0);
      final rejected = expectLater(
        pendingOldChapter,
        throwsA(isA<SourceException>()),
      );
      await repository.cached.future;
      final candidate = _remoteBook(
        id: 'replacement',
        sourceId: 'https://source-1.example',
        sourceLabel: 'Source 1',
      );
      engine.loadedBook = candidate;
      engine.loadedChapter = candidate.chapters.single.withParagraphs(const [
        '新源正文',
      ]);
      await controller.switchBookSource(current.id, candidate);
      repository.release.complete();
      await rejected;

      final switched = controller.book(current.id)!;
      expect(switched.sourceId, candidate.sourceId);
      expect(switched.chapters.single.paragraphs, ['新源正文']);
    },
  );

  for (final afterWrite in [false, true]) {
    test(
      'late old-source progress ${afterWrite ? 'completion' : 'write'} rejects switched binding',
      () async {
        controller.dispose();
        final repository = _PausedProgressRepository(
          database,
          afterWrite: afterWrite,
        );
        final engine = _SwitchSourceEngine();
        controller = AppController(repository, engine);
        await controller.initialize();
        await controller.importSources(
          jsonEncode([_searchSource(0), _searchSource(1)]),
        );
        final current = _remoteBook(
          id: 'late-progress-book',
          sourceId: 'https://source-0.example',
          sourceLabel: 'Source 0',
          position: const ReadingPosition(paragraphIndex: 1),
          chapters: [
            Chapter(
              id: 'old-chapter',
              title: '第一章 正文',
              url: 'https://source-0.example/chapter',
              paragraphs: const ['旧首段', '锚点', '中段', '待写段落'],
            ),
          ],
        );
        await controller.addBook(current);
        final candidate = _remoteBook(
          id: 'replacement',
          sourceId: 'https://source-1.example',
          sourceLabel: 'Source 1',
          chapters: [
            Chapter(
              id: 'new-chapter',
              title: '第一章 正文',
              url: 'https://source-1.example/chapter',
            ),
          ],
        );
        engine.loadedBook = candidate;
        engine.loadedChapter = candidate.chapters.single.withParagraphs(const [
          '新首段',
          '前插一',
          '前插二',
          '前插三',
          '锚点',
          '待写段落',
        ]);
        // An unchanged write lets the post-commit case pass the switch's position CAS.
        final rejected = expectLater(
          controller.savePosition(
            current.id,
            ReadingPosition(paragraphIndex: afterWrite ? 1 : 3),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'binding failure',
              contains('阅读进度'),
            ),
          ),
        );
        await repository.started.future;
        final switched = await controller.switchBookSource(
          current.id,
          candidate,
        );
        expect(switched.position.paragraphIndex, 4);
        repository.release.complete();
        await rejected;

        final latest = controller.book(current.id)!;
        final stored = (await repository.books()).firstWhere(
          (book) => book.id == current.id,
        );
        expect(latest.sourceId, candidate.sourceId);
        expect(stored.sourceId, candidate.sourceId);
        expect(latest.position.paragraphIndex, 4);
        expect(stored.position.paragraphIndex, 4);
      },
    );
  }

  test('late chapter load cannot publish after a source switch', () async {
    controller.dispose();
    final engine = _SwitchSourceEngine()
      ..delayedSourceId = 'https://source-0.example'
      ..delayedChapter = Completer<Chapter>();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([_searchSource(0), _searchSource(1)]),
    );
    final current = _remoteBook(
      id: 'racing-book',
      sourceId: 'https://source-0.example',
      sourceLabel: 'Source 0',
      chapters: [
        Chapter(
          id: 'old-chapter',
          title: '第一章',
          url: 'https://source-0.example/chapter',
        ),
      ],
    );
    await controller.addBook(current);
    final pendingOldChapter = controller.chapter(current.id, 0);
    final candidate = _remoteBook(
      id: 'replacement',
      sourceId: 'https://source-1.example',
      sourceLabel: 'Source 1',
    );
    engine.loadedBook = candidate;
    engine.loadedChapter = candidate.chapters.single.withParagraphs(const [
      '新正文',
    ]);

    await controller.switchBookSource(current.id, candidate);
    final rejected = expectLater(
      pendingOldChapter,
      throwsA(
        isA<SourceException>().having(
          (error) => error.toString(),
          'stale result message',
          contains('重新获取'),
        ),
      ),
    );
    engine.delayedChapter!.complete(
      current.chapters.single.withParagraphs(const ['迟到的旧正文']),
    );
    await rejected;

    final switched = controller.book(current.id)!;
    expect(switched.sourceId, 'https://source-1.example');
    expect(switched.chapters.single.paragraphs, ['新正文']);
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
