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

  Future<void> savePosition(
    String id,
    ReadingPosition position, {
    bool? finished,
  }) async {
    // 迟到的进度写入不能重新创建已被删除的书籍。
    await _books.record(id).update(database, {
      'position': position.toJson(),
      'lastOpenedAt': DateTime.now().toIso8601String(),
      'finished': ?finished,
    });
  }

  Future<void> cacheChapter(String bookId, int index, Chapter chapter) async {
    // 下载期间进度可能已更新，必须在事务中合并最新记录而非下载前快照。
    await database.transaction((transaction) async {
      final json = await _books.record(bookId).get(transaction);
      if (json == null) return;
      final book = Book.fromJson(Map<String, dynamic>.from(json));
      if (index < 0 || index >= book.chapters.length) return;
      final chapters = [...book.chapters]..[index] = chapter;
      await _books
          .record(bookId)
          .put(transaction, book.copyWith(chapters: chapters).toJson());
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
