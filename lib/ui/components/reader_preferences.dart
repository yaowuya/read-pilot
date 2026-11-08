import 'package:flutter/material.dart';

import '../../domain/reader_settings.dart';
import '../../domain/reader_style_preset.dart';
import '../reader/reader_palette.dart';
import '../reader/reader_paragraph.dart';
import '../theme.dart';
import 'common.dart';

/// Reading settings sheet following the draft: brightness, size, family,
/// leading, background and page-turn rows, then local style presets and a
/// live preview.
///
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

  /// Panel-local only: [ReaderSettings] has no brightness field, so this never
  /// leaves the sheet.
  double _brightness = 90;

  /// Panel-local only: the preview family is not part of the saved settings.
  bool _serif = false;

  /// Draft background order: paper-white, cream, eye-care, mist, night.
  static const _themeOrder = <ReaderTheme>[
    ReaderTheme.light,
    ReaderTheme.paper,
    ReaderTheme.sage,
    ReaderTheme.mist,
    ReaderTheme.dark,
  ];

  /// Draft leading presets keyed for tests.
  static const _leadings = <({String key, String label, double lineHeight})>[
    (key: 'reader-leading-compact', label: '紧凑', lineHeight: 1.6),
    (key: 'reader-leading-comfort', label: '舒适', lineHeight: 1.95),
    (key: 'reader-leading-loose', label: '宽松', lineHeight: 2.3),
  ];

  /// Draft swatch aliases; only themes whose enum name differs from the
  /// draft name need one, otherwise the alias would duplicate the key.
  static const _themeAliases = <ReaderTheme, String>{
    ReaderTheme.light: 'reader-theme-white',
    ReaderTheme.sage: 'reader-theme-green',
    ReaderTheme.dark: 'reader-theme-night',
  };

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

  @override
  void didUpdateWidget(covariant ReaderPreferences oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving && widget.settings != oldWidget.settings) {
      _value = widget.settings;
      _savedValue = widget.settings;
    }
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

  void _setBrightness(double value) => setState(() => _brightness = value);

  void _setSerif(bool serif) => setState(() => _serif = serif);

  double get _nearestLeading {
    var nearest = _leadings.first.lineHeight;
    for (final leading in _leadings) {
      if ((leading.lineHeight - _value.lineHeight).abs() <
          (nearest - _value.lineHeight).abs()) {
        nearest = leading.lineHeight;
      }
    }
    return nearest;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          const Text('阅读设置', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            _saving ? '保存中…' : '自动保存',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
      // 背景放在首位：设置面板本身位于若干功能项之后，只有靠前才不至于
      // 在窄屏/矮窗口里落到折叠线以下（读者最常调的就是这一行）。
      _themeRow(),
      _brightnessRow(),
      _fontSizeRow(),
      _fontFamilyRow(),
      _leadingRow(),
      _flowRow(),
      const SizedBox(height: 10),
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
        const SizedBox(height: 8),
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
      Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          key: const Key('reader-bold-text'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('正文加粗'),
          value: _value.boldText,
          onChanged: _saving
              ? null
              : (bold) => _save(_value.copyWith(boldText: bold)),
        ),
      ),
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
      const SizedBox(height: 8),
      _preview(),
      const SizedBox(height: 14),
      const Text(
        '排版随手调整，设置会自动记住。',
        style: TextStyle(fontSize: 10, height: 1.8, color: Color(0xFFA9AFBA)),
      ),
    ],
  );

  // ---------------------------------------------------------------- 亮度

  Widget _brightnessRow() => _SettingRow(
    label: '亮度',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.brightness_low,
              size: 18,
              color: Color(0xFF9DA5AF),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                ),
                child: Slider(
                  key: const Key('reader-brightness'),
                  value: _brightness,
                  min: 65,
                  max: 100,
                  divisions: 7,
                  semanticFormatterCallback: (value) =>
                      '阅读观感亮度 ${value.round()}',
                  onChanged: _setBrightness,
                ),
              ),
            ),
            const Icon(
              Icons.brightness_high,
              size: 18,
              color: Color(0xFF9DA5AF),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(left: 26, right: 26),
          child: Text(
            '调节仅影响本次预览',
            style: TextStyle(fontSize: 9, color: Color(0xFFA9AFBA)),
          ),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------- 字号

  Widget _fontSizeRow() => _SettingRow(
    label: '字号',
    child: _Stepper(
      key: const Key('reader-font-size'),
      decreaseLabel: 'A−',
      valueLabel: '${_value.fontSize.round()}',
      increaseLabel: 'A＋',
      onDecrease: _saving || _value.fontSize <= 18
          ? null
          : () => _save(_value.copyWith(fontSize: _value.fontSize - 2)),
      onIncrease: _saving || _value.fontSize >= 32
          ? null
          : () => _save(_value.copyWith(fontSize: _value.fontSize + 2)),
    ),
  );

  // ---------------------------------------------------------------- 字体

  Widget _fontFamilyRow() => _SettingRow(
    label: '字体',
    child: _Segmented(
      children: [
        _Segment(
          controlKey: const Key('reader-font-serif'),
          label: '阅读宋体',
          selected: _serif,
          onTap: _saving ? null : () => _setSerif(true),
        ),
        _Segment(
          controlKey: const Key('reader-font-sans'),
          label: '系统黑体',
          selected: !_serif,
          onTap: _saving ? null : () => _setSerif(false),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------- 行距

  Widget _leadingRow() => _SettingRow(
    label: '行距',
    child: _Segmented(
      children: [
        for (final leading in _leadings)
          _Segment(
            controlKey: Key(leading.key),
            label: leading.label,
            selected: (_nearestLeading - leading.lineHeight).abs() < .01,
            onTap: _saving
                ? null
                : () => _save(_value.copyWith(lineHeight: leading.lineHeight)),
          ),
      ],
    ),
  );

  // ---------------------------------------------------------------- 背景

  Widget _themeRow() => _SettingRow(
    label: '背景',
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final theme in _themeOrder)
          _ThemeSwatch(
            theme: theme,
            active: _value.theme == theme,
            alias: _themeAliases[theme],
            onTap: _saving ? null : () => _save(_value.copyWith(theme: theme)),
          ),
      ],
    ),
  );

  // ---------------------------------------------------------------- 翻页

  Widget _flowRow() => _SettingRow(
    label: '翻页',
    child: _Segmented(
      children: [
        _Segment(
          controlKey: const Key('reader-flow-tap'),
          innerKey: const Key('reader-flow-paged'),
          label: '点击翻页',
          selected: _value.flow == ReaderFlow.paged,
          onTap: _saving
              ? null
              : () => _save(_value.copyWith(flow: ReaderFlow.paged)),
        ),
        _Segment(
          controlKey: const Key('reader-flow-scroll'),
          innerKey: const Key('reader-flow-scrolling'),
          label: '上下滚动',
          selected: _value.flow == ReaderFlow.scrolling,
          onTap: _saving
              ? null
              : () => _save(_value.copyWith(flow: ReaderFlow.scrolling)),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------- 预览

  Widget _preview() {
    final palette = ReaderPalette.of(_value.theme);
    final dark = palette.isDark;
    final dim = ((100 - _brightness) / 100 * .5).clamp(0.0, .5);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
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
                      fontFamily: _serif ? 'Songti SC' : 'NotoSansSC',
                      fontSize: _value.fontSize,
                      height: _value.lineHeight,
                      fontWeight: _value.boldText
                          ? FontWeight.bold
                          : FontWeight.w400,
                      color: dark ? const Color(0xFFE0E0E0) : AppColors.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (dim > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
              ),
            ),
        ],
      ),
    );
  }
}

/// One draft setting row: a right-aligned control after a faint label.
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF7E8794)),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: child),
      ],
    ),
  );
}

