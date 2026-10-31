import 'package:sembast/sembast.dart';

import '../domain/book.dart';
import '../domain/book_source.dart';
import '../domain/reader_settings.dart';
import '../domain/source_import.dart';
import 'sample_catalog.dart';

class AppRepository {
  AppRepository(this.database);

  final Database database;
  final _books = stringMapStoreFactory.store('books');
  final _notes = stringMapStoreFactory.store('bookmarks');
  final _sources = stringMapStoreFactory.store('sources');
  final _sourceStates = stringMapStoreFactory.store('source_state');
  final _meta = stringMapStoreFactory.store('meta');

  Future<void> initialize() async {
    if (await _meta.record('seed').exists(database)) return;
    final catalog = await loadSampleCatalog();
    // 并发首启也只播种一次；标记独立于书架，用户清空后不再灌入。
    await database.transaction((transaction) async {
      if (await _meta.record('seed').exists(transaction)) return;
      for (final book in catalog.take(3)) {
        await _books
            .record(book.id)
            .put(transaction, book.copyWith(addedAt: DateTime.now()).toJson());
      }
      await _meta.record('seed').put(transaction, {'version': 1});
    });
  }

  Future<List<Book>> books() async => [
    for (final record in await _books.find(database))
      Book.fromJson(Map<String, dynamic>.from(record.value)),
  ];

  Future<void> saveBook(Book book) async {
    await _books.record(book.id).put(database, book.toJson());
  }

  Future<void> removeBook(String id) async {
    await database.transaction((transaction) async {
      await _books.record(id).delete(transaction);
      await _notes.delete(
        transaction,
        finder: Finder(filter: Filter.equals('bookId', id)),
      );
    });
  }

  /// Updates progress atomically without replacing content or recreating a book.
  /// With expectedBook, rejects a missing or changed source/URL/TOC slot via StateError.
  /// Without it, legacy writes to missing records remain no-ops. Storage errors propagate.
  Future<void> savePosition(
    String id,
    ReadingPosition position, {
    bool? finished,
    Book? expectedBook,
  }) async {
    await database.transaction((transaction) async {
      final record = _books.record(id);
      final json = await record.get(transaction);
      if (json == null) {
        if (expectedBook != null) throw StateError('书籍已移除，阅读进度未保存。');
        return;
      }
      if (expectedBook != null) {
        // Only inspect binding metadata; progress saves must not clone cached text.
        final index = position.chapterIndex;
        final chapters = json['chapters'] as List? ?? const [];
        if (expectedBook.id != id ||
            json['sourceId'] != expectedBook.sourceId ||
            json['url'] != expectedBook.url ||
            index < 0 ||
            index >= expectedBook.chapters.length ||
            index >= chapters.length ||
            (chapters[index] as Map)['id'] != expectedBook.chapters[index].id) {
          throw StateError('书籍来源或章节已变化，旧阅读进度未应用到当前书籍。');
        }
      }
      await record.update(transaction, {
        'position': position.toJson(),
        'lastOpenedAt': DateTime.now().toIso8601String(),
        'finished': ?finished,
      });
    });
  }

  /// Changes only the cover of an existing, still-bound book.
  /// Returns null without writing if removed/rebound; storage errors propagate.
  Future<Book?> updateBookCover(
    String bookId,
    String coverUrl, {
    required String? expectedSourceId,
  }) => database.transaction((transaction) async {
    final json = await _books.record(bookId).get(transaction);
    if (json == null) return null;
    final current = Book.fromJson(Map<String, dynamic>.from(json));
    if (current.sourceId != expectedSourceId) return null;
    final updated = current.copyWith(coverUrl: coverUrl);
    await _books.record(bookId).put(transaction, updated.toJson());
    return updated;
  });

  /// Replaces one existing source binding and its note positions atomically.
  /// Optional source/position expectations reject stale plans before writing.
  /// Any failure rolls back both; note text edits and deletions are preserved.
  Future<void> replaceBookSource(
    Book book,
    Iterable<Bookmark> bookmarks, {
    String? expectedSourceId,
    ReadingPosition? expectedPosition,
  }) async {
    await database.transaction((transaction) async {
      final existing = await _books.record(book.id).get(transaction);
      if (existing == null) throw StateError('书籍已移除，未执行换源。');
      final current = Book.fromJson(Map<String, dynamic>.from(existing));
      if (expectedSourceId != null && current.sourceId != expectedSourceId) {
        throw StateError('书籍来源已变化，请重新选择书源。');
      }
      if (expectedPosition != null &&
          (current.position.chapterIndex != expectedPosition.chapterIndex ||
              current.position.paragraphIndex !=
                  expectedPosition.paragraphIndex)) {
        throw StateError('阅读位置已变化，请重试换源。');
      }
      await _books.record(book.id).put(transaction, book.toJson());
      for (final bookmark in bookmarks) {
        if (bookmark.bookId != book.id) {
          throw ArgumentError.value(
            bookmark.bookId,
            'bookmarks',
            'must belong to ${book.id}',
          );
        }
        // Only move anchors; concurrent note text edits and deletions stay authoritative.
        await _notes.record(bookmark.id).update(transaction, {
          'chapterIndex': bookmark.chapterIndex,
          'paragraphIndex': bookmark.paragraphIndex,
        });
      }
    });
  }

