import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/ui/components/reader_toc_sheet.dart';

Book _book() => Book(
  id: 'toc-fixture',
  title: '目录测试',
  author: '测试作者',
  description: '',
  category: '测试',
  coverStyle: 0,
  sourceLabel: '本地',
  addedAt: DateTime.utc(2026),
  chapters: [
    Chapter(id: 'first', title: '第一章', paragraphs: ['甲']),
    Chapter(id: 'second', title: '第二章'),
    Chapter(id: 'third', title: '第三章', paragraphs: ['丙']),
  ],
);

Future<void> _open(
  WidgetTester tester, {
  Book? book,
  bool descending = false,
  Future<void> Function(bool)? onOrderChanged,
  ValueChanged<int>? onChapterSelected,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ReaderTocSheet(
        book: book ?? _book(),
        currentChapterIndex: 1,
        descending: descending,
        onOrderChanged: onOrderChanged ?? (_) async {},
        onChapterSelected: onChapterSelected ?? (_) {},
      ),
    ),
  ),
);

List<String?> _titles(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .map((tile) => (tile.title! as Text).data)
    .toList();

void main() {
  testWidgets('descending display preserves original indices and markers', (
    tester,
  ) async {
    final book = _book();
    int? selected;
    await _open(
      tester,
      book: book,
      descending: true,
      onChapterSelected: (index) => selected = index,
    );
    expect(_titles(tester), ['第三章', '第二章', '第一章']);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('toc-chapter-1')))
          .selected,
      isTrue,
    );
    expect(find.byIcon(Icons.offline_pin_outlined), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('toc-chapter-2')));
    expect(selected, 2);
    expect(book.chapters.map((chapter) => chapter.id), [
      'first',
      'second',
      'third',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the directory order toggles and saves once per action', (
    tester,
  ) async {
    final saved = <bool>[];
    await _open(tester, onOrderChanged: (value) async => saved.add(value));
    final order = find.byKey(const Key('reader-toc-order'));
    expect(_titles(tester), ['第一章', '第二章', '第三章']);
    await tester.tap(order);
    await tester.pumpAndSettle();
    expect(_titles(tester), ['第三章', '第二章', '第一章']);
    await tester.tap(order);
    await tester.pumpAndSettle();
    expect(_titles(tester), ['第一章', '第二章', '第三章']);
    expect(saved, [true, false]);
  });

  testWidgets('failed order saves roll back and can be retried', (
    tester,
  ) async {
    var fail = true;
    await _open(
      tester,
      onOrderChanged: (_) async {
        if (fail) throw StateError('保存目录失败');
      },
    );
    final order = find.byKey(const Key('reader-toc-order'));
    await tester.tap(order);
    await tester.pumpAndSettle();
    expect(_titles(tester), ['第一章', '第二章', '第三章']);
    expect(find.textContaining('保存目录失败'), findsOneWidget);
    fail = false;
    await tester.tap(order);
    await tester.pumpAndSettle();
    expect(_titles(tester), ['第三章', '第二章', '第一章']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending saves disable actions and completion after closing is safe',
    (tester) async {
      final pending = Completer<void>();
      await _open(tester, onOrderChanged: (_) => pending.future);
      final order = find.byKey(const Key('reader-toc-order'));
      await tester.tap(order);
      await tester.pump();
      expect(tester.widget<IconButton>(order).onPressed, isNull);
      expect(
        tester.widget<ListTile>(find.byType(ListTile).first).onTap,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an external order change updates the visible directory', (
    tester,
  ) async {
    await _open(tester);
    await _open(tester, descending: true);
    expect(_titles(tester), ['第三章', '第二章', '第一章']);
  });

  testWidgets('empty directories remain usable without index errors', (
    tester,
  ) async {
    await _open(tester, book: _book().copyWith(chapters: []));
    expect(find.byType(ListTile), findsNothing);
    await tester.tap(find.byKey(const Key('reader-toc-order')));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
