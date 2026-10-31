import 'dart:math' as math;

class ReadingPosition {
  const ReadingPosition({this.chapterIndex = 0, this.paragraphIndex = 0});

  final int chapterIndex;
  final int paragraphIndex;

  factory ReadingPosition.fromJson(Map<String, dynamic> json) =>
      ReadingPosition(
        chapterIndex: math.max(0, (json['chapterIndex'] as num?)?.toInt() ?? 0),
        paragraphIndex: math.max(
          0,
          (json['paragraphIndex'] as num?)?.toInt() ?? 0,
        ),
      );

  Map<String, dynamic> toJson() => {
    'chapterIndex': chapterIndex,
    'paragraphIndex': paragraphIndex,
  };
}

class Chapter {
  Chapter({
    required this.id,
    required this.title,
    this.url,
    Iterable<String> paragraphs = const [],
  }) : paragraphs = List<String>.unmodifiable(paragraphs);

  final String id;
  final String title;
  final String? url;
  final List<String> paragraphs;

  bool get isCached => paragraphs.isNotEmpty;

  Chapter withParagraphs(List<String> value) =>
      Chapter(id: id, title: title, url: url, paragraphs: value);

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    id: json['id'] as String,
    title: json['title'] as String,
    url: json['url'] as String?,
    paragraphs: (json['paragraphs'] as List? ?? const []).cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (url != null) 'url': url,
    'paragraphs': paragraphs,
  };
}

class Book {
  Book({
    required String id,
    required String title,
    required String author,
    required String description,
    required String category,
    required int coverStyle,
    required String sourceLabel,
    required DateTime addedAt,
    bool isExcerpt = false,
    String provenance = '',
    String? sourceId,
    String? url,
    String? coverUrl,
    Iterable<Chapter> chapters = const [],
    ReadingPosition position = const ReadingPosition(),
    DateTime? lastOpenedAt,
    bool finished = false,
  }) : this._(
         id: id,
         title: title,
         author: author,
         description: description,
         category: category,
         coverStyle: coverStyle,
         sourceLabel: sourceLabel,
         addedAt: addedAt,
         isExcerpt: isExcerpt,
         provenance: provenance,
         sourceId: sourceId,
         url: url,
         coverUrl: coverUrl,
         chapters: List<Chapter>.unmodifiable(chapters),
         position: position,
         lastOpenedAt: lastOpenedAt,
         finished: finished,
       );

  Book._({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.category,
    required this.coverStyle,
    required this.sourceLabel,
    required this.addedAt,
    required this.isExcerpt,
    required this.provenance,
    required this.sourceId,
    required this.url,
    required this.coverUrl,
    required this.chapters,
    required this.position,
    required this.lastOpenedAt,
    required this.finished,
  });

  final String id;
  final String title;
  final String author;
  final String description;
  final String category;
  final int coverStyle;
  final String sourceLabel;
  final DateTime addedAt;
  final bool isExcerpt;
  final String provenance;
  final String? sourceId;
  final String? url;
  final String? coverUrl;
  final List<Chapter> chapters;
  final ReadingPosition position;
  final DateTime? lastOpenedAt;
  final bool finished;

  bool get isRemote => sourceId != null;
  bool get hasStarted => lastOpenedAt != null;
  int get cachedChapters =>
      chapters.where((chapter) => chapter.isCached).length;

  double get progress {
    if (finished) return 1;
    if (!hasStarted || chapters.isEmpty) return 0;
    final index = position.chapterIndex.clamp(0, chapters.length - 1);
    final count = chapters[index].paragraphs.length;
    final fraction = count == 0 ? 0.0 : position.paragraphIndex / count;
    return ((index + fraction.clamp(0, 1)) / chapters.length).clamp(0, 1);
  }

  String get progressLabel => finished
      ? '已读完'
      : hasStarted
      ? '已读 ${(progress * 100).round()}%'
      : '未读';

