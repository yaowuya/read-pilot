final class ShelfGroup {
  ShelfGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    Iterable<String> bookIds = const [],
  }) : bookIds = Set.unmodifiable(bookIds);

  final String id;
  final String name;
  final DateTime createdAt;
  final Set<String> bookIds;

  bool containsBook(String bookId) => bookIds.contains(bookId);

  ShelfGroup withoutBook(String bookId) => ShelfGroup(
    id: id,
    name: name,
    createdAt: createdAt,
    bookIds: bookIds.where((id) => id != bookId),
  );

  factory ShelfGroup.fromJson(String id, Map<String, dynamic> json) =>
      ShelfGroup(
        id: id,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        bookIds: (json['bookIds'] as List? ?? const []).cast<String>(),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'bookIds': bookIds.toList(),
  };
}
