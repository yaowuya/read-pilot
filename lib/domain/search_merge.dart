import 'book.dart';
import 'book_source.dart';

/// One merged row of a cross-source search.
///
/// [primary] is the first [Book] seen for one `(title, author)` identity and
/// carries the display data; [sources] holds every distinct source that offered
/// a book under that identity, in first-seen order, without repeats.
class MergedBookResult {
  const MergedBookResult({required this.primary, required this.sources});

  final Book primary;
  final List<BookSource> sources;

  int get sourceCount => sources.length;
}

/// Merges per-source search results into one row per distinct book.
///
/// Mirrors legado's `SearchViewModel.mergeSearchResults`
/// (`SearchViewModel.kt:1040-1063`):
///
/// * The primary key is the exact `(title, author)` pair; no normalisation.
/// * A secondary `url -> key` index catches aliases: a book whose `url` was
///   already seen under a different key joins that existing row instead of
///   creating a new one.
/// * A book with `url == null` still merges by key, it just never enters the
///   url index.
/// * A group whose source failed carries no books (`SourceSearchGroup` maps a
///   non-null `error` to an empty `books` list), so failed groups contribute
///   nothing and the merge layer never inspects errors.
///
/// Sources are deduplicated by [BookSource.id] (the source URL), so the same
/// source returning the same book twice, or two [BookSource] instances built
/// from the same definition, never inflate [MergedBookResult.sourceCount].
///
/// Results are ordered the way legado orders search hits
/// (`SearchViewModel.kt:1073-1093`): four priority buckets concatenated in
/// order — exact `title`/`author` match, `category` containing the keyword,
/// `title`/`author` containing the keyword, then everything else. Each bucket
/// is sorted by [MergedBookResult.sourceCount] descending, keeping first-seen
/// order for ties.
List<MergedBookResult> mergeSearchResults(
  Iterable<({BookSource source, List<Book> books})> groups, {
  required String keyword,
}) {
  final merged = <_BookKey, _MergeAggregate>{};
  final urlIndex = <String, _BookKey>{};

  for (final group in groups) {
    for (final book in group.books) {
      final key = _BookKey(book.title, book.author);
      final url = book.url;
      final owner = url == null ? null : urlIndex[url];
      if (owner != null && owner != key) {
        final target = merged[owner];
        if (target != null) {
          target.addSource(group.source);
          continue;
        }
      }
      final existing = merged[key];
      if (existing != null) {
        existing.addSource(group.source);
        continue;
      }
      merged[key] = _MergeAggregate(book)..addSource(group.source);
      if (url != null) urlIndex[url] = key;
    }
  }

  return _prioritise([
    for (final aggregate in merged.values) aggregate.toResult(),
  ], keyword.toLowerCase());
}

/// Stable bucket sort: 4 priority buckets, each by source count descending.
List<MergedBookResult> _prioritise(
  List<MergedBookResult> results,
  String lowerKeyword,
) {
  final equal = <MergedBookResult>[];
  final tagged = <MergedBookResult>[];
  final contains = <MergedBookResult>[];
  final other = <MergedBookResult>[];
  for (final result in results) {
    final book = result.primary;
    if (_matchesExactly(book.title, lowerKeyword) ||
        _matchesExactly(book.author, lowerKeyword)) {
      equal.add(result);
    } else if (_containsKeyword(book.category, lowerKeyword)) {
      tagged.add(result);
    } else if (_containsKeyword(book.title, lowerKeyword) ||
        _containsKeyword(book.author, lowerKeyword)) {
      contains.add(result);
    } else {
      other.add(result);
    }
  }
  return List.unmodifiable([
    ..._bySourceCount(equal),
    ..._bySourceCount(tagged),
    ..._bySourceCount(contains),
    ..._bySourceCount(other),
  ]);
}

bool _matchesExactly(String value, String lowerKeyword) =>
    value.toLowerCase() == lowerKeyword;

bool _containsKeyword(String value, String lowerKeyword) =>
    value.toLowerCase().contains(lowerKeyword);

/// Sorts by source count descending, keeping first-seen order for ties.
///
/// [List.sort] is not guaranteed stable, so the original index breaks ties.
List<MergedBookResult> _bySourceCount(List<MergedBookResult> bucket) {
  final order = [for (var index = 0; index < bucket.length; index++) index];
  order.sort((a, b) {
    final delta = bucket[b].sourceCount - bucket[a].sourceCount;
    return delta != 0 ? delta : a - b;
  });
  return [for (final index in order) bucket[index]];
}

/// Identity of one merged book; exact `(title, author)` with value equality.
final class _BookKey {
  const _BookKey(this.title, this.author);

  final String title;
  final String author;

  @override
  bool operator ==(Object other) =>
      other is _BookKey && other.title == title && other.author == author;

  @override
  int get hashCode => Object.hash(title, author);
}

/// Mutable working set for one key; frozen into [MergedBookResult] at the end.
final class _MergeAggregate {
  _MergeAggregate(this.primary);

  final Book primary;
  final List<BookSource> _sources = [];
  final Set<String> _sourceIds = {};

  void addSource(BookSource source) {
    if (_sourceIds.add(source.id)) _sources.add(source);
  }

  MergedBookResult toResult() =>
      MergedBookResult(primary: primary, sources: List.unmodifiable(_sources));
}
