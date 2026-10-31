import 'dart:convert';

import '../domain/book_source.dart';
import '../domain/source_definition.dart';

/// Bounded, side-effect-free codec for imported source definitions.
///
/// Parsing accepts representable fields even when their runtime capability is
/// not implemented. Network access, scripts and persistence happen elsewhere.
class SourceImporter {
  static const maxBytes = 10 * 1024 * 1024;
  static const maxSources = 500;
  static const maxJsonDepth = 64;

  List<BookSource> parse(String input) {
    if (utf8.encode(input).length > maxBytes) {
      throw const FormatException('书源 JSON 不能超过 10 MiB。');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(input);
    } on FormatException {
      throw const FormatException('不是有效的 JSON，请粘贴完整的书源对象或数组。');
    }
    _checkDepth(decoded, 0);
    final items = decoded is List ? decoded : [decoded];
    if (items.isEmpty || items.length > maxSources) {
      throw const FormatException('请一次导入 1–500 个书源。');
    }
    final sources = <String, BookSource>{};
    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('每个书源必须是 JSON 对象。');
      }
      final definition = SourceDefinition.fromJson(item);
      sources[definition.id] = BookSource.fromDefinition(definition);
    }
    return List.unmodifiable(sources.values);
  }

  static bool isHttpUrl(Uri uri) =>
      {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty;

  static void _checkDepth(dynamic value, int depth) {
    if (depth > maxJsonDepth) {
      throw const FormatException('书源 JSON 嵌套不能超过 64 层。');
    }
    if (value is Map) {
      for (final entry in value.entries) {
        _checkDepth(entry.value, depth + 1);
      }
    } else if (value is List) {
      for (final item in value) {
        _checkDepth(item, depth + 1);
      }
    }
  }
}
