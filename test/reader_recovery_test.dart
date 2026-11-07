import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/reader_preferences.dart';
import 'package:read_pilot/ui/reader/reader_paragraph.dart';
import 'package:read_pilot/ui/reader/reader_paginator.dart';
import 'package:read_pilot/ui/screens/reader_screen.dart';
import 'package:sembast/sembast_memory.dart';

const _bookId = 'recovery-fixture';
const _saveError = '阅读进度暂未保存，请检查本机存储空间。';

List<String> _paragraphs(String prefix) =>
    List.generate(15, (index) => '$prefix $index. ${'用于验证阅读锚点的正文。' * 15}');

class _FailingProgressRepository extends AppRepository {
  _FailingProgressRepository(super.database);
  bool failWrites = false;
  int failedWrites = 0;
  Completer<void>? pendingWrite;
  Completer<void>? pendingSettingsWrite;

  @override
  Future<void> saveSettings(ReaderSettings settings) async {
    await pendingSettingsWrite?.future;
    await super.saveSettings(settings);
  }

  @override
  Future<void> savePosition(
    String id,
    ReadingPosition position, {
    bool? finished,
    Book? expectedBook,
  }) async {
    if (failWrites) {
      failedWrites++;
      throw StateError('Storage write failed');
    }
    await pendingWrite?.future;
    await super.savePosition(
      id,
      position,
      finished: finished,
      expectedBook: expectedBook,
    );
  }
}

class _RetrySourceEngine extends SourceEngine {
  _RetrySourceEngine()
    : super(
        client: MockClient(
          (_) async => throw StateError('Unexpected HTTP request'),
        ),
      );
  int requests = 0;

  @override
  Future<Chapter> loadChapter(
    BookSource source,
    Chapter chapter, {
    Future<void>? abortTrigger,
  }) async {
    if (requests++ == 0) throw const SourceException('临时网络错误');
    return chapter.withParagraphs(_paragraphs('Second chapter'));
  }
}

class _SwitchingSourceEngine extends _RetrySourceEngine {
  final oldChapter = Completer<Chapter>();

  @override
  Future<Book> loadBook(
    BookSource source,
    Book result, {
    Future<void>? abortTrigger,
  }) async => result;

