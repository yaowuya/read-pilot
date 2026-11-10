/// Stages a health check walks through, in the order Legado checks them.
///
/// Legado's `checkSource` runs search, then discovery, then the book detail,
/// catalog and content of whatever candidate the first two produced; the stage
/// list here keeps that order so a failure stops the later stages instead of
/// hammering a host that just proved unreachable.
enum SourceHealthStage {
  search('搜索'),
  explore('发现'),
  catalog('详情与目录'),
  content('正文');

  const SourceHealthStage(this.label);

  /// The stage name the reader sees. The comment written back to the source
  /// ends up in the source list, next to the UI's own Chinese labels, so an
  /// English enum name there would be the only English in the app.
  final String label;
}

enum SourceHealthStatus { passed, skipped, failed, timedOut, cancelled }

/// Group tags a health check writes into the source's group list.
///
/// Legado has no separate health field: it marks a source by adding one of
/// these strings to `bookSourceGroup` and by prefixing a `// Error:` block to
/// `bookSourceComment`. Keeping the same vocabulary means tags that Legado
/// itself wrote are recognised (and cleared) by the next run here, instead of
/// accumulating as meaningless groups.
abstract final class SourceHealthTag {
  static const searchRuleMissing = '搜索链接规则为空';
  static const exploreRuleMissing = '发现规则为空';
  static const searchFailed = '搜索失效';
  static const exploreFailed = '发现失效';
  static const searchCatalogFailed = '搜索目录失效';
  static const exploreCatalogFailed = '发现目录失效';
  static const searchContentFailed = '搜索正文失效';
  static const exploreContentFailed = '发现正文失效';
  static const timeout = '校验超时';
  static const scriptFailed = 'js失效';
  static const siteFailed = '网站失效';

  /// Every tag this build may add, so [invalid] can recognise its own output.
  static const all = <String>{
    searchRuleMissing,
    exploreRuleMissing,
    searchFailed,
    exploreFailed,
    searchCatalogFailed,
    exploreCatalogFailed,
    searchContentFailed,
    exploreContentFailed,
    timeout,
    scriptFailed,
    siteFailed,
  };

  /// Whether a stored group name is a health verdict rather than a user tag.
  ///
  /// Legado's rule is only "contains 失效, or is 校验超时", which is enough for
  /// the tags it writes but not for [searchRuleMissing] or [exploreRuleMissing]:
  /// neither contains 失效, so a source that once had no discover rules would
  /// keep that group forever even after the rules were added. Checking [all]
  /// first fixes that while the looser substring rule still recognises verdicts
  /// written by older versions, including Legado's own.
  static bool isInvalid(String group) =>
      all.contains(group) || group.contains('失效') || group == timeout;
}

final class SourceHealthResult {
  const SourceHealthResult({
    required this.stage,
    required this.status,
    required this.summary,
    this.tags = const <String>[],
  });

  final SourceHealthStage stage;
  final SourceHealthStatus status;
  final String summary;

  /// Tags this stage wants written onto the source; empty when it passed.
  final List<String> tags;

  bool get isFailure =>
      status == SourceHealthStatus.failed ||
      status == SourceHealthStatus.timedOut ||
      status == SourceHealthStatus.cancelled;
}

final class SourceHealthReport {
  SourceHealthReport({
    required this.sourceId,
    required this.sourceName,
    required Iterable<SourceHealthResult> results,
    this.duration = Duration.zero,
    this.timedOutAt,
  }) : results = List.unmodifiable(results);

  final String sourceId;
  final String sourceName;
  final List<SourceHealthResult> results;

  /// Wall-clock time the whole check took.
  ///
  /// Written to the source's `respondTime` when the check completed, exactly
  /// like Legado's `source.respondTime = System.currentTimeMillis() - startedAt`.
  final Duration duration;

  /// Set when the check hit its overall budget instead of finishing.
  ///
  /// Legado stores `timeout + elapsed` in that case so a dead source sorts
  /// behind every live one rather than looking merely slow.
  final Duration? timedOutAt;

  bool get hasFailures => results.any((result) => result.isFailure);

  /// Every tag the run wants on the source, in stage order, without duplicates.
  List<String> get tags => List.unmodifiable({
    for (final result in results)
      for (final tag in result.tags) tag,
  });

  /// The value to store in `respondTime`.
  int get respondTimeMillis => (timedOutAt ?? duration).inMilliseconds;

  /// First failure's explanation, for the `// Error:` comment.
  String? get failureSummary {
    for (final result in results) {
      if (!result.isFailure) continue;
      return '${result.summary}（${result.stage.label}）';
    }
    return null;
  }
}
