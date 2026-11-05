import 'dart:typed_data';

import 'package:sembast/sembast.dart';

import '../domain/book.dart';
import '../domain/book_source.dart';
import '../domain/change_source_settings.dart';
import '../domain/explore_kind.dart';
import '../domain/reader_settings.dart';
import '../domain/reader_style_preset.dart';
import '../domain/reader_mark.dart';
import '../domain/reading_activity.dart';
import '../domain/shelf_group.dart';
import '../domain/source_check_settings.dart';
import '../domain/source_health.dart';
import '../domain/source_import.dart';
import '../domain/source_switch_candidate.dart';
import '../services/book_text_rules.dart';
import '../services/encrypted_local_backup.dart';
import '../services/local_backup.dart';
import '../services/source_runtime/content_normalizer.dart';
import 'sample_catalog.dart';

class AppRepository {
  AppRepository(this.database);

  final Database database;
  final _books = stringMapStoreFactory.store('books');
  final _notes = stringMapStoreFactory.store('bookmarks');
  final _readerMarks = stringMapStoreFactory.store('reader_marks');
  final _readingActivity = stringMapStoreFactory.store('reading_activity');
  final _shelfGroups = stringMapStoreFactory.store('shelf_groups');
  final _textRules = stringMapStoreFactory.store('book_text_rules');
  final _readerStylePresets = stringMapStoreFactory.store(
    'reader_style_presets',
  );
  final _sources = stringMapStoreFactory.store('sources');
  final _sourceStates = stringMapStoreFactory.store('source_state');
  final _sourceExploreInfo = stringMapStoreFactory.store('source_explore_info');
  final _sourceSwitchCandidateCaches = stringMapStoreFactory.store(
    'source_switch_candidate_cache',
  );
  final _meta = stringMapStoreFactory.store('meta');

  /// Bumped whenever stored chapter text must be re-derived on open.
  static const _contentSplitVersion = 1;

  Future<void> initialize() async {
    if (!await _meta.record('seed').exists(database)) {
      final catalog = await loadSampleCatalog();
      // 并发首启也只播种一次；标记独立于书架，用户清空后不再灌入。
      await database.transaction((transaction) async {
        if (await _meta.record('seed').exists(transaction)) return;
        for (final book in catalog.take(3)) {
          await _books
              .record(book.id)
              .put(
                transaction,
                book.copyWith(addedAt: DateTime.now()).toJson(),
              );
        }
        await _meta.record('seed').put(transaction, {'version': 1});
      });
    }
    // Whitespace alone cannot prove that a cached chapter needs re-splitting.
    final contentSplit = await _meta.record('contentSplit').get(database);
    if (contentSplit?['requested'] == true) {
      await _migrateCachedParagraphs();
    }
  }

  /// Chapters cached before gap-aware splitting hold a whole chapter in one
  /// paragraph. Re-split them once and move each saved anchor onto the
  /// sub-paragraph that replaced it, so reading position and notes never jump.
  Future<void> _migrateCachedParagraphs() async {
    final marker = _meta.record('contentSplit');
    final stored = await marker.get(database);
    if ((stored?['version'] as num?)?.toInt() == _contentSplitVersion) return;
    const normalizer = ContentNormalizer();
    await database.transaction((transaction) async {
      final moved = <String, Map<int, Map<int, int>>>{};
      for (final record in await _books.find(transaction)) {
        final json = Map<String, dynamic>.from(record.value);
        final chapters = json['chapters'] as List? ?? const [];
        final remaps = <int, Map<int, int>>{};
        final updated = <Map<String, dynamic>>[];
        for (var index = 0; index < chapters.length; index++) {
          final chapter = Map<String, dynamic>.from(chapters[index] as Map);
          final paragraphs = (chapter['paragraphs'] as List? ?? const [])
              .cast<String>();
          if (paragraphs.isEmpty) {
            updated.add(chapter);
            continue;
          }
          final split = <String>[];
          final remap = <int, int>{};
          for (var offset = 0; offset < paragraphs.length; offset++) {
            final parts = normalizer.splitParagraphs(
              paragraphs[offset],
              decode: false,
            );
            if (parts.isEmpty) continue;
            remap[offset] = split.length;
            split.addAll(parts);
          }
          if (split.length == paragraphs.length) {
            updated.add(chapter);
            continue;
          }
          remaps[index] = remap;
          updated.add({...chapter, 'paragraphs': split});
        }
        if (remaps.isEmpty) continue;
        moved[record.key] = remaps;
        final position = Map<String, dynamic>.from(
          json['position'] as Map? ?? const {},
        );
        final chapterIndex = (position['chapterIndex'] as num?)?.toInt() ?? 0;
        final paragraphIndex =
            (position['paragraphIndex'] as num?)?.toInt() ?? 0;
        await _books.record(record.key).put(transaction, {
          ...json,
          'chapters': updated,
          'position': {
            ...position,
            'paragraphIndex':
                remaps[chapterIndex]?[paragraphIndex] ?? paragraphIndex,
          },
        });
      }
      for (final record in await _notes.find(transaction)) {
        final remaps = moved[record.value['bookId']];
        if (remaps == null) continue;
        final chapterIndex =
            (record.value['chapterIndex'] as num?)?.toInt() ?? 0;
        final paragraphIndex =
            (record.value['paragraphIndex'] as num?)?.toInt() ?? 0;
        final target = remaps[chapterIndex]?[paragraphIndex];
        if (target == null || target == paragraphIndex) continue;
        await _notes.record(record.key).update(transaction, {
          'paragraphIndex': target,
        });
      }
      await marker.put(transaction, {'version': _contentSplitVersion});
    });
  }

