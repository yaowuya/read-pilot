import 'source_capability.dart';
import 'source_definition.dart';

class SourceExploreEntry {
  const SourceExploreEntry({required this.title, required this.url});

  final String title;
  final String url;
}

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
    final entries = <SourceExploreEntry>[];
    for (final rawLine in value.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf('::');
      final title = separator > 0 ? line.substring(0, separator).trim() : name;
      final url = separator > 0 ? line.substring(separator + 2).trim() : line;
      if (title.isEmpty || url.isEmpty) continue;
      entries.add(SourceExploreEntry(title: title, url: url));
      if (entries.length == 200) break;
    }
    return List.unmodifiable(entries);
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
