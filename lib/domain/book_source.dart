import 'dart:convert';

import 'source_capability.dart';
import 'source_definition.dart';

class SourceExploreEntry {
  const SourceExploreEntry({required this.title, required this.url});

  final String title;
  final String url;
}

/// Whole-value script markers mirrored from legado's `exploreKinds`:
/// such `exploreUrl` values need a JS runtime this app does not ship, so they
/// yield no static explore entries at all instead of junk fragments.
final RegExp _scriptExploreUrl = RegExp(
  r'^\s*(?:@js:|@webjs:|<js>|<webjs>)',
  caseSensitive: false,
);

/// Splits the legacy `标题::地址` list the same way legado does: on newlines
/// and the literal `&&` separator.
final RegExp _legacyExploreSeparator = RegExp(r'(?:&&|[\r\n])+');

/// Cap on explore entries per source, matching the previous behaviour.
const int _maxExploreEntries = 200;

/// Persisted source facade used by the existing controller and repository.
///
/// Raw JSON remains round-trippable while normalized fields and compatibility
/// diagnostics are delegated to [SourceDefinition].
class BookSource {
  BookSource(Map<String, dynamic> json)
    : definition = SourceDefinition.fromJson(json);

  BookSource.fromDefinition(this.definition);

  final SourceDefinition definition;

  String get id => definition.id;
  String get name => definition.name;
  int get type => definition.type;
  bool get enabled => definition.enabled;
  String get searchUrl => definition.searchUrl ?? '';
  Map<String, String> get headers => definition.staticHeaders;
  Set<SourceCapability> get requiredCapabilities =>
      definition.requiredCapabilities;
  Map<String, String> get searchRules => _rules('ruleSearch');
  Map<String, String> get exploreRules => _rules('ruleExplore');
  Map<String, String> get infoRules => _rules('ruleBookInfo');
  Map<String, String> get tocRules => _rules('ruleToc');
  Map<String, String> get contentRules => _rules('ruleContent');

  List<SourceExploreEntry> get exploreEntries {
    final value = definition.exploreUrl;
    if (value == null || value.isEmpty) return const [];
    if (_scriptExploreUrl.hasMatch(value)) return const [];
    final entries = <SourceExploreEntry>[];
    final seen = <String>{};

    void add(String title, String url) {
      if (entries.length >= _maxExploreEntries) return;
      final trimmedUrl = url.trim();
      final trimmedTitle = title.trim();
      if (!_isUsableExploreUrl(trimmedUrl)) return;
      final resolvedTitle = trimmedTitle.isEmpty ? name : trimmedTitle;
      if (resolvedTitle.isEmpty) return;
      // Keyed widgets and the category id both build from (title, url), so a
      // duplicate pair would crash the discover page's Wrap.
      if (!seen.add('$resolvedTitle\u{0}$trimmedUrl')) return;
      entries.add(SourceExploreEntry(title: resolvedTitle, url: trimmedUrl));
    }

    final trimmed = value.trim();
    if (trimmed.startsWith('[')) {
      final decoded = _tryDecodeJsonEntries(trimmed);
      if (decoded != null) {
        for (final entry in decoded) {
          add(entry.$1, entry.$2);
        }
        return List.unmodifiable(entries);
      }
    }
    for (final rawLine in value.split(_legacyExploreSeparator)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf('::');
      if (separator > 0) {
        add(line.substring(0, separator), line.substring(separator + 2));
      } else {
        add('', line);
      }
    }
    return List.unmodifiable(entries);
  }

  /// Decodes the JSON-array `exploreUrl` form legado supports, e.g.
  /// `[{"title":"玄幻","url":"/sort/1/{{page}}.html"}, ...]` (pretty-printed
  /// or single-line). Returns null when the value is not a decodable array.
  static List<(String, String)>? _tryDecodeJsonEntries(String value) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return null;
    }
    if (decoded is! List) return null;
    final result = <(String, String)>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final title = item['title'];
      final url = item['url'];
      result.add((title is String ? title : '', url is String ? url : ''));
    }
    return result;
  }

  /// A usable explore URL is an absolute http(s) URL or a site-relative path.
  /// Bare fragments of shredded scripts or JSON (`}`, `});`, `[`,
  /// `{"title": ...`) are rejected so they can never surface as categories.
  static bool _isUsableExploreUrl(String url) {
    if (url.isEmpty) return false;
    if (url.startsWith('http://') || url.startsWith('https://')) return true;
    if (url.startsWith('/')) return true;
    // Relative path: after removing {{...}} template placeholders there must
    // be no JSON punctuation, quoting, or whitespace left.
    final stripped = url.replaceAll(RegExp(r'\{\{[^{}]*\}\}'), '');
    if (stripped.isEmpty) return true;
    return !RegExp(r'''[\s{}[\]"',;()\\]''').hasMatch(stripped);
  }

  Map<String, String> _rules(String key) => {
    for (final entry in definition.rules(key).entries)
      if (entry.value is String && (entry.value as String).isNotEmpty)
        entry.key: entry.value as String,
  };

  SourceCapabilityReport capabilitiesFor(SourceRuntimeProfile profile) =>
      definition.capabilitiesFor(profile);

  BookSource withEnabled(bool enabled) =>
      BookSource({...toJson(), 'enabled': enabled});

  Map<String, dynamic> toJson() => definition.toJson();
}
