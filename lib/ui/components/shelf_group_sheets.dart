import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/shelf_group.dart';
import '../theme.dart';
import 'common.dart';

Future<String?> _groupNameDialog(
  BuildContext context, {
  String? existing,
}) async {
  final form = GlobalKey<FormState>();
  var name = existing ?? '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      title: Text(existing == null ? '新建分组' : '重命名分组'),
      content: Form(
        key: form,
        child: TextFormField(
          key: const Key('shelf-group-name'),
          initialValue: name,
          autofocus: true,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '给分组起个名字'),
          validator: (value) => (value ?? '').trim().isEmpty ? '请输入分组名称' : null,
          onChanged: (value) => name = value,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('shelf-group-save'),
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(dialogContext, name);
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

class ShelfGroupManagerSheet extends StatefulWidget {
  const ShelfGroupManagerSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<ShelfGroupManagerSheet> createState() => _ShelfGroupManagerSheetState();
}

class _ShelfGroupManagerSheetState extends State<ShelfGroupManagerSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _edit([ShelfGroup? group]) async {
    if (_busy) return;
    final name = await _groupNameDialog(context, existing: group?.name);
    if (!mounted || name == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (group == null) {
        await widget.controller.createShelfGroup(name);
      } else {
        await widget.controller.renameShelfGroup(group.id, name);
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ShelfGroup group) async {
    if (_busy ||
        !await confirmRemoval(
          context,
          '删除分组《${group.name}》？',
          '只删除分组，书籍、阅读进度与笔记仍保留。',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.deleteShelfGroup(group.id);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                        '管理分组',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('shelf-group-close'),
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '按自己的方式整理书籍。删除分组不会删除书或阅读记录。',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 18),
                for (final group in widget.controller.shelfGroups) ...[
                  QuietPanel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      title: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${group.bookIds.length} 本书'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('shelf-group-rename-${group.id}'),
                            tooltip: '重命名${group.name}',
                            onPressed: _busy ? null : () => _edit(group),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            key: Key('shelf-group-delete-${group.id}'),
                            tooltip: '删除${group.name}',
                            onPressed: _busy ? null : () => _delete(group),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (widget.controller.shelfGroups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Text(
                      '还没有自定义分组。',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                FilledButton.icon(
                  key: const Key('shelf-group-add'),
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建分组'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      key: const Key('shelf-group-error'),
                      style: const TextStyle(color: Color(0xFFB54444)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ShelfBookGroupsSheet extends StatefulWidget {
  const ShelfBookGroupsSheet({
    super.key,
    required this.controller,
    required this.bookId,
  });

  final AppController controller;
  final String bookId;

  @override
  State<ShelfBookGroupsSheet> createState() => _ShelfBookGroupsSheetState();
}

class _ShelfBookGroupsSheetState extends State<ShelfBookGroupsSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _toggle(ShelfGroup group, bool value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.setShelfGroupMembership(
        group.id,
        widget.bookId,
        value,
      );
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
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
                        '加入分组',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('shelf-group-membership-close'),
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '一本书可以加入多个分组。',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                if (widget.controller.shelfGroups.isEmpty)
                  const Text(
                    '暂无分组，请先在书架顶部创建。',
                    style: TextStyle(color: AppColors.muted),
                  ),
                for (final group in widget.controller.shelfGroups)
                  CheckboxListTile(
                    key: Key('shelf-group-member-${group.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(group.name),
                    value: group.containsBook(widget.bookId),
                    activeColor: AppColors.blue,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: _busy ? null : (value) => _toggle(group, value!),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      key: const Key('shelf-group-membership-error'),
                      style: const TextStyle(color: Color(0xFFB54444)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
