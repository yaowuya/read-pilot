import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/application/app_controller.dart';
import 'package:read_pilot/data/app_repository.dart';
import 'package:read_pilot/services/epub_importer.dart';
import 'package:read_pilot/services/source_engine.dart';
import 'package:sembast/sembast_memory.dart';

Uint8List _epub({
  String? mimetype,
  String? container,
  String? opf,
  Map<String, String> chapters = const {},
  Map<String, Uint8List> rawFiles = const {},
}) {
  final archive = Archive();
  final mime = utf8.encode(mimetype ?? 'application/epub+zip');
  archive.addFile(
    ArchiveFile.noCompress('mimetype', mime.length, Uint8List.fromList(mime)),
  );
  final containerText =
      container ??
      '''<?xml version="1.0"?><container><rootfiles><rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''';
  archive.addFile(
    ArchiveFile(
      'META-INF/container.xml',
      utf8.encode(containerText).length,
      utf8.encode(containerText),
    ),
  );
  final opfText =
      opf ??
      '''<?xml version="1.0"?><package><metadata><dc:title xmlns:dc="urn:dc">样例 EPUB</dc:title><dc:creator xmlns:dc="urn:dc">作者甲</dc:creator></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>''';
  archive.addFile(
    ArchiveFile(
      'OPS/content.opf',
      utf8.encode(opfText).length,
      utf8.encode(opfText),
    ),
  );
  for (final entry in {
    'OPS/one.xhtml':
        '<html><body><h1>第一章</h1><p>第一段</p><script>不应导入</script><p>第二段</p></body></html>',
    'OPS/two.xhtml': '<html><body><h1>第二章</h1><p>第三段</p></body></html>',
    ...chapters,
  }.entries) {
    archive.addFile(
      ArchiveFile(
        entry.key,
        utf8.encode(entry.value).length,
        utf8.encode(entry.value),
      ),
    );
  }
  for (final entry in rawFiles.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imports standard EPUB spine without executing embedded content', () {
    final book = EpubImporter().parse(_epub(), 'sample.EPUB');
    expect(book.title, '样例 EPUB');
    expect(book.author, '作者甲');
    expect(book.isRemote, isFalse);
    expect(book.chapters, hasLength(2));
    expect(book.chapters.first.title, '第一章');
    expect(book.chapters.first.paragraphs, ['第一段', '第二段']);
    expect(book.chapters.first.paragraphs.join(), isNot(contains('不应导入')));
    expect(book.provenance, contains('EPUB'));
  });

  test(
    'rejects bad mimetype, DTD, traversal and oversized chapter resources',
    () {
      expect(
        () => EpubImporter().parse(_epub(mimetype: 'text/plain'), 'book.epub'),
        throwsFormatException,
      );
      expect(
        () => EpubImporter().parse(
          _epub(opf: '<!DOCTYPE package><package/>'),
          'book.epub',
        ),
        throwsFormatException,
      );
      expect(
        () => EpubImporter().parse(
          _epub(
            container:
                '<container><rootfiles><rootfile full-path="../OPS/content.opf"/></rootfiles></container>',
          ),
          'book.epub',
        ),
        throwsFormatException,
      );
      expect(
        () => EpubImporter().parse(
          _epub(
            rawFiles: {
              'OPS/too-big.bin': Uint8List(EpubImporter.maxEntryBytes + 1),
            },
          ),
          'book.epub',
        ),
        throwsFormatException,
      );
      expect(
        () => EpubImporter().parse(
          _epub(
            rawFiles: {
              'META-INF/encryption.xml': Uint8List.fromList(
                utf8.encode('<encryption/>'),
              ),
            },
          ),
          'book.epub',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'generic local import dispatches EPUB but rejects unsupported formats',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'epub-controller-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(database.close);
      final controller = AppController(AppRepository(database), SourceEngine());
      addTearDown(controller.dispose);
      await controller.initialize();
      final imported = await controller.importLocalFile(_epub(), 'novel.epub');
      expect(imported.title, '样例 EPUB');
      expect(controller.book(imported.id), isNotNull);
      await expectLater(
        controller.importLocalFile(Uint8List.fromList([1, 2]), 'book.pdf'),
        throwsFormatException,
      );
    },
  );
}
