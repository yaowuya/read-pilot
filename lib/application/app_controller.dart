import 'package:flutter/foundation.dart';

import '../data/app_repository.dart';
import '../data/sample_catalog.dart';
import '../domain/book.dart';
import '../domain/book_source.dart';
import '../domain/reader_settings.dart';
import '../domain/source_import.dart';
import '../domain/source_switch.dart';
import '../services/source_engine.dart';
import '../services/source_import_service.dart';
import '../services/source_runtime/source_search_scheduler.dart';
import '../services/txt_importer.dart';

class AppController extends ChangeNotifier {
  AppController(
    this.repository,
    this.engine, {
    SourceImportService? sourceImportService,
    SourceSearchScheduler? sourceSearchScheduler,
  }) : sourceImportService = sourceImportService ?? SourceImportService(),
       _sourceSearchScheduler =
           sourceSearchScheduler ?? const SourceSearchScheduler();

  final AppRepository repository;
  final SourceEngine engine;
  final SourceImportService sourceImportService;
  final SourceSearchScheduler _sourceSearchScheduler;
  List<Book> _books = [];
  List<Book> _catalog = [];
  List<BookSource> _sources = [];
  List<Bookmark> _bookmarks = [];
  ReaderSettings _settings = const ReaderSettings();
  final _chapterLoads = <String, Future<Chapter>>{};
  bool _disposed = false;

