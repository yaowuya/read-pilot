final class BookTextRule {
  const BookTextRule({
    required this.id,
    required this.needle,
    required this.replacement,
    this.enabled = true,
  });

  final String id;
  final String needle;
  final String replacement;
  final bool enabled;

  BookTextRule copyWith({String? needle, String? replacement, bool? enabled}) =>
      BookTextRule(
        id: id,
        needle: needle ?? this.needle,
        replacement: replacement ?? this.replacement,
        enabled: enabled ?? this.enabled,
      );

  factory BookTextRule.fromJson(Map<String, dynamic> json) => BookTextRule(
    id: json['id'] as String,
    needle: json['needle'] as String,
    replacement: json['replacement'] as String,
    enabled: json['enabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'needle': needle,
    'replacement': replacement,
    'enabled': enabled,
  };
}

abstract final class BookTextRules {
  static const maxRulesPerBook = 10;
  static const maxNeedleCharacters = 64;
  static const maxReplacementCharacters = 128;
  static const maxOutputCharacters = 131072;
  static const maxChapterOutputCharacters = 2 * 1024 * 1024;
  static const maxMatchesPerRule = 1024;
  static final _lineBreaks = [
    '\r',
    '\n',
    String.fromCharCode(0x0085),
    String.fromCharCode(0x2028),
    String.fromCharCode(0x2029),
  ];

  static bool _hasLineBreak(String text) =>
      _lineBreaks.any((character) => text.contains(character));

  static void validate(String needle, String replacement) {
    if (needle.trim().isEmpty ||
        needle.length > maxNeedleCharacters ||
        replacement.length > maxReplacementCharacters ||
        _hasLineBreak(needle) ||
        _hasLineBreak(replacement)) {
      throw const FormatException('只支持无换行的字面替换：查找 1–64 字，替换最多 128 字。');
    }
  }

  static String apply(String paragraph, Iterable<BookTextRule> rules) {
    if (paragraph.length > maxOutputCharacters) return paragraph;
    var result = paragraph;
    for (final rule in rules.take(maxRulesPerBook)) {
      if (!rule.enabled ||
          rule.needle.isEmpty ||
          rule.needle.length > maxNeedleCharacters ||
          rule.replacement.length > maxReplacementCharacters ||
          _hasLineBreak(rule.needle) ||
          _hasLineBreak(rule.replacement)) {
        continue;
      }
      var count = 0;
      var offset = 0;
      while (true) {
        final match = result.indexOf(rule.needle, offset);
        if (match < 0) break;
        count++;
        if (count > maxMatchesPerRule) break;
        offset = match + rule.needle.length;
      }
      if (count == 0 || count > maxMatchesPerRule) continue;
      final length =
          result.length +
          count * (rule.replacement.length - rule.needle.length);
      if (length > maxOutputCharacters) continue;
      result = result.replaceAll(rule.needle, rule.replacement);
    }
    return result;
  }

  static List<String> applyChapter(
    List<String> paragraphs,
    Iterable<BookTextRule> rules,
  ) {
    final enabled = rules
        .take(maxRulesPerBook)
        .where((rule) => rule.enabled)
        .toList();
    if (enabled.isEmpty) return paragraphs;
    var rawCharacters = 0;
    for (final paragraph in paragraphs) {
      rawCharacters += paragraph.length;
      if (rawCharacters > maxChapterOutputCharacters) return paragraphs;
    }

    final transformed = <String>[];
    var totalCharacters = 0;
    var changed = false;
    for (final paragraph in paragraphs) {
      final display = apply(paragraph, enabled);
      totalCharacters += display.length;
      if (totalCharacters > maxChapterOutputCharacters) return paragraphs;
      transformed.add(display);
      changed |= display != paragraph;
    }
    return changed ? List<String>.unmodifiable(transformed) : paragraphs;
  }
}
