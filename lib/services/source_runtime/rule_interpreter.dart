import 'dart:collection';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:json_path/json_path.dart';

import '../../domain/source_rule_support.dart';
import 'rule_tokenizer.dart';
import 'script_runtime.dart';

/// Opaque value passed between source-rule stages.
final class RuleNode {
  const RuleNode._(this._value);

  factory RuleNode.html(dom.Element element) => RuleNode._(element);
  factory RuleNode.json(Object? value) => RuleNode._(_JsonRuleValue(value));

  final Object? _value;
}

final class _JsonRuleValue {
  const _JsonRuleValue(this.value);

  final Object? value;
}

final class _RegexReplacement {
  const _RegexReplacement({
    required this.rule,
    required this.pattern,
    required this.replacement,
  });

  final String rule;
  final String pattern;
  final String replacement;
}

final class _XPathQuery {
  const _XPathQuery({
    required this.steps,
    required this.accessor,
    required this.absolute,
  });

  final List<_XPathStep> steps;
  final String accessor;
  final bool absolute;
}

final class _XPathStep {
  const _XPathStep({
    required this.selector,
    required this.descendant,
    this.position,
  });

  final String selector;
  final bool descendant;
  final int? position;
}

final class _XPathSegment {
  const _XPathSegment(this.value, {required this.descendant});

  final String value;
  final bool descendant;
}

final class _LegacyTextQuery {
  const _LegacyTextQuery({required this.text, required this.accessor});

  final String text;
  final String accessor;
}

/// Evaluates the safe declarative subset of imported source rules.
class RuleInterpreter {
  const RuleInterpreter({
    this.maxOutputCharacters = 2 * 1024 * 1024,
    RuleTokenizer tokenizer = const RuleTokenizer(),
  }) : _tokenizer = tokenizer;

  final int maxOutputCharacters;
  final RuleTokenizer _tokenizer;

  bool isJsonRule(String? rule) => rule != null && _isJsonRule(rule);

  List<RuleNode> select(RuleNode input, String rule) {
    for (final rawBranch in _tokenizer.splitTopLevel(rule, '||')) {
      final branch = rawBranch.trim();
      final nodes = _isJsonRule(branch)
          ? _jsonValues(input, branch).map(RuleNode.json).toList()
          : _isXPathRule(branch)
          ? _selectXPath(input, branch)
          : _selectCss(input, branch);
      if (nodes.isNotEmpty) return List.unmodifiable(nodes);
    }
    return const [];
  }

  String extract(RuleNode input, String? rule) => _extract(input, rule);

  String extractFirst(RuleNode input, String? rule) =>
      _extract(input, rule, firstOnly: true);

