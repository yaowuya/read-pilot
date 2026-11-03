import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/reader_settings.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late AppController controller;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'style-preset-${DateTime.now().microsecondsSinceEpoch}',
    );
    controller = AppController(AppRepository(database), SourceEngine());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'local style presets persist, normalize names, and delete safely',
    () async {
      final preset = await controller.saveReaderStylePreset(
        '  夜读   舒缓  ',
        const ReaderSettings(
          theme: ReaderTheme.mist,
          flow: ReaderFlow.scrolling,
          fontSize: 24,
          lineHeight: 2.1,
          paragraphSpacing: 28,
          boldText: true,
        ),
      );

      expect(preset.name, '夜读 舒缓');
      expect(controller.readerStylePresets, [preset]);
      await expectLater(
        controller.saveReaderStylePreset('夜读 舒缓', const ReaderSettings()),
        throwsFormatException,
      );

      await controller.initialize();
      expect(controller.readerStylePresets.single.name, '夜读 舒缓');
      expect(
        controller.readerStylePresets.single.settings.theme,
        ReaderTheme.mist,
      );
      final backup = jsonDecode(
        utf8.decode(await controller.exportLocalBackup()),
      );
      expect(backup, isNot(contains('readerStylePresets')));
      await controller.deleteReaderStylePreset(preset.id);
      expect(controller.readerStylePresets, isEmpty);
    },
  );
}
