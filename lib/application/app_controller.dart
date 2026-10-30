import 'package:flutter/foundation.dart';

import '../data/app_repository.dart';
import '../data/sample_catalog.dart';
import '../domain/book.dart';
import '../domain/book_source.dart';
import '../domain/reader_settings.dart';
import '../domain/source_import.dart';
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
    await repository.savePosition(id, safe, finished: finished);
    final latest = book(id);
    if (latest == null) return;
    _replace(
      latest.copyWith(
        position: safe,
        lastOpenedAt: DateTime.now(),
        finished: finished,
      ),
    );
  }

  Future<Chapter> chapter(String bookId, int index) async {
    final current = book(bookId);
    if (current == null || index < 0 || index >= current.chapters.length) {
      throw const SourceException('这本书或章节已被移除。');
    }
    final chapter = current.chapters[index];
    if (chapter.isCached) return chapter;
    if (current.sourceId == null) throw const SourceException('本地章节没有正文。');
    final key = '$bookId::$index';
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
    final loaded = await engine.loadChapter(
      _source(current.sourceId!),
      current.chapters[index],
    );
    await repository.cacheChapter(current.id, index, loaded);
    final latest = book(current.id);
    if (latest != null) {
      _replace(
        latest.copyWith(chapters: [...latest.chapters]..[index] = loaded),
      );
    }
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

class SourceSearchGroup {
  const SourceSearchGroup(this.source, this.books, {this.error});
  final BookSource source;
  final List<Book> books;
  final String? error;
}
