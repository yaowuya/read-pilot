import 'dart:convert';

/// Kind of one explore row item, mirroring legado's `ExploreKind.Type`.
///
/// Legado's discover page renders every category as a row item whose widget is
/// chosen by this type: [url] navigates to a book list, while [text], [select],
/// [toggle] and [button] collect or act on parameters before any request is
/// made. The collected parameters live in a per-source info map and reach the
/// request URL as `{{name}}` placeholders.
enum ExploreKindType {
  /// Opens the book list at [ExploreKind.url].
  url('url'),

  /// Collects a free-form value into the source's explore info map.
  text('text'),

  /// Runs [ExploreKind.action] against the current info map.
  button('button'),

  /// Cycles through [ExploreKind.chars].
  toggle('toggle'),

  /// Picks one of [ExploreKind.chars].
  select('select');

  const ExploreKindType(this.wireName);

  /// The `type` value used by legado's `exploreUrl` JSON.
  final String wireName;

  /// Unknown or absent types fall back to [url], which is also legado's default.
  static ExploreKindType parse(String? value) {
    final normalized = value?.trim().toLowerCase();
    for (final type in values) {
      if (type.wireName == normalized) return type;
    }
    return ExploreKindType.url;
  }
}

/// Flex layout hints carried by an explore kind, mirroring legado's
/// `FlexChildStyle`.
///
/// Only the fields that decide how many row items share one line are modelled:
/// [flexGrow] makes a plain item 3-across, [basisPercent] asks for a fraction of
/// the row, and [wrapBefore] forces a full-width item ahead of the rest.
class ExploreKindStyle {
  const ExploreKindStyle({
    this.flexGrow = 0,
    this.basisPercent = -1,
    this.wrapBefore = false,
    this.justifySelf,
    this.alignSelf,
  });

  final double flexGrow;
  final double basisPercent;
  final bool wrapBefore;
  final String? justifySelf;
  final String? alignSelf;

  /// How many of legado's 12 layout spans this item asks for.
  ///
  /// Mirrors `calculateExploreKindRows`: a wrapping or full-basis item takes the
  /// whole row, a percentage takes that fraction, a growing item takes a third,
  /// and everything else takes a half.
  int spanFor(int maxSpan) {
    if (wrapBefore || basisPercent >= 1.0) return maxSpan;
    if (basisPercent > 0) {
      return (maxSpan * basisPercent).round().clamp(1, maxSpan);
    }
    if (flexGrow > 0) return maxSpan >= 3 ? 3 : maxSpan;
    return maxSpan >= 2 ? 2 : maxSpan;
  }

  static ExploreKindStyle fromJson(Object? value) {
    if (value is! Map) return const ExploreKindStyle();
    double readDouble(String key, double fallback) {
      final raw = value[key];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw.trim()) ?? fallback;
      return fallback;
    }

    String? readString(String key) {
      final raw = value[key];
      return raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
    }

    return ExploreKindStyle(
      flexGrow: readDouble('layout_flexGrow', 0),
      basisPercent: readDouble('layout_flexBasisPercent', -1),
      wrapBefore: value['layout_wrapBefore'] == true,
      justifySelf: readString('layout_justifySelf'),
      alignSelf: readString('layout_alignSelf'),
    );
  }
}

/// One discover category row, mirroring legado's `ExploreKind`.
///
/// [title] doubles as the info-map key for every non-[ExploreKindType.url] type,
/// which is how legado threads a text field's value into a category's URL.
class ExploreKind {
  const ExploreKind({
    required this.title,
    this.url,
    this.type = ExploreKindType.url,
    this.action,
    this.chars = const <String>[],
    this.defaultValue,
    this.viewName,
    this.style = const ExploreKindStyle(),
    this.errorMessage,
  });

  final String title;
  final String? url;
  final ExploreKindType type;
  final String? action;
  final List<String> chars;
  final String? defaultValue;
  final String? viewName;
  final ExploreKindStyle style;
  final String? errorMessage;

  /// Stable identity for pager keys and saved preferences, mirroring legado's
  /// `exploreKindKey`: the title length keeps `a:bc` and `a:b:c` distinct.
  String get key => '${title.length}:$title:${url ?? ''}';

  /// Whether this kind can be opened as a book list.
  bool get isLoadable =>
      errorMessage == null &&
      type == ExploreKindType.url &&
      (url ?? '').trim().isNotEmpty;

  bool get isError => errorMessage != null;

