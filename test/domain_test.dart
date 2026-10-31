import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/book.dart';
import 'package:read_pilot/domain/book_source.dart';
import 'package:read_pilot/domain/reader_settings.dart';

Book _bookWithChapters(List<Chapter> chapters) => Book(
  id: 'immutable-book',
  title: '测试书',
  author: '作者',
  description: '',
  category: '测试',
  coverStyle: 0,
  sourceLabel: '本地',
  addedAt: DateTime.utc(2026),
  chapters: chapters,
);

Map<String, dynamic> _sourceData() => {
  'bookSourceUrl': 'https://books.example',
  'bookSourceName': '测试书源',
  'searchUrl': '/search?q={{key}}',
  'enabled': true,
  'ruleSearch': {'name': '@CSS:a@text'},
  'metadata': {
    'tags': ['original'],
  },
};

void main() {
  test('positions survive JSON without depending on page dimensions', () {
    const position = ReadingPosition(chapterIndex: 2, paragraphIndex: 7);
    final restored = ReadingPosition.fromJson(position.toJson());
    expect(restored.chapterIndex, 2);
    expect(restored.paragraphIndex, 7);
  });

  test('invalid stored positions are clamped', () {
    final restored = ReadingPosition.fromJson({
      'chapterIndex': -3,
      'paragraphIndex': -9,
    });
    expect(restored.chapterIndex, 0);
    expect(restored.paragraphIndex, 0);
  });

  test('book round trip retains cached paragraphs and provenance', () {
    final book = Book(
      id: 'local-1',
      title: '浮生六记',
      author: '沈复',
      description: '公版节选',
      category: '文学',
      coverStyle: 0,
      sourceLabel: '本地公版',
      isExcerpt: true,
      addedAt: DateTime.utc(2026, 10, 28),
      chapters: [
        Chapter(id: 'chapter-1', title: '闲情记趣', paragraphs: ['余忆童稚时。']),
      ],
      position: const ReadingPosition(chapterIndex: 0, paragraphIndex: 0),
    );
    final restored = Book.fromJson(book.toJson());
    expect(restored.title, book.title);
    expect(restored.isExcerpt, isTrue);
    expect(restored.chapters.single.paragraphs.single, '余忆童稚时。');
    expect(restored.addedAt, book.addedAt);
    expect(restored.isRemote, isFalse);
  });

  test('chapter owns an immutable copy of its paragraphs', () {
    final input = ['original'];
    final chapter = Chapter(id: 'c', title: 'Chapter', paragraphs: input);
    input[0] = 'changed';
    expect(chapter.paragraphs, ['original']);
    expect(() => chapter.paragraphs.add('extra'), throwsUnsupportedError);
  });

  test('book owns an immutable copy of its chapters', () {
    final input = [Chapter(id: 'c', title: 'Chapter')];
    final book = _bookWithChapters(input);
    input.clear();
    expect(book.chapters, hasLength(1));
    expect(() => book.chapters.clear(), throwsUnsupportedError);
  });

  test('copyWith isolates replacement chapter lists', () {
    final original = _bookWithChapters([
      Chapter(id: 'original', title: 'Original'),
    ]);
    final replacement = [Chapter(id: 'replacement', title: 'Replacement')];
    final copy = original.copyWith(chapters: replacement);
    replacement.clear();
    expect(original.chapters.single.id, 'original');
    expect(copy.chapters.single.id, 'replacement');
    expect(() => copy.chapters.clear(), throwsUnsupportedError);
  });

  test('source constructor isolates nested caller data', () {
    final input = _sourceData();
    final source = BookSource(input);
    (input['ruleSearch'] as Map)['name'] = '@js:1';
    ((input['metadata'] as Map)['tags'] as List).add('changed');
    expect(source.searchRules['name'], '@CSS:a@text');
    expect((source.toJson()['metadata'] as Map)['tags'], ['original']);
  });

  test('source JSON exports do not mutate validated rules or metadata', () {
    final source = BookSource(_sourceData());
    final exported = source.toJson();
    (exported['ruleSearch'] as Map)['name'] = '@js:1';
    ((exported['metadata'] as Map)['tags'] as List).clear();
    expect(source.searchRules['name'], '@CSS:a@text');
    expect((source.toJson()['metadata'] as Map)['tags'], ['original']);
  });

  test('toggling a source preserves isolated rules and metadata', () {
    final source = BookSource(_sourceData());
    final disabled = source.withEnabled(false);
    final exported = disabled.toJson();
    (exported['ruleSearch'] as Map)['name'] = 'changed';
    expect(source.enabled, isTrue);
    expect(disabled.enabled, isFalse);
    expect(source.searchRules['name'], '@CSS:a@text');
    expect(disabled.searchRules['name'], '@CSS:a@text');
  });

  test('settings keep values within readable ranges', () {
    final settings = ReaderSettings.fromJson({
      'fontSize': 999,
      'lineHeight': 0.1,
      'theme': 'not-a-theme',
      'flow': 'not-a-flow',
    });
    expect(settings.fontSize, 32);
    expect(settings.lineHeight, 1.4);
    expect(settings.theme, ReaderTheme.paper);
    expect(settings.flow, ReaderFlow.paged);

    final scrolling = const ReaderSettings().copyWith(
      flow: ReaderFlow.scrolling,
    );
    expect(
      ReaderSettings.fromJson(scrolling.toJson()).flow,
      ReaderFlow.scrolling,
    );
  });

  test('bookmark preserves an exact logical anchor and note', () {
    final bookmark = Bookmark(
      id: 'note-1',
      bookId: 'local-1',
      chapterIndex: 1,
      paragraphIndex: 4,
      quote: '闲情记趣',
      note: '留住小事。',
      createdAt: DateTime.utc(2026, 10, 28),
    );
    final restored = Bookmark.fromJson(bookmark.toJson());
    expect(restored.paragraphIndex, 4);
    expect(restored.note, '留住小事。');
    expect(restored.bookId, 'local-1');
  });
}
