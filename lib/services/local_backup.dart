import 'dart:convert';
import 'dart:typed_data';

import '../domain/book.dart';
import '../domain/reader_settings.dart';
import '../domain/shelf_group.dart';
import 'book_text_rules.dart';

final class LocalBackup {
  LocalBackup({
    required this.createdAt,
    required Iterable<Book> books,
    required Iterable<Bookmark> bookmarks,
    required Iterable<ShelfGroup> groups,
    required Map<String, List<BookTextRule>> textRules,
    required this.settings,
  }) : books = List.unmodifiable(books),
       bookmarks = List.unmodifiable(bookmarks),
       groups = List.unmodifiable(groups),
       textRules = Map.unmodifiable({
         for (final entry in textRules.entries)
           entry.key: List<BookTextRule>.unmodifiable(entry.value),
       });

  final DateTime createdAt;
  final List<Book> books;
  final List<Bookmark> bookmarks;
  final List<ShelfGroup> groups;
  final Map<String, List<BookTextRule>> textRules;
  final ReaderSettings settings;
}

final class LocalBackupPlan {
  LocalBackupPlan({
    required this.backup,
    required Iterable<String> existingBookIds,
  }) : existingBookIds = Set.unmodifiable(existingBookIds);

  final LocalBackup backup;
  final Set<String> existingBookIds;

  int get newBooks =>
      backup.books.where((book) => !existingBookIds.contains(book.id)).length;
  int get skippedBooks => backup.books.length - newBooks;
}

final class LocalBackupImportResult {
  const LocalBackupImportResult({
    required this.importedBooks,
    required this.skippedBooks,
    required this.importedBookmarks,
    required this.newGroups,
    required this.mergedGroups,
    required this.importedRules,
    required this.settingsRestored,
  });

  final int importedBooks;
  final int skippedBooks;
  final int importedBookmarks;
  final int newGroups;
  final int mergedGroups;
  final int importedRules;
  final bool settingsRestored;
}

abstract final class LocalBackupCodec {
  static const format = 'read-pilot-local';
  static const version = 1;
  static const maxBytes = 10 * 1024 * 1024;
  static const maxBooks = 1000;
  static const maxBookmarks = 10000;
  static const maxChaptersPerBook = 10000;
  static const maxParagraphs = 200000;

