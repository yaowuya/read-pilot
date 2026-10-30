import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:jsf/jsf.dart';

enum SourceScriptErrorKind {
  unsupported,
  timeout,
  memory,
  invalidInput,
  evaluation,
}

class SourceScriptException implements Exception {
  const SourceScriptException(this.kind, this.message);

  final SourceScriptErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Executes one imported script in a disposable, capability-free worker.
class SandboxedScriptRuntime {
  const SandboxedScriptRuntime({
    this.timeout = const Duration(milliseconds: 250),
    this.memoryLimitBytes = 16 * 1024 * 1024,
    this.maxStackSizeBytes = 512 * 1024,
  });

  final Duration timeout;
  final int memoryLimitBytes;
  final int maxStackSizeBytes;

  JsRuntimeOptions get _options => JsRuntimeOptions(
    timeout: timeout,
    memoryLimitBytes: memoryLimitBytes,
    maxStackSizeBytes: maxStackSizeBytes,
    maxTimers: 32,
    maxCallbacks: 64,
    maxPendingFutures: 64,
    maxModuleSourceBytes: 64 * 1024,
    jobBatchSize: 16,
  );

  Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    JsWorker? worker;
    try {
      worker = await JsWorker.start(options: _options, maxPendingRequests: 1);
      return true;
    } catch (_) {
      return false;
    } finally {
      await worker?.dispose();
    }
  }

  Future<Object?> evaluate(
    String script, {
    Map<String, Object?> globals = const {},
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const SourceScriptException(
        SourceScriptErrorKind.unsupported,
        '仅 Android 平台执行受限书源 JavaScript。',
      );
    }
    if (script.length > 64 * 1024) {
      throw const SourceScriptException(
        SourceScriptErrorKind.invalidInput,
        '书源脚本超过 64 KiB 限制。',
      );
    }

    late final Map<String, Object?> safeGlobals;
    try {
      safeGlobals = Map<String, Object?>.from(
        jsonDecode(jsonEncode(globals)) as Map,
      );
    } catch (_) {
      throw const SourceScriptException(
        SourceScriptErrorKind.invalidInput,
        '书源脚本变量必须是 JSON 可序列化数据。',
      );
    }
    if (safeGlobals.keys.any(
      (name) => !RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(name),
    )) {
      throw const SourceScriptException(
        SourceScriptErrorKind.invalidInput,
        '书源脚本变量名无效。',
      );
    }

    JsWorker? worker;
    try {
      worker = await JsWorker.start(options: _options, maxPendingRequests: 4);
      for (final entry in safeGlobals.entries) {
        await worker.setGlobal(entry.key, entry.value);
      }
      final source =
          '''
        'use strict';
        globalThis.fetch = undefined;
        globalThis.XMLHttpRequest = undefined;
        globalThis.WebSocket = undefined;
        globalThis.require = undefined;
        globalThis.process = undefined;
        globalThis.Java = undefined;
        globalThis.Packages = undefined;
        (() => eval(${jsonEncode(script)}))()
      ''';
      return await worker.eval(
        source,
        filename: '<source-rule>',
        timeout: timeout + const Duration(milliseconds: 250),
      );
    } on UnsupportedError {
      throw const SourceScriptException(
        SourceScriptErrorKind.unsupported,
        '当前平台不支持受限书源 JavaScript。',
      );
    } on JsException catch (error) {
      final summary = '${error.name} ${error.message}'.toLowerCase();
      if (summary.contains('timeout') ||
          summary.contains('interrupt') ||
          summary.contains('deadline')) {
        throw const SourceScriptException(
          SourceScriptErrorKind.timeout,
          '书源脚本执行超时。',
        );
      }
      if (summary.contains('memory') || summary.contains('allocation')) {
        throw const SourceScriptException(
          SourceScriptErrorKind.memory,
          '书源脚本超过内存限制。',
        );
      }
      if (summary.contains('failed to load dynamic library') ||
          summary.contains('module could not be found')) {
        throw const SourceScriptException(
          SourceScriptErrorKind.unsupported,
          '当前平台未安装书源脚本运行库。',
        );
      }
      throw const SourceScriptException(
        SourceScriptErrorKind.evaluation,
        '书源脚本执行失败。',
      );
    } on SourceScriptException {
      rethrow;
    } catch (_) {
      throw const SourceScriptException(
        SourceScriptErrorKind.evaluation,
        '无法启动书源脚本沙箱。',
      );
    } finally {
      await worker?.dispose();
    }
  }

  Future<void> close() async {}
}
