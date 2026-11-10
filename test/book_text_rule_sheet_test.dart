import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/book_details.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;
  late Book book;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'text-rules-ui-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
    book = controller.book('public-fusheng')!;
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> openSheet(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookDetails(book: book, controller: controller, onRead: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-text-rules')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'local books can create, preview, edit and toggle literal rules',
    (tester) async {
      final raw = book.chapters.first.paragraphs.first;
      await openSheet(tester);
      expect(find.textContaining('只影响显示'), findsOneWidget);
      await tester.tap(find.byKey(const Key('text-rule-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('text-rule-needle')), '余生');
      await tester.enterText(
        find.byKey(const Key('text-rule-replacement')),
        '我生',
      );
      await tester.tap(find.byKey(const Key('text-rule-save')));
      await tester.pumpAndSettle();
      final rule = controller.textRules(book.id).single;
      expect(find.byKey(Key('text-rule-${rule.id}')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('text-rule-preview-input')),
        '余生仍在',
      );
      await tester.pumpAndSettle();
      expect(find.text('预览：我生仍在'), findsOneWidget);
      expect(controller.book(book.id)!.chapters.first.paragraphs.first, raw);

      await tester.tap(find.byKey(Key('text-rule-enabled-${rule.id}')));
      await tester.pumpAndSettle();
      expect(controller.textRules(book.id).single.enabled, isFalse);
      expect(find.text('预览：余生仍在'), findsOneWidget);
      await tester.tap(find.byKey(Key('text-rule-edit-${rule.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('text-rule-replacement')),
        '新生',
      );
      await tester.tap(find.byKey(const Key('text-rule-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('text-rule-enabled-${rule.id}')));
      await tester.pumpAndSettle();
      expect(find.text('预览：新生仍在'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rules reorder and delete only after confirmation', (
    tester,
  ) async {
    final rules = await tester.runAsync(() async {
      final first = await controller.addTextRule(book.id, '旧', '中');
      final second = await controller.addTextRule(book.id, '中', '新');
      return [first, second];
    });
    await openSheet(tester);
    await tester.tap(find.byKey(Key('text-rule-up-${rules![1].id}')));
    await tester.pumpAndSettle();
    expect(controller.textRules(book.id).first.id, rules[1].id);

    await tester.tap(find.byKey(Key('text-rule-delete-${rules[0].id}')));
    await tester.pumpAndSettle();
    expect(controller.textRules(book.id), hasLength(2));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.textRules(book.id), hasLength(2));
    await tester.tap(find.byKey(Key('text-rule-delete-${rules[0].id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();
    expect(controller.textRules(book.id).single.id, rules[1].id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rule controls fit a 320-pixel phone viewport', (tester) async {
    final rule = await tester.runAsync(
      () => controller.addTextRule(book.id, '旧', '新'),
    );
    await openSheet(tester, width: 320);
    expect(find.byKey(Key('text-rule-${rule!.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty rules leave space before the add action', (tester) async {
    await openSheet(tester);
    final gap =
        tester.getTopLeft(find.byKey(const Key('text-rule-add'))).dy -
        tester.getBottomLeft(find.text('尚未添加正文替换。')).dy;
    expect(gap, greaterThanOrEqualTo(12));
    expect(tester.takeException(), isNull);
  });
}
