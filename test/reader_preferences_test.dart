import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/domain/reader_style_preset.dart';
import 'package:read_pilot/ui/components/reader_preferences.dart';
import 'package:read_pilot/ui/reader/reader_paragraph.dart';

Future<void> _open(
  WidgetTester tester, {
  ReaderSettings settings = const ReaderSettings(),
  required Future<void> Function(ReaderSettings) onChanged,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ReaderPreferences(settings: settings, onChanged: onChanged),
      ),
    ),
  ),
);

void main() {
  testWidgets('reader preferences persist paged and scrolling flow', (
    tester,
  ) async {
    var settings = const ReaderSettings(flow: ReaderFlow.scrolling);
    await _open(
      tester,
      settings: settings,
      onChanged: (value) async => settings = value,
    );
    expect(find.byKey(const Key('reader-flow-paged')), findsOneWidget);
    expect(find.byKey(const Key('reader-flow-scrolling')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-flow-paged')));
    await tester.pumpAndSettle();
    expect(settings.flow, ReaderFlow.paged);
  });

  testWidgets('paragraph spacing and bold controls save their preferences', (
    tester,
  ) async {
    var saved = const ReaderSettings();
    await _open(tester, onChanged: (value) async => saved = value);
    final spacing = find.byKey(const Key('reader-paragraph-spacing'));
    expect(spacing, findsOneWidget);
    tester.widget<Slider>(spacing).onChanged!(40);
    await tester.pump();
    tester.widget<Slider>(spacing).onChangeEnd!(40);
    await tester.pumpAndSettle();
    expect(saved.paragraphSpacing, 40);
    final bold = find.byKey(const Key('reader-bold-text'));
    await tester.ensureVisible(bold);
    await tester.tap(bold);
    await tester.pumpAndSettle();
    expect(saved.boldText, isTrue);
    expect(saved.paragraphSpacing, 40);
  });

  testWidgets('preview uses two indented paragraphs with saved typography', (
    tester,
  ) async {
    await _open(
      tester,
      settings: const ReaderSettings(paragraphSpacing: 40, boldText: true),
      onChanged: (_) async {},
    );
    final preview = find.byKey(const Key('reader-preview'));
    final paragraphs = find.descendant(
      of: preview,
      matching: find.byType(ReaderParagraph),
    );
    expect(paragraphs, findsNWidgets(2));
    final widgets = tester.widgetList<ReaderParagraph>(paragraphs).toList();
    expect(
      widgets.every(
        (paragraph) => paragraph.style.fontWeight == FontWeight.bold,
      ),
      isTrue,
    );
    final boxes = paragraphs
        .evaluate()
        .map((element) => tester.getRect(find.byWidget(element.widget)))
        .toList();
    expect(boxes[1].top - boxes[0].bottom, closeTo(40, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving disables the new controls until persistence completes', (
    tester,
  ) async {
    final pending = Completer<void>();
    await _open(tester, onChanged: (_) => pending.future);
    final bold = find.byKey(const Key('reader-bold-text'));
    await tester.ensureVisible(bold);
    await tester.tap(bold);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(bold).onChanged, isNull);
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('reader-paragraph-spacing')))
          .onChanged,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(bold).onChanged, isNotNull);
  });

  testWidgets('failed saves restore the latest successful values', (
    tester,
  ) async {
    var fail = false;
    await _open(
      tester,
      onChanged: (_) async {
        if (fail) throw StateError('保存失败');
      },
    );
    final spacing = find.byKey(const Key('reader-paragraph-spacing'));
    tester.widget<Slider>(spacing).onChanged!(40);
    await tester.pump();
    tester.widget<Slider>(spacing).onChangeEnd!(40);
    await tester.pumpAndSettle();
    fail = true;
    final bold = find.byKey(const Key('reader-bold-text'));
    await tester.ensureVisible(bold);
    await tester.tap(bold);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(bold).value, isFalse);
    expect(tester.widget<Slider>(spacing).value, 40);
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preferences render on decorated settings cards', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.white),
              child: ReaderPreferences(
                settings: const ReaderSettings(),
                onChanged: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a save completing after the preferences close is safe', (
    tester,
  ) async {
    final pending = Completer<void>();
    await _open(tester, onChanged: (_) => pending.future);
    final bold = find.byKey(const Key('reader-bold-text'));
    await tester.ensureVisible(bold);
    await tester.tap(bold);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'relaxed preset changes typography without resetting reader mode',
    (tester) async {
      var saved = const ReaderSettings(
        theme: ReaderTheme.dark,
        flow: ReaderFlow.scrolling,
        boldText: true,
      );
      await _open(
        tester,
        settings: saved,
        onChanged: (value) async => saved = value,
      );

      await tester.tap(find.byKey(const Key('reader-preset-relaxed')));
      await tester.pumpAndSettle();

      expect(saved.fontSize, 24);
      expect(saved.lineHeight, 2.1);
      expect(saved.paragraphSpacing, 28);
      expect(saved.theme, ReaderTheme.dark);
      expect(saved.flow, ReaderFlow.scrolling);
      expect(saved.boldText, isTrue);
    },
  );

  testWidgets('named local presets save and apply without theme reset', (
    tester,
  ) async {
    var settings = const ReaderSettings();
    final presets = [
      ReaderStylePreset(
        id: 'night',
        name: '夜读',
        settings: const ReaderSettings(
          theme: ReaderTheme.dark,
          flow: ReaderFlow.scrolling,
          fontSize: 24,
          lineHeight: 2.1,
          paragraphSpacing: 28,
        ),
        createdAt: DateTime.utc(2026),
      ),
    ];
    String? savedName;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReaderPreferences(
              settings: settings,
              onChanged: (value) async => settings = value,
              stylePresets: presets,
              onSaveStylePreset: (name, value) async => savedName = name,
              onDeleteStylePreset: (_) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('reader-style-preset-night')));
    await tester.pumpAndSettle();
    expect(settings.theme, ReaderTheme.dark);
    expect(settings.flow, ReaderFlow.scrolling);

    await tester.tap(find.byKey(const Key('reader-style-preset-add')));
    await tester.pump();
    final name = find.byKey(const Key('reader-style-preset-name'));
    await tester.ensureVisible(name);
    await tester.enterText(name, '当前样式');
    await tester.tap(find.byKey(const Key('reader-style-preset-save')));
    await tester.pumpAndSettle();
    expect(savedName, '当前样式');
    expect(tester.takeException(), isNull);
  });
  testWidgets('local palette preserves unrelated reader preferences', (
    tester,
  ) async {
    var saved = const ReaderSettings(
      flow: ReaderFlow.scrolling,
      fontSize: 26,
      lineHeight: 2.1,
      paragraphSpacing: 28,
      boldText: true,
    );
    await _open(
      tester,
      settings: saved,
      onChanged: (value) async => saved = value,
    );

    final sage = find.byKey(const Key('reader-theme-sage'));
    await tester.ensureVisible(sage);
    await tester.tap(sage);
    await tester.pumpAndSettle();

    expect(saved.theme, ReaderTheme.sage);
    expect(saved.flow, ReaderFlow.scrolling);
    expect(saved.fontSize, 26);
    expect(saved.lineHeight, 2.1);
    expect(saved.paragraphSpacing, 28);
    expect(saved.boldText, isTrue);
  });
  testWidgets('local palette choices wrap on a narrow phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _open(tester, onChanged: (_) async {});

    for (final theme in ReaderTheme.values) {
      expect(find.byKey(Key('reader-theme-${theme.name}')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