  Future<List<Book>> books() async => [
    for (final record in await _books.find(database))
      Book.fromJson(Map<String, dynamic>.from(record.value)),
  ];

  /// Returns the unexpired source-switch snapshot stored for [bookId].
  ///
  /// The snapshot is book-scoped on purpose: a completed source switch, a moved
  /// reading position and a different target chapter must all keep reusing the
  /// candidate list the user already loaded instead of scanning every source
  /// again. Only unreadable or expired records are removed here.
  Future<SourceCandidateCache?> sourceCandidateCache(
    String bookId, {
    DateTime? now,
  }) async {
    final record = _sourceSwitchCandidateCaches.record(
      SourceCandidateCache.recordKey(bookId),
    );
    final stored = await record.get(database);
    if (stored == null) return null;
    SourceCandidateCache cache;
    try {
      cache = SourceCandidateCache.fromJson(Map<String, dynamic>.from(stored));
    } on FormatException {
      await record.delete(database);
      return null;
    } on TypeError {
      await record.delete(database);
      return null;
    }
    if (cache.bookId != bookId || !cache.isFreshAt(now ?? DateTime.now())) {
      await record.delete(database);
      return null;
    }
    return cache;
  }

  /// Saves the source-switch snapshot for its book.
  ///
  /// Returns false when the book is gone or when the write must be skipped:
  /// a slow search started before a manual refresh must not overwrite a newer
  /// result (equal request-start times keep the first saved snapshot), and an
  /// incomplete manual refresh must not replace the snapshot the
  /// user already has. An incomplete result still seeds a book without any
  /// snapshot yet — otherwise a book whose source list always contains a few
  /// dead sources would never cache anything and would rescan on every open.
  /// When [requireInstalledCandidateSources] is true, the transaction also
  /// rejects a refresh whose candidates were all deleted or disabled mid-load.
  Future<bool> saveSourceCandidateCache(
    SourceCandidateCache cache, {
    bool replaceFreshExisting = true,
    bool requireInstalledCandidateSources = false,
    DateTime? now,
  }) async {
    final checkedAt = now ?? DateTime.now();
    return database.transaction((transaction) async {
      if (await _books.record(cache.bookId).get(transaction) == null) {
        return false;
      }
      var snapshot = cache;
      if (requireInstalledCandidateSources && cache.entries.isNotEmpty) {
        final installed = <SourceCandidateCacheEntry>[];
        for (final entry in cache.entries) {
          final sourceId = entry.candidate.sourceId;
          if (sourceId == null) continue;
          final storedSource = await _sources.record(sourceId).get(transaction);
          if (storedSource != null && storedSource['enabled'] != false) {
            installed.add(entry);
          }
        }
        // If an in-flight refresh now contains only sources that were deleted
        // or disabled, do not resurrect a fresh authoritative empty snapshot.
        // A delete that follows this transaction will prune it atomically too.
        if (installed.isEmpty) return false;
        if (installed.length != cache.entries.length) {
          snapshot = cache.copyWith(entries: installed);
        }
      }
      final key = SourceCandidateCache.recordKey(snapshot.bookId);
      final stored = await _sourceSwitchCandidateCaches
          .record(key)
          .get(transaction);
      if (stored != null) {
        try {
          final existing = SourceCandidateCache.fromJson(
            Map<String, dynamic>.from(stored),
          );
          if (existing.isFreshAt(checkedAt)) {
            if (!replaceFreshExisting) return false;
            if (!existing.loadedAt.toUtc().isBefore(
              snapshot.loadedAt.toUtc(),
            )) {
              return false;
            }
          }
        } on FormatException {
          // An unreadable leftover is replaced by the snapshot below.
        } on TypeError {
          // An unreadable leftover is replaced by the snapshot below.
        }
      }
      await _sourceSwitchCandidateCaches
          .record(key)
          .put(transaction, snapshot.toJson());
      return true;
    });
  }

