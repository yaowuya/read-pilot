import 'dart:math' as math;

import 'book.dart';

/// Immutable book and bookmark values ready for one atomic source switch.
final class SourceSwitchPlan {
  SourceSwitchPlan({required this.book, required Iterable<Bookmark> bookmarks})
    : bookmarks = List.unmodifiable(bookmarks);

  final Book book;
  final List<Bookmark> bookmarks;
}

/// Maps logical reading anchors between two independently loaded source catalogs.
final class SourceSwitchMapper {
  const SourceSwitchMapper();

  /// Maps this book's anchors onto a nonempty remote catalog with a book URL.
  /// Unique full titles take priority over unique suffixes, then clamped indexes.
  /// Unique cached text refines paragraph anchors; ambiguous/uncached text retains indexes.
  /// Invalid replacements throw ArgumentError; other books' bookmarks pass through.
  SourceSwitchPlan plan({
    required Book current,
    required Book replacement,
    required Iterable<Bookmark> bookmarks,
  }) {
    if (replacement.chapters.isEmpty) {
      throw ArgumentError.value(
        replacement,
        'replacement',
        'must contain chapters',
      );
    }
    final fullIndexes = <String, int?>{};
    final suffixIndexes = <String, int?>{};
    // A null entry marks ambiguity: repeated titles must not pick the first match.
    void addUnique(Map<String, int?> indexes, String key, int index) {
      if (key.isNotEmpty) {
        indexes.update(key, (_) => null, ifAbsent: () => index);
      }
    }

    for (var index = 0; index < replacement.chapters.length; index++) {
      final title = replacement.chapters[index].title;
      addUnique(fullIndexes, _fullChapterKey(title), index);
      addUnique(suffixIndexes, _chapterKey(title), index);
    }

    int mapChapter(int oldIndex) {
      if (current.chapters.isEmpty) return 0;
      final safeOld = oldIndex.clamp(0, current.chapters.length - 1);
      final title = current.chapters[safeOld].title;
      final exact =
          fullIndexes[_fullChapterKey(title)] ??
          suffixIndexes[_chapterKey(title)];
      return exact ?? safeOld.clamp(0, replacement.chapters.length - 1);
    }

    int mapParagraph(
      int oldChapterIndex,
      int oldParagraphIndex,
      int newChapterIndex, {
      String? quote,
    }) {
      final target = replacement.chapters[newChapterIndex].paragraphs;
      // Uncached note chapters cannot yet bound the anchor; do not reset it to zero.
      if (target.isEmpty) return math.max(0, oldParagraphIndex);
      String? anchor;
      if (quote != null && quote.trim().isNotEmpty) {
        anchor = quote;
      } else if (current.chapters.isNotEmpty) {
        final safeChapter = oldChapterIndex.clamp(
          0,
          current.chapters.length - 1,
        );
        final sourceParagraphs = current.chapters[safeChapter].paragraphs;
        if (sourceParagraphs.isNotEmpty) {
          anchor =
              sourceParagraphs[oldParagraphIndex.clamp(
                0,
                sourceParagraphs.length - 1,
              )];
        }
      }
      final anchorKey = anchor == null ? '' : _paragraphKey(anchor);
      if (anchorKey.isNotEmpty) {
        // Repeated text cannot identify one logical occurrence; retain the index.
        int? uniqueMatch(bool Function(String) matches) {
          int? found;
          for (var index = 0; index < target.length; index++) {
            if (!matches(target[index])) continue;
            if (found != null) return null;
            found = index;
          }
          return found;
        }

        final exact = uniqueMatch(
          (paragraph) => _paragraphKey(paragraph) == anchorKey,
        );
        if (exact != null) return exact;
        if (quote != null) {
          final containing = uniqueMatch(
            (paragraph) => _paragraphKey(paragraph).contains(anchorKey),
          );
          if (containing != null) return containing;
        }
      }
      return oldParagraphIndex.clamp(0, target.length - 1);
    }

    final newChapterIndex = mapChapter(current.position.chapterIndex);
    final newPosition = ReadingPosition(
      chapterIndex: newChapterIndex,
      paragraphIndex: mapParagraph(
        current.position.chapterIndex,
        current.position.paragraphIndex,
        newChapterIndex,
      ),
    );
    final mappedBookmarks = <Bookmark>[
      for (final bookmark in bookmarks)
        if (bookmark.bookId != current.id)
          bookmark
        else
          () {
            final chapterIndex = mapChapter(bookmark.chapterIndex);
            return bookmark.copyWithPosition(
              chapterIndex: chapterIndex,
              paragraphIndex: mapParagraph(
                bookmark.chapterIndex,
                bookmark.paragraphIndex,
                chapterIndex,
                quote: bookmark.quote,
              ),
            );
          }(),
    ];
    return SourceSwitchPlan(
      book: current.rebindSource(replacement, position: newPosition),
      bookmarks: mappedBookmarks,
    );
  }

  static String _fullChapterKey(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s 　，。！？；：、,.!?;:\-—_《》【】()\[\]]+'),
    '',
  );

  // Numbering differs across sources; discard it only for an unambiguous fallback.
  static String _chapterKey(String value) => _fullChapterKey(
    value.replaceFirst(
      RegExp(r'^\s*第\s*[零〇一二三四五六七八九十百千万两0-9]+\s*[章节卷回部集篇]\s*'),
      '',
    ),
  );

  static String _paragraphKey(String value) => value.toLowerCase().replaceAll(
    RegExp(r'''[\s 　，。！？；：、,.!?;:\-—_《》【】()\[\]“”"']+'''),
    '',
  );
}
