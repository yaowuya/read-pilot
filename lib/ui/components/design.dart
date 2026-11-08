import 'package:flutter/material.dart';

import '../theme.dart';

/// Structural widgets transcribed from `docs/阅读助手_完整设计稿.html`.
///
/// The draft repeats a small set of shapes on almost every page: a page title,
/// a section label, a row with a leading icon, a pill search field, a round
/// icon button, an info note and an empty state. Every screen composes those
/// instead of re-deriving padding, radius and font size by hand, so a change
/// in the draft maps to one place here.

/// Page title row: 28 px title with up to three round actions on the right.
class LargeTitle extends StatelessWidget {
  const LargeTitle({
    super.key,
    required this.title,
    this.trailing = const <Widget>[],
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final List<Widget> trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
        for (final action in trailing) ...[const SizedBox(width: 4), action],
      ],
    ),
  );
}

/// Sub-page header: back arrow, centred title and trailing actions.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.onBack,
    this.title = '',
    this.actions = const <Widget>[],
    this.bottom,
  });

  final VoidCallback? onBack;
  final String title;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(52 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    leading: onBack == null
        ? const SizedBox.shrink()
        : CircleIconButton(
            key: const Key('topbar-back'),
            icon: Icons.chevron_left,
            tooltip: '返回',
            onPressed: onBack!,
          ),
    leadingWidth: 56,
    title: Semantics(
      header: true,
      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    actions: [...actions, const SizedBox(width: 8)],
    bottom: bottom,
  );
}

/// Small grey caption that introduces a group of rows.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A leading icon, a title with an optional second line, and a trailing slot.
///
/// Used by 我的, 设置, 详情, 发现 and 书源 so the row rhythm matches the draft.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.iconColor = AppColors.ink,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color iconColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailingText != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                trailingText!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onTap != null && showChevron)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.muted,
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// White rounded container that groups rows, with hairline separators.
class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(height: 1, indent: 46, endIndent: 14),
          children[index],
        ],
      ],
    ),
  );
}

/// Round icon button matching the draft's `.icon-btn`: 44 px target, 22 px
/// glyph, hairline border, optional tinted selected state.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.selected = false,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: selected ? AppColors.softBlue : Colors.white,
        shape: CircleBorder(
          side: BorderSide(
            color: selected ? AppColors.softBlue : AppColors.line,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size * .5,
              color: selected ? AppColors.blue : AppColors.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Search field shaped as the draft's `.search-pill`: 42 px tall, fully
/// rounded, no border colour change on focus, optional trailing widget.
class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.trailing,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        const SizedBox(width: 14),
        const Icon(Icons.search, size: 18, color: AppColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 14, color: AppColors.ink),
            cursorColor: AppColors.blue,
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: hintText,
              hintStyle: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
        ),
        ?trailing,
        if (trailing == null) const SizedBox(width: 14),
      ],
    ),
  );
}

/// Draft `.switch`: 44×26 capsule with a white knob, no Material splash.
class SwitchDot extends StatelessWidget {
  const SwitchDot({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    toggled: value,
    button: true,
    child: GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value ? AppColors.blue : const Color(0xFFD7DAE0),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
  );
}

/// Muted multi-line hint block used under lists ("只读取你主动选择的文件。").
class InfoNote extends StatelessWidget {
  const InfoNote({
    super.key,
    required this.lines,
    this.icon = Icons.info_outline,
  });

  final List<String> lines;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Text(
                  line,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Draft `.empty-state`: round tinted symbol, headline, two-line body, one
/// primary action and one quiet link.
class EmptyBlock extends StatelessWidget {
  const EmptyBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 12 : 28,
      vertical: compact ? 28 : 56,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 64 : 76,
          height: compact ? 64 : 76,
          decoration: const BoxDecoration(
            color: AppColors.softBlue,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: compact ? 28 : 34, color: AppColors.blue),
        ),
        SizedBox(height: compact ? 16 : 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 17 : 21,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.7,
            color: AppColors.muted,
          ),
        ),
        if (primaryLabel != null) ...[
          SizedBox(height: compact ? 20 : 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPrimary,
              child: Text(primaryLabel!),
            ),
          ),
        ],
        if (secondaryLabel case final String label) ...[
          const SizedBox(height: 4),
          TextButton(onPressed: onSecondary, child: Text(label)),
        ],
      ],
    ),
  );
}

/// Rounded white panel used for cards that are more than a list of rows.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.radius = AppRadii.card,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding,
      child: child,
    );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Small filled label ("分类", "仅搜索", "本地 EPUB", "阅读中").
class PillTag extends StatelessWidget {
  const PillTag(
    this.text, {
    super.key,
    this.tone = PillTone.neutral,
    this.icon,
  });

  final String text;
  final PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      PillTone.neutral => (const Color(0xFFF1F2F5), AppColors.muted),
      PillTone.blue => (AppColors.softBlue, AppColors.blue),
      PillTone.green => (AppColors.softGreen, AppColors.green),
      PillTone.danger => (const Color(0xFFFFEFEE), const Color(0xFFC2413B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

enum PillTone { neutral, blue, green, danger }

/// Horizontal set of mutually exclusive options (draft `.segmented`).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.keyOf,
  });

  final List<T> values;
  final String Function(T value) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;
  final Key Function(T value)? keyOf;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F2F5),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        for (final value in values)
          Expanded(
            child: GestureDetector(
              key: keyOf?.call(value),
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: value == selected
                      ? const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labelOf(value),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: value == selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: value == selected ? AppColors.ink : AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