  Future<List<ShelfGroup>> shelfGroups() async {
    final groups = [
      for (final record in await _shelfGroups.find(database))
        ShelfGroup.fromJson(
          record.key,
          Map<String, dynamic>.from(record.value),
        ),
    ];
    groups.sort((a, b) {
      final order = a.createdAt.compareTo(b.createdAt);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return groups;
  }

  static String _groupName(String value) {
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.runes.length > 24) {
      throw const FormatException('分组名称需为 1–24 个字。');
    }
    return name;
  }

  Future<ShelfGroup> createShelfGroup(String value) async {
    final name = _groupName(value);
    return database.transaction((transaction) async {
      final existing = await _shelfGroups.find(transaction);
      if (existing.length >= 32) throw StateError('最多可创建 32 个分组。');
      if (existing.any(
        (item) =>
            (item.value['name'] as String).toLowerCase() == name.toLowerCase(),
      )) {
        throw StateError('已存在同名分组。');
      }
      final now = DateTime.now();
      var id = 'group-${now.microsecondsSinceEpoch.toRadixString(36)}';
      while (await _shelfGroups.record(id).exists(transaction)) {
        id = '${id}_';
      }
      final group = ShelfGroup(id: id, name: name, createdAt: now);
      await _shelfGroups.record(id).put(transaction, group.toJson());
      return group;
    });
  }

  Future<void> renameShelfGroup(String id, String value) async {
    final name = _groupName(value);
    await database.transaction((transaction) async {
      if (!await _shelfGroups.record(id).exists(transaction)) {
        throw StateError('分组已不存在。');
      }
      final groups = await _shelfGroups.find(transaction);
      if (groups.any(
        (item) =>
            item.key != id &&
            (item.value['name'] as String).toLowerCase() == name.toLowerCase(),
      )) {
        throw StateError('已存在同名分组。');
      }
      await _shelfGroups.record(id).update(transaction, {'name': name});
    });
  }

  Future<void> deleteShelfGroup(String id) async {
    await database.transaction((transaction) async {
      if (!await _shelfGroups.record(id).exists(transaction)) {
        throw StateError('分组已不存在。');
      }
      await _shelfGroups.record(id).delete(transaction);
    });
  }

  Future<void> setShelfGroupMembership(
    String groupId,
    String bookId,
    bool included,
  ) async {
    await database.transaction((transaction) async {
      if (!await _books.record(bookId).exists(transaction)) {
        throw StateError('书籍已移出书架。');
      }
      final record = _shelfGroups.record(groupId);
      final stored = await record.get(transaction);
      if (stored == null) throw StateError('分组已不存在。');
      final ids = Set<String>.from(
        (stored['bookIds'] as List? ?? const []).cast<String>(),
      );
      if (included ? !ids.add(bookId) : !ids.remove(bookId)) return;
      await record.update(transaction, {'bookIds': ids.toList()});
    });
  }

  static List<BookTextRule> _decodeTextRules(Map<String, dynamic>? stored) {
    final rules = <BookTextRule>[
      for (final raw in (stored?['rules'] as List? ?? const []))
        BookTextRule.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];
    if (rules.length > BookTextRules.maxRulesPerBook) {
      throw StateError('替换规则超出单本书上限。');
    }
    for (final rule in rules) {
      BookTextRules.validate(rule.needle, rule.replacement);
    }
    return rules;
  }

  Future<List<BookTextRule>> textRules(String bookId) async =>
      List<BookTextRule>.unmodifiable(
        _decodeTextRules(await _textRules.record(bookId).get(database)),
      );

  Future<Map<String, List<BookTextRule>>> allTextRules() async =>
      Map<String, List<BookTextRule>>.unmodifiable({
        for (final record in await _textRules.find(database))
          record.key: List<BookTextRule>.unmodifiable(
            _decodeTextRules(record.value),
          ),
      });

  Future<T> _changeTextRules<T>(
    String bookId,
    T Function(List<BookTextRule> rules) change,
  ) => database.transaction((transaction) async {
    if (!await _books.record(bookId).exists(transaction)) {
      throw StateError('书籍已移出书架。');
    }
    final record = _textRules.record(bookId);
    final rules = _decodeTextRules(await record.get(transaction));
    final result = change(rules);
    if (rules.isEmpty) {
      await record.delete(transaction);
    } else {
      await record.put(transaction, {
        'rules': [for (final rule in rules) rule.toJson()],
      });
    }
    return result;
  });

  Future<BookTextRule> addTextRule(
    String bookId,
    String needle,
    String replacement,
  ) {
    BookTextRules.validate(needle, replacement);
    return _changeTextRules<BookTextRule>(bookId, (rules) {
      if (rules.length >= BookTextRules.maxRulesPerBook) {
        throw StateError('每本书最多添加 ${BookTextRules.maxRulesPerBook} 条替换规则。');
      }
      var id =
          'rule-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      while (rules.any((rule) => rule.id == id)) {
        id = '${id}_';
      }
      final created = BookTextRule(
        id: id,
        needle: needle,
        replacement: replacement,
      );
      rules.add(created);
      return created;
    });
  }

  Future<void> updateTextRule(
    String bookId,
    String ruleId,
    String needle,
    String replacement,
  ) async {
    BookTextRules.validate(needle, replacement);
    await _changeTextRules<void>(bookId, (rules) {
      final index = rules.indexWhere((rule) => rule.id == ruleId);
      if (index < 0) throw StateError('替换规则已不存在。');
      rules[index] = rules[index].copyWith(
        needle: needle,
        replacement: replacement,
      );
    });
  }

  Future<void> setTextRuleEnabled(
    String bookId,
    String ruleId,
    bool enabled,
  ) async {
    await _changeTextRules<void>(bookId, (rules) {
      final index = rules.indexWhere((rule) => rule.id == ruleId);
      if (index < 0) throw StateError('替换规则已不存在。');
      rules[index] = rules[index].copyWith(enabled: enabled);
    });
  }

  Future<void> moveTextRule(String bookId, String ruleId, int delta) async {
    if (delta != -1 && delta != 1) throw ArgumentError.value(delta, 'delta');
    await _changeTextRules<void>(bookId, (rules) {
      final index = rules.indexWhere((rule) => rule.id == ruleId);
      if (index < 0) throw StateError('替换规则已不存在。');
      final next = index + delta;
      if (next < 0 || next >= rules.length) return;
      final item = rules.removeAt(index);
      rules.insert(next, item);
    });
  }

  Future<void> deleteTextRule(String bookId, String ruleId) async {
    await _changeTextRules<void>(bookId, (rules) {
      if (!rules.any((rule) => rule.id == ruleId)) {
        throw StateError('替换规则已不存在。');
      }
      rules.removeWhere((rule) => rule.id == ruleId);
    });
  }

  Future<void> saveBook(Book book) async {
    await _books.record(book.id).put(database, book.toJson());
  }

  Future<void> saveBooks(Iterable<Book> books) async {
    final values = List<Book>.unmodifiable(books);
    final ids = values.map((book) => book.id).toSet();
    if (ids.length != values.length) {
      throw ArgumentError.value(books, 'books', 'must have unique IDs');
    }
    await database.transaction((transaction) async {
      for (final book in values) {
        await _books.record(book.id).put(transaction, book.toJson());
      }
    });
  }