  @override
  Future<Chapter> loadChapter(
    BookSource source,
    Chapter chapter, {
    Future<void>? abortTrigger,
  }) async {
    if (source.id == 'https://books.example') return oldChapter.future;
    return chapter.withParagraphs(_paragraphs('New source'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late _FailingProgressRepository repository;
  late AppController controller;
  late _RetrySourceEngine engine;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'recovery-${DateTime.now().microsecondsSinceEpoch}',
    );
    repository = _FailingProgressRepository(database);
    engine = _RetrySourceEngine();
    controller = AppController(repository, engine);
    await controller.initialize();
    await controller.updateSettings(
      controller.settings.copyWith(flow: ReaderFlow.scrolling),
    );
    await controller.importSources(
      jsonEncode({
        'bookSourceUrl': 'https://books.example',
        'bookSourceName': '恢复测试书源',
        'searchUrl': '/search?q={{key}}',
        'ruleSearch': {
          'bookList': '@CSS:.book',
          'name': '@CSS:a@text',
          'bookUrl': '@CSS:a@href',
        },
        'ruleToc': {
          'chapterList': '@CSS:a',
          'chapterName': '@text',
          'chapterUrl': '@href',
        },
        'ruleContent': {'content': '@CSS:article@html'},
      }),
    );
    await controller.addBook(
      Book(
        id: _bookId,
        title: '复现书',
        author: 'Test',
        description: '',
        category: 'Test',
        coverStyle: 0,
        sourceLabel: '恢复测试书源',
        sourceId: 'https://books.example',
        url: 'https://books.example/book/1',
        addedAt: DateTime.utc(2026),
        chapters: [
          Chapter(
            id: 'first',
            title: 'First chapter',
            url: 'https://books.example/c/1',
            paragraphs: _paragraphs('First chapter'),
          ),
          Chapter(
            id: 'second',
            title: 'Second chapter',
            url: 'https://books.example/c/2',
          ),
        ],
      ),
    );
    await controller.savePosition(
      _bookId,
      const ReadingPosition(chapterIndex: 0, paragraphIndex: 7),
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> openReader(WidgetTester tester) async {
    await tester.pumpWidget(
      ReadPilotApp(
        key: UniqueKey(),
        controller: controller,
        initialRoute: '/read/$_bookId',
      ),
    );
    await tester.pumpAndSettle();
  }

  // 阅读页默认沉浸式，需要先点正文中部唤出工具栏才能操作顶栏与底栏。
  Future<void> showChrome(WidgetTester tester) async {
    final body =
        find.byKey(const Key('reader-paged-view')).evaluate().isNotEmpty
        ? find.byKey(const Key('reader-paged-view'))
        : find.byKey(const Key('reader-scrolling-view'));
    await tester.tapAt(tester.getRect(body).center);
    await tester.pumpAndSettle();
  }

  Future<void> failLeaving(WidgetTester tester) async {
    await openReader(tester);
    await showChrome(tester);
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('reader-back')));
    await tester.pumpAndSettle();
  }

  Future<void> checkSourceRebind(
    WidgetTester tester, {
    required bool cachedOld,
    bool delayProgress = false,
  }) async {
    final original = controller.book(_bookId)!;
    final old = Chapter(
      id: 'first',
      title: 'First chapter',
      url: 'https://books.example/c/1',
      paragraphs: cachedOld ? _paragraphs('Old source') : const [],
    );
    final switching = _SwitchingSourceEngine();
    final delayedWrite = delayProgress ? Completer<void>() : null;
    await tester.runAsync(() async {
      controller.dispose();
      engine = switching;
      await repository.saveBook(original.copyWith(chapters: [old]));
      controller = AppController(repository, engine);
      await controller.initialize();
      await controller.importSources(
        jsonEncode({
          'bookSourceUrl': 'https://alternate.example',
          'bookSourceName': '新书源',
          'searchUrl': '/search?q={{key}}',
          'ruleSearch': {
            'bookList': '@CSS:.book',
            'name': '@text',
            'bookUrl': '@href',
          },
          'ruleToc': {
            'chapterList': '@CSS:a',
            'chapterName': '@text',
            'chapterUrl': '@href',
          },
          'ruleContent': {'content': '@CSS:article@html'},
        }),
      );
    });
    await tester.pumpWidget(
      ReadPilotApp(
        key: UniqueKey(),
        controller: controller,
        initialRoute: '/read/$_bookId',
      ),
    );
    await tester.pump();
    if (cachedOld) {
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('reader-scrolling-view')),
          )
          .controller!;
      repository.pendingWrite = delayedWrite;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump(
        delayProgress ? const Duration(milliseconds: 600) : Duration.zero,
      );
    }
    final replacement = Book(
      id: 'alternate-candidate',
      title: original.title,
      author: original.author,
      description: '',
      category: '测试',
      coverStyle: 0,
      sourceLabel: '新书源',
      sourceId: 'https://alternate.example',
      url: 'https://alternate.example/book',
      addedAt: DateTime.utc(2026),
      chapters: [
        Chapter(
          id: 'new-first',
          title: 'First chapter',
          url: 'https://alternate.example/c/1',
        ),
      ],
    );
    await tester.runAsync(
      () => controller.switchBookSource(_bookId, replacement),
    );
    repository.pendingWrite = null;
    await tester.runAsync(() async {
      switching.oldChapter.complete(
        old.withParagraphs(_paragraphs('Old source')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    if (delayedWrite != null) {
      await tester.runAsync(() async {
        delayedWrite.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
    }
    final displayed = tester
        .widgetList<ReaderParagraph>(find.byType(ReaderParagraph))
        .map((paragraph) => paragraph.text)
        .toList();
    expect(displayed.any((text) => text.startsWith('New source')), isTrue);
    expect(displayed.any((text) => text.startsWith('Old source')), isFalse);
    expect(find.text('重新加载'), findsNothing);
    expect(controller.book(_bookId)!.sourceId, 'https://alternate.example');
    expect(controller.book(_bookId)!.position.paragraphIndex, 7);
    expect(find.text(_saveError), findsNothing);
    expect(tester.takeException(), isNull);
  }

  testWidgets('source rebinding invalidates a pending old chapter', (
    tester,
  ) async {
    await checkSourceRebind(tester, cachedOld: false);
  });

  testWidgets(
    'source rebinding reloads cached text without saving stale anchors',
    (tester) async {
      await checkSourceRebind(tester, cachedOld: true);
    },
  );

  testWidgets(
    'late progress rejection does not show a storage error on the new source',
    (tester) async {
      await checkSourceRebind(tester, cachedOld: true, delayProgress: true);
    },
  );

  testWidgets('reader chrome exposes 换源 and opens the source sheet', (
    tester,
  ) async {
    // 用户要求：阅读中点中央唤出的菜单里要能直接换源（对齐 Legado）。
    await openReader(tester);
    await showChrome(tester);

    final entry = find.byKey(const Key('reader-change-source'));
    expect(entry, findsOneWidget);
    expect(find.byTooltip('换源'), findsOneWidget);

    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('换源'), findsOneWidget);
    expect(find.byKey(const Key('source-switch-filter')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 关掉面板后阅读页仍然可用（本套 fixture 默认是滚动阅读）。
    Navigator.of(tester.element(entry)).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-scrolling-view')), findsWidgets);
  });

  testWidgets('local books disable the reader 换源 entry', (tester) async {
    // 内置离线书籍没有书源，入口应禁用而不是打开一个空面板。
    await tester.runAsync(() async {
      await controller.addBook(
        Book(
          id: 'local-only',
          title: '本地书',
          author: '作者',
          description: '',
          category: '公版',
          coverStyle: 0,
          sourceLabel: '内置',
          addedAt: DateTime.utc(2026),
          chapters: [
            Chapter(
              id: 'local-1',
              title: '第一章',
              url: 'local://local-only/1',
              paragraphs: _paragraphs('Local'),
            ),
          ],
        ),
      );
    });
    await tester.pumpWidget(
      ReadPilotApp(
        key: UniqueKey(),
        controller: controller,
        initialRoute: '/read/local-only',
      ),
    );
    await tester.pumpAndSettle();
    await showChrome(tester);

    final button = tester.widget<IconButton>(
      find.byKey(const Key('reader-change-source')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('paged reader swipes and restores a logical paragraph anchor', (
    tester,
  ) async {
    await tester.runAsync(
      () => controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.paged),
      ),
    );
    await tester.pumpWidget(
      ReadPilotApp(
        key: UniqueKey(),
        controller: controller,
        initialRoute: '/read/$_bookId',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final paged = find.byKey(const Key('reader-paged-view'));
    expect(paged, findsOneWidget);
    final pageController = tester.widget<PageView>(paged).controller!;
    final initialPage = pageController.page!;

    for (var index = 0; index < 4; index++) {
      await tester.drag(paged, const Offset(-700, 0));
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(pageController.page, greaterThan(initialPage));
    final saved = controller.book(_bookId)!.position.paragraphIndex;
    expect(saved, greaterThan(7));

    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-back')));
    await tester.pumpAndSettle();
    await openReader(tester);
    expect(find.byKey(const Key('reader-paged-view')), findsOneWidget);
    expect(controller.book(_bookId)!.position.paragraphIndex, saved);
  });

  testWidgets('center tap toggles reading chrome without repagination', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(
      () => controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.paged),
      ),
    );
    await openReader(tester);
    final paged = find.byKey(const Key('reader-paged-view'));
    final pageController = tester.widget<PageView>(paged).controller;
    final page = pageController!.page;
    final anchor = controller.book(_bookId)!.position.paragraphIndex;
    final center = tester.getRect(paged).center;

    // 进入阅读页默认沉浸式：先无工具栏，点中部才唤出。
    expect(find.byKey(const Key('reader-back')), findsNothing);
    expect(find.byKey(const Key('reader-settings')), findsNothing);
    expect(find.byKey(const Key('reader-compact-heading')), findsOneWidget);
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsOneWidget);
    expect(find.byKey(const Key('reader-settings')), findsOneWidget);
    expect(find.byKey(const Key('reader-compact-heading')), findsNothing);
    expect(tester.widget<PageView>(paged).controller, same(pageController));
    expect(pageController.page, page);
    expect(controller.book(_bookId)!.position.paragraphIndex, anchor);

    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsNothing);
    expect(find.byKey(const Key('reader-settings')), findsNothing);
    expect(find.byKey(const Key('reader-compact-heading')), findsOneWidget);
    expect(find.byKey(const Key('reader-reading-progress')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+/\d+$')), findsNothing);
    expect(tester.widget<PageView>(paged).controller, same(pageController));
    expect(pageController.page, page);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page edges still turn pages while controls are hidden', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.paged),
      );
      await controller.savePosition(_bookId, const ReadingPosition());
    });
    await openReader(tester);
    final paged = find.byKey(const Key('reader-paged-view'));
    final pages = tester.widget<PageView>(paged).controller!;
    final viewport = tester.getRect(paged);
    // 默认即隐藏工具栏，边缘翻页不需要先唤出控件。
    expect(find.byKey(const Key('reader-back')), findsNothing);
    await tester.tapAt(Offset(viewport.right - 12, viewport.center.dy));
    await tester.pumpAndSettle();
    expect(pages.page, 1);
    expect(find.byKey(const Key('reader-back')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling text also toggles chrome without losing position', (
    tester,
  ) async {
    await openReader(tester);
    final scrolling = find.byKey(const Key('reader-scrolling-view'));
    final scrollController = tester
        .widget<SingleChildScrollView>(scrolling)
        .controller;
    await tester.drag(scrolling, const Offset(0, -180));
    await tester.pumpAndSettle();
    // 默认沉浸式：滚动后仍保持隐藏，中部点按才切换。
    expect(find.byKey(const Key('reader-back')), findsNothing);
    final offset = scrollController!.offset;
    await tester.tapAt(tester.getRect(scrolling).center);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsOneWidget);
    expect(scrollController.offset, offset);
    await tester.tapAt(tester.getRect(scrolling).center);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsNothing);
    expect(scrollController.offset, offset);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reading toolbar theme shortcut saves without moving the anchor',
    (tester) async {
      await openReader(tester);
      await showChrome(tester);
      final anchor = controller.book(_bookId)!.position.paragraphIndex;
      await tester.tap(find.byKey(const Key('reader-theme-toggle')));
      await tester.pumpAndSettle();
      expect(controller.settings.theme, ReaderTheme.dark);
      expect(controller.book(_bookId)!.position.paragraphIndex, anchor);
      await tester.tap(find.byKey(const Key('reader-theme-toggle')));
      await tester.pumpAndSettle();
      expect(controller.settings.theme, ReaderTheme.paper);
      expect(controller.book(_bookId)!.position.paragraphIndex, anchor);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tapping page edges animates paging and the middle stays put', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.paged),
      );
      await controller.savePosition(_bookId, const ReadingPosition());
    });
    await openReader(tester);
    final paged = find.byKey(const Key('reader-paged-view'));
    final pages = tester.widget<PageView>(paged).controller!;
    final rect = tester.getRect(paged);
    expect(find.bySemanticsLabel('上一页'), findsWidgets);
    expect(find.bySemanticsLabel('下一页'), findsWidgets);
    expect(pages.page, 0);
    await tester.tapAt(Offset(rect.left + 12, rect.center.dy));
    await tester.pumpAndSettle();
    expect(pages.page, 0);

    await tester.tapAt(Offset(rect.right - 12, rect.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pages.page, greaterThan(0));
    expect(pages.page, lessThan(1));
    await tester.pumpAndSettle();
    expect(pages.page, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(pages.page, 1);
    // 默认沉浸式，边缘翻页不会唤起工具栏。
    expect(find.byKey(const Key('reader-back')), findsNothing);

    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsOneWidget);
    expect(pages.page, 1);
    await tester.tapAt(Offset(rect.left + 12, rect.center.dy));
    await tester.pumpAndSettle();
    expect(pages.page, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paged reader uses compact top spacing and fills its viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.paged),
      );
      await controller.savePosition(_bookId, const ReadingPosition());
    });
    await openReader(tester);
    final paged = find.byKey(const Key('reader-paged-view'));
    final viewport = tester.getRect(paged);
    final title = find.descendant(
      of: paged,
      matching: find.text('First chapter'),
    );
    final heading = tester.getRect(title);
    expect(heading.top - viewport.top, lessThanOrEqualTo(16));
    final bodyParagraphs = find.descendant(
      of: paged,
      matching: find.byType(ReaderParagraph),
    );
    final fragments = bodyParagraphs
        .evaluate()
        .map((element) => tester.getRect(find.byWidget(element.widget)))
        .toList();
    expect(fragments, isNotEmpty);
    expect(fragments.first.top - heading.bottom, lessThanOrEqualTo(24));
    final lastBottom = fragments
        .map((rect) => rect.bottom)
        .reduce((left, right) => left > right ? left : right);
    expect(viewport.bottom - lastBottom, lessThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short reader viewport safely falls back instead of overflowing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 220));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => controller.updateSettings(
          controller.settings.copyWith(flow: ReaderFlow.paged, fontSize: 32),
        ),
      );
      await openReader(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('reader-scrolling-view')), findsOneWidget);
    },
  );

  testWidgets('both reading flows apply bold text without moving the anchor', (
    tester,
  ) async {
    for (final flow in ReaderFlow.values) {
      await tester.runAsync(
        () => controller.updateSettings(
          controller.settings.copyWith(
            flow: flow,
            boldText: true,
            paragraphSpacing: 40,
          ),
        ),
      );
      await openReader(tester);
      final paragraphs = tester.widgetList<ReaderParagraph>(
        find.byType(ReaderParagraph),
      );
      expect(paragraphs, isNotEmpty);
      expect(
        paragraphs.every(
          (paragraph) => paragraph.style.fontWeight == FontWeight.bold,
        ),
        isTrue,
      );
      expect(controller.book(_bookId)!.position.paragraphIndex, 7);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('scrolling reader uses the chosen paragraph spacing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.updateSettings(
        controller.settings.copyWith(paragraphSpacing: 40),
      );
      await controller.savePosition(_bookId, const ReadingPosition());
    });
    await openReader(tester);
    final paragraphs = find.byType(ReaderParagraph);
    final first = tester.getRect(paragraphs.at(0));
    final second = tester.getRect(paragraphs.at(1));
    expect(second.top - first.bottom, closeTo(40, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paged layout invalidates when spacing or weight changes', (
    tester,
  ) async {
    await tester.runAsync(
      () => controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.paged),
      ),
    );
    await openReader(tester);
    final paged = find.byKey(const Key('reader-paged-view'));
    var previous = tester.widget<PageView>(paged).controller;
    for (final settings in [
      controller.settings.copyWith(paragraphSpacing: 40),
      controller.settings.copyWith(paragraphSpacing: 40, boldText: true),
    ]) {
      await tester.runAsync(() => controller.updateSettings(settings));
      await tester.pumpAndSettle();
      final current = tester.widget<PageView>(paged).controller;
      expect(current, isNot(same(previous)));
      expect(controller.book(_bookId)!.position.paragraphIndex, 7);
      expect(tester.takeException(), isNull);
      previous = current;
    }
  });

  testWidgets('reader search opens a cached hit without network access', (
    tester,
  ) async {
    await openReader(tester);
    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-search')));
    await tester.pumpAndSettle();
    expect(find.text('仅检索已缓存的 1 / 2 章'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('reader-search-query')),
      'First chapter 10',
    );
    await tester.tap(find.byKey(const Key('reader-search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-search-hit-0-10')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(controller.book(_bookId)!.position.paragraphIndex, 10);
    expect(engine.requests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory order persists and still opens the original chapter', (
    tester,
  ) async {
    engine.requests = 1;
    await openReader(tester);
    await showChrome(tester);
    final originalIds = controller
        .book(_bookId)!
        .chapters
        .map((chapter) => chapter.id)
        .toList();
    await tester.tap(find.byTooltip('章节目录'));
    await tester.pumpAndSettle();
    final order = find.byKey(const Key('reader-toc-order'));
    expect(order, findsOneWidget);
    await tester.tap(order);
    await tester.pumpAndSettle();
    expect(controller.settings.tocDescending, isTrue);
    expect(
      (tester.widget<ListTile>(find.byType(ListTile).first).title! as Text)
          .data,
      'Second chapter',
    );
    expect(
      controller.book(_bookId)!.chapters.map((chapter) => chapter.id),
      originalIds,
    );
    await tester.tap(find.byKey(const ValueKey('toc-chapter-1')));
    await tester.pumpAndSettle();
    expect(controller.book(_bookId)!.position.chapterIndex, 1);
    await tester.tap(find.byTooltip('章节目录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('倒序'), findsWidgets);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('toc-chapter-1')))
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sorting a directory preserves typography and the current page controller',
    (tester) async {
      await tester.runAsync(
        () => controller.updateSettings(
          controller.settings.copyWith(
            flow: ReaderFlow.paged,
            paragraphSpacing: 32,
            boldText: true,
          ),
        ),
      );
      await openReader(tester);
      await showChrome(tester);
      final paged = find.byKey(const Key('reader-paged-view'));
      final pages = tester.widget<PageView>(paged).controller;
      await tester.tap(find.byTooltip('章节目录'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-toc-order')));
      await tester.pumpAndSettle();
      expect(tester.widget<PageView>(paged).controller, same(pages));
      expect(controller.settings.paragraphSpacing, 32);
      expect(controller.settings.boldText, isTrue);
      expect(controller.settings.tocDescending, isTrue);
      expect(controller.book(_bookId)!.position.paragraphIndex, 7);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reader preferences persist the selected flow', (tester) async {
    await openReader(tester);
    expect(find.byKey(const Key('reader-scrolling-view')), findsOneWidget);
    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();

    final paged = find.byKey(const Key('reader-flow-paged'));
    await tester.ensureVisible(paged);
    await tester.tap(paged);
    await tester.pumpAndSettle();

    expect(controller.settings.flow, ReaderFlow.paged);
  });

  testWidgets(
    'late settings completion cannot restore another chapter anchor',
    (tester) async {
      engine.requests = 1;
      await openReader(tester);
      await showChrome(tester);
      final pending = Completer<void>();
      repository.pendingSettingsWrite = pending;
      await tester.tap(find.byKey(const Key('reader-settings')));
      await tester.pumpAndSettle();
      final bold = find.byKey(const Key('reader-bold-text'));
      await tester.ensureVisible(bold);
      await tester.tap(bold);
      await tester.pump();
      Navigator.of(tester.element(find.byType(ReaderPreferences))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-next')));
      await tester.pumpAndSettle();
      expect(controller.book(_bookId)!.position.chapterIndex, 1);
      expect(controller.book(_bookId)!.position.paragraphIndex, 0);
      pending.complete();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(controller.book(_bookId)!.position.chapterIndex, 1);
      expect(controller.book(_bookId)!.position.paragraphIndex, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'height-only fallback restores the paragraph reached while scrolling',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => controller.updateSettings(
          controller.settings.copyWith(flow: ReaderFlow.paged),
        ),
      );
      await openReader(tester);
      final paged = find.byKey(const Key('reader-paged-view'));
      final original = tester.widget<PageView>(paged).controller;
      await tester.binding.setSurfaceSize(const Size(700, 220));
      await tester.pumpAndSettle();
      final scrolling = find.byKey(const Key('reader-scrolling-view'));
      expect(scrolling, findsOneWidget);
      final scroll = tester
          .widget<SingleChildScrollView>(scrolling)
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final anchor = controller.book(_bookId)!.position.paragraphIndex;
      expect(anchor, greaterThan(7));
      await tester.binding.setSurfaceSize(const Size(700, 700));
      await tester.pumpAndSettle();
      final pages = tester.widget<PageView>(paged).controller!;
      expect(pages, isNot(same(original)));
      final rect = tester.getRect(paged);
      final body = tester
          .widget<ReaderParagraph>(
            find
                .descendant(of: paged, matching: find.byType(ReaderParagraph))
                .first,
          )
          .style;
      final layout = ReaderPaginator.paginate(
        title: 'First chapter',
        paragraphs: _paragraphs('First chapter'),
        maxWidth: rect.width - 96,
        maxHeight: rect.height - 40,
        bodyStyle: body,
        titleStyle: const TextStyle(
          inherit: false,
          fontFamily: 'NotoSansSC',
          fontSize: 26,
          height: 1.6,
          fontWeight: FontWeight.w600,
        ),
        firstPageChromeHeight: 20,
        paragraphSpacing: controller.settings.paragraphSpacing,
      );
      expect(
        pages.page,
        closeTo(layout.pageForParagraph(anchor).toDouble(), .001),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('paged headings share the measured text scaling policy', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.paged),
      );
      await controller.savePosition(_bookId, const ReadingPosition());
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: ReaderScreen(controller: controller, bookId: _bookId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final paged = find.byKey(const Key('reader-paged-view'));
    expect(paged, findsOneWidget);
    final headingFinder = find.descendant(
      of: paged,
      matching: find.text('First chapter'),
    );
    final heading = tester.widget<Text>(headingFinder);
    final scaler =
        heading.textScaler ??
        MediaQuery.textScalerOf(tester.element(headingFinder));
    expect(scaler.scale(26), 26);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme-only change keeps the current paged screen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.updateSettings(
        controller.settings.copyWith(
          flow: ReaderFlow.paged,
          theme: ReaderTheme.sage,
        ),
      );
      await controller.savePosition(_bookId, const ReadingPosition());
    });
    await openReader(tester);
    final paged = find.byKey(const Key('reader-paged-view'));
    final pages = tester.widget<PageView>(paged).controller!;
    final viewport = tester.getRect(paged);
    await tester.tapAt(Offset(viewport.right - 12, viewport.center.dy));
    await tester.pumpAndSettle();
    expect(pages.page, 1);

    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-theme-toggle')));
    await tester.pumpAndSettle();
    expect(controller.settings.theme, ReaderTheme.dark);
    expect(tester.widget<PageView>(paged).controller, same(pages));
    expect(pages.page, 1);

    await tester.tap(find.byKey(const Key('reader-theme-toggle')));
    await tester.pumpAndSettle();
    expect(controller.settings.theme, ReaderTheme.sage);
    expect(tester.widget<PageView>(paged).controller, same(pages));
    expect(pages.page, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading controls fit a narrow phone at large text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: ReaderScreen(controller: controller, bookId: _bookId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await showChrome(tester);
    expect(find.byKey(const Key('reader-settings')), findsOneWidget);
    expect(find.byKey(const Key('reader-theme-toggle')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('reader-next')),
        matching: find.byIcon(Icons.skip_next),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('下一章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter load failure restores hidden reader controls', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.paged),
      );
      await controller.savePosition(_bookId, const ReadingPosition());
    });
    await openReader(tester);
    final paged = find.byKey(const Key('reader-paged-view'));
    final pages = tester.widget<PageView>(paged).controller!;
    // 默认沉浸式，隐藏工具栏时遇到加载失败也必须把控件暴露出来。
    expect(find.byKey(const Key('reader-back')), findsNothing);

    final nextChapterPage =
        (pages.position.maxScrollExtent / pages.position.viewportDimension)
            .round();
    pages.jumpToPage(nextChapterPage);
    await tester.pumpAndSettle();
    expect(find.text('临时网络错误'), findsOneWidget);
    expect(find.byKey(const Key('reader-back')), findsOneWidget);
    expect(find.byKey(const Key('reader-settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('next chapter retry retains the requested start anchor', (
    tester,
  ) async {
    await openReader(tester);
    await showChrome(tester);
    expect(controller.book(_bookId)!.position.paragraphIndex, 7);
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(find.text('临时网络错误'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(controller.book(_bookId)!.position.chapterIndex, 1);
    expect(controller.book(_bookId)!.position.paragraphIndex, 0);
    expect(engine.requests, 2);
  });

  testWidgets(
    'failed close-time progress save keeps the reader and allows retry',
    (tester) async {
      await failLeaving(tester);
      expect(repository.failedWrites, greaterThan(0));
      expect(controller.book(_bookId)!.position.paragraphIndex, 7);
      expect(find.text(_saveError), findsOneWidget);
      expect(find.byKey(const Key('reader-back')), findsOneWidget);
      repository.failWrites = false;
      await tester.tap(find.byKey(const Key('reader-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-back')), findsNothing);
      expect(controller.book(_bookId)!.position.paragraphIndex, greaterThan(7));
    },
  );

  testWidgets('save retry clears the error without leaving the reader', (
    tester,
  ) async {
    await failLeaving(tester);
    repository.failWrites = false;
    await tester.tap(find.byKey(const Key('reader-save-retry')));
    await tester.pumpAndSettle();
    expect(find.text(_saveError), findsNothing);
    expect(find.byKey(const Key('reader-back')), findsOneWidget);
    expect(controller.book(_bookId)!.position.paragraphIndex, greaterThan(7));
  });

  testWidgets('explicit discard exits without another progress write', (
    tester,
  ) async {
    await failLeaving(tester);
    final failedWrites = repository.failedWrites;
    await tester.tap(find.byKey(const Key('reader-discard-progress')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-back')), findsNothing);
    expect(controller.book(_bookId)!.position.paragraphIndex, 7);
    expect(repository.failedWrites, failedWrites);
  });

  testWidgets('failed progress save prevents moving to another chapter', (
    tester,
  ) async {
    await openReader(tester);
    await showChrome(tester);
    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(engine.requests, 0);
    expect(controller.book(_bookId)!.position.chapterIndex, 0);
    expect(find.text(_saveError), findsOneWidget);
  });

  testWidgets('failed final chapter loading cannot report completion', (
    tester,
  ) async {
    await openReader(tester);
    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(find.text('临时网络错误'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('reader-next'))).onPressed,
      isNull,
    );
    expect(controller.book(_bookId)!.finished, isFalse);
    expect(find.text('又读完一本，下一本见。'), findsNothing);
  });

  testWidgets('save retry preserves a failed completion request', (
    tester,
  ) async {
    await tester.runAsync(() async {
      engine.requests = 1;
      await controller.chapter(_bookId, 1);
      await controller.savePosition(
        _bookId,
        const ReadingPosition(chapterIndex: 1),
      );
    });
    await openReader(tester);
    await showChrome(tester);
    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(find.text(_saveError), findsOneWidget);
    repository.failWrites = false;
    await tester.tap(find.byKey(const Key('reader-save-retry')));
    await tester.pumpAndSettle();
    expect(find.text(_saveError), findsNothing);
    expect(controller.book(_bookId)!.finished, isTrue);
    await tester.runAsync(() async {
      final stored = (await repository.books()).singleWhere(
        (book) => book.id == _bookId,
      );
      expect(stored.finished, isTrue);
    });
  });

  testWidgets('discard during pending close retry pops the reader only once', (
    tester,
  ) async {
    await failLeaving(tester);
    repository.failWrites = false;
    final pending = Completer<void>();
    repository.pendingWrite = pending;
    await tester.tap(find.byKey(const Key('reader-back')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reader-discard-progress')));
    await tester.pump(const Duration(milliseconds: 10));
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('reader-back')), findsNothing);
    expect(find.text('我的书架'), findsOneWidget);
  });

  testWidgets('marking a book finished reports storage failure', (
    tester,
  ) async {
    await tester.runAsync(() async {
      engine.requests = 1;
      await controller.chapter(_bookId, 1);
      await controller.savePosition(
        _bookId,
        const ReadingPosition(chapterIndex: 1),
      );
    });
    await openReader(tester);
    await showChrome(tester);
    repository.failWrites = true;
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(controller.book(_bookId)!.finished, isFalse);
    expect(find.text(_saveError), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