  static Uint8List encode(LocalBackup backup) {
    final data = {
      'format': format,
      'version': version,
      'createdAt': backup.createdAt.toUtc().toIso8601String(),
      'books': [for (final book in backup.books) _localBookJson(book)],
      'bookmarks': [for (final note in backup.bookmarks) note.toJson()],
      'groups': [
        for (final group in backup.groups) {'id': group.id, ...group.toJson()},
      ],
      'textRules': {
        for (final entry in backup.textRules.entries)
          entry.key: [for (final rule in entry.value) rule.toJson()],
      },
      'settings': backup.settings.toJson(),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    if (bytes.length > maxBytes) {
      throw const FormatException('本地备份超过 10 MiB，请减少导入的 TXT 后重试。');
    }
    return bytes;
  }

  static Map<String, dynamic> _localBookJson(Book book) {
    if (book.isRemote) throw const FormatException('备份不包含网络书籍或书源。');
    final json = book.toJson()
      ..remove('sourceId')
      ..remove('url')
      ..remove('coverUrl');
    json['chapters'] = [
      for (final chapter in book.chapters)
        {
          'id': chapter.id,
          'title': chapter.title,
          'paragraphs': chapter.paragraphs,
        },
    ];
    return json;
  }

  static LocalBackup decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('本地备份必须小于 10 MiB。');
    }
    try {
      final root = _map(jsonDecode(utf8.decode(bytes)));
      _keys(root, const {
        'format',
        'version',
        'createdAt',
        'books',
        'bookmarks',
        'groups',
        'textRules',
        'settings',
      });
      if (root['format'] != format || root['version'] != version) {
        throw const FormatException('不支持此备份格式或版本。');
      }
      final createdAt = DateTime.parse(root['createdAt'] as String);
      final rawBooks = _list(root['books']);
      if (rawBooks.length > maxBooks) throw const FormatException('备份书籍过多。');
      final books = <Book>[];
      final bookIds = <String>{};
      var paragraphCount = 0;
      for (final raw in rawBooks) {
        final json = _map(raw);
        _keys(json, const {
          'id',
          'title',
          'author',
          'description',
          'category',
          'coverStyle',
          'sourceLabel',
          'addedAt',
          'isExcerpt',
          'provenance',
          'chapters',
          'position',
          'lastOpenedAt',
          'finished',
        });
        final chapters = _list(json['chapters']);
        if (chapters.isEmpty || chapters.length > maxChaptersPerBook) {
          throw const FormatException('本地书籍目录数量无效。');
        }
        for (final item in chapters) {
          final chapter = _map(item);
          _keys(chapter, const {'id', 'title', 'paragraphs'});
          final paragraphs = _list(chapter['paragraphs']);
          paragraphCount += paragraphs.length;
          if (paragraphCount > maxParagraphs ||
              paragraphs.any((value) => value is! String)) {
            throw const FormatException('备份正文数量或格式无效。');
          }
        }
        final book = Book.fromJson(json);
        if (book.id.isEmpty ||
            book.id.length > 512 ||
            !bookIds.add(book.id) ||
            book.isRemote ||
            book.url != null ||
            book.coverUrl != null ||
            book.chapters.map((chapter) => chapter.id).toSet().length !=
                book.chapters.length ||
            book.chapters.any(
              (chapter) => chapter.id.isEmpty || chapter.url != null,
            )) {
          throw const FormatException('备份含无效或重复的本地书籍。');
        }
        final position = _map(json['position']);
        final chapterIndex = position['chapterIndex'];
        final paragraphIndex = position['paragraphIndex'];
        if (chapterIndex is! int ||
            paragraphIndex is! int ||
            chapterIndex < 0 ||
            chapterIndex >= book.chapters.length ||
            paragraphIndex < 0 ||
            paragraphIndex >=
                (book.chapters[chapterIndex].paragraphs.isEmpty
                    ? 1
                    : book.chapters[chapterIndex].paragraphs.length)) {
          throw const FormatException('备份阅读位置无效。');
        }
        books.add(book);
      }
      final rawNotes = _list(root['bookmarks']);
      if (rawNotes.length > maxBookmarks) {
        throw const FormatException('备份笔记过多。');
      }
      final notes = <Bookmark>[];
      final noteIds = <String>{};
      final byId = {for (final book in books) book.id: book};
      for (final raw in rawNotes) {
        final json = _map(raw);
        _keys(json, const {
          'id',
          'bookId',
          'chapterIndex',
          'paragraphIndex',
          'quote',
          'note',
          'createdAt',
        });
        final note = Bookmark.fromJson(json);
        final book = byId[note.bookId];
        if (note.id.isEmpty ||
            note.id.length > 512 ||
            !noteIds.add(note.id) ||
            book == null ||
            note.chapterIndex < 0 ||
            note.chapterIndex >= book.chapters.length ||
            note.paragraphIndex < 0 ||
            note.paragraphIndex >=
                (book.chapters[note.chapterIndex].paragraphs.isEmpty
                    ? 1
                    : book.chapters[note.chapterIndex].paragraphs.length)) {
          throw const FormatException('备份笔记引用无效。');
        }
        notes.add(note);
      }
      final rawGroups = _list(root['groups']);
      if (rawGroups.length > 32) throw const FormatException('备份分组过多。');
      final groups = <ShelfGroup>[];
      final groupIds = <String>{};
      final groupNames = <String>{};
      for (final raw in rawGroups) {
        final json = _map(raw);
        _keys(json, const {'id', 'name', 'createdAt', 'bookIds'});
        final group = ShelfGroup.fromJson(json['id'] as String, json);
        final name = group.name.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (group.id.isEmpty ||
            group.id.length > 128 ||
            !groupIds.add(group.id) ||
            group.name != name ||
            name.isEmpty ||
            name.runes.length > 24 ||
            !groupNames.add(name.toLowerCase()) ||
            group.bookIds.any((id) => !bookIds.contains(id))) {
          throw const FormatException('备份分组引用无效。');
        }
        groups.add(group);
      }
      final rawRules = _map(root['textRules']);
      final rules = <String, List<BookTextRule>>{};
      for (final entry in rawRules.entries) {
        if (!bookIds.contains(entry.key)) {
          throw const FormatException('备份替换规则引用无效。');
        }
        final list = _list(entry.value);
        if (list.length > BookTextRules.maxRulesPerBook) {
          throw const FormatException('备份替换规则过多。');
        }
        final ids = <String>{};
        rules[entry.key] = [for (final raw in list) _rule(_map(raw), ids)];
      }
      final rawSettings = _map(root['settings']);
      _keys(rawSettings, const {
        'theme',
        'flow',
        'fontSize',
        'lineHeight',
        'paragraphSpacing',
        'boldText',
        'tocDescending',
      });
      return LocalBackup(
        createdAt: createdAt,
        books: books,
        bookmarks: notes,
        groups: groups,
        textRules: rules,
        settings: ReaderSettings.fromJson(rawSettings),
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('备份结构无效或内容已损坏。');
    }
  }

  static BookTextRule _rule(Map<String, dynamic> json, Set<String> ids) {
    _keys(json, const {'id', 'needle', 'replacement', 'enabled'});
    final rule = BookTextRule.fromJson(json);
    if (rule.id.isEmpty || rule.id.length > 128 || !ids.add(rule.id)) {
      throw const FormatException('备份替换规则标识无效。');
    }
    BookTextRules.validate(rule.needle, rule.replacement);
    return rule;
  }

  static Map<String, dynamic> _map(Object? value) =>
      Map<String, dynamic>.from(value as Map);

  static List<dynamic> _list(Object? value) =>
      List<dynamic>.from(value as List);

  static void _keys(Map<String, dynamic> value, Set<String> allowed) {
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('备份包含不支持的字段。');
    }
  }
}
