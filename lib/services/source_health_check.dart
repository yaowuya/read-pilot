import 'dart:async';

import '../domain/book.dart';
import '../domain/book_source.dart';
import '../domain/source_check_settings.dart';
import '../domain/source_health.dart';
import 'source_engine.dart';

/// One book source's liveness check, following Legado's
/// `BookSourceCheckRepository.checkSource`.
///
/// Legado's shape is preserved deliberately:
///
/// 1. clear the previous verdict (invalid group tags + `// Error:` comment),
/// 2. check search when enabled — a missing rule is its own verdict,
/// 3. check discovery when enabled — likewise,
/// 4. take the first candidate either produced and walk its detail page,
///    chapter list and first chapter's body,
/// 5. report the whole run so the caller can record `respondTime`, the tags and
///    the error comment on the source.
///
/// The differences from Legado are all budget choices, not semantics: this
/// runtime has no script engine, so a script-driven stage is reported as
/// [SourceHealthStatus.failed] with the [SourceHealthTag.scriptFailed] tag
/// instead of silently passing.
final class SourceHealthCheck {
  const SourceHealthCheck(
    this.engine, {
    this.settings = const SourceCheckSettings(),
  });

  static const _probeKeyword = '健康检查';

  final SourceEngine engine;
  final SourceCheckSettings settings;

  /// Runs the configured stages against [source].
  ///
  /// [abortTrigger] stops the run at the next stage boundary and inside the
  /// current stage's racing future, the same "stop means stop" contract the
  /// caller's stop button relies on.
  Future<SourceHealthReport> check(
    BookSource source, {
    Future<void>? abortTrigger,
  }) async {
    final startedAt = DateTime.now();
    final results = <SourceHealthResult>[];
    // One budget for the whole run, like Legado wrapping `checkSource` in a
    // single `withTimeout(settings.timeoutMillis)`; a per-stage budget would
    // multiply the worst case by the number of stages.
    final budget = Completer<void>();
    final budgetTimer = Timer(settings.timeout, () {
      if (!budget.isCompleted) budget.complete();
    });
    try {
      return await _check(
        source,
        results,
        startedAt,
        budget.future,
        abortTrigger,
      );
    } finally {
      budgetTimer.cancel();
    }
  }

