import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/source_import.dart';
import '../../services/source_importer.dart';
import '../theme.dart';
import 'common.dart';

/// Validates source input before users explicitly choose an import subset.
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
  Set<String> _selectedSourceIds = {};
  String? _fileLabel;
  String? _error;
  bool _busy = false;
  bool _committing = false;
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
      if (file.size > SourceImporter.maxBytes) {
        throw const FormatException(
          '书源文件不能超过 ${SourceImporter.maxBytesLabel}。',
        );
      }
      if (file.bytes == null) {
        throw const FormatException('无法读取文件，请重新选择。');
      }
      _text.text = utf8.decode(file.bytes!);
      setState(() {
        _fileLabel = file.name;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    }
  }

  SourceImportInput _input() => switch (_mode) {
    SourceImportKind.text => SourceImportInput.text(_text.text),
    SourceImportKind.file => SourceImportInput.file(
      _text.text,
      label: _fileLabel ?? '书源文件.json',
    ),
    SourceImportKind.url => SourceImportInput.url(Uri.parse(_url.text.trim())),
  };

  Future<void> _prepare() async {
    if (_busy) return;
    final SourceImportInput input;
    try {
      input = _input();
    } on FormatException {
      setState(() => _error = '请输入完整的 HTTP(S) 书源 JSON 地址。');
      return;
    }

    final abort = Completer<void>();
    setState(() {
      _busy = true;
      _abort = abort;
      _error = null;
    });
    try {
      final preview = await widget.controller.prepareSourceImport(
        input,
        abortTrigger: abort.future,
      );
      if (!mounted) return;
      if (abort.isCompleted) {
        throw const SourceImportException(
          SourceImportErrorKind.cancelled,
          '已取消导入书源。',
        );
      }
      setState(() {
        _preview = preview;
        _selectedSourceIds = {for (final source in preview.sources) source.id};
        _busy = false;
        _abort = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorMessage(error);
          _busy = false;
          _committing = false;
          _abort = null;
        });
      }
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (_busy || preview == null || _selectedSourceIds.isEmpty) return;
    setState(() {
      _busy = true;
      _committing = true;
      _error = null;
    });
    try {
      final result = await widget.controller.commitSourceImport(
        preview,
        selectedSourceIds: _selectedSourceIds,
      );
      if (!mounted) return;
      showMessage(
        context,
        '已导入 ${result.total} 个书源（新增 ${result.added}，更新 ${result.updated}）。',
      );
      Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorMessage(error);
          _busy = false;
          _committing = false;
        });
      }
    }
  }

  void _cancel() {
    if (_committing) return;
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
  }

  void _backToInput() {
    if (_busy) return;
    setState(() {
      _preview = null;
      _selectedSourceIds = {};
      _error = null;
    });
  }

  void _selectAll() {
    final preview = _preview;
    if (preview == null || _busy) return;
    setState(() {
      _selectedSourceIds = {for (final source in preview.sources) source.id};
    });
  }

  void _clearSelection() {
    if (_busy) return;
    setState(() => _selectedSourceIds = {});
  }

  void _setSelected(String id, bool selected) {
    if (_busy) return;
    setState(() {
      if (selected) {
        _selectedSourceIds = {..._selectedSourceIds, id};
      } else {
        _selectedSourceIds = _selectedSourceIds
            .where((item) => item != id)
            .toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) => _preview == null
      ? _buildInput(context)
      : _buildPreview(context, _preview!);

  Widget _buildInput(BuildContext context) => SingleChildScrollView(
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
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '书源 JSON 地址',
              hintText: 'https://example.com/sources.json',
            ),
          )
        else ...[
          if (_mode == SourceImportKind.file) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(_fileLabel ?? '选择 JSON 文件'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '最大 ${SourceImporter.maxBytesLabel}，仅限 JSON。',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            key: const Key('source-json'),
            controller: _text,
            enabled: !_busy,
            minLines: 6,
            maxLines: 12,
            style: const TextStyle(fontSize: 13, height: 1.6),
            decoration: const InputDecoration(
              labelText: '书源 JSON',
              hintText: '{"bookSourceName":"…"}',
            ),
          ),
        ],
        if (_error != null) _errorText(),
        const SizedBox(height: 18),
        if (_busy)
          Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('正在检查书源…')),
              TextButton(onPressed: _cancel, child: const Text('取消')),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('source-import'),
              onPressed: _prepare,
              child: const Text('检查并预览'),
            ),
          ),
      ],
    ),
  );

  Widget _buildPreview(BuildContext context, SourceImportPreview preview) {
    final height = math.min(640.0, MediaQuery.sizeOf(context).height * .78);
    return SafeArea(
      child: SizedBox(
        key: const Key('source-preview'),
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('source-preview-back'),
                    tooltip: '返回编辑',
                    onPressed: _busy ? null : _backToInput,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '选择要导入的书源',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${_selectedSourceIds.length}/${preview.sources.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '检查阶段不会保存书源。只会原子导入你明确选中的来源。',
                style: TextStyle(color: AppColors.muted, height: 1.7),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: const Key('source-preview-select-all'),
                    onPressed: _busy ? null : _selectAll,
                    child: const Text('全选'),
                  ),
                  TextButton(
                    key: const Key('source-preview-clear-all'),
                    onPressed: _busy ? null : _clearSelection,
                    child: const Text('清空'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: preview.sources.length,
                  itemBuilder: (context, index) {
                    final source = preview.sources[index];
                    return CheckboxListTile(
                      key: Key('source-preview-select-${source.id}'),
                      value: _selectedSourceIds.contains(source.id),
                      onChanged: _busy
                          ? null
                          : (selected) =>
                                _setSelected(source.id, selected ?? false),
                      contentPadding: EdgeInsets.zero,
                      title: Text(source.name),
                      subtitle: Text(
                        source.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
              if (_error != null) _errorText(),
              const SizedBox(height: 12),
              if (_busy)
                Row(
                  children: [
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('正在保存书源…')),
                    TextButton(onPressed: null, child: const Text('取消')),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('source-preview-import'),
                    onPressed: _selectedSourceIds.isEmpty ? null : _commit,
                    child: Text('导入选中来源（${_selectedSourceIds.length}）'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Text(
      _error!,
      key: const Key('source-error'),
      style: const TextStyle(color: Color(0xFFB54444), height: 1.6),
    ),
  );
}
