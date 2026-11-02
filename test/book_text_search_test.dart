import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/book_text_search.dart';

Book _book(List<Chapter> chapters) => Book(
  id: 'sample',
  title: '测试书',
  author: '测试作者',
  description: '',
  category: '文学',
  coverStyle: 0,
  sourceLabel: '本地测试',
  addedAt: DateTime.utc(2026),
  chapters: chapters,
);

Chapter _chapter(String id, List<String> paragraphs) =>
    Chapter(id: id, title: '第$id章', paragraphs: paragraphs);

void main() {
  test('finds cached paragraphs and reports actual chapter coverage', () {
    final book = _book([
      _chapter('one', ['开头', '书中目标在这里']),
      _chapter('uncached', []),
      _chapter('three', ['另一个目标']),
    ]);
    final result = const BookTextSearch().search(book, '  目标  ');

    expect(result.cachedChapters, 2);
    expect(result.scannedChapters, 2);
    expect(result.truncated, isFalse);
    expect(result.hits, hasLength(2));
    expect(result.hits.map((hit) => (hit.chapterIndex, hit.paragraphIndex)), [
      (0, 1),
      (2, 0),
    ]);
    expect(result.hits.first.chapterId, 'one');
    expect(result.hits.first.chapterTitle, '第one章');
    expect(
      result.hits.first.excerpt.substring(
        result.hits.first.highlightStart,
        result.hits.first.highlightEnd,
      ),
      '目标',
    );
    expect(book.chapters[1].paragraphs, isEmpty);
  });

  test('uses literal case-insensitive matching rather than user regex', () {
    final book = _book([
      _chapter('one', ['A+B 是书名', 'aab 不应命中']),
    ]);
    final result = const BookTextSearch().search(book, 'a+b');
    expect(result.hits, hasLength(1));
    expect(result.hits.single.paragraphIndex, 0);
    expect(
      result.hits.single.excerpt.substring(
        result.hits.single.highlightStart,
        result.hits.single.highlightEnd,
      ),
      'A+B',
    );
  });

  test('empty and oversized queries do not scan cached content', () {
    final book = _book([
      _chapter('one', ['目标']),
    ]);
    final empty = const BookTextSearch().search(book, ' \t ');
    expect(empty.hits, isEmpty);
    expect(empty.cachedChapters, 1);
    expect(empty.scannedChapters, 0);
    expect(empty.truncated, isFalse);
    expect(
      () => const BookTextSearch().search(
        book,
        '甲' * (BookTextSearch.maxQueryCharacters + 1),
      ),
      throwsFormatException,
    );
  });

  test('result and scan limits never pretend to cover the whole book', () {
    final hits = const BookTextSearch().search(
      _book([
        _chapter('many', List.filled(BookTextSearch.maxResults + 2, '目标')),
      ]),
      '目标',
    );
    expect(hits.hits, hasLength(BookTextSearch.maxResults));
    expect(hits.scannedChapters, 0);
    expect(hits.truncated, isTrue);
    expect(() => hits.hits.clear(), throwsUnsupportedError);

    final tooLong = const BookTextSearch().search(
      _book([
        _chapter('large', ['甲' * (BookTextSearch.maxScannedCharacters + 1)]),
      ]),
      '甲',
    );
    expect(tooLong.hits, isEmpty);
    expect(tooLong.scannedChapters, 0);
    expect(tooLong.truncated, isTrue);
  });

  test('excerpt boundaries preserve Unicode surrogate pairs', () {
    final text = '甲${'😀' * 20}目标${'📖' * 30}';
    final hit = const BookTextSearch()
        .search(
          _book([
            _chapter('emoji', [text]),
          ]),
          '目标',
        )
        .hits
        .single;
    expect(hit.excerpt.length, lessThan(text.length));
    expect(hit.excerpt.runes, isNot(contains(0xFFFD)));
    expect(hit.excerpt.substring(hit.highlightStart, hit.highlightEnd), '目标');
  });
}
