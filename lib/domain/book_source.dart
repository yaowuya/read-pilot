import 'explore_kind.dart';
import 'source_capability.dart';
import 'source_definition.dart';

/// One openable discover category.
///
/// Kept as the flat title/url pair the search page, health check, and controller
/// already pass around; [ExploreKindSet] remains the richer representation.
class SourceExploreEntry {
  const SourceExploreEntry({required this.title, required this.url});

  final String title;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is SourceExploreEntry && other.title == title && other.url == url;

  @override
  int get hashCode => Object.hash(title, url);
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

  /// Raw `bookSourceGroup` value, e.g. `玄幻,都市`.
  String get group => definition.group ?? '';

  /// Group names derived by [splitSourceGroups].
  List<String> get groups => definition.groups;

  /// Whether this source contributes categories to the discover page.
  bool get enabledExplore => definition.enabledExplore;

  String get comment => definition.comment ?? '';

  /// Legado's `customOrder`; lower sorts first and `0` is the default order.
  int get customOrder => definition.customOrder;

  /// Whether the source declares any discover workflow at all.
  bool get hasExplore =>
      (definition.exploreUrl ?? '').trim().isNotEmpty ||
      exploreRules.isNotEmpty;

  /// Discover categories parsed from `exploreUrl`.
  ///
  /// A script-generated `exploreUrl` reports [ExploreKindSet.unsupportedReason]
  /// instead of claiming the source has no categories.
  ExploreKindSet get exploreKindSet =>
      parseExploreKinds(definition.exploreUrl, sourceName: name);

  /// The legacy flat view of [exploreKindSet]: only openable categories.
  List<SourceExploreEntry> get exploreEntries => [
    for (final kind in exploreKindSet.loadableKinds)
      SourceExploreEntry(title: kind.title, url: kind.url!),
  ];

  Map<String, String> _rules(String key) => {
    for (final entry in definition.rules(key).entries)
      if (entry.value is String && (entry.value as String).isNotEmpty)
        entry.key: entry.value as String,
  };

  SourceCapabilityReport capabilitiesFor(SourceRuntimeProfile profile) =>
      definition.capabilitiesFor(profile);

  /// Returns a copy with individual raw fields replaced.
  ///
  /// Every mutation goes through raw JSON so unknown legado fields the user
  /// imported keep surviving the round trip.
  BookSource withFields(Map<String, Object?> fields) {
    final json = toJson();
    for (final entry in fields.entries) {
      if (entry.value == null) {
        json.remove(entry.key);
      } else {
        json[entry.key] = entry.value;
      }
    }
    return BookSource(json);
  }

  BookSource withEnabled(bool enabled) => withFields({'enabled': enabled});

  BookSource withEnabledExplore(bool enabledExplore) =>
      withFields({'enabledExplore': enabledExplore});

  /// Replaces the group membership list, writing the joined
  /// `bookSourceGroup` form legado expects.
  BookSource withGroups(List<String> groups) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final group in groups) {
      final name = group.trim();
      if (name.isEmpty || !seen.add(name)) continue;
      normalized.add(name);
    }
    return withFields({
      'bookSourceGroup': normalized.isEmpty ? null : normalized.join(','),
    });
  }

  BookSource withCustomOrder(int order) => withFields({'customOrder': order});

  BookSource withComment(String comment) => withFields({
    'bookSourceComment': comment.trim().isEmpty ? null : comment,
  });

  BookSource withName(String name) =>
      withFields({'bookSourceName': name.trim()});

  Map<String, dynamic> toJson() => definition.toJson();
}