  Future<void> removeBook(String id) async {
    await database.transaction((transaction) async {
      await _books.record(id).delete(transaction);
      await _notes.delete(
        transaction,
        finder: Finder(filter: Filter.equals('bookId', id)),
      );
      await _readerMarks.delete(
        transaction,
        finder: Finder(filter: Filter.equals('bookId', id)),
      );
      await _readingActivity.delete(
        transaction,
        finder: Finder(filter: Filter.equals('bookId', id)),
      );
      await _textRules.record(id).delete(transaction);
      await _sourceSwitchCandidateCaches.delete(
        transaction,
        finder: Finder(filter: Filter.equals('bookId', id)),
      );
      for (final record in await _shelfGroups.find(transaction)) {
        final ids = (record.value['bookIds'] as List? ?? const [])
            .cast<String>();
        if (!ids.contains(id)) continue;
        await _shelfGroups.record(record.key).update(transaction, {
          'bookIds': [
            for (final member in ids)
              if (member != id) member,
          ],
        });
      }
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
  /// Optional current/target-source and position expectations reject stale
  /// plans before writing.
  /// Any failure rolls back both; note text edits and deletions are preserved.
  Future<void> replaceBookSource(
    Book book,
    Iterable<Bookmark> bookmarks, {
    String? expectedSourceId,
    String? expectedTargetSourceId,
    ReadingPosition? expectedPosition,
  }) async {
    await database.transaction((transaction) async {
      final existing = await _books.record(book.id).get(transaction);
      if (existing == null) throw StateError('书籍已移除，未执行换源。');
      final current = Book.fromJson(Map<String, dynamic>.from(existing));
      if (expectedSourceId != null && current.sourceId != expectedSourceId) {
        throw StateError('书籍来源已变化，请重新选择书源。');
      }
      if (expectedTargetSourceId != null) {
        if (book.sourceId != expectedTargetSourceId) {
          throw StateError('目标书源已变化，请重新选择书源。');
        }
        final target = await _sources
            .record(expectedTargetSourceId)
            .get(transaction);
        if (target == null || target['enabled'] == false) {
          throw StateError('目标书源已移除或停用，未执行换源。');
        }
      }
      if (expectedPosition != null &&
          (current.position.chapterIndex != expectedPosition.chapterIndex ||
              current.position.paragraphIndex !=
                  expectedPosition.paragraphIndex)) {
        throw StateError('阅读位置已变化，请重试换源。');
      }
      await _books.record(book.id).put(transaction, book.toJson());
      // The candidate snapshot belongs to the book, not to the source that
      // produced it: reopening 换源 after a successful switch must still show
      // the list the user already loaded instead of scanning every source
      // again. Only an explicit manual refresh replaces it.
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

  Future<Book> clearCachedChapters(Book expectedBook, List<int> indices) async {
    if (indices.isEmpty ||
        indices.length > 5 ||
        indices.toSet().length != indices.length ||
        indices.any(
          (index) => index < 0 || index >= expectedBook.chapters.length,
        )) {
      throw ArgumentError.value(
        indices,
        'indices',
        'select 1–5 distinct chapters',
      );
    }
    if (!expectedBook.isRemote) throw StateError('本地书籍的正文不能清理。');

    return database.transaction((transaction) async {
      final record = _books.record(expectedBook.id);
      final json = await record.get(transaction);
      if (json == null) throw StateError('书籍已移出书架，缓存未清理。');
      final current = Book.fromJson(Map<String, dynamic>.from(json));
      if (!current.isRemote ||
          current.sourceId != expectedBook.sourceId ||
          current.url != expectedBook.url) {
        throw StateError('书籍来源已变化，缓存未清理。');
      }

      final protected = <int>{current.position.chapterIndex};
      for (final note in await _notes.find(
        transaction,
        finder: Finder(filter: Filter.equals('bookId', expectedBook.id)),
      )) {
        final index = note.value['chapterIndex'];
        if (index is! num) throw StateError('笔记锚点异常，缓存未清理。');
        protected.add(index.toInt());
      }
      final chapters = [...current.chapters];
      for (final index in indices) {
        if (index >= chapters.length ||
            chapters[index].id != expectedBook.chapters[index].id ||
            chapters[index].url != expectedBook.chapters[index].url) {
          throw StateError('章节目录已变化，缓存未清理。');
        }
        if (protected.contains(index)) {
          throw StateError('当前阅读章或有书签的章节不能清理。');
        }
        if (!chapters[index].isCached) {
          throw StateError('所选章节缓存已变化，请重新选择。');
        }
      }
      for (final index in indices) {
        chapters[index] = chapters[index].withParagraphs(const []);
      }
      final updated = current.copyWith(chapters: chapters);
      await record.put(transaction, updated.toJson());
      return updated;
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

  Future<ChangeSourceSettings> changeSourceSettings() async =>
      ChangeSourceSettings.fromJson(
        Map<String, dynamic>.from(
          await _meta.record('change_source_settings').get(database) ?? {},
        ),
      );

  Future<void> saveChangeSourceSettings(ChangeSourceSettings settings) async {
    await _meta
        .record('change_source_settings')
        .put(database, settings.toJson());
  }

  /// What a book-source health check is allowed to probe.
  ///
  /// Legado keeps this in its own settings repository; storing it beside the
  /// reader and 换源 preferences keeps every user-tunable value in one place.
  Future<SourceCheckSettings> sourceCheckSettings() async =>
      SourceCheckSettings.fromJson(
        Map<String, dynamic>.from(
          await _meta.record('source_check_settings').get(database) ?? {},
        ),
      );

  Future<void> saveSourceCheckSettings(SourceCheckSettings settings) async {
    await _meta
        .record('source_check_settings')
        .put(database, settings.toJson());
  }

  /// Writes one health-check verdict back onto the source record.
  ///
  /// Legado has no separate health table: `BookSourceCheckRepository` clears the
  /// old verdict, then stores `respondTime`, adds the failing stage tags to
  /// `bookSourceGroup` and prepends a `// Error:` block to `bookSourceComment`.
  /// Doing the same keeps the source row honest across restarts instead of
  /// throwing the diagnosis away when the sheet closes.
  Future<BookSource> recordSourceHealth({
    required BookSource source,
    required SourceHealthReport report,
  }) async {
    var updated = source.removeInvalidGroups().removeErrorComment();
    updated = updated.withRespondTime(report.respondTimeMillis);
    final tags = report.tags;
    if (tags.isNotEmpty) updated = updated.addGroups(tags);
    final failure = report.failureSummary;
    if (failure != null) updated = updated.addErrorComment(failure);
    await replaceSource(updated);
    return updated;
  }

  static String _stylePresetName(String value) {
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.runes.length > 24) {
      throw const FormatException('样式预设名称需为 1–24 个字符。');
    }
    return name;
  }

  Future<List<ReaderStylePreset>> readerStylePresets() async {
    final presets = [
      for (final record in await _readerStylePresets.find(database))
        ReaderStylePreset.fromJson(
          record.key,
          Map<String, dynamic>.from(record.value),
        ),
    ];
    presets.sort((a, b) {
      final order = a.createdAt.compareTo(b.createdAt);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return presets;
  }

  Future<ReaderStylePreset> saveReaderStylePreset(
    String value,
    ReaderSettings settings,
  ) {
    final name = _stylePresetName(value);
    return database.transaction((transaction) async {
      final records = await _readerStylePresets.find(transaction);
      if (records.length >= 10) {
        throw StateError('最多保存 10 个阅读样式预设。');
      }
      if (records.any(
        (record) =>
            (record.value['name'] as String).toLowerCase() ==
            name.toLowerCase(),
      )) {
        throw const FormatException('已存在同名阅读样式预设。');
      }
      final now = DateTime.now().toUtc();
      var id = 'style-${now.microsecondsSinceEpoch.toRadixString(36)}';
      while (await _readerStylePresets.record(id).exists(transaction)) {
        id = '${id}_';
      }
      final preset = ReaderStylePreset(
        id: id,
        name: name,
        settings: settings,
        createdAt: now,
      );
      await _readerStylePresets.record(id).put(transaction, preset.toJson());
      return preset;
    });
  }

  Future<void> deleteReaderStylePreset(String id) =>
      _readerStylePresets.record(id).delete(database);

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

  Future<List<ReaderMark>> readerMarks() async {
    final records = await _readerMarks.find(
      database,
      finder: Finder(sortOrders: [SortOrder('createdAt', false)]),
    );
    return [
      for (final record in records)
        ReaderMark.fromJson({
          'id': record.key,
          ...Map<String, dynamic>.from(record.value),
        }),
    ];
  }

  Future<ReaderMark> saveReaderMark(
    Book expectedBook,
    int chapterIndex,
    int paragraphIndex, {
    required ReaderMarkColor color,
    required String note,
    required String? selectedText,
    required String paragraphFingerprint,
  }) {
    ReaderMark.validateNote(note);
    final normalizedSelectedText = ReaderMark.validateSelectedText(
      selectedText,
    );
    if (paragraphFingerprint.isEmpty) {
      throw const FormatException('段落标注缺少原文校验信息。');
    }
    return database.transaction((transaction) async {
      final stored = await _books.record(expectedBook.id).get(transaction);
      if (stored == null) throw StateError('书籍已移出书架，未保存段落标注。');
      final book = Book.fromJson(Map<String, dynamic>.from(stored));
      if (book.sourceId != expectedBook.sourceId ||
          book.url != expectedBook.url ||
          chapterIndex < 0 ||
          chapterIndex >= book.chapters.length ||
          chapterIndex >= expectedBook.chapters.length ||
          book.chapters[chapterIndex].id !=
              expectedBook.chapters[chapterIndex].id ||
          paragraphIndex < 0 ||
          paragraphIndex >= book.chapters[chapterIndex].paragraphs.length ||
          paragraphIndex >=
              expectedBook.chapters[chapterIndex].paragraphs.length ||
          ReaderMark.fingerprint(
                book.chapters[chapterIndex].paragraphs[paragraphIndex],
              ) !=
              paragraphFingerprint) {
        throw StateError('书籍来源、章节或段落已变化，未保存段落标注。');
      }
      final paragraph = book.chapters[chapterIndex].paragraphs[paragraphIndex];
      if (normalizedSelectedText != null &&
          !ReaderMark.hasUniqueOccurrence(paragraph, normalizedSelectedText)) {
        throw const FormatException('选中文字已变化或在段落中不唯一。');
      }
      final records = await _readerMarks.find(
        transaction,
        finder: Finder(filter: Filter.equals('bookId', book.id)),
      );
      ReaderMark? existing;
      for (final record in records) {
        final mark = ReaderMark.fromJson({
          'id': record.key,
          ...Map<String, dynamic>.from(record.value),
        });
        if (mark.sourceId == book.sourceId &&
            mark.chapterId == book.chapters[chapterIndex].id &&
            mark.paragraphIndex == paragraphIndex &&
            mark.paragraphFingerprint == paragraphFingerprint) {
          if (mark.selectedText == normalizedSelectedText) {
            existing = mark;
            break;
          }
          if (normalizedSelectedText != null && mark.selectedText != null) {
            final selectedStart = paragraph.indexOf(normalizedSelectedText);
            final existingStart = paragraph.indexOf(mark.selectedText!);
            if (selectedStart < existingStart + mark.selectedText!.length &&
                existingStart < selectedStart + normalizedSelectedText.length) {
              throw const FormatException('选中文字不能与已有选区重叠。');
            }
          }
        }
      }
      final now = DateTime.now().toUtc();
      if (existing != null) {
        final updated = ReaderMark(
          id: existing.id,
          bookId: book.id,
          sourceId: book.sourceId,
          chapterId: book.chapters[chapterIndex].id,
          paragraphIndex: paragraphIndex,
          paragraphFingerprint: paragraphFingerprint,
          color: color,
          note: note,
          selectedText: normalizedSelectedText,
          createdAt: existing.createdAt,
        );
        await _readerMarks
            .record(updated.id)
            .put(transaction, updated.toJson());
        return updated;
      }
      if (records.length >= ReaderMark.maxPerBook) {
        throw StateError('每本书最多保存 ${ReaderMark.maxPerBook} 条段落标注。');
      }
      var id = 'mark-${now.microsecondsSinceEpoch.toRadixString(36)}';
      while (await _readerMarks.record(id).exists(transaction)) {
        id = '${id}_';
      }
      final mark = ReaderMark(
        id: id,
        bookId: book.id,
        sourceId: book.sourceId,
        chapterId: book.chapters[chapterIndex].id,
        paragraphIndex: paragraphIndex,
        paragraphFingerprint: paragraphFingerprint,
        color: color,
        note: note,
        selectedText: normalizedSelectedText,
        createdAt: now,
      );
      await _readerMarks.record(id).put(transaction, mark.toJson());
      return mark;
    });
  }

  Future<void> deleteReaderMark(String id) =>
      _readerMarks.record(id).delete(database);

  Future<List<ReadingActivity>> readingActivities() async {
    final records = await _readingActivity.find(
      database,
      finder: Finder(sortOrders: [SortOrder('occurredAt', false)]),
    );
    return [
      for (final record in records)
        ReadingActivity.fromJson(Map<String, dynamic>.from(record.value)),
    ];
  }

  Future<ReadingActivity> recordReadingActivity(
    Book expectedBook,
    int chapterIndex,
    ReadingActivityKind kind,
  ) => database.transaction((transaction) async {
    final stored = await _books.record(expectedBook.id).get(transaction);
    if (stored == null) throw StateError('书籍已移出书架，未记录阅读足迹。');
    final book = Book.fromJson(Map<String, dynamic>.from(stored));
    if (book.sourceId != expectedBook.sourceId ||
        book.url != expectedBook.url ||
        chapterIndex < 0 ||
        chapterIndex >= book.chapters.length ||
        chapterIndex >= expectedBook.chapters.length ||
        book.chapters[chapterIndex].id !=
            expectedBook.chapters[chapterIndex].id) {
      throw StateError('书籍来源或章节已变化，未记录阅读足迹。');
    }
    final recent = await _readingActivity.find(
      transaction,
      finder: Finder(
        filter: Filter.equals('bookId', book.id),
        sortOrders: [SortOrder('occurredAt', false)],
        limit: 1,
      ),
    );
    final now = DateTime.now().toUtc();
    if (recent.isNotEmpty) {
      final previous = ReadingActivity.fromJson(
        Map<String, dynamic>.from(recent.first.value),
      );
      final age = now.difference(previous.occurredAt.toUtc());
      if (previous.chapterIndex == chapterIndex &&
          previous.kind == kind &&
          !age.isNegative &&
          age <= ReadingActivity.dedupeWindow) {
        return previous;
      }
    }
    var id = 'activity-${now.microsecondsSinceEpoch.toRadixString(36)}';
    while (await _readingActivity.record(id).exists(transaction)) {
      id = '${id}_';
    }
    final activity = ReadingActivity(
      id: id,
      bookId: book.id,
      bookTitle: book.title,
      author: book.author,
      sourceId: book.sourceId,
      chapterIndex: chapterIndex,
      chapterId: book.chapters[chapterIndex].id,
      chapterTitle: book.chapters[chapterIndex].title,
      kind: kind,
      occurredAt: now,
    );
    await _readingActivity.record(id).put(transaction, activity.toJson());
    final all = await _readingActivity.find(
      transaction,
      finder: Finder(sortOrders: [SortOrder('occurredAt', false)]),
    );
    for (final record in all.skip(ReadingActivity.maxEntries)) {
      await _readingActivity.record(record.key).delete(transaction);
    }
    return activity;
  });

  Future<void> clearReadingActivities() => _readingActivity.delete(database);

  Future<Uint8List> exportLocalBackup() async {
    final backup = await database.transaction((transaction) async {
      final localBooks = <Book>[];
      for (final record in await _books.find(transaction)) {
        final book = Book.fromJson(Map<String, dynamic>.from(record.value));
        if (!book.isRemote) localBooks.add(book);
      }
      final localIds = {for (final book in localBooks) book.id};
      final notes = <Bookmark>[
        for (final record in await _notes.find(transaction))
          if (localIds.contains(record.value['bookId']))
            Bookmark.fromJson(Map<String, dynamic>.from(record.value)),
      ];
      final groups = <ShelfGroup>[
        for (final record in await _shelfGroups.find(transaction))
          ShelfGroup(
            id: record.key,
            name: record.value['name'] as String,
            createdAt: DateTime.parse(record.value['createdAt'] as String),
            bookIds: (record.value['bookIds'] as List? ?? const [])
                .cast<String>()
                .where(localIds.contains),
          ),
      ];
      final textRules = <String, List<BookTextRule>>{
        for (final record in await _textRules.find(transaction))
          if (localIds.contains(record.key))
            record.key: _decodeTextRules(record.value),
      };
      final settings = ReaderSettings.fromJson(
        Map<String, dynamic>.from(
          await _meta.record('settings').get(transaction) ?? {},
        ),
      );
      return LocalBackup(
        createdAt: DateTime.now().toUtc(),
        books: localBooks,
        bookmarks: notes,
        groups: groups,
        textRules: textRules,
        settings: settings,
      );
    });
    final bytes = LocalBackupCodec.encode(backup);
    LocalBackupCodec.decode(bytes);
    return bytes;
  }

  Future<Uint8List> exportEncryptedLocalBackup(String password) async =>
      EncryptedLocalBackupCodec.encrypt(await exportLocalBackup(), password);

  Future<LocalBackupPlan> prepareLocalBackup(Uint8List bytes) async {
    final backup = LocalBackupCodec.decode(bytes);
    final existingIds = {
      for (final record in await _books.find(database)) record.key,
    };
    return LocalBackupPlan(backup: backup, existingBookIds: existingIds);
  }

  Future<LocalBackupPlan> prepareEncryptedLocalBackup(
    Uint8List bytes,
    String password,
  ) async => prepareLocalBackup(
    await EncryptedLocalBackupCodec.decrypt(bytes, password),
  );

  Future<LocalBackupImportResult> restoreLocalBackup(
    LocalBackupPlan plan, {
    bool restoreSettings = false,
  }) async {
    final backup = LocalBackupCodec.decode(
      LocalBackupCodec.encode(plan.backup),
    );
    return database.transaction((transaction) async {
      final existingIds = {
        for (final record in await _books.find(transaction)) record.key,
      };
      if (existingIds.length != plan.existingBookIds.length ||
          !existingIds.containsAll(plan.existingBookIds)) {
        throw StateError('书架在预览后已变化，请重新预览备份。');
      }
      final imported = {
        for (final book in backup.books)
          if (!existingIds.contains(book.id)) book.id,
      };
      for (final book in backup.books) {
        if (imported.contains(book.id)) {
          await _books.record(book.id).put(transaction, book.toJson());
        }
      }

      var importedBookmarks = 0;
      for (final note in backup.bookmarks) {
        if (!imported.contains(note.bookId)) continue;
        var id = note.id;
        if (await _notes.record(id).exists(transaction)) {
          var suffix = 0;
          do {
            id =
                'restored-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${suffix++}';
          } while (await _notes.record(id).exists(transaction));
        }
        await _notes
            .record(id)
            .put(
              transaction,
              Bookmark(
                id: id,
                bookId: note.bookId,
                chapterIndex: note.chapterIndex,
                paragraphIndex: note.paragraphIndex,
                quote: note.quote,
                note: note.note,
                createdAt: note.createdAt,
              ).toJson(),
            );
        importedBookmarks++;
      }

      final currentGroups = <ShelfGroup>[
        for (final record in await _shelfGroups.find(transaction))
          ShelfGroup.fromJson(
            record.key,
            Map<String, dynamic>.from(record.value),
          ),
      ];
      var newGroups = 0;
      var mergedGroups = 0;
      for (final group in backup.groups) {
        final members = group.bookIds.where(imported.contains).toSet();
        final match = currentGroups.indexWhere(
          (stored) => stored.name.toLowerCase() == group.name.toLowerCase(),
        );
        if (match >= 0) {
          final existing = currentGroups[match];
          final merged = {...existing.bookIds, ...members};
          if (merged.length == existing.bookIds.length) continue;
          await _shelfGroups.record(existing.id).update(transaction, {
            'bookIds': merged.toList(),
          });
          currentGroups[match] = ShelfGroup(
            id: existing.id,
            name: existing.name,
            createdAt: existing.createdAt,
            bookIds: merged,
          );
          mergedGroups++;
        } else {
          if (currentGroups.length >= 32) {
            throw StateError('书架分组已满，未恢复任何备份内容。');
          }
          var id = group.id;
          if (currentGroups.any((stored) => stored.id == id)) {
            id =
                'group-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${currentGroups.length}';
            while (currentGroups.any((stored) => stored.id == id)) {
              id = '${id}_';
            }
          }
          final created = ShelfGroup(
            id: id,
            name: group.name,
            createdAt: group.createdAt,
            bookIds: members,
          );
          await _shelfGroups.record(id).put(transaction, created.toJson());
          currentGroups.add(created);
          newGroups++;
        }
      }

      var importedRules = 0;
      for (final entry in backup.textRules.entries) {
        if (!imported.contains(entry.key) || entry.value.isEmpty) continue;
        final record = _textRules.record(entry.key);
        if (await record.exists(transaction)) {
          throw StateError('替换规则与本地记录冲突，未恢复任何备份内容。');
        }
        await record.put(transaction, {
          'rules': [for (final rule in entry.value) rule.toJson()],
        });
        importedRules += entry.value.length;
      }
      if (restoreSettings) {
        await _meta
            .record('settings')
            .put(transaction, backup.settings.toJson());
      }
      return LocalBackupImportResult(
        importedBooks: imported.length,
        skippedBooks: backup.books.length - imported.length,
        importedBookmarks: importedBookmarks,
        newGroups: newGroups,
        mergedGroups: mergedGroups,
        importedRules: importedRules,
        settingsRestored: restoreSettings,
      );
    });
  }

  /// 所有书源，按 `customOrder` 从小到大排列。
  ///
  /// 排序在 Dart 侧完成而不是交给 sembast 的 [SortOrder]：导入的原始 JSON 常常
  /// 没有 `customOrder` 这个键，sembast 会把缺字段的记录当成最小/最大之外的值，
  /// 于是「置顶」写进去的负数反而排到最后。这里统一按 legado 的语义——缺字段就是
  /// 0——并在值相同时保留 `sources` 的原始顺序（Dart 的 [List.sort] 不稳定，
  /// 所以显式带上索引）。
  Future<List<BookSource>> sources() async {
    final records = await _sources.find(database);
    final order = <String, int>{
      for (final record in records)
        record.key: _customOrder(record.value['customOrder']),
    };
    final sorted = records.toList();
    final index = <String, int>{
      for (var i = 0; i < sorted.length; i++) sorted[i].key: i,
    };
    sorted.sort((a, b) {
      final byOrder = order[a.key]!.compareTo(order[b.key]!);
      return byOrder != 0 ? byOrder : index[a.key]!.compareTo(index[b.key]!);
    });
    return [
      for (final record in sorted)
        BookSource(Map<String, dynamic>.from(record.value)),
    ];
  }

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

  /// Toggles a source's participation in the discover page without touching
  /// [BookSource.enabled], which governs search and 换源.
  Future<void> setSourceEnabledExplore(String id, bool enabledExplore) async {
    await _sources.record(id).update(database, {
      'enabledExplore': enabledExplore,
    });
  }

  /// Moves [id] above every other source by taking the current minimum order and
  /// subtracting one, matching legado's `topSource`.
  ///
  /// Returns the saved source, or null when the id is not installed.
  Future<BookSource?> moveSourceToTop(String id) async {
    BookSource? target;
    int? minOrder;
    for (final record in await _sources.find(database)) {
      final order = _customOrder(record.value['customOrder']);
      if (record.key == id) {
        target = BookSource(Map<String, dynamic>.from(record.value));
        continue;
      }
      if (minOrder == null || order < minOrder) minOrder = order;
    }
    final resolved = target;
    if (resolved == null) return null;
    // First source installed: keep legado's 0 baseline instead of going negative.
    final next = resolved.withCustomOrder((minOrder ?? 0) - 1);
    await saveSource(next);
    return next;
  }

  /// Moves [id] below every other source by taking the current maximum order and
  /// adding one, matching legado's `bottomSource`.
  ///
  /// Returns the saved source, or null when the id is not installed.
  Future<BookSource?> moveSourceToBottom(String id) async {
    BookSource? target;
    int? maxOrder;
    for (final record in await _sources.find(database)) {
      final order = _customOrder(record.value['customOrder']);
      if (record.key == id) {
        target = BookSource(Map<String, dynamic>.from(record.value));
        continue;
      }
      if (maxOrder == null || order > maxOrder) maxOrder = order;
    }
    final resolved = target;
    if (resolved == null) return null;
    final next = resolved.withCustomOrder((maxOrder ?? 0) + 1);
    await saveSource(next);
    return next;
  }

  static int _customOrder(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  /// Replaces one source record wholesale after an edit.
  ///
  /// The record key is the source URL and the URL is the primary key in legado
  /// too, so an edit that changes it must delete the old record; callers that
  /// only change editable fields can rely on this method instead.
  Future<void> replaceSource(BookSource source) async {
    await _sources.record(source.id).put(database, source.toJson());
  }

  /// Removes several sources in one transaction.
  Future<void> deleteSources(Iterable<String> ids) async {
    for (final id in ids) {
      await deleteSource(id);
    }
  }

  /// Stored discover form values for one source, keyed by kind title.
  Future<Map<String, String>> exploreInfo(String sourceId) async {
    final json = await _sourceExploreInfo.record(sourceId).get(database);
    if (json == null) return {};
    return {
      for (final entry in json.entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
  }

  Future<void> saveExploreInfo(
    String sourceId,
    Map<String, String> values,
  ) async {
    if (values.isEmpty) {
      await _sourceExploreInfo.record(sourceId).delete(database);
      return;
    }
    await _sourceExploreInfo.record(sourceId).put(database, values);
  }

  /// Last discover source and category per source, mirroring legado's
  /// `exploreMainSourceUrl` + `exploreMainKind` preferences.
  Future<ExploreMainSelection> exploreSelection() async {
    final json = await _meta.record('explore_selection').get(database);
    return ExploreMainSelection(
      sourceUrl: json?['sourceUrl'] is String
          ? json!['sourceUrl'] as String
          : null,
      kindKeyBySource: {
        if (json?['kindKeyBySource'] is Map)
          for (final entry in (json!['kindKeyBySource'] as Map).entries)
            if (entry.value is String)
              entry.key.toString(): entry.value as String,
      },
      showContent: json?['showContent'] == true,
    );
  }

  Future<void> saveExploreSelection(ExploreMainSelection selection) async {
    await _meta.record('explore_selection').put(database, {
      if (selection.sourceUrl != null) 'sourceUrl': selection.sourceUrl,
      'kindKeyBySource': selection.kindKeyBySource,
      'showContent': selection.showContent,
    });
  }

  Future<void> deleteSource(String id) async {
    await database.transaction((transaction) async {
      await _sources.record(id).delete(transaction);
      await _sourceStates.record(id).delete(transaction);
      for (final record in await _sourceSwitchCandidateCaches.find(
        transaction,
      )) {
        SourceCandidateCache cache;
        try {
          cache = SourceCandidateCache.fromJson(
            Map<String, dynamic>.from(record.value),
          );
        } on FormatException {
          await _sourceSwitchCandidateCaches
              .record(record.key)
              .delete(transaction);
          continue;
        } on TypeError {
          await _sourceSwitchCandidateCaches
              .record(record.key)
              .delete(transaction);
          continue;
        }
        // The snapshot itself is book-scoped, so deleting the source that
        // originally produced it must not discard candidates from sources that
        // are still installed. Only its own entries are pruned below.
        final retained = cache.entries
            .where((entry) => entry.candidate.sourceId != id)
            .toList();
        if (retained.length == cache.entries.length) continue;
        final target = _sourceSwitchCandidateCaches.record(record.key);
        if (retained.isEmpty) {
          await target.delete(transaction);
        } else {
          await target.put(
            transaction,
            cache.copyWith(entries: retained).toJson(),
          );
        }
      }
    });
  }
}
