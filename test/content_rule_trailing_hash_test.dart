import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:read_pilot/services/source_runtime/content_replacement.dart';
import 'package:read_pilot/services/source_runtime/rule_interpreter.dart';

void main() {
  test('trailing ## on content selector keeps CSS extraction', () {
    final root = RuleNode.html(
      html
          .parse('<div id="nr1">第一章正文<br>第二段</div>')
          .documentElement!,
    );
    final interpreter = RuleInterpreter();

    expect(
      interpreter.extract(root, r'id.nr1@textNodes##'),
      contains('第一章正文'),
    );
  });

  test('leading ## delete replaceRegex removes ads when safe', () {
    expect(ContentReplacement.isSupported(r'##广告词'), isTrue);
    expect(
      const ContentReplacement().apply('正文\n广告词\n续', r'##广告词'),
      '正文\n\n续',
    );
  });

  test('leading ## with ##replacement is accepted when safe', () {
    expect(ContentReplacement.isSupported(r'##广告##【已删】'), isTrue);
    expect(
      const ContentReplacement().apply('前文广告后文', r'##广告##【已删】'),
      '前文【已删】后文',
    );
  });

  test('catastrophic leading ## replaceRegex stays unsupported', () {
    expect(
      ContentReplacement.isSupported(
        r'##\n.*本章.*\n第.*章.*第.*页.*\n\s\s|.第1/.页.',
      ),
      isFalse,
    );
  });
}
