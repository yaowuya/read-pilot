import '../../domain/source_rule_support.dart';

/// Applies one bounded whole-chapter cleanup rule to complete chapter text.
///
/// Accepted forms (Legado-observable):
/// - `pattern##replacement` — replace matches
/// - `pattern##` — delete matches
/// - `##pattern` — delete matches (empty selector + pattern)
/// - `##pattern##replacement` — replace matches
final class ContentReplacement {
  const ContentReplacement();

  static const maxInputCharacters = 256 * 1024;
  static const maxOutputCharacters = 2 * 1024 * 1024;
  static const maxMatches = 10000;

  static bool isSupported(String rule) =>
      SourceRuleSupport.isSafeContentReplacement(rule);

  /// Returns a complete result or throws; never publishes truncated output.
  String apply(String input, String rule) {
    final parsed = SourceRuleSupport.parseContentReplacement(rule);
    if (parsed == null ||
        !SourceRuleSupport.isSafeRegex(parsed.pattern, parsed.replacement)) {
      throw const FormatException('replaceRegex 必须使用安全的“正则##替换文本”格式。');
    }
    if (input.length > maxInputCharacters) {
      throw const FormatException(
        'replaceRegex 输入超过 262144 个 UTF-16 代码单元安全限制。',
      );
    }

    final expression = RegExp(parsed.pattern);
    final replacement = parsed.replacement;
    final output = StringBuffer();
    var cursor = 0;
    var count = 0;

    void write(String value) {
      if (output.length + value.length > maxOutputCharacters) {
        throw const FormatException('replaceRegex 结果超过安全限制。');
      }
      output.write(value);
    }

    for (final match in expression.allMatches(input)) {
      if (++count > maxMatches) {
        throw const FormatException('replaceRegex 匹配次数超过安全限制。');
      }
      write(input.substring(cursor, match.start));
      write(
        replacement.replaceAllMapped(RegExp(r'\$(\d+)'), (reference) {
          final group = int.parse(reference[1]!);
          return group <= match.groupCount ? match.group(group) ?? '' : '';
        }),
      );
      cursor = match.end;
    }
    write(input.substring(cursor));
    return output.toString();
  }
}