  Future<SourceHealthReport> _check(
    BookSource source,
    List<SourceHealthResult> results,
    DateTime startedAt,
    Future<void> budget,
    Future<void>? abortTrigger,
  ) async {
    List<Book>? searchResults;
    if (!settings.checkSearch) {
      _skip(results, SourceHealthStage.search, '未开启搜索检查，已跳过。');
    } else if (source.searchUrl.isEmpty) {
      _skip(
        results,
        SourceHealthStage.search,
        '未配置搜索地址，已跳过。',
        tags: const [SourceHealthTag.searchRuleMissing],
      );
    } else {
      final outcome = await _run(
        results,
        SourceHealthStage.search,
        () => engine.search(source, _probeKeyword, abortTrigger: abortTrigger),
        (books) => books.isEmpty
            ? _failedStage(
                SourceHealthStage.search,
                '搜索没有返回任何候选。',
                SourceHealthTag.searchFailed,
              )
            : _passed(SourceHealthStage.search, '搜索返回 ${books.length} 个候选。'),
        budget,
        abortTrigger,
        failureTag: SourceHealthTag.searchFailed,
      );
      searchResults = outcome.value;
      if (outcome.stop) {
        _skipRemaining(results, SourceHealthStage.explore);
        return _report(source, results, startedAt, outcome.timedOut);
      }
    }

    List<Book>? exploreResults;
    if (!settings.checkExplore) {
      _skip(results, SourceHealthStage.explore, '未开启发现检查，已跳过。');
    } else if (!source.hasExplore) {
      _skip(results, SourceHealthStage.explore, '未配置发现页，已跳过。');
    } else if (source.exploreEntries.isEmpty) {
      // A source can declare `exploreUrl` (or rules) and still yield no usable
      // category — legado reports that as `发现规则为空` instead of passing.
      _skip(
        results,
        SourceHealthStage.explore,
        '未配置可用的发现分类，已跳过。',
        tags: const [SourceHealthTag.exploreRuleMissing],
      );
    } else {
      final entry = source.exploreEntries.first;
      final outcome = await _run(
        results,
        SourceHealthStage.explore,
        () => engine.explore(source, entry, abortTrigger: abortTrigger),
        (books) => books.isEmpty
            ? _failedStage(
                SourceHealthStage.explore,
                '发现页没有返回任何候选。',
                SourceHealthTag.exploreFailed,
              )
            : _passed(SourceHealthStage.explore, '发现页返回 ${books.length} 个候选。'),
        budget,
        abortTrigger,
        failureTag: SourceHealthTag.exploreFailed,
      );
      exploreResults = outcome.value;
      if (outcome.stop) {
        _skipRemaining(results, SourceHealthStage.catalog);
        return _report(source, results, startedAt, outcome.timedOut);
      }
    }

    final fromSearch = _first(searchResults) != null;
    final candidate = _first(searchResults) ?? _first(exploreResults);
    if (candidate == null) {
      _skip(results, SourceHealthStage.catalog, '未得到可检查的书籍，已跳过。');
      _skip(results, SourceHealthStage.content, '未得到可检查的章节，已跳过。');
      return _report(source, results, startedAt, false);
    }

    final catalogTag = fromSearch
        ? SourceHealthTag.searchCatalogFailed
        : SourceHealthTag.exploreCatalogFailed;
    final contentTag = fromSearch
        ? SourceHealthTag.searchContentFailed
        : SourceHealthTag.exploreContentFailed;

    if (!settings.checkInfo &&
        !settings.checkCatalog &&
        !settings.checkContent) {
      _skip(results, SourceHealthStage.catalog, '未开启详情与目录检查，已跳过。');
      _skip(results, SourceHealthStage.content, '未开启正文检查，已跳过。');
      return _report(source, results, startedAt, false);
    }

    final catalog = await _run(
      results,
      SourceHealthStage.catalog,
      () => engine.loadBook(source, candidate, abortTrigger: abortTrigger),
      (book) => book.chapters.isEmpty
          ? _failedStage(SourceHealthStage.catalog, '详情与目录没有解析到章节。', catalogTag)
          : _passed(
              SourceHealthStage.catalog,
              '详情与目录解析到 ${book.chapters.length} 个章节。',
            ),
      budget,
      abortTrigger,
      failureTag: catalogTag,
    );
    if (catalog.stop) {
      _skipRemaining(results, SourceHealthStage.content);
      return _report(source, results, startedAt, catalog.timedOut);
    }

    final book = catalog.value;
    if (book == null || book.chapters.isEmpty) {
      _skip(results, SourceHealthStage.content, '详情与目录未通过，已跳过。');
      return _report(source, results, startedAt, false);
    }

    if (!settings.checkContent) {
      _skip(results, SourceHealthStage.content, '未开启正文检查，已跳过。');
      return _report(source, results, startedAt, false);
    }

    await _run(
      results,
      SourceHealthStage.content,
      () => engine.loadChapter(
        source,
        book.chapters.first,
        abortTrigger: abortTrigger,
      ),
      (chapter) => chapter.paragraphs.isEmpty
          ? _failedStage(SourceHealthStage.content, '正文没有解析到段落。', contentTag)
          : _passed(
              SourceHealthStage.content,
              '正文解析到 ${chapter.paragraphs.length} 段。',
            ),
      budget,
      abortTrigger,
      failureTag: contentTag,
    );
    return _report(source, results, startedAt, false);
  }