  Book copyWith({
    String? title,
    String? author,
    String? description,
    List<Chapter>? chapters,
    ReadingPosition? position,
    DateTime? lastOpenedAt,
    DateTime? addedAt,
    bool? finished,
    String? coverUrl,
  }) => Book._(
    id: id,
    title: title ?? this.title,
    author: author ?? this.author,
    description: description ?? this.description,
    category: category,
    coverStyle: coverStyle,
    sourceLabel: sourceLabel,
    addedAt: addedAt ?? this.addedAt,
    isExcerpt: isExcerpt,
    provenance: provenance,
    sourceId: sourceId,
    url: url,
    coverUrl: coverUrl ?? this.coverUrl,
    chapters: chapters == null
        ? this.chapters
        : List<Chapter>.unmodifiable(chapters),
    position: position ?? this.position,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    finished: finished ?? this.finished,
  );

  /// Rebinds a shelf record to a loaded remote result while preserving user state.
  /// Requires a remote replacement with a book URL; owns an immutable chapter copy.
  Book rebindSource(Book replacement, {required ReadingPosition position}) {
    if (!replacement.isRemote || replacement.url == null) {
      throw ArgumentError.value(replacement, 'replacement', 'must be remote');
    }
    return Book._(
      id: id,
      title: replacement.title.isEmpty ? title : replacement.title,
      author: replacement.author.isEmpty ? author : replacement.author,
      description: replacement.description.isEmpty
          ? description
          : replacement.description,
      category: replacement.category,
      coverStyle: coverStyle,
      sourceLabel: replacement.sourceLabel,
      addedAt: addedAt,
      isExcerpt: replacement.isExcerpt,
      provenance: replacement.provenance,
      sourceId: replacement.sourceId,
      url: replacement.url,
      coverUrl: replacement.coverUrl ?? coverUrl,
      chapters: List<Chapter>.unmodifiable(replacement.chapters),
      position: position,
      lastOpenedAt: lastOpenedAt,
      finished: finished,
    );
  }

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String,
    title: json['title'] as String,
    author: json['author'] as String? ?? '佚名',
    description: json['description'] as String? ?? '',
    category: json['category'] as String? ?? '文学',
    coverStyle: (json['coverStyle'] as num?)?.toInt() ?? 0,
    sourceLabel: json['sourceLabel'] as String? ?? '本地导入',
    addedAt: DateTime.parse(json['addedAt'] as String),
    isExcerpt: json['isExcerpt'] == true,
    provenance: json['provenance'] as String? ?? '',
    sourceId: json['sourceId'] as String?,
    url: json['url'] as String?,
    coverUrl: json['coverUrl'] as String?,
    chapters: (json['chapters'] as List? ?? []).map(
      (item) => Chapter.fromJson(Map<String, dynamic>.from(item as Map)),
    ),
    position: ReadingPosition.fromJson(
      Map<String, dynamic>.from(json['position'] as Map? ?? {}),
    ),
    lastOpenedAt: json['lastOpenedAt'] == null
        ? null
        : DateTime.parse(json['lastOpenedAt'] as String),
    finished: json['finished'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'description': description,
    'category': category,
    'coverStyle': coverStyle,
    'sourceLabel': sourceLabel,
    'addedAt': addedAt.toIso8601String(),
    'isExcerpt': isExcerpt,
    'provenance': provenance,
    if (sourceId != null) 'sourceId': sourceId,
    if (url != null) 'url': url,
    if (coverUrl != null) 'coverUrl': coverUrl,
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'position': position.toJson(),
    if (lastOpenedAt != null) 'lastOpenedAt': lastOpenedAt!.toIso8601String(),
    'finished': finished,
  };
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.quote,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final int chapterIndex;
  final int paragraphIndex;
  final String quote;
  final String note;
  final DateTime createdAt;

  /// Moves only the logical anchor, preserving identity, quote, note, and date.
  Bookmark copyWithPosition({
    required int chapterIndex,
    required int paragraphIndex,
  }) => Bookmark(
    id: id,
    bookId: bookId,
    chapterIndex: chapterIndex,
    paragraphIndex: paragraphIndex,
    quote: quote,
    note: note,
    createdAt: createdAt,
  );

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String,
    bookId: json['bookId'] as String,
    chapterIndex: (json['chapterIndex'] as num).toInt(),
    paragraphIndex: (json['paragraphIndex'] as num).toInt(),
    quote: json['quote'] as String,
    note: json['note'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'chapterIndex': chapterIndex,
    'paragraphIndex': paragraphIndex,
    'quote': quote,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };
}