  /// Values a toggle/select kind cycles through.
  ///
  /// Legado defaults a toggle to `["chars", "is null"]`, which is the wire form
  /// of "on by default".
  List<String> get cycleValues =>
      chars.isEmpty ? const <String>['chars', 'is null'] : chars;

  ExploreKind withDefault(String? value) => ExploreKind(
    title: title,
    url: url,
    type: type,
    action: action,
    chars: chars,
    defaultValue: value,
    viewName: viewName,
    style: style,
    errorMessage: errorMessage,
  );

  @override
  bool operator ==(Object other) =>
      other is ExploreKind &&
      other.title == title &&
      other.type == type &&
      other.url == url &&
      other.action == action &&
      other.defaultValue == defaultValue;

  @override
  int get hashCode => Object.hash(title, type, url, action, defaultValue);

  @override
  String toString() => 'ExploreKind($title, ${type.wireName}, ${url ?? ''})';
}

/// Result of reading one source's `exploreUrl`.
///
/// A source either declares categories statically (legacy `标题::地址` lines or
/// a JSON array) or generates them with a script. Scripts need a JS runtime this
/// app does not ship, so those sources report [unsupportedReason] instead of
/// pretending they have no categories.
class ExploreKindSet {
  const ExploreKindSet({
    this.kinds = const <ExploreKind>[],
    this.unsupportedReason,
  });

  const ExploreKindSet.empty()
    : kinds = const <ExploreKind>[],
      unsupportedReason = null;

  final List<ExploreKind> kinds;
  final String? unsupportedReason;

  bool get isUnsupported => unsupportedReason != null;
  bool get isEmpty => kinds.isEmpty;

  /// Categories the pager can actually open, in declaration order.
  List<ExploreKind> get loadableKinds => loadableExploreKinds(kinds);
}

/// Legado's `loadableExploreMainKinds`: only url categories with a URL can be
/// paged through, and a duplicate `(title, url)` pair would collide on the pager
/// key, so the first one wins.
List<ExploreKind> loadableExploreKinds(List<ExploreKind> kinds) {
  final seen = <String>{};
  final result = <ExploreKind>[];
  for (final kind in kinds) {
    if (!kind.isLoadable) continue;
    if (!seen.add('${kind.title}\u{0}${kind.url}')) continue;
    result.add(kind);
  }
  return List.unmodifiable(result);
}

/// Cap on categories per source.
///
/// Legado has no explicit cap, but a malformed aggregate source can declare tens
/// of thousands of rows; the discover page renders them in one scrollable list,
/// so the cap keeps a bad import from stalling the frame budget.
const int maxExploreKinds = 200;

/// Whole-value script markers mirrored from legado's `exploreKinds`: such
/// `exploreUrl` values need a JS runtime this app does not ship, so they yield no
/// static categories instead of junk fragments.
final RegExp _scriptExploreUrl = RegExp(
  r'^\s*(?:@js:|@webjs:|<js>|<webjs>)',
  caseSensitive: false,
);

/// Splits the legacy `标题::地址` list the same way legado does: on newlines and
/// the literal `&&` separator.
final RegExp _legacyExploreSeparator = RegExp(r'(?:&&|[\r\n])+');

/// Parses one source's `exploreUrl` into discover categories.
///
/// [sourceName] names a category whose legacy line omitted its title, matching
/// the previous behaviour where such a line inherited the source name.
ExploreKindSet parseExploreKinds(
  String? exploreUrl, {
  required String sourceName,
}) {
  final value = exploreUrl;
  if (value == null || value.trim().isEmpty) {
    return const ExploreKindSet.empty();
  }
  if (_scriptExploreUrl.hasMatch(value)) {
    return const ExploreKindSet(unsupportedReason: '该书的发现分类由脚本生成，当前版本无法加载。');
  }

  final kinds = <ExploreKind>[];
  final seen = <String>{};

  void add(ExploreKind kind, {bool inheritSourceName = false}) {
    if (kinds.length >= maxExploreKinds) return;
    final rawTitle = kind.title.trim();
    final title = rawTitle.isEmpty && inheritSourceName
        ? sourceName.trim()
        : rawTitle;
    if (title.isEmpty) return;
    if (kind.type == ExploreKindType.url &&
        !isUsableExploreUrl((kind.url ?? '').trim())) {
      return;
    }
    final dedupeKey =
        '$title\u{0}${kind.type.wireName}\u{0}${kind.url ?? ''}'
        '\u{0}${kind.action ?? ''}\u{0}${kind.defaultValue ?? ''}';
    if (!seen.add(dedupeKey)) return;
    kinds.add(
      ExploreKind(
        title: title,
        url: kind.url,
        type: kind.type,
        action: kind.action,
        chars: kind.chars,
        defaultValue: kind.defaultValue,
        viewName: kind.viewName,
        style: kind.style,
        errorMessage: kind.errorMessage,
      ),
    );
  }

  final trimmed = value.trim();
  if (trimmed.startsWith('[')) {
    final decoded = _tryDecodeJsonKinds(trimmed);
    if (decoded != null) {
      for (final kind in decoded) {
        add(kind);
      }
      return ExploreKindSet(kinds: List.unmodifiable(kinds));
    }
  }
  for (final rawLine in value.split(_legacyExploreSeparator)) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final separator = line.indexOf('::');
    if (separator > 0) {
      add(
        ExploreKind(
          title: line.substring(0, separator),
          url: line.substring(separator + 2),
        ),
      );
    } else {
      add(ExploreKind(title: '', url: line), inheritSourceName: true);
    }
  }
  return ExploreKindSet(kinds: List.unmodifiable(kinds));
}

