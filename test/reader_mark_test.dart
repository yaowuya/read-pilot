import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_mark.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

Book _book() => Book(
  id: 'mark-book',
  title: '标注测试书',
  author: '作者',
  description: '',
  category: '本地',
  coverStyle: 0,
  sourceLabel: '本地导入',
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(id: 'mark-chapter', title: '第一章', paragraphs: const ['春风又绿江南岸。']),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'reader-mark-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
    await controller.addBook(_book());
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'local paragraph marks bind to source text and clear with their book',
    () async {
      final mark = await controller.addReaderMark(
        'mark-book',
        0,
        0,
        color: ReaderMarkColor.amber,
        note: '适合重读。',
      );

      expect(mark.color, ReaderMarkColor.amber);
      expect(controller.readerMarks('mark-book'), [mark]);
      expect(controller.readerMarkAt('mark-book', 0, 0, '春风又绿江南岸。'), mark);
      expect(controller.readerMarkAt('mark-book', 0, 0, '正文已变化。'), isNull);

      await controller.removeBook('mark-book');
      expect(controller.readerMarks('mark-book'), isEmpty);
    },
  );

  test('a mark resolves only while its bound paragraph is current', () async {
    final mark = await controller.addReaderMark(
      'mark-book',
      0,
      0,
      color: ReaderMarkColor.mint,
      note: '返回这里。',
    );

    final location = controller.readerMarkLocation(mark);
    expect(location, isNotNull);
    expect(location!.chapterIndex, 0);
    expect(location.chapterTitle, '第一章');
    expect(location.paragraphIndex, 0);
    expect(location.paragraph, '春风又绿江南岸。');

    await controller.removeBook('mark-book');
    await controller.addBook(
      _book().copyWith(
        chapters: [
          Chapter(
            id: 'mark-chapter',
            title: '第一章',
            paragraphs: const ['江南岸的正文已变化。'],
          ),
        ],
      ),
    );

    expect(controller.readerMarkLocation(mark), isNull);
  });

  test(
    'unique selected text annotations coexist and update in place',
    () async {
      final first = await controller.addReaderMark(
        'mark-book',
        0,
        0,
        color: ReaderMarkColor.amber,
        note: '春风。',
        selectedText: '春风',
      );
      final second = await controller.addReaderMark(
        'mark-book',
        0,
        0,
        color: ReaderMarkColor.mint,
        note: '江南。',
        selectedText: '江南',
      );

      expect(first.selectedText, '春风');
      expect(second.selectedText, '江南');
      expect(
        controller
            .readerRangeMarksAt('mark-book', 0, 0, '春风又绿江南岸。')
            .map((mark) => mark.id),
        containsAll({first.id, second.id}),
      );
      await controller.initialize();
      expect(
        controller
            .readerRangeMarksAt('mark-book', 0, 0, '春风又绿江南岸。')
            .map((mark) => mark.selectedText),
        containsAll({'春风', '江南'}),
      );
      expect(controller.readerMarks('mark-book'), hasLength(2));

      final updated = await controller.addReaderMark(
        'mark-book',
        0,
        0,
        color: ReaderMarkColor.blue,
        note: '更新。',
        selectedText: '春风',
      );
      expect(updated.id, first.id);
      expect(updated.color, ReaderMarkColor.blue);
      expect(controller.readerMarks('mark-book'), hasLength(2));

      await expectLater(
        controller.addReaderMark(
          'mark-book',
          0,
          0,
          color: ReaderMarkColor.blue,
          note: '',
          selectedText: '不存在',
        ),
        throwsFormatException,
      );
      await expectLater(
        controller.addReaderMark(
          'mark-book',
          0,
          0,
          color: ReaderMarkColor.blue,
          note: '',
          selectedText: '春风又绿',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'selected-text marks reject source drift and nonunique current text',
    () async {
      final mark = await controller.addReaderMark(
        'mark-book',
        0,
        0,
        color: ReaderMarkColor.mint,
        note: '唯一片段。',
        selectedText: '江南',
      );

      expect(controller.readerMarkLocation(mark), isNotNull);
      final sourceDrifted = ReaderMark(
        id: 'source-drifted',
        bookId: mark.bookId,
        sourceId: 'other-source',
        chapterId: mark.chapterId,
        paragraphIndex: mark.paragraphIndex,
        paragraphFingerprint: mark.paragraphFingerprint,
        color: mark.color,
        note: mark.note,
        selectedText: mark.selectedText,
        createdAt: mark.createdAt,
      );
      expect(controller.readerMarkLocation(sourceDrifted), isNull);

      const duplicateParagraph = '江南江南';
      await controller.removeBook('mark-book');
      await controller.addBook(
        _book().copyWith(
          chapters: [
            Chapter(
              id: 'mark-chapter',
              title: '第一章',
              paragraphs: const [duplicateParagraph],
            ),
          ],
        ),
      );
      expect(controller.readerMarkLocation(mark), isNull);

      final noLongerUnique = ReaderMark(
        id: 'no-longer-unique',
        bookId: 'mark-book',
        sourceId: null,
        chapterId: 'mark-chapter',
        paragraphIndex: 0,
        paragraphFingerprint: ReaderMark.fingerprint(duplicateParagraph),
        color: ReaderMarkColor.blue,
        note: '',
        selectedText: '江南',
        createdAt: DateTime.utc(2026),
      );
      expect(controller.readerMarkLocation(noLongerUnique), isNull);
    },
  );

  test(
    'marks reload locally but are excluded from version-one backups',
    () async {
      await controller.addReaderMark(
        'mark-book',
        0,
        0,
        color: ReaderMarkColor.blue,
        note: '',
      );
      await controller.initialize();

      expect(controller.readerMarks('mark-book'), hasLength(1));
      final backup = jsonDecode(
        utf8.decode(await controller.exportLocalBackup()),
      );
      expect(backup, isNot(contains('readerMarks')));
    },
  );
}
