/// Applies deterministic, source-agnostic cleanup to extracted chapter text.
final class ContentNormalizer {
  const ContentNormalizer();

  static final _breakTag = RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false);
  static final _entity = RegExp(
    r'&(nbsp|ensp|emsp|thinsp|amp|lt|gt|quot|#160|#x0*a0);',
    caseSensitive: false,
  );
  static final _edgeWhitespace = RegExp(
    r'^[\u0000-    -​  　﻿]+|[\u0000-    -​  　﻿]+$',
  );
  static final _comparisonWhitespace = RegExp(r'[\s   -​  　﻿]+');
  // Many sources indent paragraphs with runs of spaces and no <br>. Splitting on
  // those runs is what turns a flattened blob back into readable paragraphs. Two
  // spaces stay significant mid-sentence, so a gap needs three or a double 　.
  static final _lineBreak = RegExp('\\n+|[ \\t\\u00a0]{3,}|\\u3000{2,}');

  /// Expands one raw block into display paragraphs, preserving their order.
  /// Set [decode] to false for text an earlier extraction already decoded.
  List<String> splitParagraphs(String raw, {bool decode = true}) {
    final blocks = (decode ? _decodeBoundaries(raw) : raw)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(_lineBreak);
    final output = <String>[];
    for (final block in blocks) {
      final text = _trimEdges(block);
      if (text.isNotEmpty) output.add(text);
    }
    return output;
  }

  /// Punctuation stays significant when comparing titles and duplicate text.
  List<String> normalize(
    Iterable<String> input, {
    required String chapterTitle,
  }) {
    final output = <String>[];
    final titleKey = _comparisonKey(chapterTitle);
    String? previousKey;
    for (final raw in input) {
      for (final text in splitParagraphs(raw)) {
        final key = _comparisonKey(text);
        if (output.isEmpty && titleKey.isNotEmpty && key == titleKey) {
          continue;
        }
        if (previousKey == key) continue;
        output.add(text);
        previousKey = key;
      }
    }
    return List.unmodifiable(output);
  }

  static String _decodeBoundaries(String value) => value
      .replaceAll(_breakTag, '\n')
      .replaceAllMapped(_entity, (match) {
        return switch (match[1]!.toLowerCase()) {
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'emsp' => '　',
          _ => ' ',
        };
      })
      .replaceAll(' ', ' ')
      .replaceAll('\t', ' ');

  static String _trimEdges(String value) =>
      value.replaceAll(_edgeWhitespace, '');

  static String _comparisonKey(String value) =>
      _trimEdges(value).toLowerCase().replaceAll(_comparisonWhitespace, ' ');
}
