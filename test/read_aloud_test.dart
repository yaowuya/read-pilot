import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:read_pilot/services/read_aloud.dart';

class _FakeReadAloudEngine implements ReadAloudEngine {
  final spoken = <String>[];
  final started = Completer<void>();
  final completed = Completer<void>();
  var stops = 0;

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    if (!started.isCompleted) started.complete();
    return completed.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

class _RejectingStopEngine implements ReadAloudEngine {
  var stops = 0;

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {
    stops++;
    throw StateError('本机朗读服务已关闭。');
  }
}

void main() {
  test(
    'device read aloud stops stale playback without reviving state',
    () async {
      final engine = _FakeReadAloudEngine();
      final controller = ReadAloudController(engine: engine, supported: true);

      final pending = controller.start('本机朗读文本。');
      await engine.started.future;
      expect(controller.state, ReadAloudState.speaking);
      expect(engine.spoken, ['本机朗读文本。']);

      await controller.stop();
      expect(controller.state, ReadAloudState.idle);
      expect(engine.stops, 1);

      engine.completed.complete();
      await pending;
      expect(controller.state, ReadAloudState.idle);
    },
  );

  test('unsupported read aloud never invokes an engine', () async {
    final engine = _FakeReadAloudEngine();
    final controller = ReadAloudController(engine: engine, supported: false);

    await controller.start('不会发送给朗读引擎。');

    expect(controller.state, ReadAloudState.unavailable);
    expect(engine.spoken, isEmpty);
  });

  test(
    'disposing safely ignores a redundant local engine stop failure',
    () async {
      final engine = _RejectingStopEngine();
      final controller = ReadAloudController(engine: engine, supported: true);

      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(engine.stops, 1);
    },
  );

  test('read aloud text preserves paragraphs within a fixed budget', () {
    final text = ReadAloudText.fromParagraphs([
      '第一段。',
      '第二段。',
      'x' * (ReadAloudText.maxCharacters + 1),
    ]);

    expect(text, '第一段。\n第二段。');
  });
}
