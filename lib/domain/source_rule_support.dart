/// Static classifier shared by capability reporting and the rule interpreter.
class SourceRuleSupport {
  const SourceRuleSupport._();

  static bool isSafeRegex(String pattern, String replacement) {
    if (pattern.isEmpty ||
        pattern.length > 256 ||
        replacement.length > 4096 ||
        pattern.contains('|') ||
        pattern.contains('{') ||
        RegExp(r'\(\?').hasMatch(pattern) ||
        RegExp(r'\\[1-9]').hasMatch(pattern) ||
        RegExp(r'\([^)]*\)[*+?{]').hasMatch(pattern) ||
        RegExp(r'[*+?}]\s*[*+?{]').hasMatch(pattern)) {
      return false;
    }
    var unboundedQuantifiers = 0;
    var escaped = false;
    var inClass = false;
    for (final code in pattern.codeUnits) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x5b) {
        inClass = true;
      } else if (code == 0x5d) {
        inClass = false;
      } else if (!inClass && code == 0x3f) {
        return false;
      } else if (!inClass && (code == 0x2a || code == 0x2b)) {
        unboundedQuantifiers++;
      }
    }
    if (unboundedQuantifiers > 1) return false;
    try {
      return !RegExp(pattern).hasMatch('');
    } on FormatException {
      return false;
    }
  }

  static bool isSafeRegexRule(String rule) {
    var foundRegex = false;
    for (final rawBranch in _splitTopLevelFallbacks(rule)) {
      final parts = _regexParts(rawBranch);
      final pattern = parts.pattern;
      if (pattern == null) continue;
      foundRegex = true;
      if (parts.baseRule.isEmpty || !isSafeRegex(pattern, parts.replacement)) {
        return false;
      }
    }
    return foundRegex;
  }

  static bool containsXPathBranch(String rule) =>
      _splitTopLevelFallbacks(rule).any(_looksLikeXPath);

  static bool isSafeXPath(String rule) {
    final branches = _splitTopLevelFallbacks(rule);
    if (branches.length > 1) {
      var foundXPath = false;
      for (final branch in branches) {
        if (!_looksLikeXPath(branch)) continue;
        foundXPath = true;
        if (!isSafeXPath(branch)) return false;
      }
      return foundXPath;
    }
    var path = _regexParts(rule).baseRule
        .replaceFirst(RegExp(r'^@xpath:', caseSensitive: false), '')
        .trim();
    if (path.isEmpty || path.length > 4096) return false;
    if (path.contains('|') || path.contains('::') || path.contains('..')) {
      return false;
    }
    if (RegExp(
      r'\[(?:-?\d+|last\(\))\](?:\[[^\]]+\])*\[(?:-?\d+|last\(\))\]',
      caseSensitive: false,
    ).hasMatch(path)) {
      return false;
    }
    for (final match in RegExp(r'([A-Za-z_][\w-]*)\s*\(').allMatches(path)) {
      if (!{'contains', 'text', 'last'}.contains(match[1]!.toLowerCase())) {
        return false;
      }
    }
    final predicates = RegExp(r'\[([^\]]*)\]').allMatches(path).toList();
    if (RegExp(r'\[').allMatches(path).length != predicates.length ||
        RegExp(r'\]').allMatches(path).length != predicates.length) {
      return false;
    }
    for (final match in predicates) {
      final predicate = match[1]!.trim();
      final position = int.tryParse(predicate);
      final valid =
          (position != null && position > 0) ||
          predicate.toLowerCase() == 'last()' ||
          RegExp(
            r'''^@[A-Za-z_][\w:.-]*\s*=\s*["'][^"']*["']$''',
          ).hasMatch(predicate) ||
          RegExp(
            r'''^contains\(\s*@[A-Za-z_][\w:.-]*\s*,\s*["'][^"']*["']\s*\)$''',
            caseSensitive: false,
          ).hasMatch(predicate);
      if (!valid) return false;
    }
    path = path
        .replaceFirst(RegExp(r'/text\(\)$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'/@[A-Za-z_][\w:.-]*$'), '');
    return RegExp(
      r'''^(?:\.?//?|/)?(?:[A-Za-z_*][\w-]*(?:\[[^\]]+\])*)(?:(?://|/)[A-Za-z_*][\w-]*(?:\[[^\]]+\])*)*$''',
    ).hasMatch(path);
  }

  static ({String baseRule, String? pattern, String replacement}) _regexParts(
    String rawBranch,
  ) {
    final branch = rawBranch.contains('##')
        ? rawBranch.trimLeft()
        : rawBranch.trim();
    final first = branch.indexOf('##');
    if (first < 0) {
      return (baseRule: branch, pattern: null, replacement: '');
    }
    final second = branch.indexOf('##', first + 2);
    return (
      baseRule: branch.substring(0, first),
      pattern: second < 0
          ? branch.substring(first + 2)
          : branch.substring(first + 2, second),
      replacement: second < 0 ? '' : branch.substring(second + 2),
    );
  }

  static bool _looksLikeXPath(String rule) {
    final value = _regexParts(rule).baseRule.trimLeft().toLowerCase();
    return value.startsWith('@xpath:') ||
        value.startsWith('/') ||
        value.startsWith('.//');
  }

  static List<String> _splitTopLevelFallbacks(String input) {
    final parts = <String>[];
    var start = 0;
    var parentheses = 0;
    var brackets = 0;
    var braces = 0;
    int? quote;
    var escaped = false;
    for (var index = 0; index < input.length; index++) {
      final code = input.codeUnitAt(index);
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == quote) {
          quote = null;
        }
        continue;
      }
      if (code == 0x22 || code == 0x27) {
        quote = code;
        continue;
      }
      if (code == 0x28) {
        parentheses++;
      } else if (code == 0x29 && parentheses > 0) {
        parentheses--;
      } else if (code == 0x5b) {
        brackets++;
      } else if (code == 0x5d && brackets > 0) {
        brackets--;
      } else if (code == 0x7b) {
        braces++;
      } else if (code == 0x7d && braces > 0) {
        braces--;
      }
      if (parentheses == 0 &&
          brackets == 0 &&
          braces == 0 &&
          input.startsWith('||', index)) {
        parts.add(input.substring(start, index));
        index++;
        start = index + 1;
      }
    }
    parts.add(input.substring(start));
    return parts;
  }
}
