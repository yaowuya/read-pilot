import 'dart:async';

import 'package:flutter/foundation.dart';

enum ReadAloudState { idle, speaking, unavailable, error }

abstract interface class ReadAloudEngine {
  Future<void> speak(String text);
  Future<void> stop();
}

abstract final class ReadAloudText {
  static const maxCharacters = 8000;

  static String fromParagraphs(Iterable<String> paragraphs) {
    final output = StringBuffer();
    for (final paragraph in paragraphs) {
      final value = paragraph.trim();
      if (value.isEmpty) continue;
      final separator = output.isEmpty ? 0 : 1;
      if (output.length + separator + value.length > maxCharacters) break;
      if (separator == 1) output.writeln();
      output.write(value);
    }
    return output.toString();
  }
}

final class ReadAloudController extends ChangeNotifier {
  ReadAloudController({ReadAloudEngine? engine, bool? supported})
    : _engine = engine,
      _supported = supported ?? engine != null;

  final ReadAloudEngine? _engine;
  final bool _supported;
  var _state = ReadAloudState.idle;
  var _generation = 0;
  var _disposed = false;

  ReadAloudState get state => _state;
  bool get isSupported => _supported;
  bool get isSpeaking => _state == ReadAloudState.speaking;

  Future<void> start(String text) async {
    final value = text.trim();
    final generation = ++_generation;
    if (!_supported || _engine == null) {
      _setState(ReadAloudState.unavailable);
      return;
    }
    if (value.isEmpty) {
      _setState(ReadAloudState.error);
      return;
    }
    _setState(ReadAloudState.speaking);
    try {
      await _engine.speak(value);
      if (generation == _generation) _setState(ReadAloudState.idle);
    } on Object {
      if (generation == _generation) _setState(ReadAloudState.error);
    }
  }

  Future<void> stop() async {
    _generation++;
    try {
      await _engine?.stop();
    } on Object {
      // A local engine may reject a redundant stop; the user intent is still idle.
    } finally {
      _setState(ReadAloudState.idle);
    }
  }

  void _setState(ReadAloudState value) {
    if (_disposed || _state == value) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
