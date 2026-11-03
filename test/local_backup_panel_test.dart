import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/services/encrypted_local_backup.dart';
import 'package:read_pilot/services/local_backup.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/ui/components/local_backup_panel.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database sourceDb;
  late Database targetDb;
  late AppController source;
  late AppController target;
  late Uint8List backupBytes;

  setUp(() async {
    sourceDb = await databaseFactoryMemory.openDatabase(
      'backup-ui-source-${DateTime.now().microsecondsSinceEpoch}',
    );
    targetDb = await databaseFactoryMemory.openDatabase(
      'backup-ui-target-${DateTime.now().microsecondsSinceEpoch}',
    );
    source = AppController(AppRepository(sourceDb), SourceEngine());
    target = AppController(AppRepository(targetDb), SourceEngine());
    await source.initialize();
    await target.initialize();
    await source.addBook(
      Book(
        id: 'my-txt',
        title: '导入的 TXT',
        author: '作者',
        description: '',
        category: '本地',
        coverStyle: 0,
        sourceLabel: '本地导入',
        addedAt: DateTime.utc(2026),
        chapters: [
          Chapter(id: 'first', title: '第一章', paragraphs: const ['原始正文']),
        ],
      ),
    );
    await source.updateSettings(
      source.settings.copyWith(theme: ReaderTheme.dark),
    );
    backupBytes = await source.exportLocalBackup();
  });

  tearDown(() async {
    source.dispose();
    target.dispose();
    await sourceDb.close();
    await targetDb.close();
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    Future<Uint8List?> Function()? pickFile,
    Future<bool> Function(Uint8List, String)? saveFile,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocalBackupPanel(
              controller: target,
              pickFile: pickFile,
              saveFile: saveFile,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('export and import preview never overwrite existing state', (
    tester,
  ) async {
    Uint8List? saved;
    await pumpPanel(
      tester,
      pickFile: () async => backupBytes,
      saveFile: (bytes, name) async {
        expect(name, endsWith('.json'));
        saved = bytes;
        return true;
      },
    );
    await tester.tap(find.byKey(const Key('backup-export')));
    await tester.pumpAndSettle();
    expect(LocalBackupCodec.decode(saved!).books, hasLength(3));
    expect(find.textContaining('请确认文件实际存在'), findsOneWidget);
    expect(target.book('my-txt'), isNull);

    await tester.tap(find.byKey(const Key('backup-import')));
    await tester.pumpAndSettle();
    expect(find.textContaining('新增 1 本'), findsOneWidget);
    expect(find.textContaining('跳过 3 本'), findsOneWidget);
    expect(target.book('my-txt'), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(target.book('my-txt'), isNull);

    await tester.tap(find.byKey(const Key('backup-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-confirm')));
    await tester.pumpAndSettle();
    expect(target.book('my-txt')!.chapters.single.paragraphs, ['原始正文']);
    expect(target.settings.theme, ReaderTheme.paper);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoring reader settings requires an explicit checkbox', (
    tester,
  ) async {
    await pumpPanel(tester, pickFile: () async => backupBytes);
    await tester.tap(find.byKey(const Key('backup-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-restore-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-confirm')));
    await tester.pumpAndSettle();
    expect(target.settings.theme, ReaderTheme.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid backup shows an error and never changes the shelf', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      pickFile: () async => Uint8List.fromList(utf8.encode('{}')),
    );
    await tester.tap(find.byKey(const Key('backup-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-error')), findsOneWidget);
    expect(target.books, hasLength(3));
    expect(target.book('my-txt'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('encrypted export confirms a password and saves no plaintext', (
    tester,
  ) async {
    Uint8List? saved;
    await pumpPanel(
      tester,
      saveFile: (bytes, name) async {
        expect(name, contains('.encrypted.json'));
        saved = bytes;
        return true;
      },
    );
    await tester.tap(find.byKey(const Key('backup-export-encrypted')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'correct horse battery staple',
    );
    await tester.enterText(
      find.byKey(const Key('backup-password-confirmation')),
      'correct horse battery staple',
    );
    await tester.tap(find.byKey(const Key('backup-password-confirm')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(EncryptedLocalBackupCodec.isEncrypted(saved!), isTrue);
    expect(utf8.decode(saved!), isNot(contains('原始正文')));
    expect(find.textContaining('密码不会被保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('encrypted import requests a local password before preview', (
    tester,
  ) async {
    final encrypted = await tester.runAsync(
      () => source.exportEncryptedLocalBackup('correct horse battery staple'),
    );
    expect(encrypted, isNotNull);
    await pumpPanel(tester, pickFile: () async => encrypted!);

    await tester.tap(find.byKey(const Key('backup-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-password')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'correct horse battery staple',
    );
    await tester.tap(find.byKey(const Key('backup-password-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('已在本机验证密码并解密'), findsOneWidget);
    expect(find.textContaining('新增 1 本'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(target.book('my-txt'), isNull);
    expect(tester.takeException(), isNull);
  });
}