/// Filled stepper matching `.font-stepper`.
class _Stepper extends StatelessWidget {
  const _Stepper({
    super.key,
    required this.decreaseLabel,
    required this.valueLabel,
    required this.increaseLabel,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String decreaseLabel;
  final String valueLabel;
  final String increaseLabel;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    decoration: BoxDecoration(
      color: const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onDecrease,
            child: Center(
              child: Text(
                decreaseLabel,
                style: TextStyle(
                  fontSize: 17,
                  color: onDecrease == null
                      ? const Color(0xFFC6CBD3)
                      : const Color(0xFF747D8A),
                ),
              ),
            ),
          ),
        ),
        Text(
          valueLabel,
          style: const TextStyle(fontSize: 13, color: Color(0xFF576170)),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onIncrease,
            child: Center(
              child: Text(
                increaseLabel,
                style: TextStyle(
                  fontSize: 17,
                  color: onIncrease == null
                      ? const Color(0xFFC6CBD3)
                      : const Color(0xFF747D8A),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Segmented control matching `.segmented`.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.children});

  final List<_Segment> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F5F8),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [for (final child in children) Expanded(child: child)],
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.controlKey,
    required this.label,
    required this.selected,
    required this.onTap,
    this.innerKey,
  });

  final Key controlKey;
  final Key? innerKey;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: selected ? const Color(0xFF414E61) : const Color(0xFF89919D),
      ),
    );
    return GestureDetector(
      key: controlKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x0A223348),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: innerKey == null
              ? text
              : KeyedSubtree(key: innerKey, child: text),
        ),
      ),
    );
  }
}

/// One draft background swatch: the palette circle plus its draft alias key.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.active,
    required this.onTap,
    this.alias,
  });

  final ReaderTheme theme;
  final bool active;
  final VoidCallback? onTap;
  final String? alias;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(theme);
    final circle = Container(
      width: 43,
      height: 43,
      decoration: BoxDecoration(
        color: palette.background,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? AppColors.blue : const Color(0xFFE8E9EA),
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.blue.withValues(alpha: .18),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: active
          ? const Icon(Icons.check, size: 19, color: AppColors.blue)
          : null,
    );
    final swatch = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: 5),
        Text(
          palette.label,
          style: TextStyle(
            fontSize: 9,
            color: active ? AppColors.blue : const Color(0xFFA0A7B1),
          ),
        ),
      ],
    );
    return Semantics(
      label: '阅读背景 ${palette.label}',
      selected: active,
      button: true,
      child: GestureDetector(
        key: Key('reader-theme-${theme.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: alias == null
            ? swatch
            : KeyedSubtree(key: Key(alias!), child: swatch),
      ),
    );
  }
}
