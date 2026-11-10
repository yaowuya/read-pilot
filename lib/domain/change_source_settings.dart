/// 换源面板的搜索开关，对应 Legado 的 `ChangeSourceSettings`。
///
/// Legado 用 `checkAuthor` 过滤同名不同作者的书、用 `loadWordCount` 决定是否
/// 按字数排序；本项目的候选行始终加载章节与字数（换源面板的核心信息），所以
/// 这里不保留 `loadInfo`/`loadToc`/`loadWordCount` 三个「是否加载」开关，而是
/// 直接把「按字数排序」作为一个独立开关暴露出来。
class ChangeSourceSettings {
  const ChangeSourceSettings({
    this.checkAuthor = false,
    this.sortByWordCount = false,
  });

  /// 只保留作者一致（包含关系）的候选，避免把同名不同作者的书写进书架。
  ///
  /// 默认关闭，与 Legado `ChangeSourceSettings.checkAuthor = false` 一致：
  /// 作者写法在不同书源之间常有差异，强制过滤会漏掉可用候选。
  final bool checkAuthor;

  /// 按字数从多到少排序，优先展示内容更完整的书源。
  ///
  /// 对应 Legado 在 `loadWordCount` 打开时的比较器：
  /// `chapterWordCount > 1000` 优先，再按章节数、字数降序。
  final bool sortByWordCount;

  ChangeSourceSettings copyWith({bool? checkAuthor, bool? sortByWordCount}) =>
      ChangeSourceSettings(
        checkAuthor: checkAuthor ?? this.checkAuthor,
        sortByWordCount: sortByWordCount ?? this.sortByWordCount,
      );

  factory ChangeSourceSettings.fromJson(Map<String, dynamic> json) =>
      ChangeSourceSettings(
        checkAuthor: json['checkAuthor'] == true,
        sortByWordCount: json['sortByWordCount'] == true,
      );

  Map<String, dynamic> toJson() => {
    'checkAuthor': checkAuthor,
    'sortByWordCount': sortByWordCount,
  };
}
