enum ReaderMarkColor { amber, mint, blue }

final class ReaderMarkLocation {
  const ReaderMarkLocation({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.paragraphIndex,
    required this.paragraph,
  });

  final int chapterIndex;
  final String chapterTitle;
  final int paragraphIndex;
  final String paragraph;
}

final class ReaderMark {
  const ReaderMark({
    required this.id,
    required this.bookId,
    required this.sourceId,
    required this.chapterId,
    required this.paragraphIndex,
    required this.paragraphFingerprint,
    required this.color,
    required this.note,
    this.selectedText,
    required this.createdAt,
  });

  static const maxPerBook = 100;
  static const maxNoteCharacters = 240;
  static const maxSelectedTextCharacters = 240;

  final String id;
  final String bookId;
  final String? sourceId;
  final String chapterId;
  final int paragraphIndex;
  final String paragraphFingerprint;
  final ReaderMarkColor color;
  final String note;
  final String? selectedText;
  final DateTime createdAt;

  static String fingerprint(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit).toUnsigned(32);
    }
    return '${value.length.toRadixString(36)}-${hash.toRadixString(16)}';
  }

  static void validateNote(String value) {
    if (value.runes.length > maxNoteCharacters || value.contains('\u0000')) {
      throw const FormatException('标注备注不能超过 240 个字符或包含空字符。');
    }
  }

  static String? validateSelectedText(String? value) {
    if (value == null) return null;
    if (value.isEmpty ||
        value.runes.length > maxSelectedTextCharacters ||
        value.contains('\u0000')) {
      throw const FormatException('选中文字需为 1–240 个字符且不能包含空字符。');
    }
    return value;
  }

  static bool hasUniqueOccurrence(String paragraph, String selectedText) {
    final first = paragraph.indexOf(selectedText);
    return first >= 0 && paragraph.indexOf(selectedText, first + 1) < 0;
  }

  factory ReaderMark.fromJson(Map<String, dynamic> json) {
    final paragraphIndex = json['paragraphIndex'];
    if (json['id'] is! String ||
        json['bookId'] is! String ||
        (json['sourceId'] != null && json['sourceId'] is! String) ||
        json['chapterId'] is! String ||
        json['paragraphFingerprint'] is! String ||
        paragraphIndex is! num ||
        paragraphIndex.toInt() < 0 ||
        json['color'] is! String ||
        json['note'] is! String ||
        (json['selectedText'] != null && json['selectedText'] is! String) ||
        json['createdAt'] is! String) {
      throw const FormatException('段落标注记录无效。');
    }
    final color = ReaderMarkColor.values
        .where((candidate) => candidate.name == json['color'])
        .firstOrNull;
    if (color == null || (json['paragraphFingerprint'] as String).isEmpty) {
      throw const FormatException('段落标注记录无效。');
    }
    final note = json['note'] as String;
    validateNote(note);
    return ReaderMark(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      sourceId: json['sourceId'] as String?,
      chapterId: json['chapterId'] as String,
      paragraphIndex: paragraphIndex.toInt(),
      paragraphFingerprint: json['paragraphFingerprint'] as String,
      color: color,
      note: note,
      selectedText: validateSelectedText(json['selectedText'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    if (sourceId != null) 'sourceId': sourceId,
    'chapterId': chapterId,
    'paragraphIndex': paragraphIndex,
    'paragraphFingerprint': paragraphFingerprint,
    'color': color.name,
    'note': note,
    if (selectedText != null) 'selectedText': selectedText,
    'createdAt': createdAt.toIso8601String(),
  };
}
