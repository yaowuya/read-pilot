import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'read_aloud.dart';

final class AndroidReadAloudEngine implements ReadAloudEngine {
  AndroidReadAloudEngine({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  static const channelName = 'dev.readpilot.read_pilot/read_aloud';

  final MethodChannel _channel;
  Completer<void>? _completion;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> speak(String text) async {
    if (!isSupported) {
      throw UnsupportedError('仅 Android 设备支持本机朗读。');
    }
    if (_completion != null) await stop();
    final completion = Completer<void>();
    _completion = completion;
    try {
      await _channel.invokeMethod<void>('speak', {'text': text});
      await completion.future;
    } finally {
      if (identical(_completion, completion)) _completion = null;
    }
  }

  @override
  Future<void> stop() async {
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) completion.complete();
    if (!isSupported) return;
    await _channel.invokeMethod<void>('stop');
  }

  Future<void> _onPlatformCall(MethodCall call) async {
    final completion = _completion;
    if (completion == null || completion.isCompleted) return;
    switch (call.method) {
      case 'completed':
      case 'cancelled':
        completion.complete();
      case 'error':
        completion.completeError(StateError('设备朗读无法完成。'));
      default:
        throw MissingPluginException('未知朗读事件：${call.method}');
    }
  }
}
