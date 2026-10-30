import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/source_capability.dart';
import '../../domain/source_import.dart';
import 'common.dart';
import '../theme.dart';

/// Two-step source import UI: prepare a read-only preview, then commit it.
class SourceImportSheet extends StatefulWidget {
  const SourceImportSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<SourceImportSheet> createState() => _SourceImportSheetState();
}

class _SourceImportSheetState extends State<SourceImportSheet> {
  final _text = TextEditingController();
  final _url = TextEditingController();
  SourceImportKind _mode = SourceImportKind.text;
  SourceImportPreview? _preview;
  Set<String> _selectedSourceIds = const {};
  String? _fileLabel;
  String? _error;
  bool _busy = false;
  Completer<void>? _abort;

  @override
  void dispose() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    _text.dispose();
    _url.dispose();
    super.dispose();
  }

  void _setMode(SourceImportKind mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _preview = null;
      _selectedSourceIds = const {};
      _error = null;
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > 1024 * 1024) {
        throw const FormatException('书源文件不能超过 1 MiB。');
      }
      if (file.bytes == null) {
        throw const FormatException('无法读取文件，请重新选择。');
      }
      _text.text = utf8.decode(file.bytes!);
      setState(() {
        _fileLabel = file.name;
        _preview = null;
        _selectedSourceIds = const {};
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    }
  }

  Future<void> _prepare() async {
    if (_busy) return;
    final SourceImportInput input;
    try {
      input = switch (_mode) {
        SourceImportKind.text => SourceImportInput.text(_text.text),
        SourceImportKind.file => SourceImportInput.file(
          _text.text,
          label: _fileLabel ?? '书源文件.json',
        ),
        SourceImportKind.url => SourceImportInput.url(
          Uri.parse(_url.text.trim()),
        ),
      };
    } on FormatException {
      setState(() => _error = '请输入完整的 HTTP(S) 书源 JSON 地址。');
      return;
    }

    final abort = Completer<void>();
    setState(() {
      _busy = true;
      _abort = abort;
      _preview = null;
      _selectedSourceIds = const {};
      _error = null;
    });
    try {
      final preview = await widget.controller.prepareSourceImport(
        input,
        abortTrigger: abort.future,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _selectedSourceIds = {
            for (final source in preview.sources) source.id,
          };
          _busy = false;
          _abort = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorMessage(error);
          _busy = false;
          _abort = null;
        });
      }
    }
  }

  void _cancel() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null || _busy || _selectedSourceIds.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.controller.commitSourceImport(
        preview,
        selectedSourceIds: Set.unmodifiable(_selectedSourceIds),
      );
      if (mounted) {
        Navigator.pop(context);
        showMessage(
          context,
          '已导入 ${result.total} 个书源（新增 ${result.added}，更新 ${result.updated}）。',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorMessage(error);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        28 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('导入书源', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const Key('source-mode-text'),
                label: const Text('粘贴 JSON'),
                selected: _mode == SourceImportKind.text,
                onSelected: (_) => _setMode(SourceImportKind.text),
              ),
              ChoiceChip(
                key: const Key('source-mode-file'),
                label: const Text('选择文件'),
                selected: _mode == SourceImportKind.file,
                onSelected: (_) => _setMode(SourceImportKind.file),
              ),
              ChoiceChip(
                key: const Key('source-mode-url'),
                label: const Text('网络 URL'),
                selected: _mode == SourceImportKind.url,
                onSelected: (_) => _setMode(SourceImportKind.url),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_mode == SourceImportKind.url)
            TextField(
              key: const Key('source-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '书源 JSON 地址',
                hintText: 'https://example.com/sources.json',
              ),
            )
          else ...[
            if (_mode == SourceImportKind.file)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(_fileLabel ?? '选择 JSON 文件'),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('source-json'),
              controller: _text,
              minLines: 6,
              maxLines: 12,
              style: const TextStyle(fontSize: 13, height: 1.6),
              decoration: const InputDecoration(
                labelText: '书源 JSON',
                hintText: '{"bookSourceName":"…"}',
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _error!,
                key: const Key('source-error'),
                style: const TextStyle(color: Color(0xFFB54444), height: 1.6),
              ),
            ),
          const SizedBox(height: 18),
          if (_busy && preview == null)
            Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('正在获取并分析书源…')),
                TextButton(onPressed: _cancel, child: const Text('取消')),
              ],
            )
          else if (preview == null)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('source-prepare'),
                onPressed: _prepare,
                child: const Text('获取并预览'),
              ),
            )
          else ...[
            _SourcePreview(
              preview: preview,
              selectedSourceIds: _selectedSourceIds,
              onSelectionChanged: _busy
                  ? null
                  : (sourceId, selected) {
                      setState(() {
                        _selectedSourceIds = {..._selectedSourceIds};
                        if (selected) {
                          _selectedSourceIds.add(sourceId);
                        } else {
                          _selectedSourceIds.remove(sourceId);
                        }
                      });
                    },
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('source-commit'),
                onPressed: _busy || _selectedSourceIds.isEmpty ? null : _commit,
                child: Text(
                  _busy
                      ? '正在保存…'
                      : _selectedSourceIds.isEmpty
                      ? '请选择书源'
                      : '确认导入 ${_selectedSourceIds.length} 个书源',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourcePreview extends StatelessWidget {
  const _SourcePreview({
    required this.preview,
    required this.selectedSourceIds,
    required this.onSelectionChanged,
  });

  final SourceImportPreview preview;
  final Set<String> selectedSourceIds;
  final void Function(String sourceId, bool selected)? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final profile = kIsWeb
        ? SourceRuntimeProfile.webCore
        : defaultTargetPlatform == TargetPlatform.android
        ? SourceRuntimeProfile.androidCore
        : SourceRuntimeProfile.nativeCore;
    final provenance = preview.provenance;
    final originChanged =
        provenance.requestedUri != null &&
        provenance.finalUri != null &&
        provenance.requestedUri!.origin != provenance.finalUri!.origin;
    return Container(
      key: const Key('source-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '预览 ${preview.sources.length} 个书源',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (provenance.requestedUri != null) ...[
            const SizedBox(height: 8),
            Text(
              '请求地址：${provenance.requestedUri}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            Text(
              '最终地址：${provenance.finalUri ?? provenance.requestedUri}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            if (originChanged)
              const Text(
                '最终地址来源已变化，请确认后再导入。',
                style: TextStyle(fontSize: 12, color: Color(0xFFB54444)),
              ),
          ] else if (provenance.label != null) ...[
            const SizedBox(height: 8),
            Text(
              '来源：${provenance.label}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${provenance.contentType ?? '本地 JSON'} · '
            '${provenance.responseBytes} bytes',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          for (final source in preview.sources) ...[
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                key: Key('source-select-${source.id}'),
                value: selectedSourceIds.contains(source.id),
                onChanged: onSelectionChanged == null
                    ? null
                    : (value) => onSelectionChanged!(source.id, value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  source.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  source.id,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ),
            if (source.headers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final name in source.headers.keys)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(name),
                    ),
                ],
              ),
            ],
            Builder(
              builder: (_) {
                final report = source.capabilitiesFor(profile);
                final unsupported = report.diagnostics
                    .where(
                      (item) =>
                          !item.runtimeImplemented || !item.platformPermitted,
                    )
                    .toList();
                if (unsupported.isEmpty) {
                  return const Text(
                    '当前平台可运行已声明能力',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in unsupported)
                      Text(
                        '${item.path}：${item.message}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9B5A20),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
