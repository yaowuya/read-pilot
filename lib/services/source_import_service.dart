import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/source_import.dart';
import 'source_importer.dart';
import 'source_runtime/network_address_policy.dart';
import 'source_runtime/safe_http_client.dart';

/// Prepares paste, file and URL imports without writing application state.
class SourceImportService {
  SourceImportService({
    http.Client? client,
    SourceImporter? importer,
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = SourceImporter.maxBytes,
  }) : _client = client ?? createSafeHttpClient(),
       _importer = importer ?? SourceImporter();

  static const _maxRedirects = 4;

  /// Bounded retries for failures that say nothing about the URL itself.
  ///
  /// Some feeds sit behind origins that drop TLS handshakes intermittently: the
  /// same request succeeds on one attempt and dies mid-handshake on the next,
  /// so a single-shot import fails roughly half the time against such a host.
  /// Retrying the transport hop turns that into a successful import; every
  /// address, scheme and redirect check still runs on each attempt, and a
  /// completed HTTP response is never retried.
  static const _maxTransportAttempts = 8;
  static const _transportRetryDelay = Duration(milliseconds: 80);

  static const _acceptedContentTypes = {
    'application/json',
    'application/octet-stream',
    'application/force-download',
    'text/json',
    'text/plain',
  };

  final http.Client _client;
  final SourceImporter _importer;
  final Duration timeout;
  final int maxResponseBytes;

  String get _maxResponseBytesLabel =>
      maxResponseBytes == SourceImporter.maxBytes
      ? SourceImporter.maxBytesLabel
      : '$maxResponseBytes 字节';

  Future<SourceImportPreview> prepare(
    SourceImportInput input, {
    Future<void>? abortTrigger,
  }) async => switch (input) {
    SourceTextImportInput() => _fromText(
      input.text,
      SourceImportProvenance(
        kind: SourceImportKind.text,
        label: input.label,
        responseBytes: utf8.encode(input.text).length,
      ),
    ),
    SourceFileImportInput() => _fromText(
      input.text,
      SourceImportProvenance(
        kind: SourceImportKind.file,
        label: input.label,
        responseBytes: utf8.encode(input.text).length,
      ),
    ),
    SourceUrlImportInput() => _fromUrl(input.uri, abortTrigger),
  };

  void close() => _client.close();

  SourceImportPreview _fromText(
    String text,
    SourceImportProvenance provenance,
  ) {
    try {
      // Aggregated feeds routinely carry a few malformed entries. Dropping only
      // those keeps the import useful, and the preview discloses what was lost.
      final report = _importer.parseReport(text);
      return SourceImportPreview(
        sources: report.sources,
        skipped: report.skipped,
        provenance: provenance,
      );
    } on FormatException catch (error) {
      throw SourceImportException(
        SourceImportErrorKind.invalidJson,
        error.message,
      );
    }
  }

  Future<SourceImportPreview> _fromUrl(
    Uri requestedUri,
    Future<void>? externalAbort,
  ) async {
    if (!_isAllowedUri(requestedUri)) {
      throw const SourceImportException(
        SourceImportErrorKind.invalidUrl,
        '网络书源地址必须是无账号密码的公开 HTTP(S) URL。',
      );
    }

    final abort = Completer<void>();
    var cancelled = false;
    var timedOut = false;
    externalAbort?.then(
      (_) {
        cancelled = true;
        if (!abort.isCompleted) abort.complete();
      },
      onError: (_) {
        cancelled = true;
        if (!abort.isCompleted) abort.complete();
      },
    );
    final timer = Timer(timeout, () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });

