import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/app.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/reading_activity.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

class _ActivitySpyController extends AppController {
  _ActivitySpyController(super.repository, super.engine);

  final calls =
      <({String bookId, int chapterIndex, ReadingActivityKind kind})>[];

  @override
  Future<void> recordReadingActivity(
    String bookId,
    int chapterIndex, {
    required ReadingActivityKind kind,
  }) async {
    calls.add((bookId: bookId, chapterIndex: chapterIndex, kind: kind));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late _ActivitySpyController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'reader-activity-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = _ActivitySpyController(
      AppRepository(database),
      SourceEngine(),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

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

  testWidgets('reader records only successful chapter milestones per session', (
    tester,
  ) async {
    await tester.pumpWidget(
      ReadPilotApp(
        controller: controller,
        initialRoute: '/read/public-fusheng',
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.calls, [
      (
        bookId: 'public-fusheng',
        chapterIndex: 0,
        kind: ReadingActivityKind.opened,
      ),
    ]);

    await showChrome(tester);
    await tester.tap(find.byKey(const Key('reader-next')));
    await tester.pumpAndSettle();
    expect(controller.calls.last, (
      bookId: 'public-fusheng',
      chapterIndex: 1,
      kind: ReadingActivityKind.chapter,
    ));
    expect(controller.calls, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
