import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/explore_kind.dart';
import '../theme.dart';

/// 发现分类按钮的底片。
const _chipFill = Color(0xFFF0F1F4);

/// 发现页里一条书源的分类行。
///
/// legado 的发现页把书源自己的 [ExploreKind] 渲染成一行可点击的格子：
/// `url` 类的格子进入该分类的书籍列表，`text`/`toggle`/`select` 类先在原地
/// 收集取值，`button` 类执行书源声明的动作。收集到的取值按分类标题存进书源
/// 自己的信息表，下一次请求作为变量发出去。
class ExploreKindRow extends StatefulWidget {
  const ExploreKindRow({
    super.key,
    required this.source,
    required this.kinds,
    required this.values,
    required this.onOpen,
    required this.onButton,
    required this.onValueChanged,
  });

  final String source;
  final List<ExploreKind> kinds;
  final Map<String, String> values;
  final ValueChanged<ExploreKind> onOpen;
  final ValueChanged<ExploreKind> onButton;
  final void Function(ExploreKind kind, String value) onValueChanged;

  /// 一行最多几个格子；legado 按屏宽取 2–4。
  static int maxSpanFor(double width) {
    if (width >= 620) return 4;
    if (width >= 420) return 3;
    return 2;
  }

  @override
  State<ExploreKindRow> createState() => _ExploreKindRowState();
}

class _ExploreKindRowState extends State<ExploreKindRow> {
  final _textControllers = <String, TextEditingController>{};
  final _debounces = <String, Timer>{};

  @override
  void dispose() {
    for (final timer in _debounces.values) {
      timer.cancel();
    }
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(ExploreKind kind) =>
      _textControllers.putIfAbsent(
        kind.key,
        () => TextEditingController(
          text: widget.values[kind.title] ?? kind.defaultValue ?? '',
        ),
      );

  void _onTextChanged(ExploreKind kind, String value) {
    _debounces[kind.key]?.cancel();
    // legado 的文本项也是防抖 600ms 再写库，避免每敲一个字都落盘。
    _debounces[kind.key] = Timer(
      const Duration(milliseconds: 600),
      () => widget.onValueChanged(kind, value),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final maxSpan = ExploreKindRow.maxSpanFor(constraints.maxWidth);
      const spacing = 10.0;
      final unit = (constraints.maxWidth - spacing * (maxSpan - 1)) / maxSpan;
      return Wrap(
        spacing: spacing,
        runSpacing: 10,
        children: [
          for (final kind in widget.kinds)
            SizedBox(
              width:
                  unit * kind.style.spanFor(maxSpan).clamp(1, maxSpan) +
                  spacing * (kind.style.spanFor(maxSpan).clamp(1, maxSpan) - 1),
              child: _buildKind(kind),
            ),
        ],
      );
    },
  );

  Widget _buildKind(ExploreKind kind) {
    if (kind.isError) return _errorTile(kind);
    switch (kind.type) {
      case ExploreKindType.url:
        return _tapTile(
          key: ValueKey('explore-kind-${widget.source}-${kind.title}'),
          label: kind.title,
          onTap: () => widget.onOpen(kind),
        );
      case ExploreKindType.button:
        return _tapTile(
          key: ValueKey('explore-kind-${widget.source}-${kind.title}'),
          label: kind.title,
          filled: true,
          onTap: () => widget.onButton(kind),
        );
      case ExploreKindType.toggle:
        return _toggleTile(kind);
      case ExploreKindType.select:
        return _selectTile(kind);
      case ExploreKindType.text:
        return _textTile(kind);
    }
  }

  Widget _tapTile({
    required Key key,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) => Material(
    key: key,
    color: filled ? AppColors.ink : _chipFill,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: filled ? Colors.white : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _errorTile(ExploreKind kind) => Material(
    key: ValueKey('explore-kind-${widget.source}-error'),
    color: const Color(0xFFFDECEC),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => widget.onButton(kind),
      child: SizedBox(
        height: 46,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '分类规则有误',
              style: const TextStyle(fontSize: 13, color: Color(0xFFB54444)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _toggleTile(ExploreKind kind) {
    // legado 的初始值是 `infoMap[title] ?: default ?: chars.first()`
    // （`ToggleTypeItem`），没有保存过取值时也要先把首个候选值显示出来。
    final value =
        widget.values[kind.title] ??
        kind.defaultValue ??
        (kind.cycleValues.isEmpty ? '' : kind.cycleValues.first);
    // legado 把当前值拼在标题旁边，点一下轮到下一个候选值；拼在标题前还是后
    // 由 layout_justifySelf 决定。
    final left = kind.style.justifySelf != 'right';
    final label = value.isEmpty
        ? kind.title
        : (left ? '$value${kind.title}' : '${kind.title}$value');
    return _tapTile(
      key: ValueKey('explore-kind-${widget.source}-${kind.title}'),
      label: label,
      onTap: () {
        final options = kind.cycleValues;
        final index = options.indexOf(value);
        // legado: `if (currentIndex < 0) 0 else (currentIndex + 1) % chars.size`
        final next = options[index < 0 ? 0 : (index + 1) % options.length];
        widget.onValueChanged(kind, next);
      },
    );
  }

  Widget _selectTile(ExploreKind kind) {
    // legado: `val displayText = "${state.displayName} $selected"`，
    // 初始值是 `infoMap[title] ?: default ?: chars.first()`。
    final value =
        widget.values[kind.title] ??
        kind.defaultValue ??
        (kind.cycleValues.isEmpty ? '' : kind.cycleValues.first);
    final label = value.isEmpty ? kind.title : '${kind.title} $value';
    return PopupMenuButton<String>(
      key: ValueKey('explore-kind-${widget.source}-${kind.title}'),
      tooltip: kind.title,
      onSelected: (next) => widget.onValueChanged(kind, next),
      itemBuilder: (context) => [
        for (final option in kind.cycleValues)
          PopupMenuItem<String>(value: option, child: Text(option)),
      ],
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: _chipFill,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: AppColors.ink),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _textTile(ExploreKind kind) => Container(
    key: ValueKey('explore-kind-${widget.source}-${kind.title}'),
    height: 46,
    decoration: BoxDecoration(
      color: _chipFill,
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Center(
      child: TextField(
        key: ValueKey('explore-kind-input-${widget.source}-${kind.title}'),
        controller: _controllerFor(kind),
        onChanged: (value) => _onTextChanged(kind, value),
        onSubmitted: (value) {
          _debounces[kind.key]?.cancel();
          widget.onValueChanged(kind, value);
        },
        style: const TextStyle(fontSize: 14, color: AppColors.ink),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: kind.title,
          hintStyle: const TextStyle(fontSize: 14, color: AppColors.muted),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ),
  );
}
