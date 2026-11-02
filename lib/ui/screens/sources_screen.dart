import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/app_controller.dart';
import '../../domain/book_source.dart';
import '../components/common.dart';
import '../components/source_import_sheet.dart';
import '../components/source_health_sheet.dart';
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
              description:
                  '导入 Legado 风格的声明式书源。\nAndroid 仅在受限沙箱中执行规则脚本，Web 不执行脚本。',
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
                    Text(
                      source.enabled ? '已启用 · 连接尚未验证' : '已停用 · 不参与搜索',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 2,
                      children: [
                        TextButton(
                          onPressed: () => _health(source),
                          child: const Text('检查书源'),
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
                  '支持 CSS/legacy、安全 XPath 子集、RFC JSONPath、GET/POST/HEAD、UTF-8/GBK 与有界分页。Android 可在 QuickJS 沙箱中执行限定规则脚本；登录、解密、媒体与设备 helper 仍会明确标记为不支持。',
                  style: TextStyle(color: AppColors.muted, height: 1.9),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Web 版遵守浏览器跨域规则（CORS）且不执行未受信任脚本。HTTP 传输不加密，请勿在来源地址中填写账号或密码。',
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
    builder: (_) => SourceImportSheet(controller: widget.controller),
  );

  void _health(BookSource source) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) =>
        SourceHealthSheet(controller: widget.controller, source: source),
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