  String _extract(RuleNode input, String? rule, {bool firstOnly = false}) {
    if (rule == null || rule.isEmpty) return '';
    for (final rawBranch in _tokenizer.splitTopLevel(rule, '||')) {
      final branch = rawBranch.contains('##')
          ? rawBranch.trimLeft()
          : rawBranch.trim();
      final replacement = _regexReplacement(branch);
      final baseRule = replacement?.rule ?? branch;
      var value = _isJsonRule(baseRule)
          ? _extractJson(input, baseRule, firstOnly: firstOnly)
          : _isXPathRule(baseRule)
          ? _extractXPath(input, baseRule, firstOnly: firstOnly)
          : _extractCss(input, baseRule, firstOnly: firstOnly);
      if (replacement != null && value.isNotEmpty) {
        value = _applyRegex(value, replacement);
      }
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<String> extractWithScripts(
    RuleNode input,
    String? rule, {
    required SandboxedScriptRuntime scriptRuntime,
    Map<String, Object?> globals = const {},
    bool firstOnly = false,
  }) async {
    if (rule == null || rule.isEmpty) return '';
    final marker = _tokenizer.indexOfTopLevel(rule.toLowerCase(), '@js:');
    if (marker < 0) {
      return firstOnly ? extractFirst(input, rule) : extract(input, rule);
    }
    final baseRule = rule.substring(0, marker);
    final script = rule.substring(marker + 4).trim();
    if (script.isEmpty) {
      throw const FormatException('JavaScript 后处理规则不能为空。');
    }
    final extracted = baseRule.isEmpty
        ? ''
        : firstOnly
        ? extractFirst(input, baseRule)
        : extract(input, baseRule);
    final result = await scriptRuntime.evaluate(
      script,
      globals: {...globals, 'result': extracted},
    );
    final value = switch (result) {
      null => '',
      String() => result,
      Map() || List() => jsonEncode(result),
      _ => result.toString(),
    };
    if (value.length > maxOutputCharacters) {
      throw const FormatException('脚本处理结果过大。');
    }
    return value;
  }

  List<RuleNode> _selectXPath(RuleNode input, String rule) {
    final root = _html(input);
    final query = _parseXPath(rule);
    return _xpathElements(root, query).map(RuleNode.html).toList();
  }

  String _extractXPath(RuleNode input, String rule, {bool firstOnly = false}) {
    final root = _html(input);
    final query = _parseXPath(rule);
    final output = StringBuffer();
    final elements = _xpathElements(root, query);
    for (final element in firstOnly ? elements.take(1) : elements) {
      final value = _elementValue(element, query.accessor);
      if (value.isEmpty) continue;
      if (output.length + value.length > maxOutputCharacters) {
        throw const FormatException('规则提取出的内容过大，请缩小选择范围。');
      }
      if (output.isNotEmpty) output.writeln();
      output.write(value);
    }
    return output.toString();
  }

  static List<dom.Element> _xpathElements(dom.Element root, _XPathQuery query) {
    var current = <dom.Element>[root];
    for (var stepIndex = 0; stepIndex < query.steps.length; stepIndex++) {
      final step = query.steps[stepIndex];
      final next = LinkedHashSet<dom.Element>.identity();
      for (final context in current) {
        final matches = <dom.Element>[
          if (stepIndex == 0 &&
              query.absolute &&
              _matchesSelector(context, step.selector))
            context,
          ...context
              .querySelectorAll(step.selector)
              .where((element) => step.descendant || element.parent == context),
        ];
        final position = step.position;
        if (position == null) {
          next.addAll(matches);
        } else if (matches.isNotEmpty && position == -1) {
          next.add(matches.last);
        } else if (position > 0 && position <= matches.length) {
          next.add(matches[position - 1]);
        }
      }
      current = next.toList();
    }
    return current;
  }

  static bool _matchesSelector(dom.Element element, String selector) {
    final parent = element.parent;
    if (parent != null) {
      return parent
          .querySelectorAll(selector)
          .any((item) => identical(item, element));
    }
    final clone = element.clone(true);
    final wrapper = dom.Element.tag('div')..append(clone);
    return wrapper
        .querySelectorAll(selector)
        .any((item) => identical(item, clone));
  }

  static _XPathQuery _parseXPath(String rule) {
    if (!SourceRuleSupport.isSafeXPath(rule)) {
      throw const FormatException('XPath 表达式超出安全子集。');
    }
    var path = rule
        .replaceFirst(RegExp(r'^@xpath:', caseSensitive: false), '')
        .trim();
    final absolute = path.startsWith('/');
    var accessor = 'text';
    final textAccessor = RegExp(r'/text\(\)$', caseSensitive: false);
    final attributeAccessor = RegExp(r'/@([A-Za-z_][\w:.-]*)$');
    if (textAccessor.hasMatch(path)) {
      path = path.replaceFirst(textAccessor, '');
    } else {
      final match = attributeAccessor.firstMatch(path);
      if (match != null) {
        accessor = match[1]!;
        path = path.substring(0, match.start);
      }
    }
    final segments = _splitXPathSegments(path);
    if (segments.isEmpty) {
      throw const FormatException('XPath 缺少元素路径。');
    }
    return _XPathQuery(
      steps: List.unmodifiable(segments.map(_parseXPathStep)),
      accessor: accessor,
      absolute: absolute,
    );
  }

  static List<_XPathSegment> _splitXPathSegments(String path) {
    final segments = <_XPathSegment>[];
    var index = 0;
    var descendant = true;
    if (path.startsWith('.//')) {
      index = 3;
    } else if (path.startsWith('//')) {
      index = 2;
    } else if (path.startsWith('/')) {
      index = 1;
      descendant = false;
    }

    while (index < path.length) {
      final start = index;
      var brackets = 0;
      int? quote;
      var escaped = false;
      while (index < path.length) {
        final code = path.codeUnitAt(index);
        if (quote != null) {
          if (escaped) {
            escaped = false;
          } else if (code == 0x5c) {
            escaped = true;
          } else if (code == quote) {
            quote = null;
          }
        } else if (code == 0x22 || code == 0x27) {
          quote = code;
        } else if (code == 0x5b) {
          brackets++;
        } else if (code == 0x5d) {
          if (brackets == 0) {
            throw const FormatException('XPath 方括号不匹配。');
          }
          brackets--;
        } else if (code == 0x2f && brackets == 0) {
          break;
        }
        index++;
      }
      if (quote != null || brackets != 0) {
        throw const FormatException('XPath 引号或方括号不匹配。');
      }
      final value = path.substring(start, index).trim();
      if (value.isNotEmpty && value != '.') {
        segments.add(_XPathSegment(value, descendant: descendant));
      }
      if (index >= path.length) break;
      if (path.startsWith('//', index)) {
        descendant = true;
        index += 2;
      } else {
        descendant = false;
        index++;
      }
    }
    return segments;
  }

  static _XPathStep _parseXPathStep(_XPathSegment segment) {
    final value = segment.value;
    final tag = RegExp(r'^([A-Za-z_][\w-]*|\*)').firstMatch(value);
    if (tag == null) throw FormatException('不支持的 XPath 片段：$value。');
    var selector = tag[1]!;
    int? position;
    var rest = value.substring(tag.end);
    while (rest.isNotEmpty) {
      if (!rest.startsWith('[')) {
        throw FormatException('不支持的 XPath 片段：$value。');
      }
      final close = _xpathPredicateEnd(rest);
      final predicate = rest.substring(1, close).trim();
      rest = rest.substring(close + 1);
      final numeric = int.tryParse(predicate);
      if (numeric != null) {
        if (numeric <= 0 || position != null) {
          throw const FormatException('XPath 位置必须是唯一的正整数。');
        }
        position = numeric;
        continue;
      }
      if (predicate.toLowerCase() == 'last()') {
        if (position != null) throw const FormatException('XPath 位置条件重复。');
        position = -1;
        continue;
      }
      if (predicate.startsWith('@')) {
        final equals = predicate.indexOf('=');
        if (equals <= 1) throw FormatException('不支持的 XPath 条件：$predicate。');
        final name = predicate.substring(1, equals).trim();
        final value = _xpathLiteral(predicate.substring(equals + 1).trim());
        selector += '[$name="${_cssString(value)}"]';
        continue;
      }
      final contains = RegExp(
        r'^contains\((.*)\)$',
        caseSensitive: false,
      ).firstMatch(predicate);
      if (contains != null) {
        final arguments = contains[1]!;
        final comma = arguments.indexOf(',');
        if (comma <= 1) {
          throw FormatException('不支持的 XPath contains：$predicate。');
        }
        final attribute = arguments.substring(0, comma).trim();
        if (!attribute.startsWith('@')) {
          throw FormatException('XPath contains 仅支持属性：$predicate。');
        }
        final name = attribute.substring(1).trim();
        final value = _xpathLiteral(arguments.substring(comma + 1).trim());
        selector += '[$name*="${_cssString(value)}"]';
        continue;
      }
      throw FormatException('不支持的 XPath 条件：$predicate。');
    }
    return _XPathStep(
      selector: selector,
      descendant: segment.descendant,
      position: position,
    );
  }

  static int _xpathPredicateEnd(String value) {
    int? quote;
    var escaped = false;
    for (var index = 1; index < value.length; index++) {
      final code = value.codeUnitAt(index);
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == quote) {
          quote = null;
        }
      } else if (code == 0x22 || code == 0x27) {
        quote = code;
      } else if (code == 0x5d) {
        return index;
      }
    }
    throw const FormatException('XPath 条件缺少右方括号。');
  }

