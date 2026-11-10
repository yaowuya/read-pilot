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
      Row(
        children: [
          const Expanded(
            child: Text(
              '本机备份',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            key: const Key('backup-export'),
            onPressed: _busy ? null : _export,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              foregroundColor: const Color(0xFF6D94CA),
              backgroundColor: const Color(0xFFEFF5FE),
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: const Text('立即备份'),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        _message ?? '尚未导出备份',
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFFA2ADBC),
          height: 1.8,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        '包含书架、进度、笔记、书源和阅读设置；不包含网络书籍、书源凭据或远程缓存。',
        style: TextStyle(fontSize: 11, color: Color(0xFFA2ADBC), height: 1.8),
      ),
      const SizedBox(height: 10),
      _BackupOption(
        key: const Key('backup-export-encrypted'),
        icon: Icons.lock_outline,
        title: '导出加密备份',
        description: '给备份加一道本机密码，只有你能打开。',
        onTap: _busy ? null : _exportEncrypted,
      ),
      _BackupOption(
        key: const Key('backup-import'),
        icon: Icons.archive_outlined,
        title: '从备份恢复',
        description: '先预览新增与跳过的数量，再决定是否恢复。',
        onTap: _busy ? null : _import,
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

class _BackupOption extends StatelessWidget {
  const _BackupOption({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE9EDF3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 21, color: const Color(0xFF93A0B4)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFFA3ADBA),
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 17,
                color: Color(0xFFB0B8C3),
              ),
            ],
          ),
        ),
      ),
    ),
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