/// Decodes the JSON-array `exploreUrl` form legado supports, e.g.
/// `[{"title":"玄幻","url":"/sort/1/{{page}}.html"}, ...]`.
///
/// Returns null when the value is not a decodable array so the caller can fall
/// back to the legacy list, and a single error kind when the array is decodable
/// but every element is unusable.
List<ExploreKind>? _tryDecodeJsonKinds(String value) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(value);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;
  final kinds = <ExploreKind>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final title = item['title'];
    final url = item['url'];
    final action = item['action'];
    final defaultValue = item['default'];
    final viewName = item['viewName'];
    kinds.add(
      ExploreKind(
        title: title is String ? title : '',
        url: url is String ? url : null,
        type: ExploreKindType.parse(item['type'] as String?),
        action: action is String ? action : null,
        chars: _stringList(item['chars']),
        defaultValue: defaultValue is String ? defaultValue : null,
        viewName: viewName is String ? viewName : null,
        style: ExploreKindStyle.fromJson(item['style']),
      ),
    );
  }
  return kinds;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return List.unmodifiable([
    for (final item in value)
      if (item != null) item.toString(),
  ]);
}

/// The discover page's remembered source and category, mirroring legado's
/// `exploreMainSourceUrl` + `exploreMainKind` preferences.
///
/// Legado stores one `sourceUrl\u0000kindKey` slot per source so switching back to
/// a source restores the category the user last read there; [kindKeyBySource]
/// keeps that same shape.
class ExploreMainSelection {
  const ExploreMainSelection({
    this.sourceUrl,
    this.kindKeyBySource = const <String, String>{},
    this.showContent = false,
  });

  /// Last opened source, or null before the user ever opened one.
  final String? sourceUrl;

  /// Category key per source URL, from [ExploreKind.key].
  final Map<String, String> kindKeyBySource;

  /// Whether the discover page shows the paged content mode instead of the
  /// source list.
  final bool showContent;

  String? kindKeyFor(String? sourceUrl) =>
      sourceUrl == null ? null : kindKeyBySource[sourceUrl];

  ExploreMainSelection withSource(String? sourceUrl) => ExploreMainSelection(
    sourceUrl: sourceUrl,
    kindKeyBySource: kindKeyBySource,
    showContent: showContent,
  );

  ExploreMainSelection withKind(String sourceUrl, String kindKey) =>
      ExploreMainSelection(
        sourceUrl: this.sourceUrl,
        kindKeyBySource: {...kindKeyBySource, sourceUrl: kindKey},
        showContent: showContent,
      );

  ExploreMainSelection withShowContent(bool showContent) =>
      ExploreMainSelection(
        sourceUrl: sourceUrl,
        kindKeyBySource: kindKeyBySource,
        showContent: showContent,
      );
}

/// A usable explore URL is an absolute http(s) URL or a site-relative path.
///
/// Bare fragments of shredded scripts or JSON (`}`, `});`, `[`, `{"title": ...`)
/// are rejected so they can never surface as categories.
bool isUsableExploreUrl(String url) {
  if (url.isEmpty) return false;
  if (url.startsWith('http://') || url.startsWith('https://')) return true;
  if (url.startsWith('/')) return true;
  // Relative path: after removing `{{...}}` placeholders there must be no JSON
  // punctuation, quoting, or whitespace left.
  final stripped = url.replaceAll(RegExp(r'\{\{[^{}]*\}\}'), '');
  if (stripped.isEmpty) return true;
  return !RegExp(r'''[\s{}[\]"',;()\\]''').hasMatch(stripped);
}
