import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/book.dart';

Future<List<Book>>? _catalog;

Future<List<Book>> loadSampleCatalog() => _catalog ??= _load();

Future<List<Book>> _load() async {
  final raw =
      jsonDecode(await rootBundle.loadString('assets/books/catalog.json'))
          as List;
  final books = <Book>[];
  for (final item in raw) {
    final json = Map<String, dynamic>.from(item as Map);
    final asset = json.remove('contentAsset') as String?;
    if (asset != null) {
      final chapters = jsonDecode(await rootBundle.loadString(asset)) as List;
      json['chapters'] = [
        for (var index = 0; index < chapters.length; index++)
          {
            ...Map<String, dynamic>.from(chapters[index] as Map),
            'id': '${json['id']}-$index',
          },
      ];
    }
    books.add(Book.fromJson(json));
  }
  return List.unmodifiable(books);
}
