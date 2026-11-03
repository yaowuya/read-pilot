import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../services/encrypted_local_backup.dart';
import '../../services/local_backup.dart';
import '../theme.dart';
import 'common.dart';

typedef BackupFilePicker = Future<Uint8List?> Function();
typedef BackupFileSaver = Future<bool> Function(Uint8List bytes, String name);

class LocalBackupPanel extends StatefulWidget {
  const LocalBackupPanel({
    super.key,
    required this.controller,
    this.pickFile,
    this.saveFile,
  });

  final AppController controller;
  final BackupFilePicker? pickFile;
  final BackupFileSaver? saveFile;

  @override
  State<LocalBackupPanel> createState() => _LocalBackupPanelState();
}

class _LocalBackupPanelState extends State<LocalBackupPanel> {
  bool _busy = false;
  String? _error;
  String? _message;

  static Future<Uint8List?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
      withReadStream: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.size > EncryptedLocalBackupCodec.maxEnvelopeBytes) {
      throw const FormatException('本地备份不能超过 16 MiB。');
    }
    final stream = file.readStream;
    if (stream == null) {
      throw const FormatException('当前平台不支持安全的流式文件读取。');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length + chunk.length >
          EncryptedLocalBackupCodec.maxEnvelopeBytes) {
        throw const FormatException('本地备份不能超过 16 MiB。');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Future<bool> _saveFile(Uint8List bytes, String name) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存本地阅读备份',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    return kIsWeb || path != null;
  }

  Future<String?> _askPassword({
    required String title,
    required bool confirmation,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        _BackupPasswordDialog(title: title, confirmation: confirmation),
  );

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final bytes = await widget.controller.exportLocalBackup();
      if (!mounted) return;
      final date = DateTime.now()
          .toIso8601String()
          .substring(0, 10)
          .replaceAll('-', '');
      final saved = await (widget.saveFile ?? _saveFile)(
        bytes,
        'read-pilot-local-$date.json',
      );
      if (mounted && saved) {
        setState(() => _message = '已发起备份保存；请确认文件实际存在，并妥善保管未加密的文件。');
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportEncrypted() async {
    if (_busy) return;
    final password = await _askPassword(title: '加密本地备份', confirmation: true);
    if (!mounted || password == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final bytes = await widget.controller.exportEncryptedLocalBackup(
        password,
      );
      if (!mounted) return;
      final date = DateTime.now()
          .toIso8601String()
          .substring(0, 10)
          .replaceAll('-', '');
      final saved = await (widget.saveFile ?? _saveFile)(
        bytes,
        'read-pilot-local-$date.encrypted.json',
      );
      if (mounted && saved) {
        setState(() => _message = '已发起加密备份保存；密码不会被保存，遗失后无法恢复文件。');
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final bytes = await (widget.pickFile ?? _pickFile)();
      if (!mounted || bytes == null) return;
      final encrypted = EncryptedLocalBackupCodec.isEncrypted(bytes);
      final LocalBackupPlan plan;
      if (encrypted) {
        final password = await _askPassword(
          title: '解密本地备份',
          confirmation: false,
        );
        if (!mounted || password == null) return;
        plan = await widget.controller.prepareEncryptedLocalBackup(
          bytes,
          password,
        );
      } else {
        plan = await widget.controller.prepareLocalBackup(bytes);
      }
      if (!mounted) return;
      var restoreSettings = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            title: const Text('预览本地备份'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('新增 ${plan.newBooks} 本 · 跳过 ${plan.skippedBooks} 本'),
                const SizedBox(height: 12),
                const Text(
                  '只恢复新增书籍及对应笔记和显示规则；同名分组会加入这些新书。现有书籍、网络书源和远程缓存不会被覆盖。',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('backup-restore-settings'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('同时恢复阅读设置'),
                  value: restoreSettings,
                  onChanged: (value) =>
                      updateDialog(() => restoreSettings = value!),
                ),
                Text(
                  encrypted
                      ? '已在本机验证密码并解密；密码不会被保存。备份仅含本地书籍，不含书源或网络书。'
                      : '备份仅含本地书籍，不含书源或网络书。文件未加密；确认前请核对来源。',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('backup-confirm'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认恢复'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || confirmed != true) return;
      final result = await widget.controller.restoreLocalBackup(
        plan,
        restoreSettings: restoreSettings,
      );
      if (mounted) {
        setState(
          () => _message =
              '已导入 ${result.importedBooks} 本、${result.importedBookmarks} 条笔记；'
              '跳过 ${result.skippedBooks} 本已有书籍。',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('本地备份与恢复', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text(
        '仅包含本地书籍、对应笔记、分组、显示规则和阅读设置；不包含网络书籍、书源凭据、远程缓存或段落标注。可选择导出明文兼容备份，或使用本机密码加密导出。',
        style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.7),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            key: const Key('backup-export'),
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: const Text('导出明文备份'),
          ),
          FilledButton.icon(
            key: const Key('backup-export-encrypted'),
            onPressed: _busy ? null : _exportEncrypted,
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('导出加密备份'),
          ),
          OutlinedButton.icon(
            key: const Key('backup-import'),
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: const Text('导入备份'),
          ),
        ],
      ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(liveRegion: true, child: Text(_message!)),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              key: const Key('backup-error'),
              style: const TextStyle(color: Color(0xFFB54444)),
            ),
          ),
        ),
    ],
  );
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({
    required this.title,
    required this.confirmation,
  });

  final String title;
  final bool confirmation;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController();
  final _repeated = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _repeated.dispose();
    super.dispose();
  }

  void _continue() {
    if (widget.confirmation && _password.text != _repeated.text) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '密码不会被保存，遗失后无法恢复加密备份。密码需为 12–128 个字符。',
          style: TextStyle(color: AppColors.muted, height: 1.6),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('backup-password'),
          controller: _password,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: '备份密码'),
        ),
        if (widget.confirmation) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('backup-password-confirmation'),
            controller: _repeated,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '再次输入密码'),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB54444)),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('backup-password-confirm'),
        onPressed: _continue,
        child: const Text('继续'),
      ),
    ],
  );
}
