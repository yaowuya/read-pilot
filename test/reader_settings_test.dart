import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/reader_settings.dart';

void main() {
  test('old settings keep original typography and directory defaults', () {
    final json = ReaderSettings.fromJson({}).toJson();
    expect(json['paragraphSpacing'], 20);
    expect(json['boldText'], isFalse);
    expect(json['tocDescending'], isFalse);
    expect(json['fontSize'], 22);
    expect(json['lineHeight'], 1.9);
  });

  test('new preferences survive JSON and existing copyWith changes', () {
    final settings = ReaderSettings.fromJson({
      'theme': 'dark',
      'flow': 'scrolling',
      'fontSize': 26,
      'lineHeight': 2.1,
      'paragraphSpacing': 36,
      'boldText': true,
      'tocDescending': true,
    });
    final json = ReaderSettings.fromJson(
      settings.copyWith(fontSize: 28).toJson(),
    ).toJson();
    expect(json['paragraphSpacing'], 36);
    expect(json['boldText'], isTrue);
    expect(json['tocDescending'], isTrue);
    expect(json['theme'], 'dark');
    expect(json['flow'], 'scrolling');
    expect(json['fontSize'], 28);
    expect(json['lineHeight'], 2.1);
  });

  test(
    'paragraph spacing is bounded and non-finite values use the default',
    () {
      for (final entry in {
        -10.0: 0.0,
        100.0: 40.0,
        double.infinity: 20.0,
        double.negativeInfinity: 20.0,
        double.nan: 20.0,
      }.entries) {
        final settings = ReaderSettings.fromJson({
          'paragraphSpacing': entry.key,
        });
        expect(settings.toJson()['paragraphSpacing'], entry.value);
      }
    },
  );

  test(
    'copyWith updates bounded preferences without dropping existing values',
    () {
      const original = ReaderSettings(
        theme: ReaderTheme.dark,
        flow: ReaderFlow.scrolling,
        fontSize: 26,
        lineHeight: 2,
      );
      final updated = original.copyWith(
        paragraphSpacing: 99,
        boldText: true,
        tocDescending: true,
      );
      expect(updated.paragraphSpacing, 40);
      expect(updated.boldText, isTrue);
      expect(updated.tocDescending, isTrue);
      expect(updated.theme, original.theme);
      expect(updated.flow, original.flow);
      expect(updated.fontSize, original.fontSize);
      expect(updated.lineHeight, original.lineHeight);
      expect(
        updated.copyWith(paragraphSpacing: double.nan).paragraphSpacing,
        20,
      );
      expect(updated.copyWith(paragraphSpacing: -1).paragraphSpacing, 0);
    },
  );

  test('malformed new preference values fall back without enabling flags', () {
    final json = ReaderSettings.fromJson({
      'paragraphSpacing': 'wide',
      'boldText': 'true',
      'tocDescending': 1,
    }).toJson();
    expect(json['paragraphSpacing'], 20);
    expect(json['boldText'], isFalse);
    expect(json['tocDescending'], isFalse);
  });
}
