import 'dart:convert';

import 'source_capability.dart';
import 'source_rule_support.dart';

const _ruleSetNames = {
  'ruleSearch',
  'ruleExplore',
  'ruleBookInfo',
  'ruleToc',
  'ruleContent',
  'ruleReview',
};

const _knownRuleFields = <String, Set<String>>{
  'ruleSearch': {
    'bookList',
    'name',
    'author',
    'intro',
    'kind',
    'lastChapter',
    'bookUrl',
    'coverUrl',
  },
  'ruleExplore': {
    'bookList',
    'name',
    'author',
    'intro',
    'kind',
    'lastChapter',
    'bookUrl',
    'coverUrl',
  },
  'ruleBookInfo': {
    'name',
    'author',
    'intro',
    'kind',
    'lastChapter',
    'coverUrl',
    'tocUrl',
  },
  'ruleToc': {'chapterList', 'chapterName', 'chapterUrl', 'nextTocUrl'},
  'ruleContent': {'title', 'content', 'nextContentUrl', 'replaceRegex'},
};

const _regexExtractionFields = <String, Set<String>>{
  'ruleSearch': {'name', 'author', 'intro', 'kind', 'bookUrl', 'coverUrl'},
  'ruleExplore': {'name', 'author', 'intro', 'kind', 'bookUrl', 'coverUrl'},
  'ruleBookInfo': {'name', 'author', 'intro', 'coverUrl', 'tocUrl'},
  'ruleToc': {'chapterName', 'chapterUrl', 'nextTocUrl'},
  'ruleContent': {'title', 'content', 'nextContentUrl'},
};

const _hopByHopHeaders = {
  'connection',
  'content-length',
  'host',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
};

const _coreProfiles = {'native-core', 'android-core', 'web-core'};

/// Immutable, raw-preserving representation of one imported source definition.
///
/// Construction validates only format and transport-safe static headers. It does
/// not execute scripts, perform network requests, or claim runtime compatibility.
class SourceDefinition {
  SourceDefinition._({
    required Map<String, dynamic> rawJson,
    required this.id,
    required this.name,
    required this.type,
    required this.enabled,
    required this.searchUrl,
    required this.exploreUrl,
    required Map<String, String> staticHeaders,
    required Map<String, Map<String, dynamic>> ruleSets,
    required List<SourceCapabilityRequirement> requirements,
  }) : _rawJson = Map.unmodifiable(rawJson),
       staticHeaders = Map.unmodifiable(staticHeaders),
       _ruleSets = Map.unmodifiable({
         for (final entry in ruleSets.entries)
           entry.key: Map<String, dynamic>.unmodifiable(entry.value),
       }),
       _requirements = List.unmodifiable(requirements);

  factory SourceDefinition.fromJson(Map<String, dynamic> input) {
    final rawJson = _copyJson(input);
    final id = _requiredString(rawJson, 'bookSourceUrl');
    final uri = Uri.tryParse(id);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('bookSourceUrl 必须是无账号密码的 HTTP(S) 地址。');
    }
    final name = _requiredString(rawJson, 'bookSourceName');
    final typeValue = rawJson['bookSourceType'] ?? 0;
    if (typeValue is! num ||
        typeValue.toInt() != typeValue ||
        typeValue < 0 ||
        typeValue > 4) {
      throw const FormatException('bookSourceType 必须是 0–4 的整数。');
    }
    final enabledValue = rawJson.containsKey('enabled')
        ? rawJson['enabled']
        : true;
    if (enabledValue is! bool) {
      throw const FormatException('enabled 必须是布尔值 true 或 false。');
    }
    final searchValue = rawJson['searchUrl'];
    if (searchValue != null && searchValue is! String) {
      throw const FormatException('searchUrl 必须是字符串。');
    }
    final exploreValue = rawJson['exploreUrl'];
    if (exploreValue != null && exploreValue is! String) {
      throw const FormatException('exploreUrl 必须是字符串。');
    }

    final requirements = <SourceCapabilityRequirement>[];
    final staticHeaders = _parseHeaders(rawJson['header'], requirements);
    final ruleSets = <String, Map<String, dynamic>>{};
    for (final name in _ruleSetNames) {
      final rules = _parseRuleSet(rawJson[name], name);
      for (final field in _knownRuleFields[name] ?? const <String>{}) {
        if (rules.containsKey(field) && rules[field] is! String) {
          throw FormatException('$name.$field 必须是字符串。');
        }
      }
      ruleSets[name] = rules;
    }
    _scanCapabilities(rawJson, ruleSets, requirements);

