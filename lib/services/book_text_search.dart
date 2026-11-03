import 'dart:math' as math;

import '../domain/book.dart';

/// A matching cached paragraph and the UTF-16 range highlighted in its excerpt.
final class BookTextHit {
  const BookTextHit({
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.chapterId,
    required this.chapterTitle,
    required this.excerpt,
    required this.highlightStart,
    required this.highlightEnd,
  });

  final int chapterIndex;
  final int paragraphIndex;
  final String chapterId;
  final String chapterTitle;
  final String excerpt;
  final int highlightStart;
  final int highlightEnd;
}

/// A bounded set of matches with explicit cached-chapter coverage.
final class BookTextSearchResult {
  BookTextSearchResult({
    required Iterable<BookTextHit> hits,
    required this.cachedChapters,
    required this.scannedChapters,
    required this.truncated,
  }) : hits = List.unmodifiable(hits);

  final List<BookTextHit> hits;
  final int cachedChapters;
  final int scannedChapters;
  final bool truncated;
}

/// Searches only text already owned by a Book; never starts a source request.
final class BookTextSearch {
  const BookTextSearch();

  static const maxQueryCharacters = 100;
  static const maxResults = 100;
  static const maxScannedCharacters = 4 * 1024 * 1024;

  BookTextSearchResult search(Book book, String query) {
    final cachedChapters = book.cachedChapters;
    final term = query.trim();
    if (term.length > maxQueryCharacters || term.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('搜索词不能超过 100 个字符或包含换行。');
    }
    if (term.isEmpty) {
      return BookTextSearchResult(
        hits: const [],
        cachedChapters: cachedChapters,
        scannedChapters: 0,
        truncated: false,
      );
    }

    final expression = RegExp(
      RegExp.escape(term),
      caseSensitive: false,
      unicode: true,
    );
    final hits = <BookTextHit>[];
    var scannedChapters = 0;
    var scannedCharacters = 0;
    var truncated = false;
    searchChapters:
    for (
      var chapterIndex = 0;
      chapterIndex < book.chapters.length;
      chapterIndex++
    ) {
      final chapter = book.chapters[chapterIndex];
      if (!chapter.isCached) continue;
      for (
        var paragraphIndex = 0;
        paragraphIndex < chapter.paragraphs.length;
        paragraphIndex++
      ) {
        final paragraph = chapter.paragraphs[paragraphIndex];
        if (paragraph.length > maxScannedCharacters - scannedCharacters) {
          truncated = true;
          break searchChapters;
        }
        scannedCharacters += paragraph.length;
        final match = expression.firstMatch(paragraph);
        if (match == null) continue;
        final excerpt = _excerpt(paragraph, match.start, match.end);
        hits.add(
          BookTextHit(
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            chapterId: chapter.id,
            chapterTitle: chapter.title,
            excerpt: excerpt.text,
            highlightStart: excerpt.highlightStart,
            highlightEnd: excerpt.highlightEnd,
          ),
        );
        if (hits.length == maxResults) {
          truncated = true;
          break searchChapters;
        }
      }
      scannedChapters++;
    }

    return BookTextSearchResult(
      hits: hits,
      cachedChapters: cachedChapters,
      scannedChapters: scannedChapters,
      truncated: truncated,
    );
  }

  static ({String text, int highlightStart, int highlightEnd}) _excerpt(
    String paragraph,
    int matchStart,
    int matchEnd,
  ) {
    var start = math.max(0, matchStart - 25);
    var end = math.min(paragraph.length, matchEnd + 49);
    if (start > 0 && _isLowSurrogate(paragraph.codeUnitAt(start))) start--;
    if (end < paragraph.length &&
        _isHighSurrogate(paragraph.codeUnitAt(end - 1))) {
      end++;
    }
    final prefix = start == 0 ? '' : '…';
    final suffix = end == paragraph.length ? '' : '…';
    return (
      text: '$prefix${paragraph.substring(start, end)}$suffix',
      highlightStart: prefix.length + matchStart - start,
      highlightEnd: prefix.length + matchEnd - start,
    );
  }

  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;
  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
}
