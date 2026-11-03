import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:read_pilot/domain/source_import.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:read_pilot/services/source_import_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live 8027 source completes search detail TOC and first content',
    (tester) async {
      await tester.runAsync(() async {
        final imports = SourceImportService(
          timeout: const Duration(seconds: 30),
        );
        final engine = SourceEngine(timeout: const Duration(seconds: 30));
        try {
          final preview = await imports.prepare(
            SourceImportInput.url(
              Uri.parse(
                'https://www.yckceo.com/yuedu/shuyuan/json/id/8027.json',
              ),
            ),
          );
          final source = preview.sources.single;
          final results = await engine.search(source, '九星霸体诀');
          expect(results, isNotEmpty);

          final candidate = results.firstWhere(
            (book) => book.title.contains('九星霸体诀'),
            orElse: () => results.first,
          );
          final book = await engine.loadBook(source, candidate);
          expect(book.chapters, isNotEmpty);

          final chapter = await engine.loadChapter(source, book.chapters.first);
          expect(chapter.paragraphs, isNotEmpty);
          expect(
            chapter.paragraphs.join('\n'),
            isNot(contains('本章未完，请点击下一页继续阅读')),
          );
        } finally {
          engine.close();
          imports.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
