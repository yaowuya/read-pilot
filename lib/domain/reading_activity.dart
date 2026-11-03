enum ReadingActivityKind { opened, chapter, finished }

final class ReadingActivity {
  const ReadingActivity({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.author,
    required this.sourceId,
    required this.chapterIndex,
    required this.chapterId,
    required this.chapterTitle,
    required this.kind,
    required this.occurredAt,
  });

  static const maxEntries = 200;
  static const dedupeWindow = Duration(seconds: 30);

  final String id;
  final String bookId;
  final String bookTitle;
  final String author;
  final String? sourceId;
  final int chapterIndex;
  final String chapterId;
  final String chapterTitle;
  final ReadingActivityKind kind;
  final DateTime occurredAt;

  factory ReadingActivity.fromJson(Map<String, dynamic> json) {
    final chapterIndex = json['chapterIndex'];
    final kind = ReadingActivityKind.values
        .where((candidate) => candidate.name == json['kind'])
        .firstOrNull;
    if (json['id'] is! String ||
        json['bookId'] is! String ||
        json['bookTitle'] is! String ||
        json['author'] is! String ||
        (json['sourceId'] != null && json['sourceId'] is! String) ||
        json['chapterId'] is! String ||
        json['chapterTitle'] is! String ||
        chapterIndex is! num ||
        chapterIndex.toInt() < 0 ||
        kind == null ||
        json['occurredAt'] is! String) {
      throw const FormatException('阅读足迹记录无效。');
    }
    return ReadingActivity(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      bookTitle: json['bookTitle'] as String,
      author: json['author'] as String,
      sourceId: json['sourceId'] as String?,
      chapterIndex: chapterIndex.toInt(),
      chapterId: json['chapterId'] as String,
      chapterTitle: json['chapterTitle'] as String,
      kind: kind,
      occurredAt: DateTime.parse(json['occurredAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'bookTitle': bookTitle,
    'author': author,
    if (sourceId != null) 'sourceId': sourceId,
    'chapterIndex': chapterIndex,
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'kind': kind.name,
    'occurredAt': occurredAt.toIso8601String(),
  };
}
