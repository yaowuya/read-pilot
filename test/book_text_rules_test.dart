import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/services/book_text_rules.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'text-rules-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test('replacements are literal, ordered, and never mutate their input', () {
    final rules = [
      const BookTextRule(id: 'first', needle: '[a-z]', replacement: '词'),
      const BookTextRule(id: 'second', needle: '词', replacement: '新词'),
      const BookTextRule(
        id: 'disabled',
        needle: '新词',
        replacement: '不出现',
        enabled: false,
      ),
    ];
    const raw = '原文 [a-z] 完。';
    expect(BookTextRules.apply(raw, rules), '原文 新词 完。');
    expect(raw, '原文 [a-z] 完。');
    expect(BookTextRules.apply(raw, rules.reversed), '原文 词 完。');
  });

  test('validation rejects newlines and very large or empty patterns', () {
    for (final input in [
      '',
      '   ',
      'a\n',
      String.fromCharCodes([97, 0x2028]),
      'x' * 65,
    ]) {
      expect(() => BookTextRules.validate(input, '替换'), throwsFormatException);
    }
    for (final value in ['a\r', 'x' * 129]) {
      expect(() => BookTextRules.validate('a', value), throwsFormatException);
    }
    expect(() => BookTextRules.validate('a', ''), returnsNormally);
  });

  test('display transform skips paragraphs and rules beyond its budget', () {
    final big = 'a' * (BookTextRules.maxOutputCharacters + 1);
    const rule = BookTextRule(id: 'a', needle: 'a', replacement: 'x');
    expect(BookTextRules.apply(big, [rule]), big);
    final dense = 'a' * (BookTextRules.maxMatchesPerRule + 1);
    expect(BookTextRules.apply(dense, [rule]), dense);
    expect(BookTextRules.apply('a' * 3, [rule]), 'xxx');
  });

  test('chapter-wide expansion stays bounded and never partially replaces', () {
    const simple = BookTextRule(id: 'simple', needle: 'a', replacement: 'x');
    expect(BookTextRules.applyChapter(['a', 'b'], [simple]), ['x', 'b']);

    final raw = List<String>.filled(17, 'a' * 1024);
    final expansion = BookTextRule(
      id: 'expand',
      needle: 'a',
      replacement: 'x' * 128,
    );
    expect(BookTextRules.applyChapter(raw, [expansion]), same(raw));
  });

  test(
    'per-book rules persist without rewriting cached chapter text',
    () async {
      final book = controller.books.first;
      final original = book.chapters.first.paragraphs.first;
      final rule = await controller.addTextRule(book.id, '余生', '我生');
      expect(controller.textRules(book.id).single.id, rule.id);
      expect(
        controller.displayParagraph(book.id, original),
        original.replaceAll('余生', '我生'),
      );
      expect(
        controller.book(book.id)!.chapters.first.paragraphs.first,
        original,
      );

      final fresh = AppController(AppRepository(database), SourceEngine());
      addTearDown(fresh.dispose);
      await fresh.initialize();
      expect(fresh.textRules(book.id).single.needle, '余生');
      expect(fresh.book(book.id)!.chapters.first.paragraphs.first, original);
      expect(
        fresh.displayParagraph(book.id, original),
        original.replaceAll('余生', '我生'),
      );
    },
  );

  test('enable, edit, reorder, and delete stay within one book', () async {
    final book = controller.books.first;
    final other = controller.books.last;
    final first = await controller.addTextRule(book.id, '旧', '中');
    final second = await controller.addTextRule(book.id, '中', '新');
    expect(controller.displayParagraph(book.id, '旧'), '新');
    expect(controller.displayParagraph(other.id, '旧'), '旧');
    final before = controller.textRulesRevision(book.id);
    await controller.moveTextRule(book.id, second.id, -1);
    expect(controller.displayParagraph(book.id, '旧'), '中');
    await controller.setTextRuleEnabled(book.id, first.id, false);
    expect(controller.displayParagraph(book.id, '旧'), '旧');
    await controller.updateTextRule(book.id, first.id, '旧', '新');
    await controller.setTextRuleEnabled(book.id, first.id, true);
    expect(controller.displayParagraph(book.id, '旧'), '新');
    expect(controller.textRulesRevision(book.id), greaterThan(before));
    await controller.deleteTextRule(book.id, second.id);
    expect(controller.textRules(book.id), hasLength(1));
    expect(
      (await AppRepository(database).textRules(book.id)).single.id,
      first.id,
    );
  });

  test(
    'removing a book removes its rules and invalid inputs write nothing',
    () async {
      final book = controller.books.first;
      await controller.addTextRule(book.id, '旧', '新');
      await expectLater(
        controller.addTextRule(book.id, 'bad\n', 'x'),
        throwsFormatException,
      );
      await expectLater(
        controller.addTextRule('missing-book', '旧', '新'),
        throwsStateError,
      );
      for (var index = 0; index < BookTextRules.maxRulesPerBook - 1; index++) {
        await controller.addTextRule(book.id, 'a$index', 'b$index');
      }
      await expectLater(
        controller.addTextRule(book.id, 'over', 'limit'),
        throwsStateError,
      );
      expect(
        controller.textRules(book.id),
        hasLength(BookTextRules.maxRulesPerBook),
      );
      await controller.removeBook(book.id);
      expect(controller.textRules(book.id), isEmpty);
      expect(await AppRepository(database).textRules(book.id), isEmpty);
    },
  );
}