    try {
      var uri = requestedUri;
      for (var redirects = 0; redirects <= _maxRedirects; redirects++) {
        if (!_isAllowedUri(uri)) {
          throw const SourceImportException(
            SourceImportErrorKind.redirect,
            '网络书源重定向到了不允许的地址。',
          );
        }
        final response = await Future.any<http.StreamedResponse>([
          _sendWithTransportRetry(uri, abort),
          abort.future.then<http.StreamedResponse>((_) {
            if (timedOut) {
              throw const SourceImportException(
                SourceImportErrorKind.timeout,
                '获取网络书源超时。',
              );
            }
            if (cancelled) {
              throw const SourceImportException(
                SourceImportErrorKind.cancelled,
                '已取消获取网络书源。',
              );
            }
            throw const SourceImportException(
              SourceImportErrorKind.network,
              '网络书源请求已中止。',
            );
          }),
        ]);
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          await response.stream.listen((_) {}).cancel();
          final location = response.headers['location'];
          if (location == null || redirects == _maxRedirects) {
            throw const SourceImportException(
              SourceImportErrorKind.redirect,
              '网络书源重定向无效或次数过多。',
            );
          }
          final next = uri.resolve(location);
          if (uri.scheme == 'https' && next.scheme != 'https') {
            throw const SourceImportException(
              SourceImportErrorKind.redirect,
              '网络书源不能从 HTTPS 降级到 HTTP。',
            );
          }
          uri = next;
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.stream.listen((_) {}).cancel();
          throw SourceImportException(
            SourceImportErrorKind.httpStatus,
            '网络书源返回 HTTP ${response.statusCode}。',
            statusCode: response.statusCode,
          );
        }

        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw SourceImportException(
              SourceImportErrorKind.tooLarge,
              '网络书源不能超过 $_maxResponseBytesLabel。',
            );
          }
          bytes.add(chunk);
        }
        final data = bytes.takeBytes();
        final contentType = response.headers['content-type'];
        final mediaType = contentType?.split(';').first.trim().toLowerCase();
        if (mediaType != null &&
            mediaType.isNotEmpty &&
            !_acceptedContentTypes.contains(mediaType) &&
            !mediaType.endsWith('+json')) {
          throw SourceImportException(
            SourceImportErrorKind.contentType,
            '网络地址返回的不是 JSON（$mediaType）。',
          );
        }
        final text = utf8.decode(data);
        return _fromText(
          text,
          SourceImportProvenance(
            kind: SourceImportKind.url,
            requestedUri: requestedUri,
            finalUri: uri,
            responseBytes: data.length,
            contentType: contentType,
          ),
        );
      }
      throw const SourceImportException(
        SourceImportErrorKind.redirect,
        '网络书源重定向次数过多。',
      );
    } on SourceImportException {
      rethrow;
    } on http.RequestAbortedException {
      if (timedOut) {
        throw const SourceImportException(
          SourceImportErrorKind.timeout,
          '获取网络书源超时。',
        );
      }
      if (cancelled) {
        throw const SourceImportException(
          SourceImportErrorKind.cancelled,
          '已取消获取网络书源。',
        );
      }
      throw const SourceImportException(
        SourceImportErrorKind.network,
        '网络书源请求已中止。',
      );
    } on TimeoutException {
      throw const SourceImportException(
        SourceImportErrorKind.timeout,
        '获取网络书源超时。',
      );
    } on UnsafeNetworkAddressException catch (error) {
      throw SourceImportException(
        SourceImportErrorKind.invalidUrl,
        error.message,
      );
    } on FormatException catch (error) {
      throw SourceImportException(
        SourceImportErrorKind.invalidJson,
        error.message,
      );
    } catch (_) {
      throw const SourceImportException(
        SourceImportErrorKind.network,
        '无法连接网络书源地址。',
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// Sends one GET, retrying only transport-level failures.
  ///
  /// A retryable failure is anything that reached the network but produced no
  /// response: a handshake that died mid-flight, a connection reset, a DNS
  /// hiccup. An abort (timeout or caller cancellation) is never retried, and a
  /// completed HTTP response is returned even when its status is an error,
  /// because the caller classifies statuses itself.
  Future<http.StreamedResponse> _sendWithTransportRetry(
    Uri uri,
    Completer<void> abort,
  ) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < _maxTransportAttempts; attempt++) {
      if (abort.isCompleted) {
        throw const SourceImportException(
          SourceImportErrorKind.network,
          '网络书源请求已中止。',
        );
      }
      if (attempt > 0) {
        final delay = _transportRetryDelay * attempt;
        if (await _delayOrAbort(delay, abort.future)) {
          throw const SourceImportException(
            SourceImportErrorKind.network,
            '网络书源请求已中止。',
          );
        }
      }
      // A request is single-use; every attempt needs its own instance.
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      try {
        return await _client.send(request);
      } on http.RequestAbortedException {
        rethrow;
      } on UnsafeNetworkAddressException {
        rethrow;
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
      }
    }
    if (lastError != null) Error.throwWithStackTrace(lastError, lastStack!);
    throw const SourceImportException(
      SourceImportErrorKind.network,
      '无法连接网络书源地址。',
    );
  }

  /// Returns true when [abort] fired before [delay] elapsed.
  static Future<bool> _delayOrAbort(Duration delay, Future<void> abort) {
    final done = Completer<bool>();
    final timer = Timer(delay, () {
      if (!done.isCompleted) done.complete(false);
    });
    abort.then(
      (_) {
        timer.cancel();
        if (!done.isCompleted) done.complete(true);
      },
      onError: (_) {
        timer.cancel();
        if (!done.isCompleted) done.complete(true);
      },
    );
    return done.future;
  }

  static bool _isAllowedUri(Uri uri) =>
      {'http', 'https'}.contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !NetworkAddressPolicy.isForbiddenHost(uri.host);
}
