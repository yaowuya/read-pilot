import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../services/book_text_rules.dart';
import '../design_icons.dart';
import '../theme.dart';
import 'common.dart';

Future<({String needle, String replacement})?> _ruleDialog(
  BuildContext context, {
  BookTextRule? rule,
}) {
  final form = GlobalKey<FormState>();
  var needle = rule?.needle ?? '';
  var replacement = rule?.replacement ?? '';
  return showDialog<({String needle, String replacement})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      title: Text(rule == null ? '新增替换规则' : '编辑替换规则'),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('text-rule-needle'),
              initialValue: needle,
              autofocus: true,
              maxLength: BookTextRules.maxNeedleCharacters,
              decoration: const InputDecoration(labelText: '查找原文（字面文本）'),
              onChanged: (value) => needle = value,
              validator: (value) {
                try {
                  BookTextRules.validate(value ?? '', replacement);
                  return null;
                } on FormatException catch (error) {
                  return error.message;
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('text-rule-replacement'),
              initialValue: replacement,
              maxLength: BookTextRules.maxReplacementCharacters,
              decoration: const InputDecoration(labelText: '替换为（可留空）'),
              onChanged: (value) => replacement = value,
              validator: (value) {
                try {
                  BookTextRules.validate(needle, value ?? '');
                  return null;
                } on FormatException catch (error) {
                  return error.message;
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('text-rule-save'),
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(dialogContext, (
                needle: needle,
                replacement: replacement,
              ));
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

class BookTextRuleSheet extends StatefulWidget {
  const BookTextRuleSheet({
    super.key,
    required this.controller,
    required this.book,
  });

  final AppController controller;
  final Book book;

  @override
  State<BookTextRuleSheet> createState() => _BookTextRuleSheetState();
}

class _BookTextRuleSheetState extends State<BookTextRuleSheet> {
  bool _busy = false;
  String? _error;
  String _previewText = '';

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([BookTextRule? rule]) async {
    if (_busy) return;
    final input = await _ruleDialog(context, rule: rule);
    if (!mounted || input == null) return;
    await _perform(() async {
      if (rule == null) {
        await widget.controller.addTextRule(
          widget.book.id,
          input.needle,
          input.replacement,
        );
      } else {
        await widget.controller.updateTextRule(
          widget.book.id,
          rule.id,
          input.needle,
          input.replacement,
        );
      }
    });
  }

  Future<void> _delete(BookTextRule rule) async {
    if (_busy ||
        !await confirmRemoval(context, '删除这条正文替换规则？', '仅移除自定义显示规则，原始正文不会改变。')) {
      return;
    }
    if (!mounted) return;
    await _perform(
      () => widget.controller.deleteTextRule(widget.book.id, rule.id),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final rules = widget.controller.textRules(widget.book.id);
      final available = widget.controller.book(widget.book.id) != null;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(
                0.0,
                MediaQuery.sizeOf(context).height * .8 -
                    MediaQuery.viewInsetsOf(context).bottom,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '正文替换 · 仅显示',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const Key('text-rule-close'),
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(DesignIcons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '只影响显示，不修改原始正文、进度和书签。查找按字面文本处理，不执行正则或脚本。',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '按顺序执行；过长段落或超出预算的规则会跳过。书内查找仍检索原文。',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  if (rules.isEmpty) ...[
                    const Text(
                      '尚未添加正文替换。',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),
                  ],
                  for (var index = 0; index < rules.length; index++) ...[
                    QuietPanel(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${rules[index].needle} → ${rules[index].replacement.isEmpty ? '（删除）' : rules[index].replacement}',
                            key: Key('text-rule-${rules[index].id}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Semantics(
                                label: '启用替换：${rules[index].needle}',
                                child: Switch(
                                  key: Key(
                                    'text-rule-enabled-${rules[index].id}',
                                  ),
                                  value: rules[index].enabled,
                                  onChanged: _busy || !available
                                      ? null
                                      : (value) => _perform(
                                          () => widget.controller
                                              .setTextRuleEnabled(
                                                widget.book.id,
                                                rules[index].id,
                                                value,
                                              ),
                                        ),
                                ),
                              ),
                              Text(rules[index].enabled ? '已启用' : '已停用'),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              children: [
                                IconButton(
                                  key: Key('text-rule-up-${rules[index].id}'),
                                  tooltip: '上移规则',
                                  onPressed: _busy || !available || index == 0
                                      ? null
                                      : () => _perform(
                                          () => widget.controller.moveTextRule(
                                            widget.book.id,
                                            rules[index].id,
                                            -1,
                                          ),
                                        ),
                                  icon: const Icon(
                                    DesignIcons.arrowUp,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  key: Key('text-rule-down-${rules[index].id}'),
                                  tooltip: '下移规则',
                                  onPressed:
                                      _busy ||
                                          !available ||
                                          index == rules.length - 1
                                      ? null
                                      : () => _perform(
                                          () => widget.controller.moveTextRule(
                                            widget.book.id,
                                            rules[index].id,
                                            1,
                                          ),
                                        ),
                                  icon: const Icon(
                                    DesignIcons.arrowDown,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  key: Key('text-rule-edit-${rules[index].id}'),
                                  tooltip: '编辑规则',
                                  onPressed: _busy || !available
                                      ? null
                                      : () => _edit(rules[index]),
                                  icon: const Icon(
                                    DesignIcons.type,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  key: Key(
                                    'text-rule-delete-${rules[index].id}',
                                  ),
                                  tooltip: '删除规则',
                                  onPressed: _busy || !available
                                      ? null
                                      : () => _delete(rules[index]),
                                  icon: const Icon(
                                    DesignIcons.trash,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    key: const Key('text-rule-add'),
                    onPressed:
                        _busy ||
                            !available ||
                            rules.length >= BookTextRules.maxRulesPerBook
                        ? null
                        : () => _edit(),
                    icon: const Icon(DesignIcons.plus, size: 18),
                    label: const Text('新增规则'),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('text-rule-preview-input'),
                    maxLength: 256,
                    maxLines: 2,
                    onChanged: (value) => setState(() => _previewText = value),
                    decoration: const InputDecoration(hintText: '输入一小段原文试试看'),
                  ),
                  if (_previewText.isNotEmpty)
                    Text(
                      '预览：${widget.controller.displayParagraph(widget.book.id, _previewText)}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        key: const Key('text-rule-error'),
                        style: const TextStyle(color: Color(0xFFB54444)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
