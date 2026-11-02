import 'package:flutter/material.dart';

import '../../domain/reader_mark.dart';
import '../theme.dart';
import 'common.dart';

class ReaderMarkSheet extends StatefulWidget {
  const ReaderMarkSheet({
    super.key,
    required this.paragraph,
    required this.onSave,
    this.mark,
    this.onDelete,
    this.isSelectedText = false,
  });

  final String paragraph;
  final ReaderMark? mark;
  final Future<ReaderMark> Function(ReaderMarkColor color, String note) onSave;
  final Future<void> Function()? onDelete;
  final bool isSelectedText;

  @override
  State<ReaderMarkSheet> createState() => _ReaderMarkSheetState();
}

class _ReaderMarkSheetState extends State<ReaderMarkSheet> {
  late final TextEditingController _note = TextEditingController(
    text: widget.mark?.note ?? '',
  );
  late ReaderMarkColor _color = widget.mark?.color ?? ReaderMarkColor.amber;
  var _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSave(_color, _note.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || widget.onDelete == null) return;
    if (!await confirmRemoval(context, '删除这条段落标注？', '只移除本机标注和备注，不会修改正文或书签。')) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _colorValue(ReaderMarkColor color) => switch (color) {
    ReaderMarkColor.amber => const Color(0xFFF3D77A),
    ReaderMarkColor.mint => const Color(0xFF9AD7BE),
    ReaderMarkColor.blue => const Color(0xFFAFCBEE),
  };

  String _colorLabel(ReaderMarkColor color) => switch (color) {
    ReaderMarkColor.amber => '琥珀',
    ReaderMarkColor.mint => '薄荷',
    ReaderMarkColor.blue => '浅蓝',
  };

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isSelectedText ? '选中文字标注' : '段落标注',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            widget.isSelectedText
                ? '只标注当前滚动段落中唯一的文字片段。内容、来源或唯一性变化后，旧标注会自动失效。'
                : '只标注当前显示段落，正文、书源和阅读进度不会被改写。内容或来源变化后，旧标注会自动失效。',
            style: const TextStyle(color: AppColors.muted, height: 1.7),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _colorValue(_color).withValues(alpha: .25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              widget.paragraph,
              maxLines: 6,
              style: const TextStyle(height: 1.7),
            ),
          ),
          const SizedBox(height: 16),
          const Text('颜色', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final color in ReaderMarkColor.values)
                ChoiceChip(
                  key: Key('reader-mark-color-${color.name}'),
                  label: Text(_colorLabel(color)),
                  selected: _color == color,
                  selectedColor: _colorValue(color),
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _color = color),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('reader-mark-note'),
            controller: _note,
            maxLength: ReaderMark.maxNoteCharacters,
            maxLines: 3,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.onDelete != null)
                TextButton(
                  key: const Key('reader-mark-delete'),
                  onPressed: _busy ? null : _delete,
                  child: const Text('删除标注'),
                ),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('reader-mark-save'),
                onPressed: _busy ? null : _save,
                child: Text(_busy ? '正在保存…' : '保存标注'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