  /// Runs one stage under the shared [budget] future.
  ///
  /// The stage itself reports pass or fail through [describe]; this wrapper only
  /// decides whether the stage was cut short by the budget or by the caller, so
  /// those two outcomes stay distinguishable in the report.
  Future<_StageOutcome<T>> _run<T>(
    List<SourceHealthResult> results,
    SourceHealthStage stage,
    Future<T> Function() operation,
    SourceHealthResult Function(T value) describe,
    Future<void> budget,
    Future<void>? abortTrigger, {
    required String failureTag,
  }) async {
    final races = <Future<T>>[
      Future<T>.sync(operation),
      budget.then<T>((_) => throw TimeoutException('source health timed out')),
      if (abortTrigger != null)
        abortTrigger.then<T>(
          (_) => throw const _SourceHealthCancelled(),
          onError: (_) => throw const _SourceHealthCancelled(),
        ),
    ];
    try {
      final value = await Future.any(races);
      results.add(describe(value));
      // A stage that ran but returned nothing usable stops the run exactly like
      // a thrown error: later stages would re-request a host that just failed.
      return _StageOutcome(
        value: value,
        stop: results.last.status == SourceHealthStatus.failed,
      );
    } on TimeoutException {
      results.add(
        SourceHealthResult(
          stage: stage,
          status: SourceHealthStatus.timedOut,
          summary: '检查超过 ${_seconds(settings.timeout)}，已停止后续检查。',
          tags: [SourceHealthTag.timeout],
        ),
      );
      return const _StageOutcome(stop: true, timedOut: true);
    } on _SourceHealthCancelled {
      results.add(
        SourceHealthResult(
          stage: stage,
          status: SourceHealthStatus.cancelled,
          summary: '检查已停止。',
        ),
      );
      return const _StageOutcome(stop: true);
    } on Object catch (error) {
      final tags = _classify(error, failureTag);
      results.add(
        SourceHealthResult(
          stage: stage,
          status: SourceHealthStatus.failed,
          summary: _failureSummary(error),
          tags: tags,
        ),
      );
      return const _StageOutcome(stop: true);
    }
  }

  /// Maps an exception to the tags Legado would add for it.
  ///
  /// Legado distinguishes a dead site (`网站失效`), a rule that needs scripts
  /// this build cannot run (`js失效`) and a stage-specific rule failure; the
  /// stage tag is always added so the source row shows which workflow broke.
  List<String> _classify(Object error, String failureTag) {
    final tags = <String>[failureTag];
    final message = error is FormatException ? error.message : '$error';
    if (message.contains('脚本') || message.contains('javascript')) {
      tags.add(SourceHealthTag.scriptFailed);
    }
    tags.add(SourceHealthTag.siteFailed);
    return tags;
  }

  static String _failureSummary(Object error) {
    final message = error is FormatException ? error.message : '$error';
    // Legado surfaces the localized message; the empty-string case only shows up
    // for exceptions without one, so fall back to a readable sentence.
    return message.trim().isEmpty ? '网络请求、书源规则或运行时能力检查失败。' : message;
  }

  static String _seconds(Duration timeout) =>
      '${(timeout.inMilliseconds / 1000).toStringAsFixed(0)} 秒';

  static SourceHealthResult _passed(SourceHealthStage stage, String summary) =>
      SourceHealthResult(
        stage: stage,
        status: SourceHealthStatus.passed,
        summary: summary,
      );

  static SourceHealthResult _failedStage(
    SourceHealthStage stage,
    String summary,
    String tag,
  ) => SourceHealthResult(
    stage: stage,
    status: SourceHealthStatus.failed,
    summary: summary,
    tags: [tag],
  );

  static Book? _first(List<Book>? books) =>
      books == null || books.isEmpty ? null : books.first;

  static void _skip(
    List<SourceHealthResult> results,
    SourceHealthStage stage,
    String summary, {
    List<String> tags = const <String>[],
  }) {
    results.add(
      SourceHealthResult(
        stage: stage,
        status: SourceHealthStatus.skipped,
        summary: summary,
        tags: tags,
      ),
    );
  }

  static void _skipRemaining(
    List<SourceHealthResult> results,
    SourceHealthStage from,
  ) {
    for (final stage in SourceHealthStage.values.skip(from.index)) {
      _skip(results, stage, '检查已停止，已跳过。');
    }
  }

  /// Builds the report the caller persists onto the source.
  ///
  /// [startedAt] drives [SourceHealthReport.duration]; a timed-out run reports
  /// `timeout + elapsed` through [SourceHealthReport.timedOutAt] so a dead source
  /// sorts behind every live one, which is exactly what Legado stores.
  SourceHealthReport _report(
    BookSource source,
    List<SourceHealthResult> results,
    DateTime startedAt,
    bool timedOut,
  ) {
    final duration = DateTime.now().difference(startedAt);
    return SourceHealthReport(
      sourceId: source.id,
      sourceName: source.name,
      results: results,
      duration: duration,
      timedOutAt: timedOut ? settings.timeout + duration : null,
    );
  }
}

final class _StageOutcome<T> {
  const _StageOutcome({this.value, this.stop = false, this.timedOut = false});

  final T? value;
  final bool stop;

  /// Whether this stage consumed the whole budget; used for `respondTime`.
  final bool timedOut;
}

final class _SourceHealthCancelled implements Exception {
  const _SourceHealthCancelled();
}
