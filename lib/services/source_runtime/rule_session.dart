/// Bounded in-memory variables for one source-engine workflow call.
///
/// Lifetime is a single `search` / `loadBook` / `loadChapter` (or explore)
/// invocation. Values are never shared across book sources or persisted.
final class RuleSession {
  RuleSession({
    this.maxEntries = 32,
    this.maxKeyCharacters = 64,
    this.maxValueCharacters = 4096,
  });

  final int maxEntries;
  final int maxKeyCharacters;
  final int maxValueCharacters;
  final Map<String, String> _values = {};

  int get length => _values.length;

  void clear() => _values.clear();

  String get(String key) => _values[key] ?? '';

  /// Stores [value] under [key]. Oversized or overflowing writes are rejected.
  void put(String key, String value) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty ||
        normalizedKey.length > maxKeyCharacters ||
        value.length > maxValueCharacters) {
      throw const FormatException('规则变量超出安全限制。');
    }
    if (!_values.containsKey(normalizedKey) && _values.length >= maxEntries) {
      throw const FormatException('规则变量数量超出安全限制。');
    }
    _values[normalizedKey] = value;
  }
}
