import 'explore_kind.dart';
import 'source_capability.dart';
import 'source_definition.dart';
import 'source_health.dart';

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

  /// Legado's `concurrentRate`, e.g. `3/1000`; empty means unlimited.
  String get concurrentRate => definition.concurrentRate ?? '';

  /// Milliseconds the source took to answer the last successful health check.
  ///
  /// `0` means "never measured". Legado writes `timeout + elapsed` on failure so
  /// a dead source sorts last instead of looking fast.
  int get respondTime => definition.respondTime;

  /// Legado's `lastUpdateTime`, used to decide whether an import is newer.
  int get lastUpdateTime => definition.lastUpdateTime;

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

  /// Records how long the source took to answer.
  ///
  /// Legado stores this as `respondTime` in milliseconds; the source list sorts
  /// on it so a consistently slow or dead source sinks to the bottom.
  BookSource withRespondTime(int milliseconds) =>
      withFields({'respondTime': milliseconds});

  /// Adds every name in [names] that is not already present.
  ///
  /// Mirrors Legado's `BookSource.addGroup`, which unions the new names into the
  /// existing set and re-joins them, so a health check tag never duplicates.
  BookSource addGroups(Iterable<String> names) {
    final merged = [...groups];
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isEmpty || merged.contains(trimmed)) continue;
      merged.add(trimmed);
    }
    return withGroups(merged);
  }

  /// Removes every name in [names]; a missing name is not an error.
  BookSource removeGroups(Iterable<String> names) {
    final dropped = names.map((name) => name.trim()).toSet();
    return withGroups([
      for (final group in groups)
        if (!dropped.contains(group)) group,
    ]);
  }

  bool hasGroup(String name) => groups.contains(name.trim());

  /// Group names that a health check decided are invalid.
  ///
  /// Legado marks a broken stage by adding tags to `bookSourceGroup`, and treats
  /// any tag containing `失效` plus the literal `校验超时` as invalid on the next
  /// run. Keeping the same rule means tags written by Legado itself are
  /// recognised here instead of piling up forever.
  List<String> get invalidGroups => [
    for (final group in groups)
      if (SourceHealthTag.isInvalid(group)) group,
  ];

  /// Drops the tags [invalidGroups] lists. Called before a fresh check.
  BookSource removeInvalidGroups() => removeGroups(invalidGroups);

  /// The source comment without the `// Error:` blocks a check appended.
  ///
  /// Legado splits the comment on `\n\n` and discards every paragraph that
  /// starts with [errorCommentPrefix], which is how it keeps a user's own note
  /// while clearing stale diagnostics.
  String get cleanComment {
    final kept = <String>[];
    for (final block in comment.split(RegExp(r'\n\n'))) {
      if (block.trimLeft().startsWith(errorCommentPrefix)) continue;
      if (block.trim().isEmpty) continue;
      kept.add(block);
    }
    return kept.join('\n\n');
  }

  BookSource removeErrorComment() => withComment(cleanComment);

  /// Prepends one `// Error:` block, like Legado's `addErrorComment`.
  BookSource addErrorComment(Object error) {
    final message = error is FormatException ? error.message : '$error';
    final existing = cleanComment;
    final block = '$errorCommentPrefix $message';
    return withComment(existing.isEmpty ? block : '$block\n\n$existing');
  }

  static const errorCommentPrefix = '// Error:';

  Map<String, dynamic> toJson() => definition.toJson();
}
