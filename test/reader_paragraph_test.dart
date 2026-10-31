import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/ui/reader/reader_paragraph.dart';

void main() {
  testWidgets('first line reserves exactly two em without source whitespace', (
    tester,
  ) async {
    for (final size in [18.0, 22.0, 30.0]) {
      final style = TextStyle(inherit: false, fontSize: size, height: 1.6);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: ReaderParagraph(text: '正文测试', style: style),
            ),
          ),
        ),
      );
      final rich = find.descendant(
        of: find.byType(ReaderParagraph),
        matching: find.byType(RichText),
      );
      final render = tester.renderObject<RenderParagraph>(rich);
      final firstCharacter = render
          .getBoxesForSelection(
            const TextSelection(baseOffset: 1, extentOffset: 2),
          )
          .single;
      expect(firstCharacter.left, closeTo(size * 2, 0.1));
      expect(render.text.toPlainText(), '￼正文测试');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('existing full-width and ASCII indentation is not doubled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderParagraph(
          text: '﻿　 \t　正文',
          style: TextStyle(inherit: false, fontSize: 22),
        ),
      ),
    );
    final render = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(ReaderParagraph),
        matching: find.byType(RichText),
      ),
    );
    expect(render.text.toPlainText(), '￼正文');
  });

  testWidgets('page continuation begins at the margin without a new indent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ReaderParagraph(
            text: '续段正文',
            isContinuation: true,
            style: TextStyle(inherit: false, fontSize: 22),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(ReaderParagraph),
        matching: find.byType(RichText),
      ),
    );
    expect(render.text.toPlainText(), '续段正文');
    expect(
      render
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 1),
          )
          .single
          .left,
      0,
    );
  });

  testWidgets('wrapped lines return to the margin after the first line', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 110,
            child: ReaderParagraph(
              text: '正文段落排版测试正文段落排版测试',
              style: TextStyle(inherit: false, fontSize: 22, height: 1.6),
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(ReaderParagraph),
        matching: find.byType(RichText),
      ),
    );
    final boxes = render.getBoxesForSelection(
      TextSelection(
        baseOffset: 1,
        extentOffset: render.text.toPlainText().length,
      ),
    );
    expect(boxes.length, greaterThan(1));
    expect(boxes.first.left, closeTo(44, 0.1));
    expect(boxes.skip(1).every((box) => box.left == 0), isTrue);
    expect(tester.takeException(), isNull);
  });
}
