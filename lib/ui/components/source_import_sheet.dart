import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/source_import.dart';
import '../../services/source_importer.dart';
import 'common.dart';

/// Validates and commits pasted, file-based, or remote source definitions.
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
        throw const FormatException('书源文件不能超过 10 MiB。');
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

  Future<void> _import() async {
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
      // Atomic persistence cannot be cancelled once it has started.
      setState(() => _committing = true);
      final result = await widget.controller.commitSourceImport(preview);
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
          _abort = null;
        });
      }
    }
  }

  void _cancel() {
    if (_committing) return;
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
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
        if (_busy)
          Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(_committing ? '正在保存书源…' : '正在获取并导入书源…')),
              TextButton(
                onPressed: _committing ? null : _cancel,
                child: const Text('取消'),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('source-import'),
              onPressed: _import,
              child: const Text('确认导入'),
            ),
          ),
      ],
    ),
  );
}
