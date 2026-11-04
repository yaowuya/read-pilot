import 'book_source.dart';

/// How an import payload entered the application.
enum SourceImportKind { text, file, url }

/// Input accepted by the source import preparation module.
sealed class SourceImportInput {
  const SourceImportInput();

  const factory SourceImportInput.text(String text, {String? label}) =
      SourceTextImportInput;
  const factory SourceImportInput.file(String text, {required String label}) =
      SourceFileImportInput;
  const factory SourceImportInput.url(Uri uri) = SourceUrlImportInput;
}

class SourceTextImportInput extends SourceImportInput {
  const SourceTextImportInput(this.text, {this.label});
  final String text;
  final String? label;
}

class SourceFileImportInput extends SourceImportInput {
  const SourceFileImportInput(this.text, {required this.label});
  final String text;
  final String label;
}

class SourceUrlImportInput extends SourceImportInput {
  const SourceUrlImportInput(this.uri);
  final Uri uri;
}

/// Read-only retrieval provenance prepared before import persistence.
class SourceImportProvenance {
  const SourceImportProvenance({
    required this.kind,
    this.label,
    this.requestedUri,
    this.finalUri,
    required this.responseBytes,
    this.contentType,
  });

  final SourceImportKind kind;
  final String? label;
  final Uri? requestedUri;
  final Uri? finalUri;
  final int responseBytes;
  final String? contentType;
}

/// One payload entry that could not be represented as a source.
///
/// Aggregate feeds ship thousands of entries and routinely carry a handful of
/// malformed ones. Rejecting those entries must not cost the caller the rest of
/// the feed, but they must stay visible instead of being silently dropped.
class SourceImportSkip {
  const SourceImportSkip({required this.label, required this.reason});

  /// Best-effort identity of the rejected entry, never empty.
  ///
  /// Falls back to the entry position when the payload omits a usable name and
  /// URL, so every skip can still be described to the user.
  final String label;

  /// Parser message that explains why the entry was rejected.
  final String reason;
}

/// Rejects grouped by [SourceImportSkip.reason], most frequent first.
class SourceImportSkipGroup {
  const SourceImportSkipGroup({required this.reason, required this.count});

  final String reason;
  final int count;
}

/// Groups [skips] by reason, most frequent first, ties in payload order.
///
/// A single feed can fail for a few distinct reasons (unparseable `header`,
/// non-HTTP `bookSourceUrl`, hop-by-hop headers), so summarizing the reasons
/// keeps the preview readable no matter how many entries were rejected.
List<SourceImportSkipGroup> groupSourceImportSkips(
  Iterable<SourceImportSkip> skips,
) {
  final counts = <String, int>{};
  final firstSeen = <String, int>{};
  for (final skip in skips) {
    firstSeen.putIfAbsent(skip.reason, () => firstSeen.length);
    counts[skip.reason] = (counts[skip.reason] ?? 0) + 1;
  }
  final reasons = counts.keys.toList()
    ..sort((left, right) {
      final byCount = counts[right]!.compareTo(counts[left]!);
      return byCount != 0
          ? byCount
          : firstSeen[left]!.compareTo(firstSeen[right]!);
    });
  return List.unmodifiable([
    for (final reason in reasons)
      SourceImportSkipGroup(reason: reason, count: counts[reason]!),
  ]);
}

/// Prepared import data. Creating a preview has no persistence side effects.
class SourceImportPreview {
  SourceImportPreview({
    required Iterable<BookSource> sources,
    required this.provenance,
    Iterable<SourceImportSkip> skipped = const [],
  }) : sources = List.unmodifiable(sources),
       skipped = List.unmodifiable(skipped);

  final List<BookSource> sources;

  /// Entries the parser rejected. Empty when the payload was fully representable.
  final List<SourceImportSkip> skipped;
  final SourceImportProvenance provenance;

  int get skippedCount => skipped.length;

  /// Entries the payload contained, whichever branch they ended up in.
  int get totalCount => sources.length + skipped.length;
}

/// Application-owned import metadata stored separately from third-party JSON.
class SourceImportState {
  const SourceImportState({
    required this.sourceId,
    required this.kind,
    this.label,
    this.requestedUri,
    this.finalUri,
    required this.responseBytes,
    this.contentType,
  });

  factory SourceImportState.fromJson(Map<String, dynamic> json) =>
      SourceImportState(
        sourceId: json['sourceId'] as String,
        kind: SourceImportKind.values.byName(json['kind'] as String),
        label: json['label'] as String?,
        requestedUri: json['requestedUri'] == null
            ? null
            : Uri.parse(json['requestedUri'] as String),
        finalUri: json['finalUri'] == null
            ? null
            : Uri.parse(json['finalUri'] as String),
        responseBytes: (json['responseBytes'] as num).toInt(),
        contentType: json['contentType'] as String?,
      );

  final String sourceId;
  final SourceImportKind kind;
  final String? label;
  final Uri? requestedUri;
  final Uri? finalUri;
  final int responseBytes;
  final String? contentType;

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'kind': kind.name,
    if (label != null) 'label': label,
    if (requestedUri != null) 'requestedUri': requestedUri.toString(),
    if (finalUri != null) 'finalUri': finalUri.toString(),
    'responseBytes': responseBytes,
    if (contentType != null) 'contentType': contentType,
  };
}

/// Counts and stable IDs returned by one atomic source import commit.
class SourceImportCommitResult {
  SourceImportCommitResult({
    required this.added,
    required this.updated,
    required Iterable<String> sourceIds,
  }) : sourceIds = List.unmodifiable(sourceIds);

  final int added;
  final int updated;
  final List<String> sourceIds;
  int get total => added + updated;
}

enum SourceImportErrorKind {
  invalidUrl,
  network,
  timeout,
  cancelled,
  httpStatus,
  redirect,
  contentType,
  tooLarge,
  invalidJson,
}

/// Stable error category and user-facing message for import preparation.
class SourceImportException implements Exception {
  const SourceImportException(this.kind, this.message, {this.statusCode});

  final SourceImportErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
