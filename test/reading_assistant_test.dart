import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/ui/components/reading_assistant_sheet.dart';

Book _book({int readChapters = 0}) => Book(
  id: 'lake',
  title: '湖边的一天',
  author: '示例作者',
  description: '一次散步的记录。',
  category: '散文',
  coverStyle: 1,
  sourceLabel: '本机',
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(id: 'c1', title: '第一章 清晨'),
    Chapter(id: 'c2', title: '第二章 午后'),
    Chapter(id: 'c3', title: '第三章 黄昏'),
  ],
  position: ReadingPosition(chapterIndex: readChapters),
);

Bookmark _note(String id, String quote) => Bookmark(
  id: id,
  bookId: 'lake',
  chapterIndex: 1,
  paragraphIndex: 2,
  quote: quote,
  note: '',
  createdAt: DateTime.utc(2026),
);

Future<void> _pump(
  WidgetTester tester, {
  required Book book,
  String chapterTitle = '第二章 午后',
  String paragraph = '湖面安静下来，只有水声。',
  List<Bookmark> notes = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReadingAssistantSheet(
          book: book,
          chapterTitle: chapterTitle,
          paragraph: paragraph,
          readChapters: book.position.chapterIndex,
          notes: notes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sheet declares local-only recall and cites the chapter', (
    tester,
  ) async {
    await _pump(tester, book: _book(readChapters: 2));

    expect(find.text('阅读助手'), findsOneWidget);
    expect(find.text('基于当前段落与已读章节 · 不涉及后文'), findsOneWidget);
    expect(find.byKey(const Key('assistant-disclaimer')), findsOneWidget);
    expect(find.text('本地回顾 · 不连接模型'), findsOneWidget);
    // 引用 chip 指回当前章节，而不是编一个出处。
    expect(
      find.descendant(
        of: find.byKey(const Key('assistant-reference')),
        matching: find.text('湖边的一天 · 第二章 午后'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the answer only restates local reading state', (tester) async {
    await _pump(tester, book: _book(readChapters: 2));

    expect(
      find.descendant(
        of: find.byKey(const Key('assistant-answer')),
        matching: find.textContaining('你已经读过 2 章'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('assistant-answer')),
        matching: find.textContaining('湖面安静下来'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('assistant-answer')),
        matching: find.textContaining('第二章 午后'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('recap mode reports the note count and never invents plot', (
    tester,
  ) async {
    await _pump(
      tester,
      book: _book(readChapters: 2),
      notes: [_note('n1', '水面上有一层薄雾'), _note('n2', '鸟鸣从左边传来')],
    );

    await tester.tap(find.byKey(const Key('assistant-suggestion-recap')));
    await tester.pumpAndSettle();

    expect(find.textContaining('已经读完 2 章'), findsOneWidget);
    expect(find.textContaining('留下 2 条笔记'), findsOneWidget);
    expect(find.textContaining('水面上有一层薄雾'), findsOneWidget);
    expect(find.byKey(const Key('assistant-note-count')), findsOneWidget);
    expect(find.text('只有本机内容 · 这本书共 2 条笔记'), findsOneWidget);
  });

  testWidgets('a chapter without text says so instead of guessing', (
    tester,
  ) async {
    await _pump(tester, book: _book(), paragraph: '');

    expect(find.textContaining('这一段没有正文'), findsOneWidget);

    await tester.tap(find.byKey(const Key('assistant-suggestion-recap')));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂时没有可以回顾的进度'), findsOneWidget);
    expect(find.textContaining('还没有笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the reference chip closes the sheet back to the paragraph', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ReadingAssistantSheet(
                  book: _book(readChapters: 1),
                  chapterTitle: '第二章 午后',
                  paragraph: '湖面安静下来。',
                  readChapters: 1,
                  notes: const [],
                ),
              ),
              child: const Text('打开助手'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开助手'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-reference')), findsOneWidget);

    await tester.tap(find.byKey(const Key('assistant-reference')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-reference')), findsNothing);
    expect(find.text('打开助手'), findsOneWidget);
  });
}
