enum SourceHealthStage { search, explore, catalog, content }

enum SourceHealthStatus { passed, skipped, failed, timedOut, cancelled }

final class SourceHealthResult {
  const SourceHealthResult({
    required this.stage,
    required this.status,
    required this.summary,
  });

  final SourceHealthStage stage;
  final SourceHealthStatus status;
  final String summary;
}

final class SourceHealthReport {
  SourceHealthReport({
    required this.sourceId,
    required this.sourceName,
    required Iterable<SourceHealthResult> results,
  }) : results = List.unmodifiable(results);

  final String sourceId;
  final String sourceName;
  final List<SourceHealthResult> results;

  bool get hasFailures => results.any(
    (result) =>
        result.status == SourceHealthStatus.failed ||
        result.status == SourceHealthStatus.timedOut ||
        result.status == SourceHealthStatus.cancelled,
  );
}
