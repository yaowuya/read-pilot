import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/services/source_import_service.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live sources can discover and switch the same shelf book', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final database = await databaseFactoryMemory.openDatabase(
        'live-switch-${DateTime.now().microsecondsSinceEpoch}',
      );
      final imports = SourceImportService(timeout: const Duration(seconds: 45));
      final controller = AppController(
        AppRepository(database),
        SourceEngine(timeout: const Duration(seconds: 45)),
        sourceImportService: imports,
      );
      try {
        await controller.initialize();
        for (final id in [8027, 1325]) {
          final preview = await controller.prepareSourceImport(
            SourceImportInput.url(
              Uri.parse(
                'https://www.yckceo.com/yuedu/shuyuan/json/id/$id.json',
              ),
            ),
          );
          await controller.commitSourceImport(preview);
        }

        final groups = await controller.searchSources('九星霸体诀');
        for (final group in groups) {
          // Public source metadata only; no response content or headers.
          debugPrint(
            'live source ${group.source.name}: '
            '${group.books.length} results; error=${group.error}; '
            'titles=${group.books.take(3).map((book) => book.title).toList()}',
          );
        }
        final origin = groups
            .expand((group) => group.books)
            .firstWhere((book) => book.title.contains('九星霸体诀'));
        final shelfBook = await controller.addBook(origin);
        final result = await controller.findSourceCandidates(shelfBook.id);
        debugPrint(
          'loaded title=${shelfBook.title}; '
          'alternative candidates=${result.candidates.length}; '
          'failed sources=${result.failedSources}',
        );
        expect(result.candidates, isNotEmpty);

        final switched = await controller.switchBookSource(
          shelfBook.id,
          result.candidates.first,
        );
        expect(switched.id, shelfBook.id);
        expect(switched.sourceId, isNot(shelfBook.sourceId));
        expect(switched.chapters, isNotEmpty);
        expect(
          (await controller.chapter(
            switched.id,
            switched.position.chapterIndex,
          )).paragraphs,
          isNotEmpty,
        );
      } finally {
        controller.dispose();
        await database.close();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 8)));
}
