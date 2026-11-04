import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_repository.dart';
import '../data/sample_catalog.dart';
import '../domain/book.dart';
import '../domain/book_source.dart';
import '../domain/reader_settings.dart';
import '../domain/reader_style_preset.dart';
import '../domain/reader_mark.dart';
import '../domain/reading_activity.dart';
import '../domain/shelf_group.dart';
import '../domain/source_import.dart';
import '../domain/source_health.dart';
import '../domain/source_switch.dart';
import '../domain/source_switch_candidate.dart';
import '../services/book_text_rules.dart';
import '../services/epub_importer.dart';
import '../services/local_backup.dart';
import '../services/source_engine.dart';
import '../services/source_health_check.dart';
import '../services/source_import_service.dart';
import '../services/source_runtime/source_search_scheduler.dart';
import '../services/txt_importer.dart';

typedef LocalImportFile = ({Uint8List bytes, String fileName});

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
  // Catalog + first-chapter reads decorate an already-visible row, so several
  // can run together. They no longer block the search or the list, so the only
  // thing this bound protects is the phone's radio and memory: a busy search of
  // a thousand sources must not queue a thousand throttled catalog reads.
  static const _sourceCandidateMetadataConcurrency = 6;
  List<Book> _books = [];
  List<ShelfGroup> _shelfGroups = [];
  List<Book> _catalog = [];
  List<BookSource> _sources = [];
  List<Bookmark> _bookmarks = [];
  List<ReaderMark> _readerMarks = [];
  List<ReaderStylePreset> _readerStylePresets = [];
  List<ReadingActivity> _readingActivities = [];
  Map<String, List<BookTextRule>> _textRules = {};
  final _textRulesRevisions = <String, int>{};
  ReaderSettings _settings = const ReaderSettings();
  final _chapterLoads = <String, Future<Chapter>>{};
  final _cacheClears = <String>{};
  bool _disposed = false;

  List<Book> get books => List.unmodifiable(_books);
  List<ShelfGroup> get shelfGroups => List.unmodifiable(_shelfGroups);
  List<Book> get catalog => _catalog;
  List<BookSource> get sources => List.unmodifiable(_sources);
  List<SourceExploreCategory> get exploreCategories {
    final categories = <SourceExploreCategory>[];
    final seenIds = <String>{};
    for (final source in _sources.where((source) => source.enabled)) {
      for (final entry in source.exploreEntries) {
        // The discover page keys each category chip by [SourceExploreCategory.id];
        // duplicate ids would crash its Wrap with "Duplicate keys found".
        if (!seenIds.add('${source.id}::${entry.title}::${entry.url}')) {
          continue;
        }
        categories.add(SourceExploreCategory(source, entry));
        if (categories.length == 500) return List.unmodifiable(categories);
      }
    }
    return List.unmodifiable(categories);
  }

  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);
  List<ReadingActivity> get readingActivities =>
      List.unmodifiable(_readingActivities);
  ReaderSettings get settings => _settings;
  List<ReaderStylePreset> get readerStylePresets =>
      List.unmodifiable(_readerStylePresets);

  List<ReaderMark> readerMarks(String bookId) =>
      List.unmodifiable(_readerMarks.where((mark) => mark.bookId == bookId));

  ReaderMarkLocation? readerMarkLocation(ReaderMark mark) {
    final current = book(mark.bookId);
    if (current == null || current.sourceId != mark.sourceId) return null;
    final chapterIndex = current.chapters.indexWhere(
      (chapter) => chapter.id == mark.chapterId,
    );
    if (chapterIndex < 0) return null;
    final chapter = current.chapters[chapterIndex];
    if (mark.paragraphIndex < 0 ||
        mark.paragraphIndex >= chapter.paragraphs.length) {
      return null;
    }
    final paragraph = chapter.paragraphs[mark.paragraphIndex];
    if (ReaderMark.fingerprint(paragraph) != mark.paragraphFingerprint) {
      return null;
    }
    final selectedText = mark.selectedText;
    if (selectedText != null &&
        !ReaderMark.hasUniqueOccurrence(paragraph, selectedText)) {
      return null;
    }
    return ReaderMarkLocation(
      chapterIndex: chapterIndex,
      chapterTitle: chapter.title,
      paragraphIndex: mark.paragraphIndex,
      paragraph: paragraph,
    );
  }

  ReaderMark? readerMarkAt(
    String bookId,
    int chapterIndex,
    int paragraphIndex,
    String rawParagraph,
  ) {
    final current = book(bookId);
    if (current == null ||
        chapterIndex < 0 ||
        chapterIndex >= current.chapters.length ||
        paragraphIndex < 0 ||
        paragraphIndex >= current.chapters[chapterIndex].paragraphs.length) {
      return null;
    }
    final chapter = current.chapters[chapterIndex];
    final fingerprint = ReaderMark.fingerprint(rawParagraph);
    for (final mark in _readerMarks) {
      if (mark.bookId == bookId &&
          mark.sourceId == current.sourceId &&
          mark.chapterId == chapter.id &&
          mark.paragraphIndex == paragraphIndex &&
          mark.paragraphFingerprint == fingerprint &&
          mark.selectedText == null) {
        return mark;
      }
    }
    return null;
  }

  List<ReaderMark> readerRangeMarksAt(
    String bookId,
    int chapterIndex,
    int paragraphIndex,
    String rawParagraph,
  ) {
    final current = book(bookId);
    if (current == null ||
        chapterIndex < 0 ||
        chapterIndex >= current.chapters.length ||
        paragraphIndex < 0 ||
        paragraphIndex >= current.chapters[chapterIndex].paragraphs.length) {
      return const [];
    }
    final chapter = current.chapters[chapterIndex];
    final paragraph = chapter.paragraphs[paragraphIndex];
    if (paragraph != rawParagraph) return const [];
    final fingerprint = ReaderMark.fingerprint(paragraph);
    return List.unmodifiable(
      _readerMarks.where(
        (mark) =>
            mark.bookId == bookId &&
            mark.sourceId == current.sourceId &&
            mark.chapterId == chapter.id &&
            mark.paragraphIndex == paragraphIndex &&
            mark.paragraphFingerprint == fingerprint &&
            mark.selectedText != null &&
            ReaderMark.hasUniqueOccurrence(paragraph, mark.selectedText!),
      ),
    );
  }

  List<BookTextRule> textRules(String bookId) =>
      List<BookTextRule>.unmodifiable(_textRules[bookId] ?? const []);

  int textRulesRevision(String bookId) => _textRulesRevisions[bookId] ?? 0;

  String displayParagraph(String bookId, String raw) =>
      BookTextRules.apply(raw, _textRules[bookId] ?? const []);

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
    _shelfGroups = await repository.shelfGroups();
    final loadedRules = Map.of(await repository.allTextRules());
    _textRulesRevisions.updateAll((_, revision) => revision + 1);
    for (final id in loadedRules.keys) {
      _textRulesRevisions.putIfAbsent(id, () => 1);
    }
    _textRules = loadedRules;
    _sources = await repository.sources();
    _bookmarks = await repository.bookmarks();
    _readerMarks = await repository.readerMarks();
    _readingActivities = await repository.readingActivities();
    _settings = await repository.settings();
    _readerStylePresets = await repository.readerStylePresets();
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
    _readerMarks = _readerMarks.where((mark) => mark.bookId != id).toList();
    _readingActivities = _readingActivities
        .where((activity) => activity.bookId != id)
        .toList();
    _shelfGroups = [for (final group in _shelfGroups) group.withoutBook(id)];
    _textRules.remove(id);
    _textRulesRevisions.remove(id);
    _notify();
  }

  Future<ShelfGroup> createShelfGroup(String name) async {
    final group = await repository.createShelfGroup(name);
    _shelfGroups = await repository.shelfGroups();
    _notify();
    return group;
  }

  Future<void> renameShelfGroup(String id, String name) async {
    await repository.renameShelfGroup(id, name);
    _shelfGroups = await repository.shelfGroups();
    _notify();
  }

  Future<void> deleteShelfGroup(String id) async {
    await repository.deleteShelfGroup(id);
    _shelfGroups = await repository.shelfGroups();
    _notify();
  }

  Future<void> setShelfGroupMembership(
    String groupId,
    String bookId,
    bool included,
  ) async {
    await repository.setShelfGroupMembership(groupId, bookId, included);
    _shelfGroups = await repository.shelfGroups();
    _notify();
  }

  Future<void> _reloadTextRules(String bookId) async {
    final rules = await repository.textRules(bookId);
    if (rules.isEmpty) {
      _textRules.remove(bookId);
    } else {
      _textRules[bookId] = rules;
    }
    _textRulesRevisions[bookId] = (_textRulesRevisions[bookId] ?? 0) + 1;
    _notify();
  }

  Future<BookTextRule> addTextRule(
    String bookId,
    String needle,
    String replacement,
  ) async {
    final rule = await repository.addTextRule(bookId, needle, replacement);
    await _reloadTextRules(bookId);
    return rule;
  }

  Future<void> updateTextRule(
    String bookId,
    String ruleId,
    String needle,
    String replacement,
  ) async {
    await repository.updateTextRule(bookId, ruleId, needle, replacement);
    await _reloadTextRules(bookId);
  }

  Future<void> setTextRuleEnabled(
    String bookId,
    String ruleId,
    bool enabled,
  ) async {
    await repository.setTextRuleEnabled(bookId, ruleId, enabled);
    await _reloadTextRules(bookId);
  }

  Future<void> moveTextRule(String bookId, String ruleId, int delta) async {
    await repository.moveTextRule(bookId, ruleId, delta);
    await _reloadTextRules(bookId);
  }

  Future<void> deleteTextRule(String bookId, String ruleId) async {
    await repository.deleteTextRule(bookId, ruleId);
    await _reloadTextRules(bookId);
  }

  Future<Uint8List> exportLocalBackup() => repository.exportLocalBackup();

  Future<Uint8List> exportEncryptedLocalBackup(String password) =>
      repository.exportEncryptedLocalBackup(password);

  Future<LocalBackupPlan> prepareLocalBackup(Uint8List bytes) =>
      repository.prepareLocalBackup(bytes);

  Future<LocalBackupPlan> prepareEncryptedLocalBackup(
    Uint8List bytes,
    String password,
  ) => repository.prepareEncryptedLocalBackup(bytes, password);

  Future<LocalBackupImportResult> restoreLocalBackup(
    LocalBackupPlan plan, {
    bool restoreSettings = false,
  }) async {
    final result = await repository.restoreLocalBackup(
      plan,
      restoreSettings: restoreSettings,
    );
    _books = await repository.books();
    _shelfGroups = await repository.shelfGroups();
    final loadedRules = Map.of(await repository.allTextRules());
    _textRulesRevisions.updateAll((_, revision) => revision + 1);
    for (final id in loadedRules.keys) {
      _textRulesRevisions.putIfAbsent(id, () => 1);
    }
    _textRules = loadedRules;
    _bookmarks = await repository.bookmarks();
    if (restoreSettings) _settings = await repository.settings();
    _notify();
    return result;
  }

  Future<Book> importText(Uint8List bytes, String fileName) =>
      addBook(TxtImporter().parse(bytes, fileName));

  Future<Book> importLocalFile(Uint8List bytes, String fileName) async =>
      addBook(_parseLocalFile(bytes, fileName));

  Future<List<Book>> importLocalFiles(Iterable<LocalImportFile> files) async {
    final selected = List<LocalImportFile>.unmodifiable(files);
    if (selected.isEmpty || selected.length > 5) {
      throw const FormatException('一次请选择 1–5 个 TXT 或 EPUB 文件。');
    }

    var totalBytes = 0;
    final parsed = <Book>[];
    final parsedIds = <String>{};
    for (final file in selected) {
      totalBytes += file.bytes.length;
      if (totalBytes > 32 * 1024 * 1024) {
        throw const FormatException('一次导入的文件总大小不能超过 32 MiB。');
      }
      final candidate = _parseLocalFile(file.bytes, file.fileName);
      if (!parsedIds.add(candidate.id)) {
        throw StateError('本次导入生成了重复的书籍标识，请重试。');
      }
      parsed.add(candidate.copyWith(addedAt: DateTime.now()));
    }

    final existingIds = _books.map((book) => book.id).toSet();
    final added = <Book>[];
    for (final book in parsed) {
      if (existingIds.add(book.id)) added.add(book);
    }
    if (added.isEmpty) return const [];

    await repository.saveBooks(added);
    _books = [..._books, ...added];
    _notify();
    return List.unmodifiable(added);
  }

  Book _parseLocalFile(Uint8List bytes, String fileName) {
    final name = fileName.trim().toLowerCase();
    if (name.endsWith('.txt')) return TxtImporter().parse(bytes, fileName);
    if (name.endsWith('.epub')) return EpubImporter().parse(bytes, fileName);
    throw const FormatException('只支持 TXT 或 EPUB 本地书籍。');
  }

  Future<void> recordReadingActivity(
    String bookId,
    int chapterIndex, {
    required ReadingActivityKind kind,
  }) async {
    final current = book(bookId);
    if (current == null ||
        chapterIndex < 0 ||
        chapterIndex >= current.chapters.length) {
      throw StateError('书籍或章节已移除，未记录阅读足迹。');
    }
    await repository.recordReadingActivity(current, chapterIndex, kind);
    _readingActivities = await repository.readingActivities();
    _notify();
  }

  Future<void> clearReadingActivities() async {
    await repository.clearReadingActivities();
    _readingActivities = [];
    _notify();
  }

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
    if (_cacheClears.contains(_chapterKey(current, chapterIndex))) {
      throw StateError('章节缓存正在清理，阅读进度未保存。');
    }
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

  String _chapterKey(Book current, int index) =>
      '${current.id}::${current.sourceId}::${current.chapters[index].id}';

  /// Returns cached text or a downloaded chapter after its cache write succeeds.
  /// Throws SourceException if the book/binding/TOC slot becomes stale; retry the
  /// current binding instead of displaying the rejected download. Storage errors propagate.
  Future<Chapter> chapter(String bookId, int index) async {
    final current = book(bookId);
    if (current == null || index < 0 || index >= current.chapters.length) {
      throw const SourceException('这本书或章节已被移除。');
    }
    final chapter = current.chapters[index];
    final key = _chapterKey(current, index);
    if (_cacheClears.contains(key)) {
      throw const SourceException('章节缓存正在清理，请稍后重试阅读。');
    }
    if (chapter.isCached) return chapter;
    if (current.sourceId == null) throw const SourceException('本地章节没有正文。');
    if (_chapterLoads.containsKey(key)) return _chapterLoads[key]!;
    final pending = _downloadChapter(current, index);
    _chapterLoads[key] = pending;
    try {
      return await pending;
    } finally {
      _chapterLoads.remove(key);
    }
  }

  List<int> clearableCachedChapterIndices(String bookId) {
    final current = book(bookId);
    if (current == null || !current.isRemote) return const [];
    final anchored = <int>{
      current.position.chapterIndex,
      for (final note in _bookmarks)
        if (note.bookId == bookId) note.chapterIndex,
    };
    return List<int>.unmodifiable([
      for (var index = 0; index < current.chapters.length; index++)
        if (current.chapters[index].isCached &&
            !anchored.contains(index) &&
            !_chapterLoads.containsKey(_chapterKey(current, index)) &&
            !_cacheClears.contains(_chapterKey(current, index)))
          index,
    ]);
  }

  Future<int> clearCachedChapters(
    String bookId,
    List<int> indices, {
    Book? expectedBook,
  }) async {
    final current = book(bookId);
    if (current == null || !current.isRemote) {
      throw const SourceException('只有书架中的网络书籍可以清理章节缓存。');
    }
    if (indices.isEmpty ||
        indices.length > 5 ||
        indices.toSet().length != indices.length ||
        indices.any((index) => index < 0 || index >= current.chapters.length)) {
      throw ArgumentError.value(
        indices,
        'indices',
        'select 1–5 distinct chapters',
      );
    }
    if (expectedBook != null &&
        (expectedBook.id != bookId ||
            expectedBook.sourceId != current.sourceId ||
            expectedBook.url != current.url ||
            indices.any(
              (index) =>
                  index >= expectedBook.chapters.length ||
                  expectedBook.chapters[index].id !=
                      current.chapters[index].id ||
                  expectedBook.chapters[index].url !=
                      current.chapters[index].url,
            ))) {
      throw StateError('书籍来源或目录已变化，请重新打开缓存管理。');
    }
    final eligible = clearableCachedChapterIndices(bookId).toSet();
    if (indices.any((index) => !eligible.contains(index))) {
      throw StateError('所选章节没有可清理缓存，或已被阅读进度、书签保护。');
    }
    final keys = {for (final index in indices) _chapterKey(current, index)};
    _cacheClears.addAll(keys);
    try {
      final updated = await repository.clearCachedChapters(current, indices);
      final latest = book(bookId);
      if (latest == null ||
          latest.sourceId != current.sourceId ||
          latest.url != current.url ||
          indices.any(
            (index) =>
                index >= latest.chapters.length ||
                latest.chapters[index].id != current.chapters[index].id ||
                latest.chapters[index].url != current.chapters[index].url,
          )) {
        throw const SourceException('书籍来源或目录已变化，旧缓存结果未应用。');
      }
      final chapters = [...latest.chapters];
      for (final index in indices) {
        chapters[index] = updated.chapters[index];
      }
      _replace(latest.copyWith(chapters: chapters));
      return indices.length;
    } finally {
      _cacheClears.removeAll(keys);
    }
  }

  /// Caches at most five consecutive chapters on an unchanged remote binding.
  /// Stop requests only prevent queued chapters; an in-flight read is not cancelled.
  /// Successful chapters remain cached if another chapter fails or the user stops.
  Future<ChapterCacheBatchResult> cacheChapterRange(
    String bookId, {
    required int startIndex,
    required int count,
    Future<void>? abortTrigger,
    void Function(int completed, int total)? onProgress,
  }) async {
    final initial = book(bookId);
    if (initial == null || !initial.isRemote) {
      throw const SourceException('只有书架中的网络书籍可以缓存章节。');
    }
    if (count < 1 || count > 5) {
      throw ArgumentError.value(count, 'count', 'must be between 1 and 5');
    }
    if (startIndex < 0 || startIndex + count > initial.chapters.length) {
      throw ArgumentError.value(
        startIndex,
        'startIndex',
        'range exceeds chapters',
      );
    }
    final expectedIds = [
      for (var offset = 0; offset < count; offset++)
        initial.chapters[startIndex + offset].id,
    ];
    bool bindingChanged() {
      final latest = book(bookId);
      if (latest == null ||
          latest.sourceId != initial.sourceId ||
          latest.url != initial.url ||
          startIndex + count > latest.chapters.length) {
        return true;
      }
      for (var offset = 0; offset < count; offset++) {
        if (latest.chapters[startIndex + offset].id != expectedIds[offset]) {
          return true;
        }
      }
      return false;
    }

    var stop = false;
    abortTrigger?.then((_) => stop = true, onError: (Object _) => stop = true);
    var completed = 0;
    var downloaded = 0;
    var skippedCached = 0;
    final failed = <int>[];
    for (var offset = 0; offset < count; offset++) {
      if (abortTrigger != null) await Future<void>.value();
      if (stop) break;
      if (bindingChanged()) {
        throw const SourceException('书籍来源或目录已变化，章节缓存已停止。');
      }
      final index = startIndex + offset;
      if (book(bookId)!.chapters[index].isCached) {
        skippedCached++;
      } else {
        try {
          await chapter(bookId, index);
          downloaded++;
        } catch (error) {
          if (bindingChanged()) {
            throw const SourceException('书籍来源或目录已变化，章节缓存已停止。');
          }
          if (error is! SourceException && error is! FormatException) rethrow;
          failed.add(index);
        }
      }
      if (bindingChanged()) {
        throw const SourceException('书籍来源或目录已变化，章节缓存已停止。');
      }
      completed++;
      onProgress?.call(completed, count);
    }
    return ChapterCacheBatchResult(
      requested: count,
      completed: completed,
      downloaded: downloaded,
      skippedCached: skippedCached,
      failedIndices: failed,
      cancelled: stop && completed < count,
    );
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

  Future<SourceHealthReport> checkSourceHealth(
    String sourceId, {
    Future<void>? abortTrigger,
  }) => SourceHealthCheck(
    engine,
  ).check(_source(sourceId), abortTrigger: abortTrigger);

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

  /// 搜索全部启用书源。
  ///
  /// [onProgress] 每完成一个书源回调一次，用于展示查询进度；[onResult] 同时
  /// 带回该批结果，让界面可以边搜索边显示，而不是等全部书源结束。异步的
  /// [onResult] 会被等待，以便受限的下游队列能够向书源搜索施加背压。
  Future<List<SourceSearchGroup>> searchSources(
    String keyword, {
    int page = 1,
    Future<void>? abortTrigger,
    void Function(int processed, int total)? onProgress,
    FutureOr<void> Function(SourceSearchGroup group, int processed, int total)?
    onResult,
  }) => _sourceSearchScheduler.run(
    _sources.where((source) => source.enabled),
    (source) =>
        _search(source, keyword, page: page, abortTrigger: abortTrigger),
    abortTrigger: abortTrigger,
    onResult: onProgress == null && onResult == null
        ? null
        : (group, processed, total) async {
            await onResult?.call(group, processed, total);
            onProgress?.call(processed, total);
          },
  );

  /// Finds same-title results while keeping source order and author preference.
  Future<SourceCandidateSearchResult> findSourceCandidates(
    String bookId, {
    Future<void>? abortTrigger,
  }) {
    final current = book(bookId);
    if (current == null) {
      return Future.value(SourceCandidateSearchResult(const []));
    }
    return findSourceCandidatesFor(current, abortTrigger: abortTrigger);
  }

  /// Returns the still-valid source candidates loaded for this shelf book.
  ///
  /// The snapshot is book-scoped: it survives a completed source switch, a
  /// moved reading position and a different target chapter, so reopening 换源
  /// shows the list the user already loaded instead of scanning every source
  /// again. Only the manual refresh control replaces it.
  ///
  /// Only shelf books use this persistence: a discovery/search result has no
  /// stable local identity to clean up when it disappears.
  Future<SourceCandidateSearchResult?> sourceCandidateCacheFor(
    Book current,
  ) async {
    if (current.sourceId == null || book(current.id) == null) return null;
    final cache = await repository.sourceCandidateCache(current.id);
    if (cache == null) return null;
    final enabledSourceIds = {
      for (final source in _sources)
        if (source.enabled) source.id,
    };
    final entries = cache.entries
        .where(
          (entry) =>
              entry.candidate.sourceId != current.sourceId &&
              entry.candidate.sourceId != null &&
              enabledSourceIds.contains(entry.candidate.sourceId),
        )
        .toList();
    // A cached list is always authoritative for this opening, including when
    // every candidate is now the current source or has been removed. Requiring
    // a nonempty list here is what made the sheet rescan all sources again.
    return SourceCandidateSearchResult(
      entries.map((entry) => entry.candidate),
      failedSources: cache.failedSources,
      candidateInfoById: {
        for (final entry in entries)
          if (entry.info != null) entry.candidate.id: entry.info!,
      },
      fromCache: true,
      loadedAt: cache.loadedAt,
    );
  }

  /// Searches again and stores the result as this book's snapshot.
  ///
  /// A complete result always replaces the previous snapshot. An incomplete one
  /// (some enabled source failed) only seeds a book that has no snapshot yet, so
  /// a partially failing refresh keeps what the user already loaded without
  /// making the next opening scan every source again.
  Future<SourceCandidateSearchResult> reloadSourceCandidatesFor(
    Book current, {
    Future<void>? abortTrigger,
    void Function(
      SourceCandidateSearchResult partial,
      int processed,
      int total,
    )?
    onUpdate,
  }) async {
    // Cache ordering is based on request start, not completion: a slow refresh
    // that finishes after a newer manual refresh must not overwrite it.
    final startedAt = DateTime.now().toUtc();
    var aborted = false;
    abortTrigger?.then((_) => aborted = true, onError: (_) => aborted = true);
    final result = await findSourceCandidatesFor(
      current,
      abortTrigger: abortTrigger,
      onUpdate: onUpdate,
    );
    final target = _sourceCandidateTarget(current);
    final sourceId = current.sourceId;
    if (!aborted && target != null && sourceId != null) {
      await repository.saveSourceCandidateCache(
        SourceCandidateCache(
          bookId: current.id,
          originSourceId: sourceId,
          targetChapterIndex: target.index,
          targetChapterId: target.id,
          targetChapterTitle: target.title,
          loadedAt: startedAt,
          failedSources: result.failedSources,
          entries: [
            for (final candidate in result.candidates)
              SourceCandidateCacheEntry(
                candidate: candidate,
                info: result.infoFor(candidate),
              ),
          ],
        ),
        replaceFreshExisting: result.hasCompleteCandidateResults,
        requireInstalledCandidateSources: true,
      );
    }
    return result;
  }

  /// Same search as [findSourceCandidates], for books that are not on the shelf.
  ///
  /// 搜索结果里的书还没加入书架也能换源，此时只有内存中的这本对象，所以直接
  /// 用传入的书籍定位同名候选。
  ///
  /// [onUpdate] emits candidates as their sources return them. A candidate's
  /// mapped chapter and word count are filled in later by a bounded metadata
  /// queue, so a usable row appears long before a long all-source search ends.
  Future<SourceCandidateSearchResult> findSourceCandidatesFor(
    Book current, {
    Future<void>? abortTrigger,
    void Function(
      SourceCandidateSearchResult partial,
      int processed,
      int total,
    )?
    onUpdate,
  }) async {
    if (!current.isRemote) {
      return SourceCandidateSearchResult(const []);
    }
    var aborted = false;
    final titleKey = _matchKey(current.title);
    final authorKey = _matchKey(current.author);
    final sourceOrderById = {
      for (final entry in _sources.where((source) => source.enabled).indexed)
        entry.$2.id: entry.$1,
    };
    final seen = <String>{};
    final ready =
        <
          String,
          ({Book book, bool authorMatch, int sourceOrder, int candidateOrder})
        >{};
    final infoById = <String, SourceCandidateInfo>{};
    final metadataQueue =
        <
          ({Book book, bool authorMatch, int sourceOrder, int candidateOrder})
        >[];
    var nextMetadata = 0;
    var activeMetadataLoads = 0;
    var searchFinished = false;
    final metadataDrained = Completer<void>();
    var failedSources = 0;
    final unavailableCandidateSourceIds = <String>{};
    var lastProcessed = 0;
    var lastTotal = 0;

    bool isEnabledAlternativeSource(String? sourceId) =>
        sourceId != null &&
        sourceId != current.sourceId &&
        _sources.any((source) => source.id == sourceId && source.enabled);

    void markUnavailableCandidateSource(String? sourceId) {
      if (!isEnabledAlternativeSource(sourceId)) return;
      if (unavailableCandidateSourceIds.add(sourceId!)) failedSources++;
    }

    late void Function() finishMetadataIfDrained;

    void cancelMetadataWaiters() {
      if (aborted) return;
      aborted = true;
      finishMetadataIfDrained();
    }

    SourceCandidateSearchResult snapshot() {
      final sorted = ready.values.toList()..sort(_compareCandidates);
      return SourceCandidateSearchResult(
        sorted.map((item) => item.book),
        failedSources: failedSources,
        unavailableCandidateSourceIds: unavailableCandidateSourceIds,
        candidateInfoById: infoById,
        pendingMetadata:
            activeMetadataLoads + metadataQueue.length - nextMetadata,
      );
    }

    void report() {
      if (aborted) return;
      onUpdate?.call(snapshot(), lastProcessed, lastTotal);
    }

    finishMetadataIfDrained = () {
      if (!metadataDrained.isCompleted &&
          (aborted ||
              (searchFinished &&
                  activeMetadataLoads == 0 &&
                  nextMetadata == metadataQueue.length))) {
        metadataDrained.complete();
      }
    };
    abortTrigger?.then(
      (_) => cancelMetadataWaiters(),
      onError: (_) => cancelMetadataWaiters(),
    );

    late void Function() scheduleMetadataLoads;

    Future<void> loadNextMetadata() async {
      if (aborted || nextMetadata >= metadataQueue.length) {
        finishMetadataIfDrained();
        return;
      }
      final item = metadataQueue[nextMetadata++];
      activeMetadataLoads++;
      try {
        final info = await _loadReadySourceCandidateInfo(
          current,
          item.book,
          abortTrigger: abortTrigger,
        );
        if (!aborted) {
          if (!isEnabledAlternativeSource(item.book.sourceId)) {
            // The source was removed or disabled mid-flight, so the candidate
            // shown optimistically for it must go away again.
            if (ready.remove(item.book.id) != null) {
              infoById.remove(item.book.id);
              report();
            }
          } else {
            if (info != null) {
              ready[item.book.id] = item;
              infoById[item.book.id] = info;
            } else {
              // The row stays selectable, only its chapter/word-count summary
              // is missing: switching loads the target anyway and reports its
              // own failure. A failed read still means this source did not
              // produce a complete candidate list, so an existing complete
              // cache must not be replaced by this truncated result.
              markUnavailableCandidateSource(item.book.sourceId);
            }
            report();
          }
        }
      } finally {
        activeMetadataLoads--;
        if (!aborted) scheduleMetadataLoads();
        finishMetadataIfDrained();
      }
    }

    scheduleMetadataLoads = () {
      // Decoration never gates the list or the search: the queue only decides
      // how many catalog reads may be in flight, and the sheet renders each row
      // as soon as its source answered.
      while (!aborted &&
          activeMetadataLoads < _sourceCandidateMetadataConcurrency &&
          nextMetadata < metadataQueue.length) {
        unawaited(loadNextMetadata());
      }
      finishMetadataIfDrained();
    };

    await searchSources(
      current.title,
      abortTrigger: abortTrigger,
      onResult: (group, processed, total) async {
        lastProcessed = processed;
        lastTotal = total;
        if (group.error != null) {
          if (_sources.any(
            (source) => source.id == group.source.id && source.enabled,
          )) {
            failedSources++;
            if (group.source.id != current.sourceId) {
              unavailableCandidateSourceIds.add(group.source.id);
            }
          }
        }
        if (isEnabledAlternativeSource(group.source.id)) {
          final sourceOrder =
              sourceOrderById[group.source.id] ?? sourceOrderById.length;
          var candidateOrder = 0;
          for (final candidate in group.books) {
            final resultOrder = candidateOrder++;
            if (!seen.add(candidate.id) ||
                _matchKey(candidate.title) != titleKey ||
                !isEnabledAlternativeSource(candidate.sourceId)) {
              continue;
            }
            // A source that returned this title is already a switchable target:
            // switching loads the catalog itself and reports its own failure.
            // Chapter mapping and word count are decoration that arrives later,
            // so they must never hold the row back — with hundreds of sources a
            // read of every candidate catalog would delay the whole list.
            final item = (
              book: candidate,
              authorMatch:
                  authorKey.isNotEmpty &&
                  _matchKey(candidate.author) == authorKey,
              sourceOrder: sourceOrder,
              candidateOrder: resultOrder,
            );
            ready[candidate.id] = item;
            metadataQueue.add(item);
          }
          // Rows are published immediately and decoration is queued without
          // blocking the search, so a slow catalog read never keeps a found
          // source off screen nor stalls the remaining sources.
          scheduleMetadataLoads();
          report();
        }
        report();
      },
    );
    searchFinished = true;
    finishMetadataIfDrained();
    await metadataDrained.future;
    return snapshot();
  }

  Future<SourceCandidateInfo?> _loadReadySourceCandidateInfo(
    Book current,
    Book candidate, {
    Future<void>? abortTrigger,
  }) async {
    var aborted = false;
    abortTrigger?.then((_) => aborted = true, onError: (_) => aborted = true);
    try {
      final sourceId = candidate.sourceId;
      if (sourceId == null) return null;
      final source = _source(sourceId);
      final loaded = await engine.loadBook(
        source,
        candidate,
        abortTrigger: abortTrigger,
      );
      if (aborted) return null;
      final plan = const SourceSwitchMapper().plan(
        current: current,
        replacement: loaded,
        bookmarks: const [],
      );
      final mappedIndex = plan.book.position.chapterIndex;
      if (mappedIndex < 0 || mappedIndex >= loaded.chapters.length) return null;
      final mappedChapter = loaded.chapters[mappedIndex];
      final chapter = await engine.loadChapter(
        source,
        mappedChapter,
        abortTrigger: abortTrigger,
      );
      if (aborted) return null;
      final info = SourceCandidateInfo(
        chapterCount: loaded.chapters.length,
        mappedChapterIndex: mappedIndex,
        mappedChapterTitle: mappedChapter.title,
        wordCount: _chapterWordCount(chapter),
      );
      return info.isReadyForDisplay ? info : null;
    } catch (_) {
      // A source that cannot supply the mapped chapter or content is not a
      // usable switch target, so it is deliberately omitted from the list.
      return null;
    }
  }

  ({int index, String id, String title})? _sourceCandidateTarget(Book current) {
    if (current.chapters.isEmpty) return null;
    final index = current.position.chapterIndex
        .clamp(0, current.chapters.length - 1)
        .toInt();
    final chapter = current.chapters[index];
    return (index: index, id: chapter.id, title: chapter.title);
  }

  static int _chapterWordCount(Chapter chapter) =>
      chapter.paragraphs.join().replaceAll(RegExp(r'\s+'), '').runes.length;

  static int _compareCandidates(
    ({Book book, bool authorMatch, int sourceOrder, int candidateOrder}) left,
    ({Book book, bool authorMatch, int sourceOrder, int candidateOrder}) right,
  ) {
    final author = (right.authorMatch ? 1 : 0).compareTo(
      left.authorMatch ? 1 : 0,
    );
    if (author != 0) return author;
    final source = left.sourceOrder.compareTo(right.sourceOrder);
    if (source != 0) return source;
    final candidate = left.candidateOrder.compareTo(right.candidateOrder);
    return candidate != 0 ? candidate : left.book.id.compareTo(right.book.id);
  }

  /// Rebinds one shelf book only after target content and persistence succeed.
  /// Rejects a destination change during loading so callers can retry explicitly.
  ///
  /// 不在书架的书（例如还没加入书架、只在发现页看到的搜索结果）换源只做内存
  /// 替换：加载目标书源的书目后直接返回，不写数据库，也没有书签与进度需要迁移，
  /// 与 Legado 对未上架书籍的处理一致。
  Future<Book> switchBookSource(String bookId, Book candidate) async {
    final current = book(bookId);
    if (candidate.sourceId == null) {
      throw const SourceException('请选择其他可用书源。');
    }
    if (current == null) {
      final source = _source(candidate.sourceId!);
      return engine.loadBook(source, candidate);
    }
    if (!current.isRemote) {
      throw const SourceException('只有书架中的网络书籍可以换源。');
    }
    if (candidate.sourceId == current.sourceId) {
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
      expectedTargetSourceId: candidate.sourceId,
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

  Future<ReaderStylePreset> saveReaderStylePreset(
    String name,
    ReaderSettings settings,
  ) async {
    final preset = await repository.saveReaderStylePreset(name, settings);
    _readerStylePresets = [..._readerStylePresets, preset];
    _notify();
    return preset;
  }

  Future<void> deleteReaderStylePreset(String id) async {
    await repository.deleteReaderStylePreset(id);
    _readerStylePresets = _readerStylePresets
        .where((preset) => preset.id != id)
        .toList();
    _notify();
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    final current = book(bookmark.bookId);
    if (current != null &&
        bookmark.chapterIndex >= 0 &&
        bookmark.chapterIndex < current.chapters.length &&
        _cacheClears.contains(_chapterKey(current, bookmark.chapterIndex))) {
      throw StateError('章节缓存正在清理，书签未保存。');
    }
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

  Future<ReaderMark> addReaderMark(
    String bookId,
    int chapterIndex,
    int paragraphIndex, {
    required ReaderMarkColor color,
    required String note,
    String? selectedText,
  }) async {
    final current = book(bookId);
    if (current == null ||
        chapterIndex < 0 ||
        chapterIndex >= current.chapters.length ||
        paragraphIndex < 0 ||
        paragraphIndex >= current.chapters[chapterIndex].paragraphs.length) {
      throw StateError('书籍、章节或段落已变化，未保存段落标注。');
    }
    if (_cacheClears.contains(_chapterKey(current, chapterIndex))) {
      throw StateError('章节缓存正在清理，未保存段落标注。');
    }
    final paragraph = current.chapters[chapterIndex].paragraphs[paragraphIndex];
    final normalizedSelectedText = ReaderMark.validateSelectedText(
      selectedText,
    );
    if (normalizedSelectedText != null &&
        !ReaderMark.hasUniqueOccurrence(paragraph, normalizedSelectedText)) {
      throw const FormatException('选中文字已变化或在段落中不唯一。');
    }
    final mark = await repository.saveReaderMark(
      current,
      chapterIndex,
      paragraphIndex,
      color: color,
      note: note,
      selectedText: normalizedSelectedText,
      paragraphFingerprint: ReaderMark.fingerprint(paragraph),
    );
    _readerMarks = [
      mark,
      ..._readerMarks.where((existing) => existing.id != mark.id),
    ];
    _notify();
    return mark;
  }

  Future<void> deleteReaderMark(String id) async {
    await repository.deleteReaderMark(id);
    _readerMarks = _readerMarks.where((mark) => mark.id != id).toList();
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

/// Summary of one user-requested bounded batch; downloaded chapters remain cached.
final class ChapterCacheBatchResult {
  ChapterCacheBatchResult({
    required this.requested,
    required this.completed,
    required this.downloaded,
    required this.skippedCached,
    required Iterable<int> failedIndices,
    required this.cancelled,
  }) : failedIndices = List.unmodifiable(failedIndices);

  final int requested;
  final int completed;
  final int downloaded;
  final int skippedCached;
  final List<int> failedIndices;
  final bool cancelled;
}

/// Ranked manual-switch candidates and failures among all searched enabled sources.
/// The failure count also includes the current source, although its books are excluded.
class SourceCandidateSearchResult {
  SourceCandidateSearchResult(
    Iterable<Book> candidates, {
    this.failedSources = 0,
    Iterable<String> unavailableCandidateSourceIds = const [],
    Map<String, SourceCandidateInfo> candidateInfoById = const {},
    this.pendingMetadata = 0,
    this.fromCache = false,
    this.loadedAt,
  }) : candidates = List.unmodifiable(candidates),
       unavailableCandidateSourceIds = Set.unmodifiable(
         unavailableCandidateSourceIds,
       ),
       candidateInfoById = Map.unmodifiable(candidateInfoById);

  final List<Book> candidates;
  final int failedSources;

  /// Enabled alternative sources that did not finish this search. A result with
  /// any of these missing must not replace a complete persisted snapshot.
  final Set<String> unavailableCandidateSourceIds;

  bool get hasCompleteCandidateResults => unavailableCandidateSourceIds.isEmpty;

  /// Metadata is kept separate from [Book] so a search candidate never leaks
  /// source-switch-only state into shelf data or normal discovery results.
  final Map<String, SourceCandidateInfo> candidateInfoById;

  /// Candidate metadata still in the bounded load queue for a live search.
  /// Cached and final results always report zero.
  final int pendingMetadata;

  /// True when this is the last successful source search restored from disk.
  final bool fromCache;

  /// The UTC time that a cached snapshot was last fully loaded.
  final DateTime? loadedAt;

  SourceCandidateInfo? infoFor(Book candidate) =>
      candidateInfoById[candidate.id];
}

class SourceSearchGroup {
  const SourceSearchGroup(this.source, this.books, {this.error});
  final BookSource source;
  final List<Book> books;
  final String? error;
}
