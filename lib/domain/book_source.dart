import 'dart:convert';

class BookSource {
  BookSource(Map<String, dynamic> json)
    : _json = Map.unmodifiable(_copyJson(json));

  final Map<String, dynamic> _json;

  String get id => _json['bookSourceUrl'] as String;
  String get name => _json['bookSourceName'] as String;
  bool get enabled => _json['enabled'] as bool? ?? true;
  String get searchUrl => _json['searchUrl'] as String;
  Map<String, String> get searchRules => _rules('ruleSearch');
  Map<String, String> get infoRules => _rules('ruleBookInfo');
  Map<String, String> get tocRules => _rules('ruleToc');
  Map<String, String> get contentRules => _rules('ruleContent');

  Map<String, String> _rules(String key) => {
    for (final entry in (_json[key] as Map? ?? {}).entries)
      if (entry.value is String && (entry.value as String).isNotEmpty)
        entry.key as String: entry.value as String,
  };

  BookSource withEnabled(bool enabled) =>
      BookSource({..._json, 'enabled': enabled});

  Map<String, dynamic> toJson() => _copyJson(_json);

  static Map<String, dynamic> _copyJson(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
}
