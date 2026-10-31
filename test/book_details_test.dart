import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/book_cover.dart';
import 'package:read_pilot/ui/components/book_details.dart';
import 'package:sembast/sembast_memory.dart';

Book _remoteBook({
  String id = 'shelf-book',
  String sourceId = 'https://old.example',
  String sourceLabel = '旧源',
  String? coverUrl,
}) => Book(
  id: id,
  title: '测试书',
  author: '测试作者',
  description: '简介',
  category: '文学',
  coverStyle: 0,
  sourceLabel: sourceLabel,
  sourceId: sourceId,
  url: '$sourceId/book',
  coverUrl: coverUrl,
  chapters: [
    Chapter(
      id: '$sourceId/chapter',
      title: '第一章',
      url: '$sourceId/chapter',
      paragraphs: const ['正文'],
    ),
  ],
  addedAt: DateTime.utc(2026),
);

class _DetailsController extends AppController {
  _DetailsController(super.repository, super.engine, this.current);

  Book current;
  List<Book> candidates = [];
  int failedSources = 0;
  Object? candidateError;
  Object? coverError;
  bool switched = false;
  bool refreshed = false;

  @override
  Book? book(String id) => id == current.id ? current : null;

  @override
  Future<SourceCandidateSearchResult> findSourceCandidates(
    String bookId, {
    Future<void>? abortTrigger,
  }) async {
    if (candidateError != null) throw candidateError!;
    return SourceCandidateSearchResult(
      candidates,
      failedSources: failedSources,
    );
  }

  @override
  Future<Book> switchBookSource(String bookId, Book candidate) async {
    switched = true;
    current = current.rebindSource(candidate, position: current.position);
    notifyListeners();
    return current;
  }

  @override
  Future<Book> refreshBookCover(String bookId) async {
    refreshed = true;
    current = current.copyWith(coverUrl: '${current.sourceId}/refreshed.png');
    notifyListeners();
    return current;
  }

  @override
  Future<Uint8List?> loadBookCover(Book value) async {
    if (coverError != null) throw coverError!;
    return Uint8List.fromList(const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late _DetailsController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'details-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = _DetailsController(
      AppRepository(database),
      SourceEngine(),
      _remoteBook(coverUrl: 'https://old.example/cover.png'),
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> pumpDetails(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookDetails(
            book: controller.current,
            controller: controller,
            onRead: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('remote details expose source and cover actions', (tester) async {
    controller.candidates = [
      _remoteBook(
        id: 'candidate',
        sourceId: 'https://new.example',
        sourceLabel: '新源',
      ),
    ];
    await pumpDetails(tester);

    expect(find.byKey(const Key('book-refresh-cover')), findsOneWidget);
    expect(find.byKey(const Key('book-change-source')), findsOneWidget);
    await tester.tap(find.byKey(const Key('book-change-source')));
    await tester.pumpAndSettle();
    expect(find.textContaining('新源'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-candidate-candidate')));
    await tester.pumpAndSettle();
    expect(controller.switched, isTrue);
    expect(find.text('文学 · 新源'), findsOneWidget);

    await tester.tap(find.byKey(const Key('book-refresh-cover')));
    await tester.pumpAndSettle();
    expect(controller.refreshed, isTrue);
  });

  testWidgets('local books hide source actions', (tester) async {
    controller.current = Book(
      id: 'local',
      title: '本地书',
      author: '作者',
      description: '',
      category: '本地',
      coverStyle: 0,
      sourceLabel: '本地导入',
      chapters: [
        Chapter(id: 'c', title: '正文', paragraphs: const ['内容']),
      ],
      addedAt: DateTime.utc(2026),
    );
    await pumpDetails(tester);

    expect(find.byKey(const Key('book-refresh-cover')), findsNothing);
    expect(find.byKey(const Key('book-change-source')), findsNothing);
  });

  testWidgets('source sheet distinguishes empty and failed searches', (
    tester,
  ) async {
    await pumpDetails(tester);
    await tester.tap(find.byKey(const Key('book-change-source')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-switch-empty')), findsOneWidget);
    Navigator.of(tester.element(find.byType(BookDetails))).pop();
    await tester.pumpAndSettle();

    controller.candidateError = StateError('候选搜索失败');
    await tester.tap(find.byKey(const Key('book-change-source')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-switch-error')), findsOneWidget);
    expect(find.textContaining('候选搜索失败'), findsOneWidget);
  });

  testWidgets('refresh reloads cover bytes even when its URL is unchanged', (
    tester,
  ) async {
    var calls = 0;
    Future<Uint8List?> loader(Book book) async {
      calls++;
      return null;
    }

    Widget cover(Book book) => MaterialApp(
      home: BookCover(book: book, imageLoader: loader),
    );
    final original = controller.current;
    await tester.pumpWidget(cover(original));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pumpWidget(
      cover(original.copyWith(coverUrl: original.coverUrl)),
    );
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('cover loader failure keeps generated cover visible', (
    tester,
  ) async {
    controller.coverError = StateError('封面失败');
    await tester.pumpWidget(
      MaterialApp(
        home: BookCover(
          book: controller.current,
          imageLoader: controller.loadBookCover,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book-cover-generated')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
