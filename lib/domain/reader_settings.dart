enum ReaderTheme { paper, light, dark }

class ReaderSettings {
  const ReaderSettings({
    this.theme = ReaderTheme.paper,
    this.fontSize = 22,
    this.lineHeight = 1.9,
  });

  final ReaderTheme theme;
  final double fontSize;
  final double lineHeight;

  ReaderSettings copyWith({
    ReaderTheme? theme,
    double? fontSize,
    double? lineHeight,
  }) => ReaderSettings(
    theme: theme ?? this.theme,
    fontSize: (fontSize ?? this.fontSize).clamp(18, 32),
    lineHeight: (lineHeight ?? this.lineHeight).clamp(1.4, 2.4),
  );

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    final size = (json['fontSize'] as num?)?.toDouble() ?? 22;
    final height = (json['lineHeight'] as num?)?.toDouble() ?? 1.9;
    return ReaderSettings(
      theme: ReaderTheme.values.firstWhere(
        (theme) => theme.name == json['theme'],
        orElse: () => ReaderTheme.paper,
      ),
      fontSize: size.isFinite ? size.clamp(18, 32) : 22,
      lineHeight: height.isFinite ? height.clamp(1.4, 2.4) : 1.9,
    );
  }

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
  };
}
