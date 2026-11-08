import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/ui/components/common.dart';

void main() {
  test('a plain intro is returned unchanged', () {
    expect(
      bookIntroText('九龙拉棺，究竟是回到了上古，还是来到了星空的彼岸？'),
      '九龙拉棺，究竟是回到了上古，还是来到了星空的彼岸？',
    );
  });

  test('block tags become line breaks and inline tags are dropped', () {
    const raw =
        '<p class="book-desc">公元前2333年，一颗微型白洞降临地球……</p><p>PS：新书已经发布。</p>';
    expect(bookIntroText(raw), '公元前2333年，一颗微型白洞降临地球……\nPS：新书已经发布。');
  });

  test('entities are restored and scripts removed', () {
    const raw = '<div>他说&nbsp;“好”<script>alert(1)</script>&hellip;</div>';
    expect(bookIntroText(raw), '他说 “好”…');
  });

  test('an intro with only markup falls back to empty', () {
    expect(bookIntroText('<p></p>\n<p> </p>'), '');
    expect(bookIntroText(''), '');
  });

  test('whitespace is collapsed but paragraphs stay separate', () {
    const raw = '<p>第一段   文字</p>\n\n\n<p>第二段</p>';
    expect(bookIntroText(raw), '第一段 文字\n第二段');
  });
}
