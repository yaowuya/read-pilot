import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../domain/book_source.dart';

class SourceImporter {
  static const maxBytes = 1024 * 1024;
  static const _allowedRules = {
    'ruleSearch': {
      'bookList',
      'name',
      'author',
      'intro',
      'bookUrl',
      'coverUrl',
    },
    'ruleBookInfo': {'name', 'author', 'intro', 'tocUrl', 'coverUrl'},
    'ruleToc': {'chapterList', 'chapterName', 'chapterUrl'},
    'ruleContent': {'content', 'title'},
  };
  static const _unsupported = {
    'jsLib',
    'loginUrl',
    'loginUi',
    'loginCheckJs',
    'coverDecodeJs',
    'header',
    'concurrentRate',
    'exploreUrl',
    'ruleExplore',
    'exploreScreen',
    'eventListener',
    'customButton',
    'homepageModules',
  };

  List<BookSource> parse(String input) {
    if (utf8.encode(input).length > maxBytes) {
      throw const FormatException('书源 JSON 不能超过 1 MiB。');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(input);
    } on FormatException {
      throw const FormatException('不是有效的 JSON，请粘贴完整的书源对象或数组。');
    }
    final items = decoded is List ? decoded : [decoded];
    if (items.isEmpty || items.length > 100) {
      throw const FormatException('请一次导入 1–100 个书源。');
    }
    final sources = <String, BookSource>{};
    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('每个书源必须是 JSON 对象。');
      }
      final json = Map<String, dynamic>.from(item);
      for (final field in ['bookSourceUrl', 'bookSourceName', 'searchUrl']) {
        if (json[field] is! String || (json[field] as String).trim().isEmpty) {
          throw FormatException('缺少必填字段 $field。');
        }
        json[field] = (json[field] as String).trim();
      }
      final origin = Uri.tryParse(json['bookSourceUrl'] as String);
      if (origin == null || !isHttpUrl(origin) || origin.userInfo.isNotEmpty) {
        throw const FormatException('bookSourceUrl 必须是无账号密码的 HTTP(S) 地址。');
      }
      if (json['bookSourceType'] != null && json['bookSourceType'] != 0) {
        throw const FormatException('bookSourceType：首版只支持文本书源（0）。');
      }
      for (final field in _unsupported) {
        if (_hasValue(json[field])) {
          throw FormatException('$field 不受支持；首版只支持无脚本的 CSS / GET 书源。');
        }
      }
      final url = json['searchUrl'] as String;
      if (RegExp(r'@js|<js|,\s*\{|[<>]', caseSensitive: false).hasMatch(url)) {
        throw const FormatException('searchUrl：不支持脚本、分页表达式或请求选项。');
      }
      for (final match in RegExp(r'\{\{(.*?)\}\}').allMatches(url)) {
        if (!{'key', 'page', 'baseUrl'}.contains(match[1])) {
          throw const FormatException(
            'searchUrl：只支持 {{key}}、{{page}}、{{baseUrl}}。',
          );
        }
      }
      final probe = url
          .replaceAll('{{key}}', 'test')
          .replaceAll('{{page}}', '1')
          .replaceAll('{{baseUrl}}', origin.toString());
      if (probe.contains('{') ||
          probe.contains('}') ||
          !isHttpUrl(origin.resolve(probe)) ||
          origin.resolve(probe).origin != origin.origin) {
        throw const FormatException(
          'searchUrl 必须使用与 bookSourceUrl 同源的 HTTP(S) 地址。',
        );
      }
      for (final entry in _allowedRules.entries) {
        dynamic value = json[entry.key];
        if (value is String && value.isNotEmpty) {
          try {
            value = jsonDecode(value);
          } on FormatException {
            throw FormatException('${entry.key} 不是有效的 JSON 规则对象。');
          }
        }
        if (value == null || value == '') value = <String, dynamic>{};
        if (value is! Map) throw FormatException('${entry.key} 必须是对象。');
        final rules = <String, dynamic>{};
        for (final rule in value.entries) {
          if (!_hasValue(rule.value)) continue;
          final field = '${entry.key}.${rule.key}';
          if (!entry.value.contains(rule.key) || rule.value is! String) {
            throw FormatException('$field 不受支持。请使用 CSS 声明式子集。');
          }
          final text = (rule.value as String).trim();
          _validateRule(
            text,
            field,
            isList: {'bookList', 'chapterList'}.contains(rule.key),
          );
          rules[rule.key as String] = text;
        }
        json[entry.key] = rules;
      }
      for (final entry in {
        'ruleSearch': ['bookList', 'name', 'bookUrl'],
        'ruleToc': ['chapterList', 'chapterName', 'chapterUrl'],
        'ruleContent': ['content'],
      }.entries) {
        for (final field in entry.value) {
          if (!_hasValue((json[entry.key] as Map)[field])) {
            throw FormatException('缺少必填规则 ${entry.key}.$field。');
          }
        }
      }
      if (json.containsKey('enabled') && json['enabled'] is! bool) {
        throw const FormatException('enabled 必须是布尔值 true 或 false。');
      }
      json.putIfAbsent('enabled', () => true);
      json['bookSourceType'] = 0;
      final source = BookSource(json);
      sources[source.id] = source;
    }
    return List.unmodifiable(sources.values);
  }

  static bool isHttpUrl(Uri uri) =>
      {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty;

  static bool _hasValue(dynamic value) =>
      value != null &&
      value != '' &&
      value != false &&
      !(value is Map && value.isEmpty) &&
      !(value is List && value.isEmpty);

  void _validateRule(String rule, String field, {required bool isList}) {
    if (RegExp(
      r'@(?:js|webjs|xpath|json|get|put)|<js|\{\{|##|&&|\|\||%%|^/|^\$|^(?:class|tag|id|text)\.',
      caseSensitive: false,
    ).hasMatch(rule)) {
      throw FormatException('$field：不支持脚本、XPath、JSONPath、规则组合或旧式规则。');
    }
    var selector = rule.replaceFirst(
      RegExp(r'^@css:', caseSensitive: false),
      '',
    );
    if (!isList) {
      final split = selector.lastIndexOf('@');
      if (split >= 0) selector = selector.substring(0, split);
    }
    if (selector.contains('@') || (isList && selector.isEmpty)) {
      throw FormatException('$field：请选择单个 CSS 规则，而不是链式规则。');
    }
    if (selector.isNotEmpty) {
      try {
        html.parse('<div></div>').querySelectorAll(selector);
      } catch (_) {
        throw FormatException('$field：CSS 选择器无效。');
      }
    }
  }
}
