/// Static classifier shared by capability reporting and the rule interpreter.
class SourceRuleSupport {
  const SourceRuleSupport._();

  /// 正则是否在安全子集内。
  ///
  /// 这里从「拒绝一切复杂写法」改成「只拒绝真正危险的形状」：真实书源的清洗
  /// 规则大量使用 `|`、`{n,m}` 和多个 `.*`（例如
  /// `<script.*?</script>|…[^<]*<br[^>]*>[\s\S]*|本章没完[\s\S]*`），按老规则会
  /// 被整体判死，导致整章读不出来。仍然拦住的：反向引用、后行断言、嵌套的无界
  /// 量词（`(a+)+`）、被量词修饰的含 `|` 分组（`(a|a)+`）、重复量词（`a**`）、
  /// 一个分支里多于两个通配无界量词（`.*.*.*=`、`.*a.*a.*=`）、相邻的通配无界
  /// 量词（`.*.*`）、能匹配空串、以及超长表达式。输入本身另有 256 KiB 上限，见
  /// `ContentReplacement.maxInputCharacters`。
  static bool isSafeRegex(String pattern, String replacement) {
    if (pattern.isEmpty || pattern.length > 4096 || replacement.length > 4096) {
      return false;
    }
    // 反向引用与后行断言：易被用来构造回溯爆炸，且真实书源几乎不用。
    if (RegExp(r'\\[1-9]').hasMatch(pattern)) return false;
    if (RegExp(r'\(\?<[=!]').hasMatch(pattern)) return false;
    // 重复量词，例如 a** / a*+ / a+?
    if (RegExp(r'[*+?}]\s*[*+{]').hasMatch(pattern)) return false;
    if (!_hasBoundedRepetitions(pattern)) return false;
    try {
      return !RegExp(pattern).hasMatch('');
    } on FormatException {
      return false;
    }
  }

  /// 允许的量词个数上限。回溯爆炸需要大量可选分支，例如
  /// `a?a?a?…ab` 这种「20 个以上并列选择」才会真正卡住；
  /// 真实书源的清洗规则远低于这个量级。
  static const _maxRepetitions = 25;

  /// 一个分支里允许几个「通配无界量词」（`.*`、`.+`、`[\s\S]*` 这类能吃掉任意
  /// 字符的无界量词）。
  ///
  /// 每多一个就多乘一层回溯：`.*.*.*=`、`.*?a.*?a.*=` 在 2 000 字符上已经跑不
  /// 完，而正文上限是 256 KiB。真实书源的清洗规则至多出现两个
  /// （`[\s\S]*?<br[^>]*>[\s\S]*`、`.*?正文.*`），所以卡在 2。
  static const _maxWildcardRepetitions = 2;

  /// 相邻（中间没隔任何别的原子）的通配无界量词上限：`.*.*` 是纯回溯，
  /// 没有任何正收益，直接判死。
  static const _maxAdjacentWildcardRepetitions = 1;

  /// 能匹配任意字符的字符类写法（去掉空白后比较）。
  static const _wildcardClasses = {
    r'\s\S',
    r'\S\s',
    r'\d\D',
    r'\D\d',
    r'\w\W',
    r'\W\w',
  };

