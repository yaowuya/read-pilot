import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppRepository repository;
  late Database database;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'test-${DateTime.now().microsecondsSinceEpoch}',
    );
    repository = AppRepository(database);
    await repository.initialize();
  });

  tearDown(() => database.close());

  test('first run seeds three books exactly once', () async {
    expect(await repository.books(), hasLength(3));
    await repository.initialize();
    expect(await repository.books(), hasLength(3));
  });

  test('removing all books does not reseed on next initialization', () async {
    for (final book in await repository.books()) {
      await repository.removeBook(book.id);
    }
    await repository.initialize();
    expect(await repository.books(), isEmpty);
  });

  test(
    'reading position is durable without replacing cached chapters',
    () async {
      final book = (await repository.books()).first;
      await repository.savePosition(
        book.id,
        const ReadingPosition(chapterIndex: 1, paragraphIndex: 2),
      );
      final restored = (await repository.books()).firstWhere(
        (b) => b.id == book.id,
      );
      expect(restored.position.chapterIndex, 1);
      expect(restored.position.paragraphIndex, 2);
      expect(
        restored.chapters.first.paragraphs,
        book.chapters.first.paragraphs,
      );
      expect(restored.lastOpenedAt, isNotNull);
    },
  );

  test('preferences survive a fresh repository instance', () async {
    await repository.saveSettings(
      const ReaderSettings(
        theme: ReaderTheme.dark,
        fontSize: 26,
        lineHeight: 2,
      ),
    );
    final fresh = AppRepository(database);
    expect((await fresh.settings()).theme, ReaderTheme.dark);
    expect((await fresh.settings()).fontSize, 26);
  });

  test('notes are stored with anchors and removed with their book', () async {
    final book = (await repository.books()).first;
    await repository.saveBookmark(
      Bookmark(
        id: 'bookmark-1',
        bookId: book.id,
        chapterIndex: 0,
        paragraphIndex: 1,
        quote: '公版文字',
        note: '我的笔记',
        createdAt: DateTime.now(),
      ),
    );
    expect((await repository.bookmarks()).single.note, '我的笔记');
    await repository.removeBook(book.id);
    expect(await repository.bookmarks(), isEmpty);
  });

  test('saving progress after deletion never resurrects the book', () async {
    final book = (await repository.books()).first;
    await repository.removeBook(book.id);
    await repository.savePosition(book.id, const ReadingPosition());
    expect((await repository.books()).any((b) => b.id == book.id), isFalse);
  });
}