  /// Caches a chapter only while its original source and TOC slot still match.
  /// Merges the latest record; false means stale/removed and no write occurred.
  /// True means the cache write committed; storage errors propagate.
  Future<bool> cacheChapter(
    String bookId,
    int index,
    Chapter chapter, {
    required String expectedSourceId,
    required String expectedChapterId,
  }) async {
    // A download started before a source switch must not contaminate the new TOC.
    return database.transaction((transaction) async {
      final json = await _books.record(bookId).get(transaction);
      if (json == null) return false;
      final book = Book.fromJson(Map<String, dynamic>.from(json));
      if (index < 0 || index >= book.chapters.length) return false;
      if (book.sourceId != expectedSourceId ||
          book.chapters[index].id != expectedChapterId) {
        return false;
      }
      final chapters = [...book.chapters]..[index] = chapter;
      await _books
          .record(bookId)
          .put(transaction, book.copyWith(chapters: chapters).toJson());
      return true;
    });
  }

  Future<ReaderSettings> settings() async => ReaderSettings.fromJson(
    Map<String, dynamic>.from(
      await _meta.record('settings').get(database) ?? {},
    ),
  );

  Future<void> saveSettings(ReaderSettings settings) async {
    await _meta.record('settings').put(database, settings.toJson());
  }

  Future<List<Bookmark>> bookmarks() async {
    final records = await _notes.find(
      database,
      finder: Finder(sortOrders: [SortOrder('createdAt', false)]),
    );
    return [
      for (final record in records)
        Bookmark.fromJson(Map<String, dynamic>.from(record.value)),
    ];
  }

  Future<void> saveBookmark(Bookmark bookmark) async {
    await _notes.record(bookmark.id).put(database, bookmark.toJson());
  }

  Future<void> deleteBookmark(String id) async {
    await _notes.record(id).delete(database);
  }

  Future<List<BookSource>> sources() async => [
    for (final record in await _sources.find(database))
      BookSource(Map<String, dynamic>.from(record.value)),
  ];

  Future<void> saveSources(List<BookSource> sources) async {
    await database.transaction((transaction) async {
      for (final source in sources) {
        await _sources.record(source.id).put(transaction, source.toJson());
      }
    });
  }

  Future<SourceImportCommitResult> commitSourceImport(
    SourceImportPreview preview, {
    Set<String>? selectedSourceIds,
  }) async {
    final selected =
        selectedSourceIds ?? {for (final source in preview.sources) source.id};
    var added = 0;
    var updated = 0;
    final committed = <String>[];
    await database.transaction((transaction) async {
      for (final source in preview.sources) {
        if (!selected.contains(source.id)) continue;
        final record = _sources.record(source.id);
        final existing = await record.get(transaction);
        final json = source.toJson();
        if (existing == null) {
          added++;
        } else {
          updated++;
          final localEnabled = existing['enabled'];
          if (localEnabled is bool) json['enabled'] = localEnabled;
        }
        await record.put(transaction, json);
        await _sourceStates
            .record(source.id)
            .put(
              transaction,
              SourceImportState(
                sourceId: source.id,
                kind: preview.provenance.kind,
                label: preview.provenance.label,
                requestedUri: preview.provenance.requestedUri,
                finalUri: preview.provenance.finalUri,
                responseBytes: preview.provenance.responseBytes,
                contentType: preview.provenance.contentType,
              ).toJson(),
            );
        committed.add(source.id);
      }
    });
    return SourceImportCommitResult(
      added: added,
      updated: updated,
      sourceIds: committed,
    );
  }

  Future<SourceImportState?> sourceState(String id) async {
    final json = await _sourceStates.record(id).get(database);
    return json == null
        ? null
        : SourceImportState.fromJson(Map<String, dynamic>.from(json));
  }

  Future<void> saveSource(BookSource source) => saveSources([source]);

  Future<void> setSourceEnabled(String id, bool enabled) async {
    await _sources.record(id).update(database, {'enabled': enabled});
  }

  Future<void> deleteSource(String id) async {
    await database.transaction((transaction) async {
      await _sources.record(id).delete(transaction);
      await _sourceStates.record(id).delete(transaction);
    });
  }
}
