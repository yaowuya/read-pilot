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
import 'package:read_pilot/domain/change_source_settings.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/domain/source_switch_candidate.dart';
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
  final searchFailures = <String, Object>{};
  String? delayedSearchSourceId;
  Completer<List<Book>>? delayedSearch;
  String? completedSearchSourceId;
  Completer<void>? searchCompleted;
  String? delayedSourceId;
  Completer<Chapter>? delayedChapter;
  Completer<void>? chapterStarted;
  Future<void>? loadBookAbortTrigger;
  Future<void>? loadChapterAbortTrigger;
  final chapterRequests = <String>[];
  final chaptersBySourceId = <String, Chapter>{};

  @override
  Future<List<Book>> search(
    BookSource source,
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    final failure = searchFailures[source.id];
    if (failure != null) throw failure;
    if (source.id == delayedSearchSourceId && delayedSearch != null) {
      return delayedSearch!.future;
    }
    final completed = searchCompleted;
    if (source.id == completedSearchSourceId &&
        completed != null &&
        !completed.isCompleted) {
      completed.complete();
    }
    return results[source.id] ?? const [];
  }

  @override
  Future<Book> loadBook(
    BookSource source,
    Book result, {
    Future<void>? abortTrigger,
  }) async {
    loadBookAbortTrigger = abortTrigger;
    if (failure != null) throw failure!;
    return loadedBook ?? result;
  }

  @override
  Future<Chapter> loadChapter(
    BookSource source,
    Chapter chapter, {
    Future<void>? abortTrigger,
  }) async {
    loadChapterAbortTrigger = abortTrigger;
    chapterRequests.add(chapter.id);
    if (chapterStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    if (source.id == delayedSourceId && delayedChapter != null) {
      return delayedChapter!.future;
    }
    return chaptersBySourceId[source.id] ??
        loadedChapter ??
        chapter.withParagraphs(const ['新正文']);
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

class _BoundedMetadataSourceEngine extends SourceEngine {
  _BoundedMetadataSourceEngine(this.metadataGate);

  final Future<void> metadataGate;
  final metadataStarted = Completer<void>();
  var searchStarted = 0;
  var metadataLoads = 0;

  @override
  Future<List<Book>> search(
    BookSource source,
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    searchStarted++;
    if (source.id == 'https://source-0.example') return const [];
    return [
      _remoteBook(
        id: 'backlog-${source.id}',
        sourceId: source.id,
        sourceLabel: source.id,
      ),
    ];
  }

  @override
  Future<Book> loadBook(
    BookSource source,
    Book result, {
    Future<void>? abortTrigger,
  }) async {
    metadataLoads++;
    if (metadataLoads == 3 && !metadataStarted.isCompleted) {
      metadataStarted.complete();
    }
    await metadataGate;
    return result;
  }

  @override
  Future<Chapter> loadChapter(
    BookSource source,
    Chapter chapter, {
    Future<void>? abortTrigger,
  }) async => chapter.withParagraphs(const ['候选正文']);
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
    String? expectedTargetSourceId,
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

  test(
    'multi-source search runs at most sixteen sources concurrently',
    () async {
      controller.dispose();
      final engine = _ConcurrencySourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([
          for (var index = 0; index < 19; index++) _searchSource(index),
        ]),
      );

      final groups = await controller.searchSources('测试');

      expect(groups, hasLength(19));
      expect(engine.peak, 16);
    },
  );

  test('cancelling search prevents queued sources from starting', () async {
    controller.dispose();
    final engine = _ConcurrencySourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([
        for (var index = 0; index < 40; index++) _searchSource(index),
      ]),
    );
    final abort = Completer<void>();

    final pending = controller.searchSources('测试', abortTrigger: abort.future);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    abort.complete();
    final groups = await pending;

    expect(engine.started, 16);
    expect(groups, hasLength(16));
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
    'streams a candidate before its chapter and word count are ready',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1), _searchSource(2)]),
      );
      const currentSource = 'https://source-0.example';
      const candidateSource = 'https://source-1.example';
      const delayedSource = 'https://source-2.example';
      final current = _remoteBook(
        id: 'metadata-ready-current',
        sourceId: currentSource,
        sourceLabel: 'Source 0',
        chapters: [
          Chapter(
            id: '$currentSource/chapter',
            title: '第一章',
            url: '$currentSource/chapter',
            paragraphs: const ['当前正文'],
          ),
        ],
      );
      final candidate = _remoteBook(
        id: 'metadata-ready-candidate',
        sourceId: candidateSource,
        sourceLabel: 'Source 1',
      );
      engine.results[candidateSource] = [candidate];
      engine.loadedChapter = candidate.chapters.single.withParagraphs(const [
        '候选正文',
      ]);
      final delayedSearch = Completer<List<Book>>();
      engine.delayedSearchSourceId = delayedSource;
      engine.delayedSearch = delayedSearch;
      final candidateUpdate = Completer<SourceCandidateSearchResult>();
      final search = controller.findSourceCandidatesFor(
        current,
        onUpdate: (partial, _, _) {
          if (!candidateUpdate.isCompleted &&
              partial.candidates.any((book) => book.id == candidate.id)) {
            candidateUpdate.complete(partial);
          }
        },
      );

      final partial = await candidateUpdate.future.timeout(
        const Duration(seconds: 1),
      );
      try {
        // A source returning this title is enough to list a switchable row: the
        // mapped chapter and word count are decoration that arrives later, so
        // they must never gate the list while a long search is still running.
        expect(
          partial.candidates.map((book) => book.id),
          contains(candidate.id),
        );
        expect(partial.infoFor(candidate), isNull);
      } finally {
        if (!delayedSearch.isCompleted) delayedSearch.complete(const []);
      }

      final found = await search;

      expect(found.infoFor(candidate)?.mappedChapterTitle, '第一章');
      expect(found.infoFor(candidate)?.wordCount, 4);
    },
  );

  test(
    'reports candidates incrementally while sources are still searched',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1)]),
      );
      const oldSource = 'https://source-0.example';
      const otherSource = 'https://source-1.example';
      final searched = _remoteBook(
        id: 'search-result',
        sourceId: oldSource,
        sourceLabel: 'Source 0',
      );
      engine.results[otherSource] = [
        _remoteBook(
          id: 'mirrored-result',
          sourceId: otherSource,
          sourceLabel: 'Source 1',
        ),
      ];

      // 上千个书源要搜几分钟，换源面板靠 onUpdate 边搜边列候选。
      final updates = <(int, int, List<String>)>[];
      final found = await controller.findSourceCandidatesFor(
        searched,
        onUpdate: (partial, processed, total) => updates.add((
          processed,
          total,
          partial.candidates.map((book) => book.id).toList(),
        )),
      );

      expect(updates, isNotEmpty);
      expect(updates.last.$1, updates.last.$2);
      expect(
        updates.map((update) => update.$3).expand((ids) => ids),
        contains('mirrored-result'),
      );
      expect(found.candidates.map((book) => book.id), ['mirrored-result']);
    },
  );

  test(
    'keeps configured source order when searches complete out of order',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1), _searchSource(2)]),
      );
      const currentSource = 'https://source-0.example';
      const firstSource = 'https://source-1.example';
      const secondSource = 'https://source-2.example';
      final current = _remoteBook(
        id: 'source-order-current',
        sourceId: currentSource,
        sourceLabel: 'Source 0',
        chapters: [
          Chapter(
            id: '$currentSource/chapter',
            title: '第一章',
            url: '$currentSource/chapter',
            paragraphs: const ['当前正文'],
          ),
        ],
      );
      final first = _remoteBook(
        id: 'source-order-first',
        sourceId: firstSource,
        sourceLabel: 'Source 1',
      );
      final second = _remoteBook(
        id: 'source-order-second',
        sourceId: secondSource,
        sourceLabel: 'Source 2',
      );
      engine.results
        ..[firstSource] = [first]
        ..[secondSource] = [second];
      final firstSearch = Completer<List<Book>>();
      final secondCompleted = Completer<void>();
      engine
        ..delayedSearchSourceId = firstSource
        ..delayedSearch = firstSearch
        ..completedSearchSourceId = secondSource
        ..searchCompleted = secondCompleted;

      final finding = controller.findSourceCandidatesFor(current);
      await secondCompleted.future;
      expect(firstSearch.isCompleted, isFalse);
      firstSearch.complete([first]);

      final found = await finding;
      expect(found.candidates.map((candidate) => candidate.id), [
        first.id,
        second.id,
      ]);
    },
  );

  test('bounds queued metadata work while sources stream results', () async {
    controller.dispose();
    final gate = Completer<void>();
    final engine = _BoundedMetadataSourceEngine(gate.future);
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([
        for (var index = 0; index < 40; index++) _searchSource(index),
      ]),
    );
    const currentSource = 'https://source-0.example';
    final current = _remoteBook(
      id: 'bounded-backlog-current',
      sourceId: currentSource,
      sourceLabel: 'Source 0',
      chapters: [
        Chapter(
          id: '$currentSource/chapter',
          title: '第一章',
          url: '$currentSource/chapter',
          paragraphs: const ['当前正文'],
        ),
      ],
    );

    final finding = controller.findSourceCandidatesFor(current);
    await engine.metadataStarted.future;
    // Catalog loads are the heaviest request a switch issues, so they stay
    // capped and their backlog bounded: however many sources answer at once,
    // only the admitted jobs may run while the gate is closed.
    await Future<void>.delayed(Duration.zero);
    expect(engine.metadataLoads, lessThanOrEqualTo(24));
    expect(engine.searchStarted, lessThanOrEqualTo(40));

    gate.complete();
    final found = await finding;
    expect(found.candidates, hasLength(39));
  });

  test(
    'reloads source candidates into a chapter-aware cache for later switching',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1)]),
      );
      const currentSource = 'https://source-0.example';
      const candidateSource = 'https://source-1.example';
      final current = _remoteBook(
        id: 'cache-book',
        sourceId: currentSource,
        sourceLabel: 'Source 0',
        chapters: [
          Chapter(
            id: '$currentSource/chapter',
            title: '第一章',
            url: '$currentSource/chapter',
            paragraphs: const ['当前正文'],
          ),
        ],
      );
      await controller.addBook(current);
      final candidate = _remoteBook(
        id: 'cached-candidate',
        sourceId: candidateSource,
        sourceLabel: 'Source 1',
      );
      engine.results[candidateSource] = [candidate];
      engine.loadedChapter = candidate.chapters.single.withParagraphs(const [
        '候选正文',
      ]);

      final refreshed = await controller.reloadSourceCandidatesFor(current);
      expect(refreshed.candidates.map((book) => book.id), [candidate.id]);
      expect(refreshed.infoFor(candidate)?.mappedChapterTitle, '第一章');
      expect(refreshed.infoFor(candidate)?.chapterCount, 1);
      expect(refreshed.infoFor(candidate)?.wordCount, 4);

      final cached = await controller.sourceCandidateCacheFor(current);
      expect(cached, isNotNull);
      expect(cached!.fromCache, isTrue);
      expect(cached.candidates, hasLength(1));
      final restoredCandidate = cached.candidates.single;
      expect(restoredCandidate.id, candidate.id);
      expect(cached.infoFor(restoredCandidate)?.mappedChapterIndex, 0);
      expect(cached.infoFor(restoredCandidate)?.wordCount, 4);
    },
  );

  test(
    'newer candidate refresh wins when an older refresh completes last',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1)]),
      );
      const currentSource = 'https://source-0.example';
      const candidateSource = 'https://source-1.example';
      final current = _remoteBook(
        id: 'refresh-order-book',
        sourceId: currentSource,
        sourceLabel: 'Source 0',
        chapters: [
          Chapter(
            id: '$currentSource/chapter',
            title: '第一章',
            url: '$currentSource/chapter',
            paragraphs: const ['当前正文'],
          ),
        ],
      );
      await controller.addBook(current);
      final olderCandidate = _remoteBook(
        id: 'older-refresh-candidate',
        sourceId: candidateSource,
        sourceLabel: 'Source 1',
      );
      final newerCandidate = _remoteBook(
        id: 'newer-refresh-candidate',
        sourceId: candidateSource,
        sourceLabel: 'Source 1',
      );
      final chapterStarted = Completer<void>();
      final delayedChapter = Completer<Chapter>();
      engine
        ..results[candidateSource] = [olderCandidate]
        ..delayedSourceId = candidateSource
        ..chapterStarted = chapterStarted
        ..delayedChapter = delayedChapter;

      final olderRefresh = controller.reloadSourceCandidatesFor(current);
      await chapterStarted.future;

      // Start a newer refresh after the old request is already waiting for its
      // candidate chapter. It must win even though the older request finishes
      // later.
      engine
        ..delayedSourceId = null
        ..results[candidateSource] = [newerCandidate];
      final newerRefresh = await controller.reloadSourceCandidatesFor(current);
      expect(newerRefresh.candidates.map((book) => book.id), [
        newerCandidate.id,
      ]);

      delayedChapter.complete(
        olderCandidate.chapters.single.withParagraphs(const ['旧刷新正文']),
      );
      await olderRefresh;

      final cached = await controller.sourceCandidateCacheFor(current);
      expect(cached, isNotNull);
      expect(cached!.candidates.map((book) => book.id), [newerCandidate.id]);
    },
  );

  test('a loaded candidate list survives a completed source switch', () async {
    controller.dispose();
    final engine = _SwitchSourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([_searchSource(0), _searchSource(1), _searchSource(2)]),
    );
    const currentSource = 'https://source-0.example';
    const candidateSource = 'https://source-1.example';
    const otherSource = 'https://source-2.example';
    final current = _remoteBook(
      id: 'switch-keeps-cache-book',
      sourceId: currentSource,
      sourceLabel: 'Source 0',
      chapters: [
        Chapter(
          id: '$currentSource/chapter',
          title: '第一章',
          url: '$currentSource/chapter',
          paragraphs: const ['当前正文'],
        ),
      ],
    );
    await controller.addBook(current);
    final candidate = _remoteBook(
      id: 'switch-keeps-cache-candidate',
      sourceId: candidateSource,
      sourceLabel: 'Source 1',
    );
    final other = _remoteBook(
      id: 'switch-keeps-cache-other',
      sourceId: otherSource,
      sourceLabel: 'Source 2',
    );
    engine.results[candidateSource] = [candidate];
    engine.results[otherSource] = [other];
    await controller.reloadSourceCandidatesFor(current);

    engine.loadedBook = candidate;
    engine.loadedChapter = candidate.chapters.single.withParagraphs(const [
      '新源正文',
    ]);
    await controller.switchBookSource(current.id, candidate);
    final switched = controller.book(current.id)!;

    // Rescanning every enabled source on each reopen is what the user
    // reported; the snapshot must outlive the switch and the moved chapter.
    final restored = await controller.sourceCandidateCacheFor(switched);
    expect(restored, isNotNull);
    expect(restored!.fromCache, isTrue);
    expect(restored.candidates.map((book) => book.id), [other.id]);
    expect(restored.infoFor(restored.candidates.single)?.wordCount, isNotNull);
  });

  test('restores a successful empty source-candidate cache', () async {
    controller.dispose();
    final engine = _SwitchSourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(jsonEncode([_searchSource(0)]));
    const sourceId = 'https://source-0.example';
    final current = _remoteBook(
      id: 'empty-source-candidate-cache-book',
      sourceId: sourceId,
      sourceLabel: 'Source 0',
      chapters: [
        Chapter(
          id: '$sourceId/chapter',
          title: '第一章',
          url: '$sourceId/chapter',
          paragraphs: const ['当前正文'],
        ),
      ],
    );
    await controller.addBook(current);
    await AppRepository(database).saveSourceCandidateCache(
      SourceCandidateCache(
        bookId: current.id,
        originSourceId: sourceId,
        targetChapterIndex: 0,
        targetChapterId: current.chapters.first.id,
        targetChapterTitle: current.chapters.first.title,
        loadedAt: DateTime.now().toUtc(),
        entries: const [],
      ),
    );

    final cached = await controller.sourceCandidateCacheFor(current);
    expect(cached, isNotNull);
    expect(cached!.fromCache, isTrue);
    expect(cached.candidates, isEmpty);
  });

  test(
    'error-completing cancellation does not save a candidate cache',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1)]),
      );
      const currentSource = 'https://source-0.example';
      const candidateSource = 'https://source-1.example';
      final current = _remoteBook(
        id: 'cancelled-source-candidate-cache-book',
        sourceId: currentSource,
        sourceLabel: 'Source 0',
        chapters: [
          Chapter(
            id: '$currentSource/chapter',
            title: '第一章',
            url: '$currentSource/chapter',
            paragraphs: const ['当前正文'],
          ),
        ],
      );
      await controller.addBook(current);
      final candidate = _remoteBook(
        id: 'cancelled-source-candidate',
        sourceId: candidateSource,
        sourceLabel: 'Source 1',
      );
      engine.results[candidateSource] = [candidate];
      final started = Completer<void>();
      final delayedChapter = Completer<Chapter>();
      engine
        ..delayedSourceId = candidateSource
        ..chapterStarted = started
        ..delayedChapter = delayedChapter;
      final abort = Completer<void>();
      final reloading = controller.reloadSourceCandidatesFor(
        current,
        abortTrigger: abort.future,
      );
      await started.future;
      expect(identical(engine.loadBookAbortTrigger, abort.future), isTrue);
      expect(identical(engine.loadChapterAbortTrigger, abort.future), isTrue);
      abort.completeError(StateError('sheet closed'));
      delayedChapter.complete(
        candidate.chapters.first.withParagraphs(const ['延迟正文']),
      );
      await reloading;

      expect(await controller.sourceCandidateCacheFor(current), isNull);
    },
  );

  test(
    'incomplete source reload keeps the last successful candidate cache',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1), _searchSource(2)]),
      );
      const currentSource = 'https://source-0.example';
      const candidateSource = 'https://source-1.example';
      const unavailableSource = 'https://source-2.example';
      final current = _remoteBook(
        id: 'failed-reload-cache-book',
        sourceId: currentSource,
        sourceLabel: 'Source 0',
        chapters: [
          Chapter(
            id: '$currentSource/chapter',
            title: '第一章',
            url: '$currentSource/chapter',
            paragraphs: const ['当前正文'],
          ),
        ],
      );
      await controller.addBook(current);
      final candidate = _remoteBook(
        id: 'failed-reload-candidate',
        sourceId: candidateSource,
        sourceLabel: 'Source 1',
      );
      engine.results[candidateSource] = [candidate];
      await controller.reloadSourceCandidatesFor(current);

      engine.searchFailures[unavailableSource] = const SourceException(
        'network unavailable',
      );
      final incomplete = await controller.reloadSourceCandidatesFor(current);
      expect(incomplete.hasCompleteCandidateResults, isFalse);
      expect(incomplete.candidates.map((book) => book.id), [candidate.id]);
      expect(
        incomplete.unavailableCandidateSourceIds,
        contains(unavailableSource),
      );

      final restored = await controller.sourceCandidateCacheFor(current);
      expect(restored?.candidates.map((book) => book.id), [candidate.id]);
    },
  );

  test('metadata failure keeps the last successful candidate cache', () async {
    controller.dispose();
    final engine = _SwitchSourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([_searchSource(0), _searchSource(1)]),
    );
    const currentSource = 'https://source-0.example';
    const candidateSource = 'https://source-1.example';
    final current = _remoteBook(
      id: 'metadata-failed-reload-cache-book',
      sourceId: currentSource,
      sourceLabel: 'Source 0',
      chapters: [
        Chapter(
          id: '$currentSource/chapter',
          title: '第一章',
          url: '$currentSource/chapter',
          paragraphs: const ['当前正文'],
        ),
      ],
    );
    await controller.addBook(current);
    final candidate = _remoteBook(
      id: 'metadata-failed-reload-candidate',
      sourceId: candidateSource,
      sourceLabel: 'Source 1',
    );
    engine.results[candidateSource] = [candidate];
    await controller.reloadSourceCandidatesFor(current);

    engine.failure = const SourceException('catalog unavailable');
    final incomplete = await controller.reloadSourceCandidatesFor(current);
    expect(incomplete.hasCompleteCandidateResults, isFalse);
    expect(incomplete.unavailableCandidateSourceIds, contains(candidateSource));
    // A metadata failure costs the row its chapter and word count, not the row:
    // the source still returned this title, so it stays a switchable target.
    expect(incomplete.candidates.map((book) => book.id), [candidate.id]);
    expect(incomplete.infoFor(candidate), isNull);

    // Read the raw snapshot: the display accessor deliberately filters some
    // entries, whereas this verifies a metadata failure cannot overwrite it.
    final raw = await controller.repository.sourceCandidateCache(current.id);
    expect(raw?.entries.map((entry) => entry.candidate.id), [candidate.id]);
  });

  test(
    'a source deleted or disabled during metadata loading cannot reenter cache',
    () async {
      for (final removeSource in [true, false]) {
        final scenarioDatabase = await databaseFactoryMemory.openDatabase(
          'deleted-source-cache-${DateTime.now().microsecondsSinceEpoch}-$removeSource',
        );
        final engine = _SwitchSourceEngine();
        final scenarioController = AppController(
          AppRepository(scenarioDatabase),
          engine,
        );
        try {
          await scenarioController.initialize();
          await scenarioController.importSources(
            jsonEncode([_searchSource(0), _searchSource(1), _searchSource(2)]),
          );
          const currentSource = 'https://source-0.example';
          const delayedSource = 'https://source-1.example';
          const survivingSource = 'https://source-2.example';
          final current = _remoteBook(
            id: 'mid-refresh-source-change-$removeSource',
            sourceId: currentSource,
            sourceLabel: 'Source 0',
            chapters: [
              Chapter(
                id: '$currentSource/chapter',
                title: '第一章',
                url: '$currentSource/chapter',
                paragraphs: const ['当前正文'],
              ),
            ],
          );
          await scenarioController.addBook(current);
          final delayed = _remoteBook(
            id: 'mid-refresh-delayed-$removeSource',
            sourceId: delayedSource,
            sourceLabel: 'Source 1',
          );
          final surviving = _remoteBook(
            id: 'mid-refresh-surviving-$removeSource',
            sourceId: survivingSource,
            sourceLabel: 'Source 2',
          );
          engine.results
            ..[delayedSource] = [delayed]
            ..[survivingSource] = [surviving];
          final delayedChapter = Completer<Chapter>();
          final started = Completer<void>();
          engine
            ..delayedSourceId = delayedSource
            ..delayedChapter = delayedChapter
            ..chapterStarted = started;

          final reloading = scenarioController.reloadSourceCandidatesFor(
            current,
          );
          await started.future;
          final changingSource = scenarioController.sources.firstWhere(
            (source) => source.id == delayedSource,
          );
          if (removeSource) {
            await scenarioController.deleteSource(delayedSource);
          } else {
            await scenarioController.setSourceEnabled(changingSource, false);
          }
          delayedChapter.complete(
            delayed.chapters.single.withParagraphs(const ['延迟正文']),
          );
          await reloading;

          final raw = await scenarioController.repository.sourceCandidateCache(
            current.id,
          );
          expect(raw?.entries.map((entry) => entry.candidate.id), [
            surviving.id,
          ]);
        } finally {
          scenarioController.dispose();
          await scenarioDatabase.close();
        }
      }
    },
  );

  test(
    'an incomplete first load still becomes the snapshot for the next opening',
    () async {
      controller.dispose();
      final engine = _SwitchSourceEngine();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1), _searchSource(2)]),
      );
      const currentSource = 'https://source-0.example';
      const candidateSource = 'https://source-1.example';
      const unavailableSource = 'https://source-2.example';
      final current = _remoteBook(
        id: 'partial-first-load-book',
        sourceId: currentSource,
        sourceLabel: 'Source 0',
        chapters: [
          Chapter(
            id: '$currentSource/chapter',
            title: '第一章',
            url: '$currentSource/chapter',
            paragraphs: const ['当前正文'],
          ),
        ],
      );
      await controller.addBook(current);
      final candidate = _remoteBook(
        id: 'partial-first-load-candidate',
        sourceId: candidateSource,
        sourceLabel: 'Source 1',
      );
      engine.results[candidateSource] = [candidate];
      engine.searchFailures[unavailableSource] = const SourceException(
        'network unavailable',
      );

      final first = await controller.reloadSourceCandidatesFor(current);
      expect(first.hasCompleteCandidateResults, isFalse);
      // Without a seeded snapshot the book could never cache anything while one
      // of its sources is dead, so every reopening would rescan every source.
      final restored = await controller.sourceCandidateCacheFor(current);
      expect(restored, isNotNull);
      expect(restored!.fromCache, isTrue);
      expect(restored.candidates.map((book) => book.id), [candidate.id]);
    },
  );

  test('switches source for a remote book that is not on the shelf', () async {
    controller.dispose();
    final engine = _SwitchSourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([_searchSource(0), _searchSource(1)]),
    );
    const oldSource = 'https://source-0.example';
    const otherSource = 'https://source-1.example';
    final searched = _remoteBook(
      id: 'search-result',
      sourceId: oldSource,
      sourceLabel: 'Source 0',
    );
    final candidate = _remoteBook(
      id: 'mirrored-result',
      sourceId: otherSource,
      sourceLabel: 'Source 1',
    );
    engine.results[otherSource] = [candidate];
    engine.loadedBook = candidate;

    // 还没上架的书也能先比较候选书源。
    final found = await controller.findSourceCandidatesFor(searched);
    expect(found.candidates.map((book) => book.id), ['mirrored-result']);
    // 按 id 查候选仍然只认书架上的书。
    expect(
      (await controller.findSourceCandidates(searched.id)).candidates,
      isEmpty,
    );

    final switched = await controller.switchBookSource(searched.id, candidate);
    expect(switched.sourceId, otherSource);
    expect(switched.sourceLabel, 'Source 1');
    // 未上架的书换源只换内存里的对象，不该悄悄写进书架。
    expect(controller.book(searched.id), isNull);
    expect(
      (await controller.repository.books()).where(
        (book) => book.id == searched.id,
      ),
      isEmpty,
    );
  });

  test('rejects switching a non-shelf book onto an unknown source', () async {
    controller.dispose();
    final engine = _SwitchSourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(jsonEncode([_searchSource(0)]));

    await expectLater(
      () => controller.switchBookSource(
        'missing',
        _remoteBook(
          id: 'orphan',
          sourceId: 'https://not-imported.example',
          sourceLabel: '不存在',
        ),
      ),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          '书源已移除。已缓存章节仍可阅读，获取新章节需重新导入书源。',
        ),
      ),
    );
  });

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
    'source switch rejects a target source deleted while it loads',
    () async {
      controller.dispose();
      const oldSource = 'https://source-0.example';
      const targetSource = 'https://source-1.example';
      final engine = _SwitchSourceEngine()
        ..delayedSourceId = targetSource
        ..delayedChapter = Completer<Chapter>()
        ..chapterStarted = Completer<void>();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1)]),
      );
      final current = _remoteBook(
        id: 'target-deleted-during-switch',
        sourceId: oldSource,
        sourceLabel: 'Source 0',
      );
      final candidate = _remoteBook(
        id: 'target-replacement',
        sourceId: targetSource,
        sourceLabel: 'Source 1',
      );
      await controller.addBook(current);
      engine.loadedBook = candidate;

      final rejected = expectLater(
        controller.switchBookSource(current.id, candidate),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'target source deletion',
            contains('目标书源已移除或停用'),
          ),
        ),
      );
      await engine.chapterStarted!.future;
      await controller.deleteSource(targetSource);
      engine.delayedChapter!.complete(
        candidate.chapters.single.withParagraphs(const ['新正文']),
      );
      await rejected;

      expect(controller.book(current.id)!.sourceId, oldSource);
      final stored = (await controller.repository.books()).singleWhere(
        (book) => book.id == current.id,
      );
      expect(stored.sourceId, oldSource);
    },
  );

  test(
    'source switch rejects a target source disabled while it loads',
    () async {
      controller.dispose();
      const oldSource = 'https://source-0.example';
      const targetSource = 'https://source-1.example';
      final engine = _SwitchSourceEngine()
        ..delayedSourceId = targetSource
        ..delayedChapter = Completer<Chapter>()
        ..chapterStarted = Completer<void>();
      controller = AppController(AppRepository(database), engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode([_searchSource(0), _searchSource(1)]),
      );
      final current = _remoteBook(
        id: 'target-disabled-during-switch',
        sourceId: oldSource,
        sourceLabel: 'Source 0',
      );
      final candidate = _remoteBook(
        id: 'target-disabled-replacement',
        sourceId: targetSource,
        sourceLabel: 'Source 1',
      );
      await controller.addBook(current);
      engine.loadedBook = candidate;

      final rejected = expectLater(
        controller.switchBookSource(current.id, candidate),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'target source disable',
            contains('目标书源已移除或停用'),
          ),
        ),
      );
      await engine.chapterStarted!.future;
      final target = controller.sources.singleWhere(
        (source) => source.id == targetSource,
      );
      await controller.setSourceEnabled(target, false);
      engine.delayedChapter!.complete(
        candidate.chapters.single.withParagraphs(const ['新正文']),
      );
      await rejected;

      expect(controller.book(current.id)!.sourceId, oldSource);
      final stored = (await controller.repository.books()).singleWhere(
        (book) => book.id == current.id,
      );
      expect(stored.sourceId, oldSource);
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

  test('作者过滤只保留作者包含关系一致的候选', () async {
    controller.dispose();
    final engine = _SwitchSourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([_searchSource(0), _searchSource(1), _searchSource(2)]),
    );
    const currentSource = 'https://source-0.example';
    final current = _remoteBook(
      id: 'author-current',
      sourceId: currentSource,
      sourceLabel: 'Source 0',
      author: '天蚕土豆',
    );
    final sameAuthor = _remoteBook(
      id: 'same-author',
      sourceId: 'https://source-1.example',
      sourceLabel: 'Source 1',
      author: '天蚕土豆 著',
    );
    final otherAuthor = _remoteBook(
      id: 'other-author',
      sourceId: 'https://source-2.example',
      sourceLabel: 'Source 2',
      author: '另一作者',
    );
    engine.results['https://source-1.example'] = [sameAuthor];
    engine.results['https://source-2.example'] = [otherAuthor];

    // 默认关闭：同名不同作者也算候选，由用户自己判断。
    final unfiltered = await controller.findSourceCandidatesFor(current);
    expect(unfiltered.candidates.map((book) => book.id), [
      'same-author',
      'other-author',
    ]);

    await controller.updateChangeSourceSettings(
      const ChangeSourceSettings(checkAuthor: true),
    );
    // Legado 用 contains 而非相等：各家书源会在作者后面加“著”之类的尾巴。
    final filtered = await controller.findSourceCandidatesFor(current);
    expect(filtered.candidates.map((book) => book.id), ['same-author']);
  });

  test('按字数排序把内容更完整的候选排在前面', () async {
    controller.dispose();
    final engine = _SwitchSourceEngine();
    controller = AppController(AppRepository(database), engine);
    await controller.initialize();
    await controller.importSources(
      jsonEncode([_searchSource(0), _searchSource(1), _searchSource(2)]),
    );
    const currentSource = 'https://source-0.example';
    final current = _remoteBook(
      id: 'word-current',
      sourceId: currentSource,
      sourceLabel: 'Source 0',
    );
    final shortSource = _remoteBook(
      id: 'short-candidate',
      sourceId: 'https://source-1.example',
      sourceLabel: 'Source 1',
    );
    final longSource = _remoteBook(
      id: 'long-candidate',
      sourceId: 'https://source-2.example',
      sourceLabel: 'Source 2',
    );
    engine.results['https://source-1.example'] = [shortSource];
    engine.results['https://source-2.example'] = [longSource];
    engine.chaptersBySourceId['https://source-1.example'] = Chapter(
      id: 'source-1/chapter',
      title: '第一章',
      url: 'source-1/chapter',
      paragraphs: const ['短'],
    );
    engine.chaptersBySourceId['https://source-2.example'] = Chapter(
      id: 'source-2/chapter',
      title: '第一章',
      url: 'source-2/chapter',
      paragraphs: const ['这句话明显要长得多，足以让字数排序把这一行排到前面去。'],
    );

    // 默认按书源顺序，两个字数是 1 vs 25，但顺序仍由 origin 决定。
    final ordered = await controller.findSourceCandidatesFor(current);
    expect(ordered.candidates.first.id, 'short-candidate');
    final shortWords = ordered.infoFor(shortSource)?.wordCount ?? 0;
    final longWords = ordered.infoFor(longSource)?.wordCount ?? 0;
    expect(shortWords, 1);
    expect(longWords, greaterThan(shortWords));

    // 打开字数排序后，内容更完整的那一本排到第一行。
    await controller.updateChangeSourceSettings(
      const ChangeSourceSettings(sortByWordCount: true),
    );
    final sorted = await controller.findSourceCandidatesFor(current);
    expect(sorted.candidates.first.id, 'long-candidate');
  });

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

  test(
    'editing a source url replaces the record instead of copying it',
    () async {
      await controller.importSources(
        jsonEncode([
          {
            'bookSourceUrl': 'https://before.example',
            'bookSourceName': '改址书源',
            'searchUrl': '/search?q={{key}}',
            'ruleSearch': {
              'bookList': '@CSS:.book',
              'name': '@CSS:a@text',
              'bookUrl': '@CSS:a@href',
            },
          },
        ]),
      );
      final before = controller.sources.single;

      await controller.updateSource(
        before.withName('改址书源').withFields({
          'bookSourceUrl': 'https://after.example',
        }),
        previousId: before.id,
      );

      expect(controller.sources.map((source) => source.id), [
        'https://after.example',
      ]);
      expect(await controller.repository.sources(), hasLength(1));
      expect(
        await controller.repository.sourceState('https://before.example'),
        isNull,
        reason: '旧地址的导入记录也应该一并清掉',
      );
    },
  );

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
