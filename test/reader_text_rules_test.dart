import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/reader/reader_paragraph.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'rules-reader-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> openReader(
    WidgetTester tester, {
    String bookId = 'public-fusheng',
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ReadPilotApp(controller: controller, initialRoute: '/read/$bookId'),
    );
    await tester.pumpAndSettle();
  }

  String visibleParagraphs(WidgetTester tester) => tester
      .widgetList<ReaderParagraph>(find.byType(ReaderParagraph))
      .map((paragraph) => paragraph.text)
      .join(' ');

  // 阅读页默认沉浸式，操作顶栏/底栏前需先点正文中部唤出工具栏。
  Future<void> showChrome(WidgetTester tester) async {
    if (find.byKey(const Key('reader-settings')).evaluate().isNotEmpty) return;
    final paged = find.byKey(const Key('reader-paged-view'));
    final body = paged.evaluate().isNotEmpty
        ? paged
        : find.byKey(const Key('reader-scrolling-view'));
    await tester.tapAt(tester.getRect(body).center);
    await tester.pumpAndSettle();
  }

  testWidgets('paged reader measures the display text but keeps raw content', (
    tester,
  ) async {
    final original = controller
        .book('public-fusheng')!
        .chapters
        .first
        .paragraphs
        .first;
    expect(original, contains('余生'));
    await tester.runAsync(
      () => controller.addTextRule('public-fusheng', '余生', '我生'),
    );
    await openReader(tester);

    expect(find.byKey(const Key('reader-paged-view')), findsOneWidget);
    expect(visibleParagraphs(tester), contains('我生'));
    expect(visibleParagraphs(tester), isNot(contains('余生')));
    expect(
      controller.book('public-fusheng')!.chapters.first.paragraphs.first,
      original,
    );
    expect(controller.book('public-fusheng')!.position.paragraphIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling reader and notes retain raw paragraph anchors', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.scrolling),
      );
      await controller.addTextRule('public-fusheng', '余生', '我生');
    });
    await openReader(tester);
    expect(visibleParagraphs(tester), contains('我生'));

    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-bookmark')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-input')), '保留原文锚点');
    await tester.tap(find.text('保存书签'));
    await tester.pumpAndSettle();
    expect(controller.bookmarks.single.quote, contains('余生'));
    expect(controller.bookmarks.single.chapterIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing rules while reader is mounted repaginates visible text',
    (tester) async {
      await openReader(tester);
      expect(visibleParagraphs(tester), contains('余生'));
      await tester.runAsync(
        () => controller.addTextRule('public-fusheng', '余生', '我生'),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(visibleParagraphs(tester), contains('我生'));
      expect(visibleParagraphs(tester), isNot(contains('余生')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scrolling rule changes keep the visible paragraph anchor', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.scrolling),
      );
      await controller.addBook(
        Book(
          id: 'rule-anchor',
          title: '锚点测试书',
          author: '作者',
          description: '',
          category: '本地',
          coverStyle: 0,
          sourceLabel: '本地导入',
          addedAt: DateTime.utc(2026),
          chapters: [
            Chapter(
              id: 'chapter',
              title: '第一章',
              paragraphs: [
                for (var index = 0; index < 16; index++)
                  index == 4 ? '目标段 第五段' : '前文 $index ${'词' * 30}',
              ],
            ),
          ],
        ),
      );
      await controller.savePosition(
        'rule-anchor',
        const ReadingPosition(chapterIndex: 0, paragraphIndex: 4),
      );
    });
    await openReader(tester, bookId: 'rule-anchor');
    final target = find.byWidgetPredicate(
      (widget) => widget is ReaderParagraph && widget.text.contains('目标段'),
    );
    final before = tester.getTopLeft(target).dy;
    expect(before, inInclusiveRange(55, 400));

    await tester.runAsync(
      () => controller.addTextRule('rule-anchor', '词', '加长文字'),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(target).dy;
    expect((after - before).abs(), lessThan(45));
    expect(controller.book('rule-anchor')!.position.paragraphIndex, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reloading rules refreshes an already mounted reader', (
    tester,
  ) async {
    await openReader(tester);
    expect(visibleParagraphs(tester), contains('余生'));
    await tester.runAsync(() async {
      await AppRepository(database).addTextRule('public-fusheng', '余生', '我生');
      await controller.initialize();
    });
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(visibleParagraphs(tester), contains('我生'));
    expect(
      controller.book('public-fusheng')!.chapters.first.paragraphs.first,
      contains('余生'),
    );
    expect(tester.takeException(), isNull);
  });
}
