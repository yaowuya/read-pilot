import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/domain/reading_activity.dart';
import 'package:read_pilot/services/local_backup.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

Book _localBook() => Book(
  id: 'private-txt',
  title: '自己的 TXT',
  author: '作者',
  description: '',
  category: '本地',
  coverStyle: 1,
  sourceLabel: '本地导入',
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(id: 'one', title: '第一章', paragraphs: const ['保留的正文']),
  ],
);

Book _remoteBook() => Book(
  id: 'remote-secret',
  title: '远程书',
  author: '作者',
  description: '',
  category: '网络',
  coverStyle: 0,
  sourceLabel: '敏感书源',
  sourceId: 'https://secret.example?token=PRIVATE_TOKEN',
  url: 'https://secret.example/book?token=PRIVATE_TOKEN',
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(
      id: 'remote-one',
      title: '秘密章',
      url: 'https://secret.example/chapter?token=PRIVATE_TOKEN',
      paragraphs: const ['远程敏感正文'],
    ),
  ],
);

Bookmark _note(String id, String bookId) => Bookmark(
  id: id,
  bookId: bookId,
  chapterIndex: 0,
  paragraphIndex: 0,
  quote: '记下原文',
  note: '自己的批注',
  createdAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'backup-source-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
    await controller.addBook(_localBook());
    await controller.addBook(_remoteBook());
    await controller.addBookmark(_note('local-note', 'private-txt'));
    await controller.addBookmark(_note('remote-note', 'remote-secret'));
    final group = await controller.createShelfGroup('收藏');
    await controller.setShelfGroupMembership(group.id, 'private-txt', true);
    await controller.setShelfGroupMembership(group.id, 'remote-secret', true);
    await controller.addTextRule('private-txt', '保留', '显示');
    await controller.addTextRule('remote-secret', '敏感', '隐藏');
    await controller.updateSettings(
      controller.settings.copyWith(theme: ReaderTheme.dark),
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test('export excludes every remote source, URL, cache and note', () async {
    final bytes = await controller.exportLocalBackup();
    expect(bytes.length, lessThanOrEqualTo(LocalBackupCodec.maxBytes));
    final text = utf8.decode(bytes);
    expect(text, isNot(contains('PRIVATE_TOKEN')));
    expect(text, isNot(contains('远程敏感正文')));
    expect(text, isNot(contains('remote-secret')));
    final backup = LocalBackupCodec.decode(bytes);
    expect(backup.books, hasLength(4));
    expect(backup.books.every((book) => !book.isRemote), isTrue);
    expect(backup.books.any((book) => book.id == 'private-txt'), isTrue);
    expect(backup.bookmarks.map((note) => note.id), ['local-note']);
    expect(backup.groups.single.bookIds, {'private-txt'});
    expect(backup.textRules.keys, {'private-txt'});
    expect(backup.settings.theme, ReaderTheme.dark);
    final json = jsonDecode(text) as Map<String, dynamic>;
    expect(json.keys, isNot(contains('sources')));
    expect(
      (json['books'] as List).every(
        (book) =>
            !(book as Map).containsKey('sourceId') &&
            !book.containsKey('url') &&
            !book.containsKey('coverUrl'),
      ),
      isTrue,
    );
  });

  test(
    'restore imports only new local books and keeps existing settings',
    () async {
      final bytes = await controller.exportLocalBackup();
      final targetDb = await databaseFactoryMemory.openDatabase(
        'backup-target-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(targetDb.close);
      final target = AppController(AppRepository(targetDb), SourceEngine());
      addTearDown(target.dispose);
      await target.initialize();
      final plan = await target.prepareLocalBackup(bytes);
      expect(plan.newBooks, 1);
      expect(plan.skippedBooks, 3);
      final result = await target.restoreLocalBackup(plan);
      expect(result.importedBooks, 1);
      expect(result.skippedBooks, 3);
      expect(result.importedBookmarks, 1);
      expect(result.settingsRestored, isFalse);
      expect(target.settings.theme, ReaderTheme.paper);
      expect(target.book('private-txt')!.chapters.single.paragraphs, ['保留的正文']);
      expect(target.bookmarks.single.bookId, 'private-txt');
      expect(target.shelfGroups.single.containsBook('private-txt'), isTrue);
      expect(target.textRules('private-txt').single.needle, '保留');
      expect(target.book('remote-secret'), isNull);
      await expectLater(target.restoreLocalBackup(plan), throwsStateError);
    },
  );

  test('reading settings restore only after explicit opt in', () async {
    final bytes = await controller.exportLocalBackup();
    final targetDb = await databaseFactoryMemory.openDatabase(
      'settings-target-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(targetDb.close);
    final target = AppController(AppRepository(targetDb), SourceEngine());
    addTearDown(target.dispose);
    await target.initialize();
    final plan = await target.prepareLocalBackup(bytes);
    final result = await target.restoreLocalBackup(plan, restoreSettings: true);
    expect(result.settingsRestored, isTrue);
    expect(target.settings.theme, ReaderTheme.dark);
  });

  test(
    'corrupt references, remote fields and oversize input reject before writes',
    () async {
      final bytes = await controller.exportLocalBackup();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final targetDb = await databaseFactoryMemory.openDatabase(
        'invalid-target-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(targetDb.close);
      final target = AppController(AppRepository(targetDb), SourceEngine());
      addTearDown(target.dispose);
      await target.initialize();
      final before = target.books.length;

      final forged = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
      (forged['books'] as List).first['sourceId'] = 'https://secret.example';
      await expectLater(
        target.prepareLocalBackup(
          Uint8List.fromList(utf8.encode(jsonEncode(forged))),
        ),
        throwsFormatException,
      );
      final orphan = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
      (orphan['bookmarks'] as List).first['bookId'] = 'missing';
      await expectLater(
        target.prepareLocalBackup(
          Uint8List.fromList(utf8.encode(jsonEncode(orphan))),
        ),
        throwsFormatException,
      );
      await expectLater(
        target.prepareLocalBackup(Uint8List(LocalBackupCodec.maxBytes + 1)),
        throwsFormatException,
      );
      expect(target.books.length, before);
      expect(target.book('private-txt'), isNull);
    },
  );

  test('a stale preview rejects atomically when the shelf changes', () async {
    final bytes = await controller.exportLocalBackup();
    final targetDb = await databaseFactoryMemory.openDatabase(
      'stale-target-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(targetDb.close);
    final target = AppController(AppRepository(targetDb), SourceEngine());
    addTearDown(target.dispose);
    await target.initialize();
    final plan = await target.prepareLocalBackup(bytes);
    await target.addBook(
      Book(
        id: 'other',
        title: '后来加入',
        author: '作者',
        description: '',
        category: '本地',
        coverStyle: 0,
        sourceLabel: '本地导入',
        addedAt: DateTime.utc(2026),
        chapters: [
          Chapter(id: 'one', title: '第一章', paragraphs: const ['原文']),
        ],
      ),
    );
    await expectLater(target.restoreLocalBackup(plan), throwsStateError);
    expect(target.book('private-txt'), isNull);
    expect(target.bookmarks, isEmpty);
    expect(target.book('other'), isNotNull);
  });

  test('full group shelf rolls back new books and notes atomically', () async {
    final bytes = await controller.exportLocalBackup();
    final targetDb = await databaseFactoryMemory.openDatabase(
      'full-groups-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(targetDb.close);
    final target = AppController(AppRepository(targetDb), SourceEngine());
    addTearDown(target.dispose);
    await target.initialize();
    for (var index = 0; index < 32; index++) {
      await target.createShelfGroup('已有分组$index');
    }
    final plan = await target.prepareLocalBackup(bytes);
    await expectLater(target.restoreLocalBackup(plan), throwsStateError);
    expect(target.book('private-txt'), isNull);
    expect(target.bookmarks, isEmpty);
    expect(target.shelfGroups, hasLength(32));
    expect(
      (await AppRepository(
        targetDb,
      ).books()).any((book) => book.id == 'private-txt'),
      isFalse,
    );
  });

  test(
    'backup intentionally excludes local reading activity history',
    () async {
      await controller.recordReadingActivity(
        'private-txt',
        0,
        kind: ReadingActivityKind.opened,
      );
      final bytes = await controller.exportLocalBackup();
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(root.containsKey('readingActivities'), isFalse);

      final targetDb = await databaseFactoryMemory.openDatabase(
        'activity-target-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(targetDb.close);
      final target = AppController(AppRepository(targetDb), SourceEngine());
      addTearDown(target.dispose);
      await target.initialize();
      await target.restoreLocalBackup(await target.prepareLocalBackup(bytes));
      expect(target.book('private-txt'), isNotNull);
      expect(target.readingActivities, isEmpty);
    },
  );

  test('colliding maximum-length note ids remain exportable', () async {
    final longId = 'n' * 512;
    await controller.addBookmark(_note(longId, 'private-txt'));
    final bytes = await controller.exportLocalBackup();
    final targetDb = await databaseFactoryMemory.openDatabase(
      'long-note-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(targetDb.close);
    final target = AppController(AppRepository(targetDb), SourceEngine());
    addTearDown(target.dispose);
    await target.initialize();
    await target.addBookmark(_note(longId, 'public-fusheng'));
    final plan = await target.prepareLocalBackup(bytes);
    await target.restoreLocalBackup(plan);

    final restored = LocalBackupCodec.decode(await target.exportLocalBackup());
    expect(
      restored.bookmarks
          .where((note) => note.bookId == 'private-txt')
          .every((note) => note.id.length <= 512),
      isTrue,
    );
  });

  test(
    'backup parser rejects group names that would create duplicates',
    () async {
      final json =
          jsonDecode(utf8.decode(await controller.exportLocalBackup()))
              as Map<String, dynamic>;
      (json['groups'] as List).single['name'] = ' 收藏 ';
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      expect(() => LocalBackupCodec.decode(bytes), throwsFormatException);
    },
  );
}
