import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/ui/components/brand_mark.dart';
import 'package:read_pilot/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the compact brand mark remains semantic at 16 pixels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: BrandMark(size: 16))),
    );
    expect(find.bySemanticsLabel('阅读标志'), findsOneWidget);
    expect(tester.getSize(find.byType(BrandMark)), const Size.square(16));
    expect(tester.takeException(), isNull);
  });

  test('the interface preserves the original blue and cool-gray palette', () {
    expect(AppColors.ink, const Color(0xFF252932));
    expect(AppColors.blue, const Color(0xFF2468DE));
    expect(AppColors.background, const Color(0xFFF7F8FA));
    expect(AppColors.softBlue, const Color(0xFFEDF3FF));
    expect(appTheme().colorScheme.primary, AppColors.blue);
  });

  test('user-visible text contains no legacy brand names', () {
    final roots = [
      'lib',
      'web',
      'android/app/src/main',
      'ios/Runner',
      'windows/runner',
      'docs',
      'assets/books',
      'examples',
      'tool',
    ];
    final files = <File>[
      File('README.md'),
      File('LICENSE'),
      File('THIRD_PARTY_NOTICES.md'),
      File('pubspec.yaml'),
      for (final root in roots)
        ...Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  const {
                    '.dart',
                    '.html',
                    '.json',
                    '.xml',
                    '.plist',
                    '.cpp',
                    '.rc',
                    '.md',
                    '.txt',
                    '.py',
                    '.yaml',
                  }.contains(
                    file.uri.pathSegments.last.contains('.')
                        ? '.${file.uri.pathSegments.last.split('.').last}'
                        : '',
                  ),
            ),
    ];
    for (final file in files) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains('阅航')), reason: file.path);
      expect(text, isNot(contains('Read Pilot')), reason: file.path);
      expect(text, isNot(contains('READ PILOT')), reason: file.path);
    }
  });

  test('platform metadata uses 阅读 as the visible product name', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync()) as Map;
    expect(manifest['name'], '阅读');
    expect(manifest['short_name'], '阅读');

    final files = {
      'web/index.html': File('web/index.html').readAsStringSync(),
      'AndroidManifest.xml': File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync(),
      'Info.plist': File('ios/Runner/Info.plist').readAsStringSync(),
      'Windows main.cpp': File('windows/runner/main.cpp').readAsStringSync(),
      'Windows Runner.rc': File('windows/runner/Runner.rc').readAsStringSync(),
    };
    for (final entry in files.entries) {
      expect(entry.value, contains('阅读'), reason: entry.key);
      expect(entry.value, isNot(contains('阅航')), reason: entry.key);
      expect(entry.value, isNot(contains('Read Pilot')), reason: entry.key);
    }
  });
}
