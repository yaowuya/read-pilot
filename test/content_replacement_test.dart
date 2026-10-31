import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/services/source_runtime/content_replacement.dart';

void main() {
  test('replaces complete chapter text with a safe pattern', () {
    final result = const ContentReplacement().apply('第12章\n广告词\n正文', r'广告词##');
    expect(result, '第12章\n\n正文');
  });

  test('expands capture groups in replacement text', () {
    final result = const ContentReplacement().apply('第12章', r'第(\d+)章##章节-$1');
    expect(result, '章节-12');
  });

  test('rejects unsafe empty matching patterns', () {
    expect(
      () => const ContentReplacement().apply('正文', r'.*##'),
      throwsFormatException,
    );
  });

  test('input limits report UTF-16 units rather than bytes', () {
    expect(
      () => const ContentReplacement().apply(
        '文' * (ContentReplacement.maxInputCharacters + 1),
        '广告##',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('UTF-16'),
        ),
      ),
    );
  });

  test('rejects excessive output without silently truncating', () {
    expect(
      () => const ContentReplacement().apply('a' * 600, 'a##${'字' * 4096}'),
      throwsFormatException,
    );
  });

  test('rejects excessive matches without silently truncating', () {
    expect(
      () => const ContentReplacement().apply(
        'a' * (ContentReplacement.maxMatches + 1),
        'a##b',
      ),
      throwsFormatException,
    );
  });

  test('rejects rules without a pattern separator', () {
    expect(
      () => const ContentReplacement().apply('正文', '广告词'),
      throwsFormatException,
    );
  });
}
