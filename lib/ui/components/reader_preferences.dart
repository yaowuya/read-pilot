import 'package:flutter/material.dart';

import '../../domain/reader_settings.dart';
import '../../domain/reader_style_preset.dart';
import '../reader/reader_palette.dart';
import '../reader/reader_paragraph.dart';
import '../theme.dart';
import 'common.dart';

/// Save failures restore the latest successful values within the same sheet.
class ReaderPreferences extends StatefulWidget {
  const ReaderPreferences({
    super.key,
    required this.settings,
    required this.onChanged,
    this.stylePresets = const [],
    this.onSaveStylePreset,
    this.onDeleteStylePreset,
  });
  final ReaderSettings settings;
  final Future<void> Function(ReaderSettings) onChanged;
  final List<ReaderStylePreset> stylePresets;
  final Future<void> Function(String name, ReaderSettings settings)?
  onSaveStylePreset;
  final Future<void> Function(String id)? onDeleteStylePreset;
  @override
  State<ReaderPreferences> createState() => _ReaderPreferencesState();
}

class _ReaderPreferencesState extends State<ReaderPreferences> {
  late ReaderSettings _value = widget.settings;
  late ReaderSettings _savedValue = widget.settings;
  final _stylePresetName = TextEditingController();
  bool _saving = false;
  bool _addingStylePreset = false;

  static const _presets =
      <
        ({
          String id,
          String label,
          double fontSize,
          double lineHeight,
          double paragraphSpacing,
        })
      >[
        (
          id: 'relaxed',
          label: '舒缓',
          fontSize: 24,
          lineHeight: 2.1,
          paragraphSpacing: 28,
        ),
        (
          id: 'balanced',
          label: '均衡',
          fontSize: 22,
          lineHeight: 1.9,
          paragraphSpacing: 20,
        ),
        (
          id: 'compact',
          label: '紧凑',
          fontSize: 20,
          lineHeight: 1.6,
          paragraphSpacing: 10,
        ),
      ];

  @override
  void dispose() {
    _stylePresetName.dispose();
    super.dispose();
  }

