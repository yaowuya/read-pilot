import 'dart:convert';

import '../domain/book_source.dart';
import '../domain/source_definition.dart';
import '../domain/source_import.dart';

/// Outcome of a tolerant import parse: everything that survived plus everything
/// that had to be dropped, in payload order.
class SourceImportReport {
  SourceImportReport({
    required Iterable<BookSource> sources,
    Iterable<SourceImportSkip> skipped = const [],
  }) : sources = List.unmodifiable(sources),
       skipped = List.unmodifiable(skipped);

  final List<BookSource> sources;

  /// Entries rejected by [SourceDefinition.fromJson], in payload order.
  final List<SourceImportSkip> skipped;

  int get skippedCount => skipped.length;

  /// Entries the payload contained, whichever branch they ended up in.
  int get totalCount => sources.length + skipped.length;
}

/// Bounded, side-effect-free codec for imported source definitions.
///
/// Parsing accepts representable fields even when their runtime capability is
/// not implemented. Network access, scripts and persistence happen elsewhere.
class SourceImporter {
  static const maxBytes = 100 * 1024 * 1024;
  static const maxBytesLabel = '100 MiB';

  /// Largest number of entries allowed in one import.
  ///
  /// Real aggregates ship thousands of sources in a single JSON array (the
  /// `yckceo.com` feeds reach ~1.5k), so the cap only has to stop accidental
  /// paste bombs. [maxSourcesLabel] is derived from this value so the message
  /// below can never drift from the enforced limit.
  static const maxSources = 10000;
  static const maxSourcesLabel = '$maxSources';
  static const maxJsonDepth = 64;

  /// Parses the whole payload and fails the batch on the first bad entry.
  ///
  /// Kept strict for callers that assert "this payload is importable" (the URL
  /// probe and the source editor). Import flows that must survive an aggregate
  /// feed use [parseReport] instead.
  List<BookSource> parse(String input) {
    final items = _items(_decode(input));
    final sources = <String, BookSource>{};
    for (final item in items) {
      final source = _entry(item);
      sources[source.id] = source;
    }
    return List.unmodifiable(sources.values);
  }

  /// Parses the payload entry by entry, skipping entries that are structurally
  /// JSON objects but do not describe a representable source.
  ///
  /// Only a *single entry* may be dropped this way. Problems with the payload
  /// itself — not JSON, larger than [maxBytes], more than [maxSources] entries,
  /// nesting deeper than [maxJsonDepth], an empty array, or an entry that is not
  /// a JSON object — still fail the whole import, because silently importing
  /// zero sources would hide the real mistake. A payload whose entries are all
  /// invalid also throws, rather than yielding an importable-looking empty set.
  SourceImportReport parseReport(String input) {
    final items = _items(_decode(input));
    final sources = <String, BookSource>{};
    final skipped = <SourceImportSkip>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item is! Map<String, dynamic>) {
        throw const FormatException('每个书源必须是 JSON 对象。');
      }
      try {
        final source = _entry(item);
        sources[source.id] = source;
      } on FormatException catch (error) {
        skipped.add(
          SourceImportSkip(
            label: _skipLabel(item, index),
            reason: error.message.toString(),
          ),
        );
      }
    }
    if (sources.isEmpty && skipped.isNotEmpty) {
      final reason = groupSourceImportSkips(skipped).first.reason;
      throw FormatException('这 ${skipped.length} 个书源都无法解析（$reason）');
    }
    return SourceImportReport(sources: sources.values, skipped: skipped);
  }

  static bool isHttpUrl(Uri uri) =>
      {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty;

  /// Decoded payload, with the size and syntax checks that fail the batch.
  static dynamic _decode(String input) {
    if (utf8.encode(input).length > maxBytes) {
      throw const FormatException('书源 JSON 不能超过 $maxBytesLabel。');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(input);
    } on FormatException {
      throw const FormatException('不是有效的 JSON，请粘贴完整的书源对象或数组。');
    }
    return decoded;
  }

  /// Entries of a decoded payload, with the structural checks that fail the batch.
  static List<dynamic> _items(dynamic decoded) {
    _checkDepth(decoded, 0);
    final List<dynamic> items = decoded is List ? decoded : <dynamic>[decoded];
    if (items.isEmpty || items.length > maxSources) {
      throw const FormatException('请一次导入 1–$maxSourcesLabel 个书源。');
    }
    return items;
  }

  /// One representable source, or a [FormatException] describing why not.
  static BookSource _entry(dynamic item) {
    if (item is! Map<String, dynamic>) {
      throw const FormatException('每个书源必须是 JSON 对象。');
    }
    return BookSource.fromDefinition(SourceDefinition.fromJson(item));
  }

  /// Best-effort identity for a rejected entry.
  ///
  /// Never empty: an entry can be malformed precisely because it lacks a usable
  /// name and URL, and an unnamed skip would be useless in the preview.
  static String _skipLabel(Map<String, dynamic> item, int index) {
    for (final field in const ['bookSourceName', 'bookSourceUrl']) {
      final value = item[field];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '第 ${index + 1} 个书源';
  }

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
