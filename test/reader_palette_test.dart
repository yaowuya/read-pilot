import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/ui/reader/reader_palette.dart';

void main() {
  test('sage palette is a stable readable local daytime theme', () {
    final palette = ReaderPalette.of(ReaderTheme.sage);

    expect(palette.label, '青苔');
    expect(palette.brightness, Brightness.light);
    expect(palette.background, const Color(0xFFEAF2E6));
    expect(palette.ink, const Color(0xFF29332A));
    expect(palette.muted, const Color(0xFF5E6C60));
  });
  test('mist palette is a stable readable local daytime theme', () {
    final palette = ReaderPalette.of(ReaderTheme.mist);

    expect(palette.label, '晨雾');
    expect(palette.brightness, Brightness.light);
    expect(palette.background, const Color(0xFFEDF2F5));
    expect(palette.ink, const Color(0xFF29313A));
    expect(palette.muted, const Color(0xFF5E6873));
  });
}
