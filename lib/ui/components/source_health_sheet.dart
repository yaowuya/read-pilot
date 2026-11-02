import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book_source.dart';
import '../../domain/source_health.dart';
import '../theme.dart';
import 'common.dart';

class SourceHealthSheet extends StatefulWidget {
  const SourceHealthSheet({
    super.key,
    required this.controller,
    required this.source,
  });

  final AppController controller;
  final BookSource source;

  @override
  State<SourceHealthSheet> createState() => _SourceHealthSheetState();
}

class _SourceHealthSheetState extends State<SourceHealthSheet> {
  Completer<void>? _abort;
  SourceHealthReport? _report;
  bool _running = false;

  void _cancel() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) {
      _cancel();
      return;
    }
    final abort = Completer<void>();
    setState(() {
      _abort = abort;
      _report = null;
      _running = true;
    });
    try {
      final report = await widget.controller.checkSourceHealth(
        widget.source.id,
        abortTrigger: abort.future,
      );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _abort = null;
        });
      }
    }
  }

  SourceHealthResult? _result(SourceHealthStage stage) {
    final results = _report?.results ?? const <SourceHealthResult>[];
    for (final result in results) {
      if (result.stage == stage) return result;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('书源健康检查', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '仅对“${widget.source.name}”执行一次有限检查；结果不保存，不展示正文、请求头或响应内容。每阶段最长 8 秒，停止后不会开始后续阶段。',
              style: const TextStyle(color: AppColors.muted, height: 1.7),
            ),
            const SizedBox(height: 16),
            for (final stage in SourceHealthStage.values)
              _StageRow(result: _result(stage), stage: stage),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('source-health-start'),
                onPressed: _start,
                icon: Icon(
                  _running
                      ? Icons.stop_circle_outlined
                      : Icons.health_and_safety_outlined,
                ),
                label: Text(_running ? '停止检查' : '开始检查'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.result});

  final SourceHealthStage stage;
  final SourceHealthResult? result;

  String get _label => switch (stage) {
    SourceHealthStage.search => '搜索',
    SourceHealthStage.explore => '发现',
    SourceHealthStage.catalog => '详情与目录',
    SourceHealthStage.content => '正文',
  };

  @override
  Widget build(BuildContext context) {
    final status = result?.status;
    final color = switch (status) {
      SourceHealthStatus.passed => const Color(0xFF34785A),
      SourceHealthStatus.skipped => AppColors.muted,
      SourceHealthStatus.failed ||
      SourceHealthStatus.timedOut ||
      SourceHealthStatus.cancelled => const Color(0xFFAE5A43),
      null => AppColors.muted,
    };
    final icon = switch (status) {
      SourceHealthStatus.passed => Icons.check_circle_outline,
      SourceHealthStatus.skipped => Icons.remove_circle_outline,
      SourceHealthStatus.failed => Icons.error_outline,
      SourceHealthStatus.timedOut => Icons.timer_off_outlined,
      SourceHealthStatus.cancelled => Icons.cancel_outlined,
      null => Icons.radio_button_unchecked,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  result?.summary ?? '尚未开始。',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
