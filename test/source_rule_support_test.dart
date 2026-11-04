import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/domain/source_rule_support.dart';

/// Every pattern below is fed through [SourceRuleSupport.isSafeRegex], which is
/// the only gate between a third-party书源 rule and a backtracking RegExp run
/// over a body of up to 256 KiB (`ContentReplacement.maxInputCharacters`).
void main() {
  group('refuses patterns that backtrack catastrophically', () {
    // These are the shapes that hang the reader. Two are known super-polynomial
    // on their own: `.*.*.*=` and `.*a.*a.*=` never finished on a 2 000
    // character body, while the body cap is 256 KiB.
    const catastrophic = <String>[
      r'.*.*.*=',
      r'.+.+=',
      r'.*a.*a.*=',
      r'.*.*',
      r'\s*\s*',
      r'[\s\S]*[\s\S]*',
      r'that-is-long.*.*x',
    ];

    for (final pattern in catastrophic) {
      test('rejects $pattern', () {
        expect(SourceRuleSupport.isSafeRegex(pattern, ''), isFalse);
      });
    }
  });

  group('refuses the classic nesting and alternation explosions', () {
    const dangerous = <String>[
      r'(a+)+',
      r'(a|aa)+',
      r'([a-z]+)*',
      r'(?:\d+)+',
      r'(a|b)*c',
      r'(?<=\d)abc',
      r'(a)\1',
      r'a**',
      r'a*+',
    ];

    for (final pattern in dangerous) {
      test('rejects $pattern', () {
        expect(SourceRuleSupport.isSafeRegex(pattern, ''), isFalse);
      });
    }
  });

  group('refuses patterns that can match the empty string', () {
    // A rule that matches empty can be re-run at every position, so the cost
    // multiplies by the body length.
    for (final pattern in <String>[r'.*?', r'\s*', r'(abc)?', r'a{0,3}']) {
      test('rejects $pattern', () {
        expect(SourceRuleSupport.isSafeRegex(pattern, ''), isFalse);
      });
    }
  });

  group('accepts the cleaning rules real book sources actually declare', () {
    // Each of these appears in published Legado sources; refusing them makes a
    // whole chapter unreadable, which is exactly the bug the relaxation fixed.
    const accepted = <String>[
      r'<script.*?</script>|[\s\S]*?<br[^>]*>[\s\S]*|本章没完[\s\S]*',
      r'<script.*?</script>|…[^<]*<br[^>]*>[\s\S]*|本章没完[\s\S]*',
      r'第\d+章.*',
      r'\(本章完\)',
      r'<!--.*?-->',
      r'\s+',
      r'\n{2,}',
      r'<br\s*/?>',
      r'&nbsp;',
      r'[0-9]{1,3}',
      r'搜\d+最新章节.*?更快',
    ];

    for (final pattern in accepted) {
      test('accepts $pattern', () {
        expect(SourceRuleSupport.isSafeRegex(pattern, ''), isTrue);
      });
    }
  });

  test('refuses an over-long pattern but accepts one just inside the cap', () {
    expect(SourceRuleSupport.isSafeRegex('a' * 4096, ''), isTrue);
    expect(SourceRuleSupport.isSafeRegex('a' * 4097, ''), isFalse);
  });

  test('a single alternation branch cannot hide three wildcards', () {
    // The branch-local counter must reset between top-level alternatives, and
    // must still be enforced inside each one.
    expect(SourceRuleSupport.isSafeRegex(r'^a$|.*.*.*=', ''), isFalse);
    expect(SourceRuleSupport.isSafeRegex(r'.*a.*|.*b.*', ''), isTrue);
  });

  test('accepts a whole-chapter replacement built on a safe pattern', () {
    expect(SourceRuleSupport.isSafeContentReplacement(r'<br\s*/?>##'), isTrue);
    expect(SourceRuleSupport.isSafeContentReplacement(r'.*.*.*=##'), isFalse);
    expect(SourceRuleSupport.isSafeContentReplacement('no separator'), isFalse);
  });
}
