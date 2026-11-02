import 'dart:async';

import '../domain/book.dart';
import '../domain/book_source.dart';
import '../domain/source_health.dart';
import 'source_engine.dart';

final class SourceHealthCheck {
  const SourceHealthCheck(
    this.engine, {
    this.stageTimeout = const Duration(seconds: 8),
  });

  static const _probeKeyword = '健康检查';

  final SourceEngine engine;
  final Duration stageTimeout;

  Future<SourceHealthReport> check(
    BookSource source, {
    Future<void>? abortTrigger,
  }) async {
    final results = <SourceHealthResult>[];

    List<Book>? searchResults;
    if (source.searchUrl.isEmpty) {
      _skip(results, SourceHealthStage.search, '未配置搜索地址，已跳过。');
    } else {
      final outcome = await _run(
        results,
        SourceHealthStage.search,
        () => engine.search(source, _probeKeyword, abortTrigger: abortTrigger),
        (books) => '搜索返回 ${books.length} 个候选。',
        abortTrigger,
      );
      searchResults = outcome.value;
      if (outcome.stop) {
        _skipRemaining(results, SourceHealthStage.explore);
        return _report(source, results);
      }
    }

    List<Book>? exploreResults;
    final entries = source.exploreEntries;
    if (entries.isEmpty) {
      _skip(results, SourceHealthStage.explore, '未配置发现页，已跳过。');
    } else {
      final outcome = await _run(
        results,
        SourceHealthStage.explore,
        () => engine.explore(source, entries.first, abortTrigger: abortTrigger),
        (books) => '发现页返回 ${books.length} 个候选。',
        abortTrigger,
      );
      exploreResults = outcome.value;
      if (outcome.stop) {
        _skipRemaining(results, SourceHealthStage.catalog);
        return _report(source, results);
      }
    }

    final candidate = _first(searchResults) ?? _first(exploreResults);
    if (candidate == null) {
      _skip(results, SourceHealthStage.catalog, '未得到可检查的书籍，已跳过。');
      _skip(results, SourceHealthStage.content, '未得到可检查的章节，已跳过。');
      return _report(source, results);
    }

    final catalog = await _run(
      results,
      SourceHealthStage.catalog,
      () => engine.loadBook(source, candidate),
      (book) => '详情与目录解析到 ${book.chapters.length} 个章节。',
      abortTrigger,
    );
    if (catalog.stop) {
      _skipRemaining(results, SourceHealthStage.content);
      return _report(source, results);
    }

    final book = catalog.value;
    if (book == null || book.chapters.isEmpty) {
      _skip(results, SourceHealthStage.content, '详情与目录未通过，已跳过。');
      return _report(source, results);
    }

    await _run(
      results,
      SourceHealthStage.content,
      () => engine.loadChapter(source, book.chapters.first),
      (chapter) => '正文解析到 ${chapter.paragraphs.length} 段。',
      abortTrigger,
    );
    return _report(source, results);
  }

  Future<_StageOutcome<T>> _run<T>(
    List<SourceHealthResult> results,
    SourceHealthStage stage,
    Future<T> Function() operation,
    String Function(T value) successSummary,
    Future<void>? abortTrigger,
  ) async {
    final races = <Future<T>>[
      Future<T>.sync(operation),
      Future<T>.delayed(stageTimeout, () {
        throw TimeoutException('source health stage timed out');
      }),
      if (abortTrigger != null)
        abortTrigger.then<T>(
          (_) => throw const _SourceHealthCancelled(),
          onError: (_) => throw const _SourceHealthCancelled(),
        ),
    ];
    try {
      final value = await Future.any(races);
      results.add(
        SourceHealthResult(
          stage: stage,
          status: SourceHealthStatus.passed,
          summary: successSummary(value),
        ),
      );
      return _StageOutcome(value: value);
    } on TimeoutException {
      results.add(
        SourceHealthResult(
          stage: stage,
          status: SourceHealthStatus.timedOut,
          summary: '该阶段超过 ${stageTimeout.inSeconds} 秒，已停止后续检查。',
        ),
      );
      return const _StageOutcome(stop: true);
    } on _SourceHealthCancelled {
      results.add(
        SourceHealthResult(
          stage: stage,
          status: SourceHealthStatus.cancelled,
          summary: '检查已停止。',
        ),
      );
      return const _StageOutcome(stop: true);
    } on Object {
      results.add(
        SourceHealthResult(
          stage: stage,
          status: SourceHealthStatus.failed,
          summary: '网络请求、书源规则或运行时能力检查失败。',
        ),
      );
      return const _StageOutcome();
    }
  }

  static Book? _first(List<Book>? books) =>
      books == null || books.isEmpty ? null : books.first;

  static void _skip(
    List<SourceHealthResult> results,
    SourceHealthStage stage,
    String summary,
  ) {
    results.add(
      SourceHealthResult(
        stage: stage,
        status: SourceHealthStatus.skipped,
        summary: summary,
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

  static SourceHealthReport _report(
    BookSource source,
    List<SourceHealthResult> results,
  ) => SourceHealthReport(
    sourceId: source.id,
    sourceName: source.name,
    results: results,
  );
}

final class _StageOutcome<T> {
  const _StageOutcome({this.value, this.stop = false});

  final T? value;
  final bool stop;
}

final class _SourceHealthCancelled implements Exception {
  const _SourceHealthCancelled();
}
