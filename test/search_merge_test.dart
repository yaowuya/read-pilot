import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/domain/search_merge.dart';

/// The record shape the controller maps `SourceSearchGroup` onto.
typedef SearchGroupLike = ({BookSource source, List<Book> books});

BookSource _source(String name) => BookSource({
  'bookSourceUrl': 'https://$name.example',
  'bookSourceName': name,
});

Book _book(
  BookSource source, {
  required String title,
  String author = '天刘留香',
  String category = '玄幻',
  String? url,
  String id = 'remote-1',
}) => Book(
  id: id,
  title: title,
  author: author,
  description: '',
  category: category,
  coverStyle: 1,
  sourceLabel: source.name,
  sourceId: source.id,
  url: url,
  addedAt: DateTime.utc(2026),
);

void main() {
  test('same title and author from two sources merge into one row', () {
    final a = _source('a');
    final b = _source('b');
    final results = mergeSearchResults(<SearchGroupLike>[
      (
        source: a,
        books: [_book(a, title: '斩神', url: 'https://a.example/book/1')],
      ),
      (
        source: b,
        books: [_book(b, title: '斩神', url: 'https://b.example/book/9')],
      ),
    ], keyword: '斩神');

    expect(results, hasLength(1));
    expect(results.single.primary.title, '斩神');
    expect(results.single.primary.author, '天刘留香');
    expect(results.single.sourceCount, 2);
    expect(results.single.sources.map((source) => source.id), [
      'https://a.example',
      'https://b.example',
    ]);
  });

  test('three distinct sources count as three', () {
    final sources = [_source('a'), _source('b'), _source('c')];
    final results = mergeSearchResults(<SearchGroupLike>[
      for (final source in sources)
        (source: source, books: [_book(source, title: '斩神')]),
    ], keyword: '斩神');

    expect(results, hasLength(1));
    expect(results.single.sourceCount, 3);
    expect(results.single.sources.map((source) => source.id), [
      'https://a.example',
      'https://b.example',
      'https://c.example',
    ]);
  });

  test('different titles sharing a book url join the first row', () {
    final a = _source('a');
    final b = _source('b');
    const sharedUrl = 'https://a.example/book/1';
    final results = mergeSearchResults(<SearchGroupLike>[
      (source: a, books: [_book(a, title: '斩神', url: sharedUrl)]),
      (source: b, books: [_book(b, title: '斩神 第二部', url: sharedUrl)]),
    ], keyword: '斩神');

    expect(results, hasLength(1));
    expect(results.single.primary.title, '斩神');
    expect(results.single.sourceCount, 2);
  });

  test(
    'a book url already owned by another row never creates a second row',
    () {
      final a = _source('a');
      final b = _source('b');
      const sharedUrl = 'https://a.example/book/1';
      final results = mergeSearchResults(<SearchGroupLike>[
        (source: a, books: [_book(a, title: '斩神', url: sharedUrl)]),
        (
          source: a,
          books: [_book(a, title: '另一本书', url: 'https://a.example/2')],
        ),
        (source: b, books: [_book(b, title: '斩神 外传', url: sharedUrl)]),
      ], keyword: '别的东西');

      // The unrelated row survives untouched and the alias joins the first row.
      expect(results, hasLength(2));
      final first = results.singleWhere(
        (result) => result.primary.title == '斩神',
      );
      expect(first.sourceCount, 2);
      expect(
        results
            .singleWhere((result) => result.primary.title == '另一本书')
            .sourceCount,
        1,
      );
    },
  );

  test('the same source returning the same book twice counts once', () {
    final a = _source('a');
    final results = mergeSearchResults(<SearchGroupLike>[
      (
        source: a,
        books: [
          _book(a, title: '斩神', url: 'https://a.example/book/1'),
          _book(a, title: '斩神', url: 'https://a.example/book/1'),
        ],
      ),
    ], keyword: '斩神');

    expect(results, hasLength(1));
    expect(results.single.sourceCount, 1);
  });

  test('a failed group contributes no books', () {
    final a = _source('a');
    final failed = _source('broken');
    final results = mergeSearchResults(<SearchGroupLike>[
      (
        source: a,
        books: [_book(a, title: '斩神', url: 'https://a.example/book/1')],
      ),
      // The controller maps `SourceSearchGroup(..., error: ...)` onto no books,
      // so a failed source can never add to the badge count.
      (source: failed, books: const <Book>[]),
    ], keyword: '斩神');

    expect(results, hasLength(1));
    expect(results.single.sourceCount, 1);
    expect(results.single.sources.single.id, 'https://a.example');
  });

  test('books without a url still merge by title and author', () {
    final a = _source('a');
    final b = _source('b');
    final results = mergeSearchResults(<SearchGroupLike>[
      (source: a, books: [_book(a, title: '斩神')]),
      (source: b, books: [_book(b, title: '斩神')]),
    ], keyword: '斩神');

    expect(results, hasLength(1));
    expect(results.single.sourceCount, 2);
  });

  test('empty input yields an empty list', () {
    expect(mergeSearchResults(const [], keyword: '斩神'), isEmpty);
    expect(
      mergeSearchResults(<SearchGroupLike>[
        (source: _source('empty'), books: const <Book>[]),
      ], keyword: '斩神'),
      isEmpty,
    );
  });

  test('ordering buckets equal, then tag, then contains, then other', () {
    final a = _source('a');
    final b = _source('b');
    final results = mergeSearchResults(<SearchGroupLike>[
      (source: a, books: [_book(a, title: '无关的书')]),
      (source: a, books: [_book(a, title: '斩神记', category: '仙侠')]),
      (source: a, books: [_book(a, title: '随便什么', category: '斩神系列')]),
      (source: a, books: [_book(a, title: '斩神')]),
      (source: b, books: [_book(b, title: '斩神记', category: '仙侠')]),
    ], keyword: '斩神');

    expect(results.map((result) => result.primary.title), [
      '斩神',
      '随便什么',
      '斩神记',
      '无关的书',
    ]);
  });

  test('equal bucket also matches on author, ignoring case', () {
    final a = _source('a');
    final results = mergeSearchResults(<SearchGroupLike>[
      (source: a, books: [_book(a, title: '不相干', author: 'Someone')]),
    ], keyword: 'someONE');

    expect(results, hasLength(1));
    expect(results.single.primary.author, 'Someone');
  });

  test(
    'higher source count leads inside a bucket, ties keep first-seen order',
    () {
      final a = _source('a');
      final b = _source('b');
      final results = mergeSearchResults(<SearchGroupLike>[
        // Both contains-bucket with one source each: first-seen order survives.
        (
          source: a,
          books: [_book(a, title: '斩神记', url: 'https://a.example/1')],
        ),
        (
          source: a,
          books: [_book(a, title: '斩神录', url: 'https://a.example/2')],
        ),
        // Two sources, so this one leads the contains bucket.
        (
          source: a,
          books: [_book(a, title: '斩神传', url: 'https://a.example/3')],
        ),
        (
          source: b,
          books: [_book(b, title: '斩神传', url: 'https://b.example/3')],
        ),
        // Other bucket, but the largest source count of all.
        (
          source: a,
          books: [_book(a, title: '别的东西', url: 'https://a.example/4')],
        ),
        (
          source: b,
          books: [_book(b, title: '别的东西', url: 'https://b.example/4')],
        ),
      ], keyword: '斩神');

      expect(results.map((result) => result.primary.title), [
        '斩神传',
        '斩神记',
        '斩神录',
        '别的东西',
      ]);
      expect(results.map((result) => result.sourceCount), [2, 1, 1, 2]);
    },
  );
}
