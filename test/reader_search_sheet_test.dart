import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/book_text_search.dart';
import 'package:read_pilot/ui/components/reader_search_sheet.dart';

Book _book() => Book(
  id: 'book',
  title: '测试书',
  author: '作者',
  description: '',
  category: '文学',
  coverStyle: 0,
  sourceLabel: '本地',
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(id: 'one', title: '第一章', paragraphs: const ['开头', '第一处目标']),
    Chapter(id: 'two', title: '第二章'),
    Chapter(id: 'three', title: '第三章', paragraphs: const ['第二处目标']),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'cached-only results return their original chapter and paragraph',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      BookTextHit? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<BookTextHit>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ReaderSearchSheet(book: _book()),
                  );
                },
                child: const Text('打开书内查找'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开书内查找'));
      await tester.pumpAndSettle();
      expect(find.text('仅检索已缓存的 2 / 3 章'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('reader-search-query')),
        '目标',
      );
      await tester.tap(find.byKey(const Key('reader-search-submit')));
      await tester.pumpAndSettle();
      expect(find.text('找到 2 段'), findsOneWidget);
      expect(find.byKey(const Key('reader-search-hit-0-1')), findsOneWidget);
      final target = find.byKey(const Key('reader-search-hit-2-0'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(selected?.chapterIndex, 2);
      expect(selected?.paragraphIndex, 0);
      expect(selected?.chapterId, 'three');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('display-only replacements do not change search semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderSearchSheet(book: _book(), displayRulesActive: true),
        ),
      ),
    );
    expect(find.text('书内查找基于原始缓存；正文替换仅影响显示。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
