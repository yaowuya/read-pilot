import 'package:flutter/material.dart';

import '../../domain/reader_settings.dart';
import '../theme.dart';
import 'common.dart';

class ReaderPreferences extends StatefulWidget {
  const ReaderPreferences({
    super.key,
    required this.settings,
    required this.onChanged,
  });
  final ReaderSettings settings;
  final Future<void> Function(ReaderSettings) onChanged;
  @override
  State<ReaderPreferences> createState() => _ReaderPreferencesState();
}

class _ReaderPreferencesState extends State<ReaderPreferences> {
  late ReaderSettings _value = widget.settings;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant ReaderPreferences oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving && widget.settings != oldWidget.settings) {
      _value = widget.settings;
    }
  }

  Future<void> _save(ReaderSettings value) async {
    setState(() {
      _value = value;
      _saving = true;
    });
    try {
      await widget.onChanged(value);
    } catch (error) {
      if (mounted) {
        setState(() => _value = widget.settings);
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
      Row(
        children: [
          for (final theme in ReaderTheme.values)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: theme == ReaderTheme.dark ? 0 : 12,
                ),
                child: Semantics(
                  selected: _value.theme == theme,
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _save(_value.copyWith(theme: theme)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: switch (theme) {
                        ReaderTheme.paper => const Color(0xFFF4F0E6),
                        ReaderTheme.light => Colors.white,
                        ReaderTheme.dark => const Color(0xFF242424),
                      },
                      foregroundColor: theme == ReaderTheme.dark
                          ? const Color(0xFFE6E6E6)
                          : AppColors.ink,
                      side: BorderSide(
                        color: _value.theme == theme
                            ? AppColors.blue
                            : AppColors.line,
                        width: _value.theme == theme ? 2 : 1,
                      ),
                    ),
                    child: Text(switch (theme) {
                      ReaderTheme.paper => '纸张',
                      ReaderTheme.light => '明亮',
                      ReaderTheme.dark => '夜间',
                    }),
                  ),
                ),
              ),
            ),
        ],
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
        child: Text(
          '清风徐来，水波不兴。\n让文字，慢慢走进心里。',
          style: TextStyle(
            fontSize: _value.fontSize,
            height: _value.lineHeight,
            color: _value.theme == ReaderTheme.dark
                ? const Color(0xFFE0E0E0)
                : AppColors.ink,
          ),
        ),
      ),
    ],
  );
}