    return SourceDefinition._(
      rawJson: rawJson,
      id: id,
      name: name,
      type: typeValue.toInt(),
      enabled: enabledValue,
      searchUrl: (searchValue as String?)?.trim(),
      exploreUrl: (exploreValue as String?)?.trim(),
      staticHeaders: staticHeaders,
      ruleSets: ruleSets,
      requirements: requirements,
    );
  }

  final Map<String, dynamic> _rawJson;
  final Map<String, Map<String, dynamic>> _ruleSets;
  final List<SourceCapabilityRequirement> _requirements;

  final String id;
  final String name;
  final int type;
  final bool enabled;
  final String? searchUrl;
  final String? exploreUrl;
  final Map<String, String> staticHeaders;

  Set<SourceCapability> get requiredCapabilities => Set.unmodifiable(
    _requirements.map((requirement) => requirement.capability),
  );

  Map<String, dynamic> rules(String name) => _ruleSets[name] ?? const {};

  SourceCapabilityReport capabilitiesFor(SourceRuntimeProfile profile) =>
      SourceCapabilityReport(profile: profile, requirements: _requirements);

  Map<String, dynamic> toJson() => _copyJson(_rawJson);

  static String _requiredString(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('缺少必填字段 $field。');
    }
    return value.trim();
  }

  static Map<String, String> _parseHeaders(
    dynamic value,
    List<SourceCapabilityRequirement> requirements,
  ) {
    if (value == null || value == '') return {};
    dynamic decoded = value;
    if (value is String) {
      final text = value.trim();
      if (_containsScript(text)) {
        requirements.add(
          const SourceCapabilityRequirement(
            path: 'header',
            capability: SourceCapability.javascript,
            message: 'header 需要脚本求值。',
          ),
        );
        return {};
      }
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw const FormatException('header 必须是 JSON 对象或编码后的 JSON 对象。');
      }
    }
    if (decoded is! Map) {
      throw const FormatException('header 必须是 JSON 对象或编码后的 JSON 对象。');
    }
    final headers = <String, String>{};
    for (final entry in decoded.entries) {
      final name = entry.key.toString().trim();
      final lowerName = name.toLowerCase();
      final headerValue = entry.value;
      if (name.isEmpty || name.contains(RegExp(r'[\r\n]'))) {
        throw const FormatException('header 名称不能为空或包含换行。');
      }
      if (_hopByHopHeaders.contains(lowerName)) {
        throw FormatException('header.$name 不允许由书源设置。');
      }
      if (headerValue == null || headerValue is Map || headerValue is List) {
        throw FormatException('header.$name 必须是字符串、数字或布尔值。');
      }
      final text = headerValue.toString();
      if (text.contains(RegExp(r'[\r\n]'))) {
        throw FormatException('header.$name 不能包含换行。');
      }
      headers[lowerName] = text;
    }
    if (headers.isNotEmpty) {
      requirements.add(
        const SourceCapabilityRequirement(
          path: 'header',
          capability: SourceCapability.staticHeaders,
          message: '书源声明了静态请求头。',
        ),
      );
    }
    return headers;
  }

  static Map<String, dynamic> _parseRuleSet(dynamic value, String path) {
    if (value == null || value == '') return {};
    // Some Legado feeds encode an absent review rule as an empty array.
    if (path == 'ruleReview' && value is List && value.isEmpty) return {};
    dynamic decoded = value;
    if (value is String) {
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        throw FormatException('$path 必须是对象或编码后的 JSON 对象。');
      }
    }
    if (decoded is! Map) {
      throw FormatException('$path 必须是对象或编码后的 JSON 对象。');
    }
    return {
      for (final entry in decoded.entries)
        entry.key.toString(): _copyValue(entry.value),
    };
  }

  static void _scanCapabilities(
    Map<String, dynamic> rawJson,
    Map<String, Map<String, dynamic>> ruleSets,
    List<SourceCapabilityRequirement> requirements,
  ) {
    void add(
      String path,
      SourceCapability capability,
      String message, {
      Set<String> implementedProfiles = const {},
      Set<String> permittedProfiles = const {},
    }) {
      if (requirements.any(
        (item) => item.path == path && item.capability == capability,
      )) {
        return;
      }
      requirements.add(
        SourceCapabilityRequirement(
          path: path,
          capability: capability,
          message: message,
          implementedProfiles: implementedProfiles,
          permittedProfiles: permittedProfiles,
        ),
      );
    }

    for (final field in ['jsLib', 'loginCheckJs', 'coverDecodeJs']) {
      if (_hasValue(rawJson[field])) {
        add(field, SourceCapability.javascript, '$field 需要 JavaScript。');
      }
    }
    for (final field in ['loginUrl', 'loginUi']) {
      if (_hasValue(rawJson[field])) {
        add(field, SourceCapability.login, '$field 需要登录能力。');
      }
    }
    if (rawJson['enabledCookieJar'] == true) {
      add('enabledCookieJar', SourceCapability.cookieJar, '书源需要持久 Cookie。');
    }
    if (_hasValue(rawJson['exploreUrl']) || _hasValue(rawJson['ruleExplore'])) {
      add('exploreUrl', SourceCapability.explore, '书源声明了发现 workflow。');
    }
    final searchUrl = rawJson['searchUrl'];
    if (searchUrl is String) {
      if (_containsScript(searchUrl)) {
        final sandboxed = RegExp(
          r'^\s*<js>[\s\S]*</js>\s*$',
          caseSensitive: false,
        ).hasMatch(searchUrl);
        add(
          'searchUrl',
          SourceCapability.javascript,
          'searchUrl 需要 JavaScript 求值。',
          implementedProfiles: sandboxed ? const {'android-core'} : const {},
          permittedProfiles: sandboxed ? const {'android-core'} : const {},
        );
      }
      for (final match in RegExp(r'\{\{(.*?)\}\}').allMatches(searchUrl)) {
        if (!{'key', 'page', 'baseUrl'}.contains(match[1])) {
          add('searchUrl', SourceCapability.javascript, 'searchUrl 包含动态表达式。');
        }
      }
    }

    final typeCapability = switch (rawJson['bookSourceType'] ?? 0) {
      1 => SourceCapability.audio,
      2 => SourceCapability.image,
      3 => SourceCapability.download,
      4 => SourceCapability.video,
      _ => null,
    };
    if (typeCapability != null) {
      add('bookSourceType', typeCapability, '当前阅读器不支持该媒体类型。');
    }

    for (final set in ruleSets.entries) {
      for (final rule in set.value.entries) {
        final path = '${set.key}.${rule.key}';
        final text = rule.value?.toString() ?? '';
        if (text.isEmpty) continue;
        final hasScript =
            _containsScript(text) ||
            RegExp(r'\{\{.*?\}\}').hasMatch(text) ||
            rule.key.toString().toLowerCase().endsWith('js');
        if (hasScript) {
          final sandboxedPostProcess =
              set.key == 'ruleContent' &&
              {'content', 'title', 'nextContentUrl'}.contains(rule.key) &&
              RegExp(r'@js:', caseSensitive: false).hasMatch(text) &&
              !RegExp(
                r'@webjs:|<js>|<webjs>',
                caseSensitive: false,
              ).hasMatch(text);
          add(
            path,
            SourceCapability.javascript,
            '$path 需要 JavaScript。',
            implementedProfiles: sandboxedPostProcess
                ? const {'android-core'}
                : const {},
            permittedProfiles: sandboxedPostProcess
                ? const {'android-core'}
                : const {},
          );
        }
        if (SourceRuleSupport.containsXPathBranch(text)) {
          final supported = SourceRuleSupport.isSafeXPath(text);
          add(
            path,
            SourceCapability.xpath,
            '$path 使用 XPath。',
            implementedProfiles: supported ? _coreProfiles : const {},
            permittedProfiles: supported ? _coreProfiles : const {},
          );
        }
        final usesJsonPath = RegExp(
          r'@json:|\$\.|\$\[',
          caseSensitive: false,
        ).hasMatch(text);
        if (usesJsonPath) {
          add(path, SourceCapability.jsonPath, '$path 使用 JSONPath。');
          if (RegExp(
            r'\b(?:match|search)\s*\(',
            caseSensitive: false,
          ).hasMatch(text)) {
            add(path, SourceCapability.regex, '$path 使用了受限的 JSONPath 正则函数。');
          }
        }
        if (text.contains('##') ||
            rule.key.toString().toLowerCase().contains('regex')) {
          final isContentReplacement =
              set.key == 'ruleContent' && rule.key == 'replaceRegex';
          final supported =
              text.contains('##') &&
              ((isContentReplacement &&
                      SourceRuleSupport.isSafeContentReplacement(text)) ||
                  (_regexExtractionFields[set.key]?.contains(rule.key) ??
                          false) &&
                      SourceRuleSupport.isSafeRegexRule(text));
          add(
            path,
            SourceCapability.regex,
            '$path 使用正则规则。',
            implementedProfiles: supported ? _coreProfiles : const {},
            permittedProfiles: supported ? _coreProfiles : const {},
          );
        }
      }
    }
    if (_hasValue(ruleSets['ruleContent']?['nextContentUrl'])) {
      add(
        'ruleContent.nextContentUrl',
        SourceCapability.contentPagination,
        '正文需要分页获取。',
      );
    }
  }

  static bool _containsScript(String value) => RegExp(
    r'@js:|<js>|</js>|@webjs:|<webjs>',
    caseSensitive: false,
  ).hasMatch(value);

  static bool _hasValue(dynamic value) =>
      value != null &&
      value != '' &&
      value != false &&
      !(value is Map && value.isEmpty) &&
      !(value is List && value.isEmpty);

  static Map<String, dynamic> _copyJson(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  static dynamic _copyValue(dynamic value) => jsonDecode(jsonEncode(value));
}
