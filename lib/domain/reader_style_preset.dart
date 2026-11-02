import 'reader_settings.dart';

final class ReaderStylePreset {
  const ReaderStylePreset({
    required this.id,
    required this.name,
    required this.settings,
    required this.createdAt,
  });

  final String id;
  final String name;
  final ReaderSettings settings;
  final DateTime createdAt;

  factory ReaderStylePreset.fromJson(String id, Map<String, dynamic> json) {
    if (json['name'] is! String ||
        json['settings'] is! Map ||
        json['createdAt'] is! String) {
      throw const FormatException('阅读样式预设无效。');
    }
    return ReaderStylePreset(
      id: id,
      name: json['name'] as String,
      settings: ReaderSettings.fromJson(
        Map<String, dynamic>.from(json['settings'] as Map),
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'settings': settings.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };
}
