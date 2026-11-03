import 'book.dart';

/// Extra information collected for a source-switch candidate.
///
/// Search results are intentionally kept separate from [Book] so the book model
/// remains a source record rather than a UI-specific result envelope.
final class SourceCandidateInfo {
  const SourceCandidateInfo({
    this.chapterCount,
    this.mappedChapterIndex,
    this.mappedChapterTitle,
    this.wordCount,
    this.errorMessage,
  });

  final int? chapterCount;
  final int? mappedChapterIndex;
  final String? mappedChapterTitle;
  final int? wordCount;
  final String? errorMessage;

  /// Whether this candidate has everything needed to render an actionable
  /// source-switch row. Candidates are never shown before this is true.
  bool get isReadyForDisplay =>
      mappedChapterIndex != null &&
      mappedChapterTitle != null &&
      wordCount != null;

  factory SourceCandidateInfo.fromJson(Map<String, dynamic> json) =>
      SourceCandidateInfo(
        chapterCount: (json['chapterCount'] as num?)?.toInt(),
        mappedChapterIndex: (json['mappedChapterIndex'] as num?)?.toInt(),
        mappedChapterTitle: json['mappedChapterTitle'] as String?,
        wordCount: (json['wordCount'] as num?)?.toInt(),
        errorMessage: json['errorMessage'] as String?,
      );

  Map<String, dynamic> toJson() => {
    if (chapterCount != null) 'chapterCount': chapterCount,
    if (mappedChapterIndex != null) 'mappedChapterIndex': mappedChapterIndex,
    if (mappedChapterTitle != null) 'mappedChapterTitle': mappedChapterTitle,
    if (wordCount != null) 'wordCount': wordCount,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };
}

/// One candidate plus the metadata that was loaded for the active chapter.
final class SourceCandidateCacheEntry {
  const SourceCandidateCacheEntry({required this.candidate, this.info});

  final Book candidate;
  final SourceCandidateInfo? info;

  factory SourceCandidateCacheEntry.fromJson(Map<String, dynamic> json) =>
      SourceCandidateCacheEntry(
        candidate: Book.fromJson(
          Map<String, dynamic>.from(json['candidate'] as Map),
        ),
        info: json['info'] == null
            ? null
            : SourceCandidateInfo.fromJson(
                Map<String, dynamic>.from(json['info'] as Map),
              ),
      );

  Map<String, dynamic> toJson() => {
    'candidate': candidate.toJson(),
    if (info != null) 'info': info!.toJson(),
  };
}

/// A persisted snapshot of source-switch candidates for one book.
///
/// Candidate catalogs can be large (and individual catalogs can contain up to
/// 10,000 chapters), so this cache stores the search result and its summary
/// metadata only. The selected source is still freshly loaded before switching.
///
/// The snapshot belongs to the book, not to the chapter or the book's *current*
/// source: after the user switches source the candidate list is exactly the one
/// they just reviewed, and re-scanning hundreds of sources again would be
/// wasteful. [originSourceId] and the target chapter fields only record which
/// chapter the mapped chapter/word-count metadata was measured against.
final class SourceCandidateCache {
  SourceCandidateCache({
    required this.bookId,
    required this.originSourceId,
    required this.targetChapterIndex,
    required this.targetChapterId,
    required this.targetChapterTitle,
    required this.loadedAt,
    required Iterable<SourceCandidateCacheEntry> entries,
    this.failedSources = 0,
  }) : entries = List.unmodifiable(entries);

  static const lifetime = Duration(days: 10);

  final String bookId;

  /// Provenance of the chapter the candidate metadata below was measured from.
  /// It deliberately does not invalidate the snapshot: choosing a different
  /// chapter reuses the same alternative sources, only the numbers were taken
  /// at an earlier position.
  final String originSourceId;
  final int targetChapterIndex;
  final String targetChapterId;
  final String targetChapterTitle;
  final DateTime loadedAt;
  final List<SourceCandidateCacheEntry> entries;
  final int failedSources;

  /// One snapshot per book: the candidate list is reusable from any chapter.
  static String recordKey(String bookId) => bookId;

  bool isFreshAt(DateTime now) {
    final age = now.toUtc().difference(loadedAt.toUtc());
    return !age.isNegative && age <= lifetime;
  }

  SourceCandidateCache copyWith({
    Iterable<SourceCandidateCacheEntry>? entries,
  }) => SourceCandidateCache(
    bookId: bookId,
    originSourceId: originSourceId,
    targetChapterIndex: targetChapterIndex,
    targetChapterId: targetChapterId,
    targetChapterTitle: targetChapterTitle,
    loadedAt: loadedAt,
    entries: entries ?? this.entries,
    failedSources: failedSources,
  );

  factory SourceCandidateCache.fromJson(Map<String, dynamic> json) =>
      SourceCandidateCache(
        bookId: json['bookId'] as String,
        originSourceId: json['originSourceId'] as String,
        targetChapterIndex: (json['targetChapterIndex'] as num).toInt(),
        targetChapterId: json['targetChapterId'] as String,
        targetChapterTitle: json['targetChapterTitle'] as String,
        loadedAt: DateTime.parse(json['loadedAt'] as String),
        entries: [
          for (final raw in (json['entries'] as List? ?? const []))
            SourceCandidateCacheEntry.fromJson(
              Map<String, dynamic>.from(raw as Map),
            ),
        ],
        failedSources: (json['failedSources'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'originSourceId': originSourceId,
    'targetChapterIndex': targetChapterIndex,
    'targetChapterId': targetChapterId,
    'targetChapterTitle': targetChapterTitle,
    'loadedAt': loadedAt.toUtc().toIso8601String(),
    'failedSources': failedSources,
    'entries': [for (final entry in entries) entry.toJson()],
  };
}
