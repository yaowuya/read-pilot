enum ReaderTheme { paper, light, dark, sage, mist }

enum ReaderFlow { paged, scrolling }

/// Persisted reading preferences with backward-compatible defaults.
class ReaderSettings {
  const ReaderSettings({
    this.theme = ReaderTheme.paper,
    this.flow = ReaderFlow.paged,
    this.fontSize = 22,
    this.lineHeight = 1.9,
    this.paragraphSpacing = 20,
    this.boldText = false,
    this.tocDescending = false,
  });

  final ReaderTheme theme;
  final ReaderFlow flow;
  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final bool boldText;
  final bool tocDescending;

  ReaderSettings copyWith({
    ReaderTheme? theme,
    ReaderFlow? flow,
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    bool? boldText,
    bool? tocDescending,
  }) => ReaderSettings(
    theme: theme ?? this.theme,
    flow: flow ?? this.flow,
    fontSize: (fontSize ?? this.fontSize).clamp(18, 32),
    lineHeight: (lineHeight ?? this.lineHeight).clamp(1.4, 2.4),
    paragraphSpacing: _spacing(paragraphSpacing ?? this.paragraphSpacing),
    boldText: boldText ?? this.boldText,
    tocDescending: tocDescending ?? this.tocDescending,
  );

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    final size = (json['fontSize'] as num?)?.toDouble() ?? 22;
    final height = (json['lineHeight'] as num?)?.toDouble() ?? 1.9;
    final spacing = json['paragraphSpacing'];
    return ReaderSettings(
      theme: ReaderTheme.values.firstWhere(
        (theme) => theme.name == json['theme'],
        orElse: () => ReaderTheme.paper,
      ),
      flow: ReaderFlow.values.firstWhere(
        (flow) => flow.name == json['flow'],
        orElse: () => ReaderFlow.paged,
      ),
      fontSize: size.isFinite ? size.clamp(18, 32) : 22,
      lineHeight: height.isFinite ? height.clamp(1.4, 2.4) : 1.9,
      paragraphSpacing: _spacing(spacing is num ? spacing.toDouble() : 20),
      boldText: json['boldText'] == true,
      tocDescending: json['tocDescending'] == true,
    );
  }

  static double _spacing(double value) =>
      value.isFinite ? value.clamp(0, 40) : 20;

  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'flow': flow.name,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'paragraphSpacing': paragraphSpacing,
    'boldText': boldText,
    'tocDescending': tocDescending,
  };
}
