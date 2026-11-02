import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppRepository repository;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'shelf-groups-${DateTime.now().microsecondsSinceEpoch}',
    );
    repository = AppRepository(database);
    controller = AppController(repository, SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'groups and memberships survive restart without changing books',
    () async {
      final book = controller.books.first;
      final before = book.toJson();
      final group = await controller.createShelfGroup('  喜欢的书  ');
      await controller.setShelfGroupMembership(group.id, book.id, true);

      expect(controller.shelfGroups.single.name, '喜欢的书');
      expect(controller.shelfGroups.single.containsBook(book.id), isTrue);
      expect(controller.book(book.id)!.toJson(), before);

      final fresh = AppController(AppRepository(database), SourceEngine());
      addTearDown(fresh.dispose);
      await fresh.initialize();
      expect(fresh.shelfGroups.single.id, group.id);
      expect(fresh.shelfGroups.single.containsBook(book.id), isTrue);
      expect(fresh.book(book.id)!.toJson(), before);
    },
  );

  test('renaming and deleting a group never deletes books or notes', () async {
    final book = controller.books.first;
    await controller.addBookmark(
      Bookmark(
        id: 'group-note',
        bookId: book.id,
        chapterIndex: 0,
        paragraphIndex: 0,
        quote: '摘录',
        note: '保留',
        createdAt: DateTime.utc(2026),
      ),
    );
    final group = await controller.createShelfGroup('旧名称');
    await controller.setShelfGroupMembership(group.id, book.id, true);
    await controller.renameShelfGroup(group.id, '新名称');
    expect(controller.shelfGroups.single.name, '新名称');
    expect(controller.shelfGroups.single.containsBook(book.id), isTrue);

    await controller.deleteShelfGroup(group.id);
    expect(controller.shelfGroups, isEmpty);
    expect(controller.book(book.id), isNotNull);
    expect(controller.bookmarks.single.note, '保留');
    expect(
      (await repository.books()).any((item) => item.id == book.id),
      isTrue,
    );
    expect((await repository.bookmarks()).single.note, '保留');
  });

  test(
    'one book can join multiple groups and removal purges membership',
    () async {
      final book = controller.books.first;
      final first = await controller.createShelfGroup('第一组');
      final second = await controller.createShelfGroup('第二组');
      await controller.setShelfGroupMembership(first.id, book.id, true);
      await controller.setShelfGroupMembership(second.id, book.id, true);
      expect(
        controller.shelfGroups.every((group) => group.containsBook(book.id)),
        isTrue,
      );

      await controller.setShelfGroupMembership(first.id, book.id, false);
      expect(controller.shelfGroups.first.containsBook(book.id), isFalse);
      expect(controller.shelfGroups.last.containsBook(book.id), isTrue);
      await controller.removeBook(book.id);
      expect(
        controller.shelfGroups.every((group) => !group.containsBook(book.id)),
        isTrue,
      );
      expect(
        (await AppRepository(
          database,
        ).shelfGroups()).every((group) => !group.containsBook(book.id)),
        isTrue,
      );
    },
  );

  test(
    'invalid names and missing books cannot create stale membership',
    () async {
      final existing = await controller.createShelfGroup('读完');
      await expectLater(
        controller.createShelfGroup('  读完  '),
        throwsStateError,
      );
      await expectLater(
        controller.createShelfGroup('   '),
        throwsFormatException,
      );
      await expectLater(
        controller.createShelfGroup('a' * 25),
        throwsFormatException,
      );
      await expectLater(
        controller.setShelfGroupMembership(existing.id, 'missing', true),
        throwsStateError,
      );
      expect(controller.shelfGroups.single.bookIds, isEmpty);
    },
  );
}