  List<Book> get books => List.unmodifiable(_books);
  List<Book> get catalog => _catalog;
  List<BookSource> get sources => List.unmodifiable(_sources);
  List<SourceExploreCategory> get exploreCategories {
    final categories = <SourceExploreCategory>[];
    for (final source in _sources.where((source) => source.enabled)) {
      for (final entry in source.exploreEntries) {
        categories.add(SourceExploreCategory(source, entry));
        if (categories.length == 500) return List.unmodifiable(categories);
      }
    }
    return List.unmodifiable(categories);
  }

  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);
  ReaderSettings get settings => _settings;

  Book? book(String id) {
    for (final item in _books) {
      if (item.id == id) return item;
    }
    return null;
  }

  Book? get recentBook {
    final opened = _books.where((book) => book.hasStarted).toList()
      ..sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
    return opened.isNotEmpty ? opened.first : _books.firstOrNull;
  }

  Future<void> initialize() async {
    await repository.initialize();
    _catalog = await loadSampleCatalog();
    _books = await repository.books();
    _sources = await repository.sources();
    _bookmarks = await repository.bookmarks();
    _settings = await repository.settings();
    _notify();
  }

  Future<Book> addBook(Book candidate) async {
    final existing = book(candidate.id);
    if (existing != null) return existing;
    var added = candidate;
    if (candidate.isRemote && candidate.chapters.isEmpty) {
      final source = _source(candidate.sourceId!);
      added = await engine.loadBook(source, candidate);
    }
    added = added.copyWith(addedAt: DateTime.now());
    await repository.saveBook(added);
    _books = [..._books.where((book) => book.id != added.id), added];
    _notify();
    return added;
  }

  Future<void> removeBook(String id) async {
    await repository.removeBook(id);
    _books = _books.where((book) => book.id != id).toList();
    _bookmarks = _bookmarks.where((note) => note.bookId != id).toList();
    _notify();
  }

  Future<Book> importText(Uint8List bytes, String fileName) =>
      addBook(TxtImporter().parse(bytes, fileName));

  /// Saves a clamped logical anchor on the binding that supplied its content.
  /// An absent/empty book is a no-op; a binding lost during persistence throws
  /// StateError rather than publishing into a replacement. Storage errors propagate.
  Future<void> savePosition(
    String id,
    ReadingPosition position, {
    bool? finished,
  }) async {
    final current = book(id);
    if (current == null || current.chapters.isEmpty) return;
    final chapterIndex = position.chapterIndex.clamp(
      0,
      current.chapters.length - 1,
    );
    final length = current.chapters[chapterIndex].paragraphs.length;
    final safe = ReadingPosition(
      chapterIndex: chapterIndex,
      paragraphIndex: position.paragraphIndex.clamp(
        0,
        length > 0 ? length - 1 : 0,
      ),
    );
    await repository.savePosition(
      id,
      safe,
      finished: finished,
      expectedBook: current,
    );
    final latest = book(id);
    if (latest == null ||
        latest.sourceId != current.sourceId ||
        latest.url != current.url ||
        chapterIndex >= latest.chapters.length ||
        latest.chapters[chapterIndex].id != current.chapters[chapterIndex].id) {
      // The write may have committed before a switch, but its completion is stale.
      throw StateError('书籍已移除或来源、章节已变化，旧阅读进度未应用到当前书籍。');
    }
    _replace(
      latest.copyWith(
        position: safe,
        lastOpenedAt: DateTime.now(),
        finished: finished,
      ),
    );
  }

  /// Returns cached text or a downloaded chapter after its cache write succeeds.
  /// Throws SourceException if the book/binding/TOC slot becomes stale; retry the
  /// current binding instead of displaying the rejected download. Storage errors propagate.
  Future<Chapter> chapter(String bookId, int index) async {
    final current = book(bookId);
    if (current == null || index < 0 || index >= current.chapters.length) {
      throw const SourceException('这本书或章节已被移除。');
    }
    final chapter = current.chapters[index];
    if (chapter.isCached) return chapter;
    if (current.sourceId == null) throw const SourceException('本地章节没有正文。');
    final key = '$bookId::${current.sourceId}::${chapter.id}';
    if (_chapterLoads.containsKey(key)) return _chapterLoads[key]!;
    final pending = _downloadChapter(current, index);
    _chapterLoads[key] = pending;
    try {
      return await pending;
    } finally {
      _chapterLoads.remove(key);
    }
  }

  Future<Chapter> _downloadChapter(Book current, int index) async {
    final expectedSourceId = current.sourceId!;
    final expectedChapterId = current.chapters[index].id;
    final loaded = await engine.loadChapter(
      _source(expectedSourceId),
      current.chapters[index],
    );
    final saved = await repository.cacheChapter(
      current.id,
      index,
      loaded,
      expectedSourceId: expectedSourceId,
      expectedChapterId: expectedChapterId,
    );
    final latest = book(current.id);
    if (!saved ||
        latest == null ||
        latest.sourceId != expectedSourceId ||
        index >= latest.chapters.length ||
        latest.chapters[index].id != expectedChapterId) {
      // Reject the Future too: avoiding a stale cache write does not protect its caller.
      throw const SourceException('书籍已移除或来源、章节已变化，请重新获取章节。');
    }
    _replace(latest.copyWith(chapters: [...latest.chapters]..[index] = loaded));
    return loaded;
  }

  BookSource _source(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    throw const SourceException('书源已移除。已缓存章节仍可阅读，获取新章节需重新导入书源。');
  }

  Future<SourceImportPreview> prepareSourceImport(
    SourceImportInput input, {
    Future<void>? abortTrigger,
  }) => sourceImportService.prepare(input, abortTrigger: abortTrigger);

  Future<SourceImportCommitResult> commitSourceImport(
    SourceImportPreview preview, {
    Set<String>? selectedSourceIds,
  }) async {
    final result = await repository.commitSourceImport(
      preview,
      selectedSourceIds: selectedSourceIds,
    );
    _sources = await repository.sources();
    _notify();
    return result;
  }

  Future<int> importSources(String input) async {
    final preview = await prepareSourceImport(SourceImportInput.text(input));
    final result = await commitSourceImport(preview);
    return result.total;
  }

  Future<void> setSourceEnabled(BookSource source, bool value) async {
    if (!_sources.any((item) => item.id == source.id)) return;
    await repository.setSourceEnabled(source.id, value);
    _sources = _sources
        .map((item) => item.id == source.id ? item.withEnabled(value) : item)
        .toList();
    _notify();
  }

  Future<void> deleteSource(String id) async {
    await repository.deleteSource(id);
    _sources = _sources.where((source) => source.id != id).toList();
    _notify();
  }

  Future<List<SourceSearchGroup>> searchSources(
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
  }) => _sourceSearchScheduler.run(
    _sources.where((source) => source.enabled),
    (source) =>
        _search(source, keyword, page: page, abortTrigger: abortTrigger),
    abortTrigger: abortTrigger,
  );

  /// Finds same-title results while keeping source order and author preference.
  Future<SourceCandidateSearchResult> findSourceCandidates(
    String bookId, {
    Future<void>? abortTrigger,
  }) async {
    final current = book(bookId);
    if (current == null || !current.isRemote) {
      return SourceCandidateSearchResult(const []);
    }
    final titleKey = _matchKey(current.title);
    final authorKey = _matchKey(current.author);
    final ranked = <({Book book, bool authorMatch, int order})>[];
    final seen = <String>{};
    var order = 0;
    var failedSources = 0;
    for (final group in await searchSources(
      current.title,
      abortTrigger: abortTrigger,
    )) {
      if (group.error != null) failedSources++;
      if (group.source.id == current.sourceId) continue;
      for (final candidate in group.books) {
        final candidateOrder = order++;
        if (!seen.add(candidate.id) || _matchKey(candidate.title) != titleKey) {
          continue;
        }
        ranked.add((
          book: candidate,
          authorMatch:
              authorKey.isNotEmpty && _matchKey(candidate.author) == authorKey,
          order: candidateOrder,
        ));
      }
    }
    ranked.sort((left, right) {
      final author = (right.authorMatch ? 1 : 0).compareTo(
        left.authorMatch ? 1 : 0,
      );
      return author != 0 ? author : left.order.compareTo(right.order);
    });
    return SourceCandidateSearchResult(
      ranked.map((item) => item.book),
      failedSources: failedSources,
    );
  }

  /// Rebinds one shelf book only after target content and persistence succeed.
  /// Rejects a destination change during loading so callers can retry explicitly.
  Future<Book> switchBookSource(String bookId, Book candidate) async {
    final current = book(bookId);
    if (current == null || !current.isRemote) {
      throw const SourceException('只有书架中的网络书籍可以换源。');
    }
    if (candidate.sourceId == null || candidate.sourceId == current.sourceId) {
      throw const SourceException('请选择其他可用书源。');
    }
    final source = _source(candidate.sourceId!);
    var replacement = await engine.loadBook(source, candidate);
    final currentBookmarks = _bookmarks
        .where((bookmark) => bookmark.bookId == current.id)
        .toList();
    final preliminary = const SourceSwitchMapper().plan(
      current: current,
      replacement: replacement,
      bookmarks: currentBookmarks,
    );
    final targetIndex = preliminary.book.position.chapterIndex;
    final loadedChapter = await engine.loadChapter(
      source,
      replacement.chapters[targetIndex],
    );
    replacement = replacement.copyWith(
      chapters: [...replacement.chapters]..[targetIndex] = loadedChapter,
    );
    final latest = book(bookId);
    if (latest == null || latest.sourceId != current.sourceId) {
      throw const SourceException('书籍已删除或来源已改变，未执行换源。');
    }
    final latestBookmarks = _bookmarks
        .where((bookmark) => bookmark.bookId == current.id)
        .toList();
    final plan = const SourceSwitchMapper().plan(
      current: latest,
      replacement: replacement,
      bookmarks: latestBookmarks,
    );
    // Only the prefetched destination is validated; do not chase a moving reader.
    if (plan.book.position.chapterIndex != targetIndex) {
      throw const SourceException('阅读位置已变化，目标章节尚未验证，请重试换源。');
    }
    await repository.replaceBookSource(
      plan.book,
      plan.bookmarks,
      expectedSourceId: latest.sourceId,
      expectedPosition: latest.position,
    );

    final mappedBookmarks = {for (final item in plan.bookmarks) item.id: item};
    _books = _books
        .map((item) => item.id == plan.book.id ? plan.book : item)
        .toList();
    _bookmarks = [
      for (final item in _bookmarks)
        if (mappedBookmarks[item.id] case final mapped?)
          item.copyWithPosition(
            chapterIndex: mapped.chapterIndex,
            paragraphIndex: mapped.paragraphIndex,
          )
        else
          item,
    ];
    _notify();
    return plan.book;
  }

  /// Refreshes and validates a cover before publishing its new URL.
  Future<Book> refreshBookCover(String bookId) async {
    final current = book(bookId);
    if (current == null || current.sourceId == null) {
      throw const SourceException('本地书籍没有可刷新的网络封面。');
    }
    final source = _source(current.sourceId!);
    final refreshed = await engine.refreshBookInfo(source, current);
    if (refreshed.coverUrl == null) {
      throw const SourceException('当前书源没有提供封面。');
    }
    await engine.loadCover(source, refreshed.coverUrl!);
    final updated = await repository.updateBookCover(
      bookId,
      refreshed.coverUrl!,
      expectedSourceId: current.sourceId,
    );
    if (updated == null) {
      throw const SourceException('书籍已删除或来源已改变，未保存封面。');
    }
    _replace(updated);
    return updated;
  }

  /// Loads source-scoped cover bytes without persisting changes.
  /// Returns null when source/cover is absent; source and download failures propagate.
  Future<Uint8List?> loadBookCover(Book value) async {
    if (value.sourceId == null || value.coverUrl == null) return null;
    return engine.loadCover(_source(value.sourceId!), value.coverUrl!);
  }

  Future<SourceSearchGroup> exploreSource(
    SourceExploreCategory category, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    try {
      return SourceSearchGroup(
        category.source,
        await engine.explore(
          category.source,
          category.entry,
          page: page,
          abortTrigger: abortTrigger,
        ),
      );
    } catch (error) {
      return SourceSearchGroup(category.source, [], error: error.toString());
    }
  }

  Future<SourceSearchGroup> _search(
    BookSource source,
    String keyword, {
    required int page,
    Future<void>? abortTrigger,
  }) async {
    try {
      return SourceSearchGroup(
        source,
        await engine.search(
          source,
          keyword,
          page: page,
          abortTrigger: abortTrigger,
        ),
      );
    } catch (error) {
      return SourceSearchGroup(source, [], error: error.toString());
    }
  }

  Future<void> updateSettings(ReaderSettings settings) async {
    await repository.saveSettings(settings);
    _settings = settings;
    _notify();
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    await repository.saveBookmark(bookmark);
    _bookmarks = [
      bookmark,
      ..._bookmarks.where((note) => note.id != bookmark.id),
    ];
    _notify();
  }

  Future<void> deleteBookmark(String id) async {
    await repository.deleteBookmark(id);
    _bookmarks = _bookmarks.where((note) => note.id != id).toList();
    _notify();
  }

  static String _matchKey(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s 　，。！？；：、,.!?;:\-—_《》【】()\[\]]+'),
    '',
  );

  void _replace(Book updated) {
    _books = _books
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    engine.close();
    sourceImportService.close();
    super.dispose();
  }
}

class SourceExploreCategory {
  const SourceExploreCategory(this.source, this.entry);

  final BookSource source;
  final SourceExploreEntry entry;
  String get id => '${source.id}::${entry.title}::${entry.url}';
}

/// Ranked manual-switch candidates and failures among all searched enabled sources.
/// The failure count also includes the current source, although its books are excluded.
class SourceCandidateSearchResult {
  SourceCandidateSearchResult(
    Iterable<Book> candidates, {
    this.failedSources = 0,
  }) : candidates = List.unmodifiable(candidates);

  final List<Book> candidates;
  final int failedSources;
}

class SourceSearchGroup {
  const SourceSearchGroup(this.source, this.books, {this.error});
  final BookSource source;
  final List<Book> books;
  final String? error;
}
