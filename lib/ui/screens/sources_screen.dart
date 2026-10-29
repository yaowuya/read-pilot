import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/app_controller.dart';
import '../../domain/book_source.dart';
import '../components/common.dart';
import '../theme.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  final _pending = <String>{};
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      return ListView(
        padding: EdgeInsets.all(compact ? 20 : 40),
        children: [
          PageHeading(
            title: '我的书源',
            subtitle: '让好内容，抵达你的书架。',
            action: compact
                ? IconButton.filled(
                    key: const Key('import-source'),
                    onPressed: _import,
                    tooltip: '导入书源',
                    icon: const Icon(Icons.add),
                  )
                : FilledButton.icon(
                    key: const Key('import-source'),
                    onPressed: _import,
                    icon: const Icon(Icons.add, size: 19),
                    label: const Text('导入书源'),
                  ),
          ),
          const SizedBox(height: 28),
          QuietPanel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.menu_book_outlined, color: AppColors.ink),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '阅读 · 公版书库',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.controller.catalog.length} 部经典节选，随应用内置。\n无需网络，随时翻开。',
                        style: const TextStyle(
                          color: AppColors.muted,
                          height: 1.8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '内置内容 · 离线可用',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.offline_pin_outlined,
                  color: AppColors.blue,
                  size: 22,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Text('导入的书源', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Text(
                '${widget.controller.sources.length} 个',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.controller.sources.isEmpty)
            EmptyState(
              title: '阅读，也可以有自己的来源',
              description: '导入 Legado 风格的声明式 CSS 书源。\n仅支持你有权访问的文本内容，不执行远程脚本。',
              action: OutlinedButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.file_upload_outlined, size: 19),
                label: const Text('导入 JSON 书源'),
              ),
            ),
          for (final source in widget.controller.sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: QuietPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            source.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Switch(
                          value: source.enabled,
                          activeThumbColor: Colors.white,
                          activeTrackColor: AppColors.ink,
                          onChanged: _pending.contains(source.id)
                              ? null
                              : (enabled) async {
                                  setState(() => _pending.add(source.id));
                                  try {
                                    await widget.controller.setSourceEnabled(
                                      source,
                                      enabled,
                                    );
                                  } catch (error) {
                                    if (context.mounted) {
                                      showMessage(context, errorMessage(error));
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(
                                        () => _pending.remove(source.id),
                                      );
                                    }
                                  }
                                },
                        ),
                      ],
                    ),
                    Text(
                      source.id,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            source.enabled ? '已启用 · 连接尚未验证' : '已停用 · 不参与搜索',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _view(source),
                          child: const Text('查看规则'),
                        ),
                        IconButton(
                          tooltip: '删除${source.name}',
                          onPressed: () async {
                            if (!await confirmRemoval(
                              context,
                              '移除“${source.name}”？',
                              '已缓存的书籍仍可阅读，新的章节需要重新导入书源才能获取。',
                            )) {
                              return;
                            }
                            try {
                              await widget.controller.deleteSource(source.id);
                            } catch (error) {
                              if (context.mounted) {
                                showMessage(context, errorMessage(error));
                              }
                            }
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          QuietPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '有边界，才更安心',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  '支持 CSS 选择器、HTTP(S) GET 和 UTF-8。暂不支持 JavaScript、XPath、登录解密或自动翻页。复杂书源会明确提示不支持的字段，不会假装兼容。',
                  style: TextStyle(color: AppColors.muted, height: 1.9),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Web 版遵守浏览器跨域规则（CORS）。HTTP 传输不加密，请勿在来源地址中填写账号或密码。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.8,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  void _import() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 680),
    builder: (_) => _SourceImport(controller: widget.controller),
  );

  void _view(BookSource source) {
    final json = const JsonEncoder.withIndent('  ').convert(source.toJson());
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(source.name),
        content: SizedBox(
          width: 560,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) showMessage(context, '书源 JSON 已复制。');
            },
            child: const Text('复制 JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _SourceImport extends StatefulWidget {
  const _SourceImport({required this.controller});
  final AppController controller;
  @override
  State<_SourceImport> createState() => _SourceImportState();
}

class _SourceImportState extends State<_SourceImport> {
  final _text = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
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
      if (file.bytes == null) throw const FormatException('无法读取文件，请重新选择。');
      _text.text = utf8.decode(file.bytes!);
      setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    }
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
        Row(
          children: [
            Text('导入书源', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.folder_open_outlined, size: 19),
              label: const Text('选择文件'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '粘贴 JSON 对象或数组，最大 1 MiB。相同地址的书源会更新配置。',
          style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.7),
        ),
        const SizedBox(height: 20),
        const Text('书源 JSON', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          key: const Key('source-json'),
          controller: _text,
          minLines: 7,
          maxLines: 12,
          style: const TextStyle(fontSize: 13, height: 1.6),
          decoration: const InputDecoration(
            hintText:
                '{\n  "bookSourceName": "我的授权书库",\n  "bookSourceUrl": "https://…"\n}',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              _error!,
              key: const Key('source-error'),
              style: const TextStyle(color: Color(0xFFB54444), height: 1.7),
            ),
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      final count = await widget.controller.importSources(
                        _text.text,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        showMessage(context, '已导入 $count 个书源。可以到“发现”中搜索。');
                      }
                    } catch (error) {
                      if (mounted) {
                        setState(() {
                          _error = errorMessage(error);
                          _busy = false;
                        });
                      }
                    }
                  },
            child: Text(_busy ? '校验并保存…' : '校验并导入'),
          ),
        ),
      ],
    ),
  );
}
