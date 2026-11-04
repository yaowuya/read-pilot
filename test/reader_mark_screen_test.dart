import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_mark.dart';
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
      'reader-mark-screen-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  // 阅读页默认沉浸式，操作顶栏/底栏前需先点正文中部唤出工具栏。
  Future<void> showChrome(WidgetTester tester) async {
    final paged = find.byKey(const Key('reader-paged-view'));
    final body = paged.evaluate().isNotEmpty
        ? paged
        : find.byKey(const Key('reader-scrolling-view'));
    if (find.byKey(const Key('reader-settings')).evaluate().isNotEmpty) return;
    await tester.tapAt(tester.getRect(body).center);
    await tester.pumpAndSettle();
  }

  testWidgets('reader saves a bounded current-paragraph mark', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/public-fusheng',
      ),
    );
    await tester.pumpAndSettle();

    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-mark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-mark-color-mint')));
    await tester.enterText(
      find.byKey(const Key('reader-mark-note')),
      '保留这个段落。',
    );
    await tester.tap(find.byKey(const Key('reader-mark-save')));
    await tester.pumpAndSettle();

    final mark = controller.readerMarks('public-fusheng').single;
    expect(mark.note, '保留这个段落。');
    expect(tester.takeException(), isNull);
  });
  testWidgets('reader opens the current book mark manager', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/public-fusheng',
      ),
    );
    await tester.pumpAndSettle();

    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-mark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-mark-save')));
    await tester.pumpAndSettle();

    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-mark-manager')));
    await tester.pumpAndSettle();

    expect(find.text('段落标注管理'), findsOneWidget);
    final mark = controller.readerMarks('public-fusheng').single;
    await tester.tap(find.byKey(Key('reader-mark-manager-open-${mark.id}')));
    await tester.pumpAndSettle();

    expect(find.text('段落标注管理'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paged reader keeps selected-text annotation disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/public-fusheng',
      ),
    );
    await tester.pumpAndSettle();
    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('reader-selected-text-mark')))
          .enabled,
      isFalse,
    );
  });

  testWidgets('scrolling reader enables a unique selected-text annotation', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.addBook(
        Book(
          id: 'selected-text-book',
          title: '选区测试书',
          author: '作者',
          description: '',
          category: '本地',
          coverStyle: 0,
          sourceLabel: '本地导入',
          addedAt: DateTime.utc(2026),
          chapters: [
            Chapter(
              id: 'selection-chapter',
              title: '第一章',
              paragraphs: const ['春风又绿江南岸。'],
            ),
          ],
        ),
      );
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.scrolling),
      );
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/selected-text-book',
      ),
    );
    await tester.pumpAndSettle();

    final selectionArea = tester.widget<SelectionArea>(
      find.byType(SelectionArea).first,
    );
    selectionArea.onSelectionChanged!(const SelectedContent(plainText: '江南'));
    await tester.pump();
    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();

    final entry = tester.widget<ListTile>(
      find.byKey(const Key('reader-selected-text-mark')),
    );
    expect(entry.enabled, isTrue);
    await tester.tap(find.byKey(const Key('reader-selected-text-mark')));
    await tester.pumpAndSettle();
    expect(find.text('选中文字标注'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reader-mark-save')));
    await tester.pumpAndSettle();
    expect(
      controller.readerMarks('selected-text-book').single.selectedText,
      '江南',
    );
    expect(
      tester
          .widgetList<ReaderParagraph>(find.byType(ReaderParagraph))
          .any(
            (paragraph) =>
                paragraph.highlights.any((highlight) => highlight.text == '江南'),
          ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing a scrolling text selection disables its annotation', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.addBook(
        Book(
          id: 'cleared-selected-text-book',
          title: '清除选区测试书',
          author: '作者',
          description: '',
          category: '本地',
          coverStyle: 0,
          sourceLabel: '本地导入',
          addedAt: DateTime.utc(2026),
          chapters: [
            Chapter(
              id: 'cleared-selection-chapter',
              title: '第一章',
              paragraphs: const ['春风又绿江南岸。'],
            ),
          ],
        ),
      );
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.scrolling),
      );
    });
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/cleared-selected-text-book',
      ),
    );
    await tester.pumpAndSettle();

    final selectionArea = tester.widget<SelectionArea>(
      find.byType(SelectionArea).first,
    );
    selectionArea.onSelectionChanged!(const SelectedContent(plainText: '江南'));
    await tester.pump();
    selectionArea.onSelectionChanged!(null);
    await tester.pump();
    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('reader-selected-text-mark')))
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing away from scrolling discards a temporary selection', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.addBook(
        Book(
          id: 'flow-changed-selected-text-book',
          title: '翻页方式选区测试书',
          author: '作者',
          description: '',
          category: '本地',
          coverStyle: 0,
          sourceLabel: '本地导入',
          addedAt: DateTime.utc(2026),
          chapters: [
            Chapter(
              id: 'flow-changed-selection-chapter',
              title: '第一章',
              paragraphs: const ['春风又绿江南岸。'],
            ),
          ],
        ),
      );
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.scrolling),
      );
    });
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/flow-changed-selected-text-book',
      ),
    );
    await tester.pumpAndSettle();

    final selectionArea = tester.widget<SelectionArea>(
      find.byType(SelectionArea).first,
    );
    selectionArea.onSelectionChanged!(const SelectedContent(plainText: '江南'));
    await tester.pump();
    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('reader-flow-paged')));
    await tester.tap(find.byKey(const Key('reader-flow-paged')));
    await tester.pumpAndSettle();
    expect(controller.settings.flow, ReaderFlow.paged);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('reader-selected-text-mark')))
          .enabled,
      isFalse,
    );
    await tester.ensureVisible(find.byKey(const Key('reader-flow-scrolling')));
    await tester.tap(find.byKey(const Key('reader-flow-scrolling')));
    await tester.pumpAndSettle();
    expect(controller.settings.flow, ReaderFlow.scrolling);
    await tester.ensureVisible(
      find.byKey(const Key('reader-selected-text-mark')),
    );

    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('reader-selected-text-mark')))
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('active display rules hide range highlights and selection', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.addBook(
        Book(
          id: 'rule-selected-text-book',
          title: '替换规则选区测试书',
          author: '作者',
          description: '',
          category: '本地',
          coverStyle: 0,
          sourceLabel: '本地导入',
          addedAt: DateTime.utc(2026),
          chapters: [
            Chapter(
              id: 'rule-selection-chapter',
              title: '第一章',
              paragraphs: const ['春风又绿江南岸。'],
            ),
          ],
        ),
      );
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.scrolling),
      );
      await controller.addReaderMark(
        'rule-selected-text-book',
        0,
        0,
        color: ReaderMarkColor.amber,
        note: '',
        selectedText: '江南',
      );
    });
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/rule-selected-text-book',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(
      tester
          .widgetList<ReaderParagraph>(find.byType(ReaderParagraph))
          .any(
            (paragraph) =>
                paragraph.highlights.any((highlight) => highlight.text == '江南'),
          ),
      isTrue,
    );
    await tester.runAsync(
      () => controller.addTextRule('rule-selected-text-book', '江南', '江北'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsNothing);
    expect(
      tester
          .widgetList<ReaderParagraph>(find.byType(ReaderParagraph))
          .every((paragraph) => paragraph.highlights.isEmpty),
      isTrue,
    );
    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('reader-selected-text-mark')))
          .enabled,
      isFalse,
    );
    expect(find.text('正文显示替换启用时不可使用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing chapters discards a temporary text selection', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await controller.addBook(
        Book(
          id: 'chapter-changed-selected-text-book',
          title: '章节选区测试书',
          author: '作者',
          description: '',
          category: '本地',
          coverStyle: 0,
          sourceLabel: '本地导入',
          addedAt: DateTime.utc(2026),
          chapters: [
            Chapter(
              id: 'chapter-selection-first',
              title: '第一章',
              paragraphs: const ['春风又绿江南岸。'],
            ),
            Chapter(
              id: 'chapter-selection-second',
              title: '第二章',
              paragraphs: const ['明月何时照我还。'],
            ),
          ],
        ),
      );
      await controller.updateSettings(
        controller.settings.copyWith(flow: ReaderFlow.scrolling),
      );
    });
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/chapter-changed-selected-text-book',
      ),
    );
    await tester.pumpAndSettle();

    final selectionArea = tester.widget<SelectionArea>(
      find.byType(SelectionArea).first,
    );
    selectionArea.onSelectionChanged!(const SelectedContent(plainText: '江南'));
    await tester.pump();
    await showChrome(tester);
    await tester.tap(find.byTooltip('章节目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toc-chapter-1')));
    await tester.pumpAndSettle();
    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-settings')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('reader-selected-text-mark')))
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
