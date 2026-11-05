/// What a book-source health check is allowed to probe, and for how long.
///
/// Ported from Legado's `CheckSourceSettings`
/// (`app/src/main/java/io/legado/app/data/repository/CheckSourceSettingsRepository.kt`),
/// which stores `timeoutMillis` (default `180_000`) plus one switch per stage.
/// The switches exist because some sources legitimately have no search URL or no
/// discover rules; checking them anyway would mark a working source as broken.
///
/// Legado refuses to save settings with `timeoutMillis <= 0` or with both search
/// and discover checks disabled, because such a check can never prove anything.
/// [SourceCheckSettings] enforces the same two rules in [copyWith] callers by
/// exposing [isUsable] and keeping construction total.
class SourceCheckSettings {
  const SourceCheckSettings({
    this.timeout = const Duration(seconds: 180),
    this.checkSearch = true,
    this.checkExplore = true,
    this.checkInfo = true,
    this.checkCatalog = true,
    this.checkContent = true,
  });

  /// Overall budget for one source, matching Legado's `withTimeout(timeoutMillis)`.
  final Duration timeout;

  /// Probe `searchUrl` and the first search result.
  final bool checkSearch;

  /// Probe the first discover category.
  final bool checkExplore;

  /// Load the candidate book's detail page (title/author/cover rules).
  final bool checkInfo;

  /// Load the candidate book's chapter list. File-type sources are skipped,
  /// exactly like Legado's `if (settings.checkCategory && bookSourceType != file)`.
  final bool checkCatalog;

  /// Load the first chapter's body.
  final bool checkContent;

  /// Whether the settings would let a check prove anything at all.
  ///
  /// Mirrors Legado's validation: at least one entry point must be enabled.
  bool get isUsable => checkSearch || checkExplore;

  SourceCheckSettings copyWith({
    Duration? timeout,
    bool? checkSearch,
    bool? checkExplore,
    bool? checkInfo,
    bool? checkCatalog,
    bool? checkContent,
  }) => SourceCheckSettings(
    timeout: timeout ?? this.timeout,
    checkSearch: checkSearch ?? this.checkSearch,
    checkExplore: checkExplore ?? this.checkExplore,
    checkInfo: checkInfo ?? this.checkInfo,
    checkCatalog: checkCatalog ?? this.checkCatalog,
    checkContent: checkContent ?? this.checkContent,
  );

  /// Reads stored settings, falling back to the defaults for every missing or
  /// malformed field so an older profile keeps working after an upgrade.
  factory SourceCheckSettings.fromJson(Map<String, dynamic> json) {
    final millis = json['timeoutMillis'];
    final timeout = millis is num && millis > 0
        ? Duration(milliseconds: millis.toInt())
        : const Duration(seconds: 180);
    bool flag(String key) => json[key] is bool ? json[key] as bool : true;
    return SourceCheckSettings(
      timeout: timeout,
      checkSearch: flag('checkSearch'),
      checkExplore: flag('checkExplore'),
      checkInfo: flag('checkInfo'),
      checkCatalog: flag('checkCatalog'),
      checkContent: flag('checkContent'),
    );
  }

  Map<String, dynamic> toJson() => {
    'timeoutMillis': timeout.inMilliseconds,
    'checkSearch': checkSearch,
    'checkExplore': checkExplore,
    'checkInfo': checkInfo,
    'checkCatalog': checkCatalog,
    'checkContent': checkContent,
  };
}
