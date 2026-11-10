import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book_source.dart';
import '../../domain/source_check_settings.dart';
import '../../domain/source_health.dart';
import '../theme.dart';
import 'common.dart';

/// Runs one bounded health check against a single source.
///
/// The verdict is written back onto the source (see
/// `AppController.checkSourceHealth`), so this sheet shows the fresh result and
/// also says where it went: `respondTime`, the failing stage tags on the source
/// group and the `// Error:` line in the comment.
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
  bool _editing = false;
  late SourceCheckSettings _settings = widget.controller.sourceCheckSettings;

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

  Future<void> _persist(SourceCheckSettings settings) async {
    setState(() => _settings = settings);
    try {
      await widget.controller.updateSourceCheckSettings(settings);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    }
  }

  SourceHealthResult? _result(SourceHealthStage stage) {
    final results = _report?.results ?? const <SourceHealthResult>[];
    for (final result in results) {
      if (result.stage == stage) return result;
    }
    return null;
  }

  String get _statusLine {
    final report = _report;
    if (report == null) return '尚未检查。';
    final seconds = (report.respondTimeMillis / 1000).toStringAsFixed(1);
    final failed = report.results.where((result) => result.isFailure).length;
    if (failed == 0) return '检查通过，用时 $seconds 秒。';
    return '有 $failed 个阶段没通过，用时 $seconds 秒。';
  }

  Widget _buildSettings() {
    final settings = _settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSwitch(
          settingsKey: 'source-check-search',
          title: '搜索检查',
          subtitle: '用关键词跑一次搜索，至少需要开启搜索或发现之一',
          value: settings.checkSearch,
          onChanged: (value) => _persist(settings.copyWith(checkSearch: value)),
        ),
        _SettingsSwitch(
          settingsKey: 'source-check-explore',
          title: '发现检查',
          subtitle: '打开第一个发现分类，看是否返回内容',
          value: settings.checkExplore,
          onChanged: (value) =>
              _persist(settings.copyWith(checkExplore: value)),
        ),
        _SettingsSwitch(
          settingsKey: 'source-check-info',
          title: '详情检查',
          subtitle: '解析书名、作者、封面等详情字段',
          value: settings.checkInfo,
          onChanged: (value) => _persist(settings.copyWith(checkInfo: value)),
        ),
        _SettingsSwitch(
          settingsKey: 'source-check-catalog',
          title: '目录检查',
          subtitle: '读取目录，确认章节列表不是空的',
          value: settings.checkCatalog,
          onChanged: (value) =>
              _persist(settings.copyWith(checkCatalog: value)),
        ),
        _SettingsSwitch(
          settingsKey: 'source-check-content',
          title: '正文检查',
          subtitle: '读取第一章正文，确认不是空的',
          value: settings.checkContent,
          onChanged: (value) =>
              _persist(settings.copyWith(checkContent: value)),
        ),
        const SizedBox(height: 4),
        Text(
          '超时上限 ${settings.timeout.inSeconds} 秒（整轮共用）',
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final seconds in const [60, 180, 300])
              ChoiceChip(
                key: Key('source-check-timeout-$seconds'),
                label: Text('$seconds 秒'),
                selected: settings.timeout.inSeconds == seconds,
                onSelected: (_) => _persist(
                  settings.copyWith(timeout: Duration(seconds: seconds)),
                ),
              ),
          ],
        ),
      ],
    );
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
              '仅对“${widget.source.name}”执行一次有限检查，不展示正文、请求头或响应内容。'
              '结论会写回书源：响应时间、失效分组和失败原因都会留在书源列表里。',
              style: const TextStyle(color: AppColors.muted, height: 1.7),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _statusLine,
                    key: const Key('source-health-status'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  key: const Key('source-health-settings-toggle'),
                  onPressed: _running
                      ? null
                      : () => setState(() => _editing = !_editing),
                  child: Text(_editing ? '收起选项' : '检查选项'),
                ),
              ],
            ),
            if (_editing) ...[
              const SizedBox(height: 4),
              _buildSettings(),
              const SizedBox(height: 12),
            ],
            for (final stage in SourceHealthStage.values)
              _StageRow(result: _result(stage), stage: stage),
            if (_report case final report?)
              if (report.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '已标记：${report.tags.join('、')}',
                    key: const Key('source-health-tags'),
                    style: const TextStyle(
                      color: Color(0xFFAE5A43),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
            const SizedBox(height: 8),
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

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.settingsKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String settingsKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: Key(settingsKey),
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
    ),
    value: value,
    onChanged: onChanged,
  );
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.result});

  final SourceHealthStage stage;
  final SourceHealthResult? result;

  String get _label => stage.label;

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
    final tags = result?.tags ?? const <String>[];
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
                  tags.isEmpty ? _label : '$_label · ${tags.join('、')}',
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