  /// 拒绝「无界量词套无界量词」（`(a+)+`）、「含 `|` 的分组再被无界量词修饰」
  /// （`(a|a)+`）、并列或过多的通配无界量词（`.*.*`、`.*.*.*=`、
  /// `.*a.*a.*=`）以及量词数量超过 [_maxRepetitions] 的表达式。
  static bool _hasBoundedRepetitions(String pattern) {
    final stack = <({int repetitions, bool unbounded, bool alternation})>[];
    var repetitions = 0;

    // 当前分支里的通配无界量词总数，以及连续出现的个数。新分支（`|`）重新计数，
    // 因为回溯是按分支独立进行的。
    var wildcards = 0;
    var adjacentWildcards = 0;

    // 最近一个原子的信息：是否通配，以及它结束在哪。只有「量词紧跟在原子后面」
    // 才算量词修饰了那个原子，`.*` 的 `*` 才算通配无界量词。
    var atomWildcard = false;
    var atomEnd = -1;

    var escaped = false;
    var inClass = false;
    var classStart = 0;

    bool tooManyWildcards() =>
        wildcards > _maxWildcardRepetitions ||
        adjacentWildcards > _maxAdjacentWildcardRepetitions;

    for (var index = 0; index < pattern.length; index++) {
      final code = pattern.codeUnitAt(index);

      if (escaped) {
        escaped = false;
        // 转义原子（`\s`、`\.`、`\n`）都不通配。
        atomWildcard = false;
        atomEnd = index;
        continue;
      }
      if (code == 0x5c) {
        escaped = true;
        continue;
      }
      if (inClass) {
        if (code == 0x5d) {
          inClass = false;
          final body = pattern
              .substring(classStart + 1, index)
              .replaceAll(RegExp(r'\s+'), '');
          atomWildcard = _wildcardClasses.contains(body);
          atomEnd = index;
        }
        continue;
      }
      if (code == 0x5b) {
        inClass = true;
        classStart = index;
        atomWildcard = false;
        atomEnd = -1;
        continue;
      }
      if (code == 0x28) {
        stack.add((repetitions: 0, unbounded: false, alternation: false));
        atomWildcard = false;
        atomEnd = -1;
        continue;
      }
      if (code == 0x29) {
        if (stack.isEmpty) return false;
        final group = stack.removeLast();
        final next = index + 1 < pattern.length
            ? pattern.codeUnitAt(index + 1)
            : -1;
        // `*` `+` `{n,}` 是无界的；`?` 与 `{n,m}` 是有界的，不算危险。
        final unboundedNext = next == 0x2a || next == 0x2b || next == 0x7b;
        if (unboundedNext && group.unbounded) return false;
        if (unboundedNext && group.alternation) return false;
        final closedRepetitions =
            group.repetitions + (unboundedNext || next == 0x3f ? 1 : 0);
        if (stack.isNotEmpty) {
          final parent = stack.last;
          stack[stack.length - 1] = (
            repetitions: parent.repetitions + closedRepetitions,
            unbounded: parent.unbounded || group.unbounded || unboundedNext,
            alternation: parent.alternation || group.alternation,
          );
        }
        // 分组本身按非通配原子算：`(?:.|\n)*` 这类已被上面的规则挡掉。
        atomWildcard = false;
        atomEnd = index;
        continue;
      }
      if (code == 0x7c) {
        wildcards = 0;
        adjacentWildcards = 0;
        atomWildcard = false;
        atomEnd = -1;
        if (stack.isEmpty) continue;
        final group = stack.last;
        stack[stack.length - 1] = (
          repetitions: group.repetitions,
          unbounded: group.unbounded,
          alternation: true,
        );
        continue;
      }

      // `(?` 里的 `?` 是分组修饰符（`?:`、`?=`、`?!`），不是量词。
      final previous = index > 0 ? pattern.codeUnitAt(index - 1) : -1;
      final isQuantifier =
          (code == 0x2a || code == 0x2b || code == 0x3f || code == 0x7b) &&
          !(code == 0x3f && previous == 0x28);
      if (!isQuantifier) {
        // `.` 是通配原子，别的普通字符都不是。普通原子把相邻链打断：`.*a.*`
        // 的两个通配量词被字面量 `a` 分隔，不会退化成 `.*.*` 那种纯回溯。
        atomWildcard = code == 0x2e;
        atomEnd = index;
        if (!atomWildcard) adjacentWildcards = 0;
        continue;
      }

      repetitions++;
      final appliesToWildcard = atomWildcard && atomEnd == index - 1;
      var unbounded = code != 0x3f;
      if (code == 0x7b) {
        // 只有 `{n,}` 无界；`{n,m}` / `{n}` 有界。
        final close = pattern.indexOf('}', index);
        final body = close > index ? pattern.substring(index + 1, close) : '';
        unbounded = RegExp(r'^\s*\d*\s*,\s*$').hasMatch(body);
      }
      if (unbounded && appliesToWildcard) {
        wildcards++;
        adjacentWildcards++;
        if (tooManyWildcards()) return false;
      } else if (!appliesToWildcard) {
        // 量词没有修饰通配原子，相邻链在这里断开。
        adjacentWildcards = 0;
      }
      // 量词吃掉了紧邻的原子；`.*?` 仍然是通配无界量词。位置前移，避免同一个
      // 原子被后面的量词重复计数。
      atomWildcard = appliesToWildcard && unbounded;
      atomEnd = index;
      if (stack.isNotEmpty) {
        final group = stack.last;
        stack[stack.length - 1] = (
          repetitions: group.repetitions + 1,
          unbounded: group.unbounded || unbounded,
          alternation: group.alternation,
        );
      }
    }
    return repetitions <= _maxRepetitions;
  }

  /// Accepts one whole-chapter `pattern##replacement` under the regex limits.
  static bool isSafeContentReplacement(String rule) {
    final separator = rule.indexOf('##');
    if (separator <= 0) return false;
    final pattern = rule.substring(0, separator);
    return pattern.trim().isNotEmpty &&
        isSafeRegex(pattern, rule.substring(separator + 2));
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