  Future<void> _saveStylePreset() async {
    final save = widget.onSaveStylePreset;
    if (_saving || save == null) return;
    setState(() => _saving = true);
    try {
      await save(_stylePresetName.text, _value);
      if (mounted) {
        setState(() {
          _stylePresetName.clear();
          _addingStylePreset = false;
        });
      }
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteStylePreset(ReaderStylePreset preset) async {
    final delete = widget.onDeleteStylePreset;
    if (_saving || delete == null) return;
    if (!await confirmRemoval(
      context,
      '删除“${preset.name}”？',
      '只移除这个本地样式预设，不会修改当前阅读设置。',
    )) {
      return;
    }
    setState(() => _saving = true);
    try {
      await delete(preset.id);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void didUpdateWidget(covariant ReaderPreferences oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving && widget.settings != oldWidget.settings) {
      _value = widget.settings;
      _savedValue = widget.settings;
    }
  }

  Future<void> _save(ReaderSettings value) async {
    setState(() {
      _value = value;
      _saving = true;
    });
    try {
      await widget.onChanged(value);
      _savedValue = value;
    } catch (error) {
      if (mounted) {
        setState(() => _value = _savedValue);
        showMessage(context, errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          const Text('阅读主题', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            _saving ? '保存中…' : '自动保存',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final theme in ReaderTheme.values)
            Builder(
              builder: (_) {
                final palette = ReaderPalette.of(theme);
                return Semantics(
                  label: '阅读主题 ${palette.label}',
                  selected: _value.theme == theme,
                  child: ChoiceChip(
                    key: Key('reader-theme-${theme.name}'),
                    avatar: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.background,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.isDark
                              ? palette.muted
                              : palette.ink.withValues(alpha: .25),
                        ),
                      ),
                      child: const SizedBox(width: 14, height: 14),
                    ),
                    label: Text(palette.label),
                    selected: _value.theme == theme,
                    showCheckmark: true,
                    onSelected: _saving
                        ? null
                        : (_) => _save(_value.copyWith(theme: theme)),
                  ),
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 24),
      const Text('排版预设', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in _presets)
            ChoiceChip(
              key: Key('reader-preset-${preset.id}'),
              label: Text(preset.label),
              selected:
                  (_value.fontSize - preset.fontSize).abs() < .01 &&
                  (_value.lineHeight - preset.lineHeight).abs() < .01 &&
                  (_value.paragraphSpacing - preset.paragraphSpacing).abs() <
                      .01,
              onSelected: _saving
                  ? null
                  : (_) => _save(
                      _value.copyWith(
                        fontSize: preset.fontSize,
                        lineHeight: preset.lineHeight,
                        paragraphSpacing: preset.paragraphSpacing,
                      ),
                    ),
            ),
        ],
      ),
      if (widget.onSaveStylePreset != null) ...[
        const SizedBox(height: 24),
        Row(
          children: [
            const Text('我的预设', style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              key: const Key('reader-style-preset-add'),
              onPressed: _saving
                  ? null
                  : () => setState(() => _addingStylePreset = true),
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('保存当前'),
            ),
          ],
        ),
        if (_addingStylePreset) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('reader-style-preset-name'),
            controller: _stylePresetName,
            maxLength: 24,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: '预设名称'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('reader-style-preset-save'),
              onPressed: _saving ? null : _saveStylePreset,
              child: const Text('保存预设'),
            ),
          ),
        ],
        if (widget.stylePresets.isEmpty && !_addingStylePreset)
          const Text(
            '保存一组属于自己的阅读样式。',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          )
        else if (widget.stylePresets.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in widget.stylePresets)
                InputChip(
                  key: Key('reader-style-preset-${preset.id}'),
                  label: Text(preset.name),
                  onPressed: _saving ? null : () => _save(preset.settings),
                  onDeleted: widget.onDeleteStylePreset == null || _saving
                      ? null
                      : () {
                          _deleteStylePreset(preset);
                        },
                ),
            ],
          ),
        ],
      ],
      const SizedBox(height: 24),
      const Text('翻页方式', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<ReaderFlow>(
          segments: const [
            ButtonSegment(
              value: ReaderFlow.paged,
              icon: Icon(Icons.swipe, size: 18),
              label: Text('左右翻页', key: Key('reader-flow-paged')),
            ),
            ButtonSegment(
              value: ReaderFlow.scrolling,
              icon: Icon(Icons.swap_vert, size: 18),
              label: Text('上下滚动', key: Key('reader-flow-scrolling')),
            ),
          ],
          selected: {_value.flow},
          onSelectionChanged: _saving
              ? null
              : (selection) => _save(_value.copyWith(flow: selection.single)),
        ),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          const Text('字号', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            '${_value.fontSize.round()} px',
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
      Row(
        children: [
          IconButton(
            tooltip: '字号减小',
            onPressed: _saving || _value.fontSize <= 18
                ? null
                : () => _save(_value.copyWith(fontSize: _value.fontSize - 2)),
            icon: const Icon(Icons.text_decrease, size: 22),
          ),
          Expanded(
            child: Slider(
              value: _value.fontSize,
              min: 18,
              max: 32,
              divisions: 7,
              label: '${_value.fontSize.round()}',
              onChanged: _saving
                  ? null
                  : (size) => setState(
                      () => _value = _value.copyWith(fontSize: size),
                    ),
              onChangeEnd: (_) => _save(_value),
            ),
          ),
          IconButton(
            tooltip: '字号增大',
            onPressed: _saving || _value.fontSize >= 32
                ? null
                : () => _save(_value.copyWith(fontSize: _value.fontSize + 2)),
            icon: const Icon(Icons.text_increase, size: 22),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Text('行间距', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            '${_value.lineHeight.toStringAsFixed(1)} 倍',
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
      Slider(
        value: _value.lineHeight,
        min: 1.4,
        max: 2.4,
        divisions: 10,
        semanticFormatterCallback: (value) => '${value.toStringAsFixed(1)} 倍行距',
        onChanged: _saving
            ? null
            : (height) =>
                  setState(() => _value = _value.copyWith(lineHeight: height)),
        onChangeEnd: (_) => _save(_value),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          const Text('段间距', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            '${_value.paragraphSpacing.round()} px',
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
      Slider(
        key: const Key('reader-paragraph-spacing'),
        value: _value.paragraphSpacing,
        min: 0,
        max: 40,
        divisions: 10,
        semanticFormatterCallback: (value) => '${value.round()} 像素段距',
        onChanged: _saving
            ? null
            : (spacing) => setState(
                () => _value = _value.copyWith(paragraphSpacing: spacing),
              ),
        onChangeEnd: _saving ? null : (_) => _save(_value),
      ),
      Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          key: const Key('reader-bold-text'),
          contentPadding: EdgeInsets.zero,
          title: const Text('正文加粗'),
          value: _value.boldText,
          onChanged: _saving
              ? null
              : (bold) => _save(_value.copyWith(boldText: bold)),
        ),
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _value.theme == ReaderTheme.dark
              ? const Color(0xFF242424)
              : _value.theme == ReaderTheme.paper
              ? const Color(0xFFF4F0E6)
              : AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          key: const Key('reader-preview'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < 2; index++) ...[
              if (index > 0) SizedBox(height: _value.paragraphSpacing),
              ReaderParagraph(
                text: index == 0 ? '清风徐来，水波不兴。' : '让文字，慢慢走进心里。',
                style: TextStyle(
                  inherit: false,
                  fontFamily: 'NotoSansSC',
                  fontSize: _value.fontSize,
                  height: _value.lineHeight,
                  fontWeight: _value.boldText
                      ? FontWeight.bold
                      : FontWeight.w400,
                  color: _value.theme == ReaderTheme.dark
                      ? const Color(0xFFE0E0E0)
                      : AppColors.ink,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
