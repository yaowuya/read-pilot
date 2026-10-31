import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/source_switch.dart';

Book _book({
  required String id,
  required String sourceId,
  required String sourceLabel,
  required List<Chapter> chapters,
  ReadingPosition position = const ReadingPosition(),
  String? coverUrl,
}) => Book(
  id: id,
  title: '测试书',
  author: '测试作者',
  description: '简介',
  category: '文学',
  coverStyle: 1,
  sourceLabel: sourceLabel,
  sourceId: sourceId,
  url: '$sourceId/book',
  coverUrl: coverUrl,
  chapters: chapters,
  position: position,
  addedAt: DateTime.utc(2026, 1, 1),
  lastOpenedAt: DateTime.utc(2026, 2, 1),
);

Chapter _chapter(
  String id,
  String title, [
  List<String> paragraphs = const [],
]) => Chapter(
  id: id,
  title: title,
  url: 'https://chapter.example/$id',
  paragraphs: paragraphs,
);

void main() {
  test(
    'maps normalized chapter and paragraph text while preserving identity',
    () {
      final current = _book(
        id: 'shelf-book',
        sourceId: 'https://old.example',
        sourceLabel: '旧源',
        position: const ReadingPosition(chapterIndex: 1, paragraphIndex: 1),
        coverUrl: 'https://old.example/cover.jpg',
        chapters: [
          _chapter('old-9', '第 9 章 前奏', ['前奏']),
          _chapter('old-10', '第 10 章 归来', ['旧段', '目标段落', '尾段']),
        ],
      );
      final replacement = _book(
        id: 'search-result',
        sourceId: 'https://new.example',
        sourceLabel: '新源',
        chapters: [
          _chapter('new-10', '第十章 归来', ['新段', '目标段落', '新尾段']),
          _chapter('new-11', '第十一章 继续'),
        ],
      );
      final bookmarks = [
        Bookmark(
          id: 'bookmark-1',
          bookId: current.id,
          chapterIndex: 1,
          paragraphIndex: 1,
          quote: '目标段落',
          note: '保留',
          createdAt: DateTime.utc(2026, 2, 2),
        ),
      ];

      final plan = const SourceSwitchMapper().plan(
        current: current,
        replacement: replacement,
        bookmarks: bookmarks,
      );

      expect(plan.book.id, current.id);
      expect(plan.book.sourceId, 'https://new.example');
      expect(plan.book.sourceLabel, '新源');
      expect(plan.book.coverUrl, 'https://old.example/cover.jpg');
      expect(plan.book.position.chapterIndex, 0);
      expect(plan.book.position.paragraphIndex, 1);
      expect(plan.book.addedAt, current.addedAt);
      expect(plan.book.lastOpenedAt, current.lastOpenedAt);
      expect(plan.bookmarks.single.id, 'bookmark-1');
      expect(plan.bookmarks.single.bookId, current.id);
      expect(plan.bookmarks.single.chapterIndex, 0);
      expect(plan.bookmarks.single.paragraphIndex, 1);
    },
  );

  for (final scenario in [
    (
      name: 'duplicate suffixes retain distinct numbered chapters',
      currentTitles: ['第一章 开始', '第二章 无题', '第三章 无题'],
      replacementTitles: ['第一章 开始', '第二章 无题', '第三章 无题'],
      oldPosition: 2,
      oldBookmark: 2,
      newPosition: 2,
      newBookmark: 2,
    ),
    (
      name: 'full numbered titles follow catalog insertion and reordering',
      currentTitles: ['第一章 开始', '第二章 无题', '第三章 无题'],
      replacementTitles: ['第三章 无题', '新增序言', '第一章 开始', '第二章 无题'],
      oldPosition: 2,
      oldBookmark: 1,
      newPosition: 0,
      newBookmark: 3,
    ),
    (
      name: 'ambiguous full titles and suffixes fall back to clamped indexes',
      currentTitles: ['第一章 无题', '第二章 无题', '第三章 无题', '第四章 无题', '第五章 无题'],
      replacementTitles: ['第一章 无题', '第五章 无题', '第五章 无题'],
      oldPosition: 4,
      oldBookmark: 1,
      newPosition: 2,
      newBookmark: 1,
    ),
    (
      name: 'unique number-only titles follow reordered chapters',
      currentTitles: ['第九章', '第十章'],
      replacementTitles: ['第十章', '第九章'],
      oldPosition: 1,
      oldBookmark: 0,
      newPosition: 0,
      newBookmark: 1,
    ),
  ]) {
    test(scenario.name, () {
      final current = _book(
        id: 'shelf-book',
        sourceId: 'https://old.example',
        sourceLabel: '旧源',
        position: ReadingPosition(
          chapterIndex: scenario.oldPosition,
          paragraphIndex: 1,
        ),
        chapters: [
          for (var index = 0; index < scenario.currentTitles.length; index++)
            _chapter('old-$index', scenario.currentTitles[index], [
              '首段',
              '目标段落',
            ]),
        ],
      );
      final replacement = _book(
        id: 'replacement',
        sourceId: 'https://new.example',
        sourceLabel: '新源',
        chapters: [
          for (
            var index = 0;
            index < scenario.replacementTitles.length;
            index++
          )
            _chapter('new-$index', scenario.replacementTitles[index], [
              '首段',
              '目标段落',
            ]),
        ],
      );
      final bookmark = Bookmark(
        id: 'mapped-note',
        bookId: current.id,
        chapterIndex: scenario.oldBookmark,
        paragraphIndex: 1,
        quote: '目标段落',
        note: '保留',
        createdAt: DateTime.utc(2026),
      );

      final plan = const SourceSwitchMapper().plan(
        current: current,
        replacement: replacement,
        bookmarks: [bookmark],
      );

      expect(plan.book.position.chapterIndex, scenario.newPosition);
      expect(plan.book.position.paragraphIndex, 1);
      expect(plan.bookmarks.single.chapterIndex, scenario.newBookmark);
      expect(plan.bookmarks.single.paragraphIndex, 1);
    });
  }

  test('falls back to a clamped chapter and paragraph index', () {
    final current = _book(
      id: 'shelf-book',
      sourceId: 'https://old.example',
      sourceLabel: '旧源',
      position: const ReadingPosition(chapterIndex: 4, paragraphIndex: 9),
      chapters: List.generate(
        5,
        (index) => _chapter('old-$index', '旧章节 $index', ['旧正文']),
      ),
    );
    final replacement = _book(
      id: 'replacement',
      sourceId: 'https://new.example',
      sourceLabel: '新源',
      chapters: [
        _chapter('new-0', '完全不同', ['一', '二']),
        _chapter('new-1', '仍然不同', ['三']),
      ],
    );

    final plan = const SourceSwitchMapper().plan(
      current: current,
      replacement: replacement,
      bookmarks: const [],
    );

    expect(plan.book.position.chapterIndex, 1);
    expect(plan.book.position.paragraphIndex, 0);
  });

  test('number-only chapter titles use the neighboring index fallback', () {
    final current = _book(
      id: 'shelf-book',
      sourceId: 'https://old.example',
      sourceLabel: '旧源',
      position: const ReadingPosition(chapterIndex: 1),
      chapters: [
        _chapter('old-1', '第 98 章', ['一']),
        _chapter('old-2', '第 99 章', ['二']),
      ],
    );
    final replacement = _book(
      id: 'replacement',
      sourceId: 'https://new.example',
      sourceLabel: '新源',
      chapters: [
        _chapter('new-1', '第一章', ['一']),
        _chapter('new-2', '第二章', ['二']),
      ],
    );

    final plan = const SourceSwitchMapper().plan(
      current: current,
      replacement: replacement,
      bookmarks: const [],
    );

    expect(plan.book.position.chapterIndex, 1);
  });

  test(
    'repeated paragraph text keeps progress and notes near their original index',
    () {
      final paragraphs = ['开头', '重复句', '过渡', '重复句'];
      final current = _book(
        id: 'shelf-book',
        sourceId: 'https://old.example',
        sourceLabel: '旧源',
        position: const ReadingPosition(paragraphIndex: 3),
        chapters: [_chapter('old', '第一章', paragraphs)],
      );
      final replacement = _book(
        id: 'replacement',
        sourceId: 'https://new.example',
        sourceLabel: '新源',
        chapters: [_chapter('new', '第一章', paragraphs)],
      );
      final plan = const SourceSwitchMapper().plan(
        current: current,
        replacement: replacement,
        bookmarks: [
          Bookmark(
            id: 'repeat-note',
            bookId: current.id,
            chapterIndex: 0,
            paragraphIndex: 3,
            quote: '重复句',
            note: '',
            createdAt: DateTime.utc(2026),
          ),
        ],
      );
      expect(plan.book.position.paragraphIndex, 3);
      expect(plan.bookmarks.single.paragraphIndex, 3);
    },
  );

  test(
    'ambiguous quote fragments do not select the first containing paragraph',
    () {
      final paragraphs = ['开头', '他说重复句', '过渡', '又说重复句'];
      final current = _book(
        id: 'shelf-book',
        sourceId: 'https://old.example',
        sourceLabel: '旧源',
        position: const ReadingPosition(paragraphIndex: 3),
        chapters: [_chapter('old', '第一章', paragraphs)],
      );
      final replacement = _book(
        id: 'replacement',
        sourceId: 'https://new.example',
        sourceLabel: '新源',
        chapters: [_chapter('new', '第一章', paragraphs)],
      );
      final plan = const SourceSwitchMapper().plan(
        current: current,
        replacement: replacement,
        bookmarks: [
          Bookmark(
            id: 'partial-note',
            bookId: current.id,
            chapterIndex: 0,
            paragraphIndex: 3,
            quote: '重复句',
            note: '',
            createdAt: DateTime.utc(2026),
          ),
        ],
      );
      expect(plan.bookmarks.single.paragraphIndex, 3);
    },
  );

  test('owns immutable copies of replacement chapters and bookmarks', () {
    final chapters = [
      _chapter('new', '第一章', ['正文']),
    ];
    final bookmarks = <Bookmark>[];
    final plan = const SourceSwitchMapper().plan(
      current: _book(
        id: 'shelf-book',
        sourceId: 'https://old.example',
        sourceLabel: '旧源',
        chapters: [
          _chapter('old', '第一章', ['旧正文']),
        ],
      ),
      replacement: _book(
        id: 'replacement',
        sourceId: 'https://new.example',
        sourceLabel: '新源',
        chapters: chapters,
      ),
      bookmarks: bookmarks,
    );

    chapters.clear();
    bookmarks.add(
      Bookmark(
        id: 'late',
        bookId: 'shelf-book',
        chapterIndex: 0,
        paragraphIndex: 0,
        quote: '',
        note: '',
        createdAt: DateTime.utc(2026),
      ),
    );
    expect(plan.book.chapters, hasLength(1));
    expect(plan.bookmarks, isEmpty);
    expect(() => plan.bookmarks.add(bookmarks.single), throwsUnsupportedError);
  });
}
