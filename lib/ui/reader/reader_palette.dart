import 'package:flutter/material.dart';

import '../../domain/reader_settings.dart';

/// Fixed reader colors are local, curated, and never sourced from the device.
final class ReaderPalette {
  const ReaderPalette._({
    required this.label,
    required this.brightness,
    required this.background,
    required this.ink,
    required this.muted,
    required this.errorBackground,
    required this.errorInk,
  });

  final String label;
  final Brightness brightness;
  final Color background;
  final Color ink;
  final Color muted;
  final Color errorBackground;
  final Color errorInk;

  bool get isDark => brightness == Brightness.dark;

  static const _paper = ReaderPalette._(
    label: '纸张',
    brightness: Brightness.light,
    background: Color(0xFFF4EFDC),
    ink: Color(0xFF34332F),
    muted: Color(0xFF6E6B62),
    errorBackground: Color(0xFFFFEDEA),
    errorInk: Color(0xFF831C1E),
  );
  static const _light = ReaderPalette._(
    label: '明亮',
    brightness: Brightness.light,
    background: Color(0xFFFEFEFC),
    ink: Color(0xFF34332F),
    muted: Color(0xFF6E6B62),
    errorBackground: Color(0xFFFFEDEA),
    errorInk: Color(0xFF831C1E),
  );
  // 设计稿指定的夜间配色（背景 #202225 / 正文 #C3C0B8）。
  static const _dark = ReaderPalette._(
    label: '夜间',
    brightness: Brightness.dark,
    background: Color(0xFF202225),
    ink: Color(0xFFC3C0B8),
    muted: Color(0xFF8B8D8F),
    errorBackground: Color(0xFF2C1A20),
    errorInk: Color(0xFFE5566F),
  );
  static const _sage = ReaderPalette._(
    label: '青苔',
    brightness: Brightness.light,
    background: Color(0xFFEAF2E6),
    ink: Color(0xFF29332A),
    muted: Color(0xFF5E6C60),
    errorBackground: Color(0xFFFDEBEC),
    errorInk: Color(0xFF8B1C25),
  );
  static const _mist = ReaderPalette._(
    label: '晨雾',
    brightness: Brightness.light,
    background: Color(0xFFEDF2F5),
    ink: Color(0xFF29313A),
    muted: Color(0xFF5E6873),
    errorBackground: Color(0xFFFDEBEC),
    errorInk: Color(0xFF8B1C25),
  );

  static ReaderPalette of(ReaderTheme theme) => switch (theme) {
    ReaderTheme.paper => _paper,
    ReaderTheme.light => _light,
    ReaderTheme.dark => _dark,
    ReaderTheme.sage => _sage,
    ReaderTheme.mist => _mist,
  };
}
