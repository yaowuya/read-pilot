import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/source_switch_candidate.dart';
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
  bool onShelf = true;

  SourceCandidateSearchResult _candidateResult() => SourceCandidateSearchResult(
    candidates,
    failedSources: failedSources,
    candidateInfoById: {
      for (final candidate in candidates)
        candidate.id: const SourceCandidateInfo(
          chapterCount: 1,
          mappedChapterIndex: 0,
          mappedChapterTitle: '第一章',
          wordCount: 2,
        ),
    },
  );

  @override
  Book? book(String id) => onShelf && id == current.id ? current : null;

  @override
  Future<SourceCandidateSearchResult> findSourceCandidates(
    String bookId, {
    Future<void>? abortTrigger,
  }) async {
    if (candidateError != null) throw candidateError!;
    return _candidateResult();
  }

  @override
  Future<SourceCandidateSearchResult> findSourceCandidatesFor(
    Book current, {
    Future<void>? abortTrigger,
    void Function(
      SourceCandidateSearchResult partial,
      int processed,
      int total,
    )?
    onUpdate,
  }) async {
    if (candidateError != null) throw candidateError!;
    return _candidateResult();
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

  /// 设计稿把换源、刷新封面、缓存收进「更多」菜单，测试统一从菜单进。
  Future<void> pickFromMore(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(const Key('book-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
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

    await tester.tap(find.byKey(const Key('book-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-refresh-cover')), findsOneWidget);
    expect(find.byKey(const Key('book-change-source')), findsOneWidget);
    expect(find.byKey(const Key('book-cache-chapters')), findsOneWidget);
    await tester.tap(find.byKey(const Key('book-change-source')));
    await tester.pumpAndSettle();
    expect(find.textContaining('新源'), findsOneWidget);

    await tester.tap(find.byKey(const Key('source-candidate-candidate')));
    await tester.pumpAndSettle();
    expect(controller.switched, isTrue);
    expect(find.text('新源'), findsOneWidget);

    await pickFromMore(tester, 'book-refresh-cover');
    expect(controller.refreshed, isTrue);
  });

  testWidgets('source switch sheet includes its drag handle on warm paper', (
    tester,
  ) async {
    await pumpDetails(tester);
    await pickFromMore(tester, 'book-change-source');

    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor, const Color(0xFFF1EDE1));
  });

  testWidgets('search results switch source before joining the shelf', (
    tester,
  ) async {
    controller.onShelf = false;
    controller.candidates = [
      _remoteBook(
        id: 'candidate',
        sourceId: 'https://new.example',
        sourceLabel: '新源',
      ),
    ];
    await pumpDetails(tester);

    // 还没上架的搜索结果也应该能换源，否则只能先加入书架再换。
    await tester.tap(find.byKey(const Key('book-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-change-source')), findsOneWidget);
    expect(find.text('加入书架'), findsOneWidget);
    await tester.tap(find.byKey(const Key('book-change-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source-candidate-candidate')));
    await tester.pumpAndSettle();

    // 换源结果留在详情页上，父级持有的旧对象不会把它改回去。
    expect(find.text('新源'), findsOneWidget);
    expect(find.text('加入书架'), findsOneWidget);
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

    // 本地书仍有正文替换与缓存操作，但没有换源与刷新封面。
    await tester.tap(find.byKey(const Key('book-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-refresh-cover')), findsNothing);
    expect(find.byKey(const Key('book-change-source')), findsNothing);
    expect(find.byKey(const Key('book-text-rules')), findsOneWidget);
  });

  testWidgets('source sheet distinguishes empty and failed searches', (
    tester,
  ) async {
    await pumpDetails(tester);
    await pickFromMore(tester, 'book-change-source');
    expect(find.byKey(const Key('source-switch-empty')), findsOneWidget);
    Navigator.of(tester.element(find.byType(BookDetails))).pop();
    await tester.pumpAndSettle();

    controller.candidateError = StateError('候选搜索失败');
    await pickFromMore(tester, 'book-change-source');
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
