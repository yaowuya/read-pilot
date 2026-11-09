import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设计稿：底栏「设置」= 排版六行；辅助能力在「阅读工具」sheet。
Future<void> openReaderMoreSheet(WidgetTester tester) async {
  if (find.byKey(const Key('reader-auto-read')).evaluate().isNotEmpty) return;
  if (find.byKey(const Key('reader-more')).evaluate().isEmpty) {
    await showReaderToolChrome(tester);
  }
  await tester.tap(find.byKey(const Key('reader-more')));
  await tester.pumpAndSettle();
}

Future<void> openReaderTypographySettings(WidgetTester tester) async {
  if (find.byKey(const Key('reader-flow-paged')).evaluate().isNotEmpty) return;
  if (find.byKey(const Key('reader-tool-settings')).evaluate().isEmpty) {
    await showReaderToolChrome(tester);
  }
  await tester.tap(find.byKey(const Key('reader-tool-settings')));
  await tester.pumpAndSettle();
}

Future<void> dismissReaderTypographySettings(WidgetTester tester) async {
  if (find.byKey(const Key('reader-settings-close')).evaluate().isEmpty) return;
  await tester.tap(find.byKey(const Key('reader-settings-close')));
  await tester.pumpAndSettle();
}

Future<void> showReaderToolChrome(WidgetTester tester) async {
  final body = find.byKey(const Key('reader-paged-view')).evaluate().isNotEmpty
      ? find.byKey(const Key('reader-paged-view'))
      : find.byKey(const Key('reader-scrolling-view'));
  await tester.tapAt(tester.getRect(body).center);
  await tester.pumpAndSettle();
}