  static String _xpathLiteral(String value) {
    if (value.length < 2 ||
        !((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      throw FormatException('XPath 属性值必须使用引号：$value。');
    }
    return value
        .substring(1, value.length - 1)
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\\', r'\');
  }

  static String _cssString(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  static bool _isXPathRule(String rule) {
    final value = rule.trimLeft().toLowerCase();
    return value.startsWith('@xpath:') ||
        value.startsWith('//') ||
        value.startsWith('.//') ||
        value.startsWith('/');
  }

  List<RuleNode> _selectCss(RuleNode input, String rule) {
    final root = _html(input);
    final legacyText = _legacyTextQuery(rule, forSelection: true);
    if (legacyText != null) {
      return _legacyTextElements(
        root,
        legacyText.text,
      ).map(RuleNode.html).toList();
    }
    final (selector, _, legacySteps) = _cssParts(rule, forSelection: true);
    final elements = legacySteps != null
        ? _selectLegacyChain(root, legacySteps)
        : selector.isEmpty
        ? <dom.Element>[root]
        : _querySelectorAllSafe(root, selector);
    return elements.map(RuleNode.html).toList();
  }

  String _extractCss(RuleNode input, String rule, {bool firstOnly = false}) {
    final root = _html(input);
    final legacyText = _legacyTextQuery(rule);
    final (selector, accessor, legacySteps) = legacyText == null
        ? _cssParts(rule)
        : ('', legacyText.accessor, null);
    final elements = legacyText != null
        ? _legacyTextElements(root, legacyText.text)
        : legacySteps != null
        ? _selectLegacyChain(root, legacySteps)
        : selector.isEmpty
        ? <dom.Element>[root]
        : _querySelectorAllSafe(root, selector);
    final output = StringBuffer();
    for (final element in firstOnly ? elements.take(1) : elements) {
      final value = _elementValue(element, accessor);
      if (value.isEmpty) continue;
      if (output.length + value.length > maxOutputCharacters) {
        throw const FormatException('规则提取出的内容过大，请缩小选择范围。');
      }
      if (output.isNotEmpty) output.writeln();
      output.write(value);
    }
    return output.toString();
  }

  _RegexReplacement? _regexReplacement(String rule) {
    final first = rule.indexOf('##');
    if (first < 0) return null;
    final second = rule.indexOf('##', first + 2);
    final pattern = second < 0
        ? rule.substring(first + 2)
        : rule.substring(first + 2, second);
    final replacement = second < 0 ? '' : rule.substring(second + 2);
    if (first == 0 || pattern.isEmpty) {
      throw const FormatException('正则替换规则缺少选择规则或匹配表达式。');
    }
    if (!SourceRuleSupport.isSafeRegex(pattern, replacement)) {
      throw const FormatException('正则表达式超出安全子集。');
    }
    return _RegexReplacement(
      rule: rule.substring(0, first),
      pattern: pattern,
      replacement: replacement,
    );
  }

  String _applyRegex(String input, _RegexReplacement replacement) {
    if (input.length > 256 * 1024) {
      throw const FormatException('正则替换输入超过 256 KiB 安全限制。');
    }
    final expression = RegExp(replacement.pattern);
    if (expression.hasMatch('')) {
      throw const FormatException('正则表达式不能匹配空字符串。');
    }
    final output = StringBuffer();
    var cursor = 0;
    var matchCount = 0;

    void write(String value) {
      if (output.length + value.length > maxOutputCharacters) {
        throw const FormatException('正则替换结果过大。');
      }
      output.write(value);
    }

    for (final match in expression.allMatches(input)) {
      if (match.start == match.end || ++matchCount > 10000) {
        throw const FormatException('正则匹配次数超过安全限制。');
      }
      write(input.substring(cursor, match.start));
      write(
        replacement.replacement.replaceAllMapped(RegExp(r'\$(\d+)'), (group) {
          final index = int.parse(group[1]!);
          return index <= match.groupCount ? match.group(index) ?? '' : '';
        }),
      );
      cursor = match.end;
    }
    write(input.substring(cursor));
    return output.toString();
  }

  String _extractJson(RuleNode input, String rule, {bool firstOnly = false}) {
    final output = StringBuffer();
    final values = _jsonValues(input, rule);
    for (final value in firstOnly ? values.take(1) : values) {
      final text = switch (value) {
        null => '',
        Map() || List() => jsonEncode(value),
        _ => value.toString(),
      };
      if (text.isEmpty) continue;
      if (output.length + text.length > maxOutputCharacters) {
        throw const FormatException('规则提取出的内容过大，请缩小选择范围。');
      }
      if (output.isNotEmpty) output.writeln();
      output.write(text);
    }
    return output.toString();
  }

  static List<Object?> _jsonValues(RuleNode input, String rule) {
    final wrapped = input._value;
    if (wrapped is! _JsonRuleValue) {
      throw const FormatException('当前规则需要 JSON 输入。');
    }
    final path = rule.replaceFirst(
      RegExp(r'^@json:', caseSensitive: false),
      '',
    );
    if (!path.startsWith(r'$')) {
      throw const FormatException('JSONPath 必须从根节点 \$ 开始。');
    }
    if (path.length > 4096 ||
        RegExp(
          r'\b(?:match|search)\s*\(',
          caseSensitive: false,
        ).hasMatch(path)) {
      throw const FormatException('JSONPath 超出安全子集。');
    }
    try {
      return [
        for (final match in JsonPath(path).read(wrapped.value)) match.value,
      ];
    } catch (_) {
      throw const FormatException('JSONPath 表达式无效或不受支持。');
    }
  }

  static bool _isJsonRule(String rule) {
    final lower = rule.trimLeft().toLowerCase();
    return lower.startsWith('@json:') || lower.startsWith(r'$');
  }

  static dom.Element _html(RuleNode input) {
    final value = input._value;
    if (value is dom.Element) return value;
    throw const FormatException('当前规则需要 HTML 输入。');
  }

  static _LegacyTextQuery? _legacyTextQuery(
    String rule, {
    bool forSelection = false,
  }) {
    final trimmed = rule.trim();
    if (trimmed.startsWith('@')) return null;
    final accessorAt = trimmed.lastIndexOf('@');
    final selector = accessorAt < 0
        ? trimmed
        : trimmed.substring(0, accessorAt).trim();
    if (!selector.toLowerCase().startsWith('text.') || selector.length <= 5) {
      return null;
    }
    return _LegacyTextQuery(
      text: selector.substring(5),
      accessor: forSelection || accessorAt < 0
          ? 'text'
          : trimmed.substring(accessorAt + 1).trim(),
    );
  }

  static List<dom.Element> _legacyTextElements(
    dom.Element root,
    String expected,
  ) => [
    for (final element in <dom.Element>[root, ...root.querySelectorAll('*')])
      if (_elementValue(element, 'text') == expected) element,
  ];

  /// Trailing positional suffix of the legacy rule grammar (`tag.a.0`).
  ///
  /// A valid CSS selector never ends with `.<digits>` because identifiers may
  /// not start with a number, so the suffix is unambiguous. Negative indexes
  /// count from the end, as in Legado.
  static final RegExp _trailingIndex = RegExp(r'\.(-?\d+)$');

  /// Queries [root] with [selector], honouring legacy positional suffixes.
  ///
  /// Real-world sources write `span.0` (or `class.book.2`) to mean "the N-th
  /// match", which CSS cannot express. Those suffixes are stripped and applied
  /// as 0-based indexes over the matches, mirroring Legado's `indexDefault`
  /// (negative indexes count from the end). A part that fails to parse yields
  /// nothing instead of aborting the whole rule, so a following `||` branch can
  /// still supply a value.
  List<dom.Element> _querySelectorAllSafe(dom.Element root, String selector) {
    final parts = <(String, List<int>)>[];
    var hasIndexSuffix = false;
    for (final rawPart in _tokenizer.splitTopLevel(selector, ',')) {
      final part = rawPart.trim();
      if (part.isEmpty) continue;
      final (base, indexes) = _splitIndexes(part);
      if (indexes.isNotEmpty) hasIndexSuffix = true;
      parts.add((base, indexes));
    }
    if (!hasIndexSuffix) {
      return _querySelectorAll(root, selector);
    }
    final selected = LinkedHashSet<dom.Element>.identity();
    for (final (base, indexes) in parts) {
      selected.addAll(_applyIndexes(_querySelectorAll(root, base), indexes));
    }
    return List.unmodifiable(selected);
  }

  /// Resolves a legacy rule chain step by step, so each `@` segment can carry
  /// its own positional suffix (`class.book.1@tag.a`).
  List<dom.Element> _selectLegacyChain(dom.Element root, List<String> steps) {
    var current = <dom.Element>[root];
    for (final step in steps) {
      if (current.isEmpty) return const <dom.Element>[];
      final (base, indexes) = _splitIndexes(_legacySelector(step));
      final matches = LinkedHashSet<dom.Element>.identity();
      for (final element in current) {
        if (base.isEmpty) {
          matches.add(element);
          continue;
        }
        matches.addAll(_querySelectorAll(element, base));
      }
      current = _applyIndexes(matches.toList(), indexes);
    }
    return List.unmodifiable(current);
  }

  /// Splits a compound selector into its base and trailing positional indexes.
  static (String, List<int>) _splitIndexes(String selector) {
    var base = selector.trim();
    final indexes = <int>[];
    while (true) {
      final match = _trailingIndex.firstMatch(base);
      if (match == null) break;
      indexes.insert(0, int.parse(match.group(1)!));
      base = base.substring(0, match.start).trim();
    }
    return (base, indexes);
  }

  /// Picks the requested positions (0-based, negative from the end) in order.
  static List<dom.Element> _applyIndexes(
    List<dom.Element> matches,
    List<int> indexes,
  ) {
    if (indexes.isEmpty) return matches;
    final picked = <dom.Element>[];
    for (final index in indexes) {
      final resolved = index < 0 ? matches.length + index : index;
      if (resolved >= 0 && resolved < matches.length) {
        picked.add(matches[resolved]);
      }
    }
    return picked;
  }

  /// Runs a single CSS selector, turning parse failures into no matches.
  ///
  /// Sources in the wild contain selectors that no CSS engine accepts; the
  /// fallback branch machinery in [select]/[extract] handles an empty result,
  /// so containment here keeps such rules working instead of surfacing an
  /// English parser error to the reader.
  static List<dom.Element> _querySelectorAll(
    dom.Element root,
    String selector,
  ) {
    if (selector.isEmpty) return <dom.Element>[root];
    try {
      return root.querySelectorAll(selector);
    } on FormatException {
      return const <dom.Element>[];
    }
  }

  static bool _isBareAccessor(String rule) => RegExp(
    r'^(?:text|ownText|textNodes|html|href|src|data-[\w-]+|aria-[\w-]+)$',
  ).hasMatch(rule);

  static (String, String, List<String>?) _cssParts(
    String rule, {
    bool forSelection = false,
  }) {
    final trimmed = rule.trim();
    if (!forSelection && _isBareAccessor(trimmed)) return ('', trimmed, null);
    final explicitCss = RegExp(r'^@css:', caseSensitive: false).hasMatch(rule);
    if (!explicitCss) {
      final parts = rule.split('@');
      final legacy = parts.any((part) {
        final lower = part.toLowerCase();
        return lower.startsWith('class.') ||
            lower.startsWith('id.') ||
            lower.startsWith('tag.');
      });
      if (legacy) {
        final selectorParts = [
          for (final part in parts)
            if (part.trim().isNotEmpty) part.trim(),
        ];
        final accessor = forSelection || selectorParts.length == 1
            ? 'text'
            : selectorParts.removeLast();
        return ('', accessor.trim(), selectorParts);
      }
    }

    var selector = rule.replaceFirst(
      RegExp(r'^@css:', caseSensitive: false),
      '',
    );
    if (forSelection) return (selector.trim(), 'text', null);
    final index = selector.lastIndexOf('@');
    final accessor = index < 0 ? 'text' : selector.substring(index + 1);
    if (index >= 0) selector = selector.substring(0, index);
    return (selector.trim(), accessor.trim(), null);
  }

  static String _legacySelector(String raw) {
    final part = raw.trim();
    final lower = part.toLowerCase();
    if (lower.startsWith('class.')) return '.${part.substring(6)}';
    if (lower.startsWith('id.')) return '#${part.substring(3)}';
    if (lower.startsWith('tag.')) return part.substring(4);
    return part;
  }

  static String _elementValue(dom.Element element, String accessor) {
    final clean = element.clone(true);
    for (final node in clean.querySelectorAll('script, style')) {
      node.remove();
    }
    return switch (accessor) {
      'text' => clean.text.trim(),
      'ownText' =>
        clean.nodes
            .whereType<dom.Text>()
            .map((node) => node.data)
            .join(' ')
            .trim(),
      'textNodes' =>
        clean.nodes
            .whereType<dom.Text>()
            .map((node) => node.data.trim())
            .where((value) => value.isNotEmpty)
            .join('\n'),
      'html' => clean.outerHtml,
      _ => clean.attributes[accessor]?.trim() ?? '',
    };
  }
}
