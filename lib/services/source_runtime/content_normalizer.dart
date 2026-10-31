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

  /// Punctuation stays significant when comparing titles and duplicate text.
  List<String> normalize(
    Iterable<String> input, {
    required String chapterTitle,
  }) {
    final output = <String>[];
    final titleKey = _comparisonKey(chapterTitle);
    String? previousKey;
    for (final raw in input) {
      final lines = _decodeBoundaries(
        raw,
      ).replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n+'));
      for (final line in lines) {
        final text = _trimEdges(line);
        if (text.isEmpty) continue;
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
