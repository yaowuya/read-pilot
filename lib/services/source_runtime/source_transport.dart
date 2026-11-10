import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:http/http.dart' as http;

import 'network_address_policy.dart';
import 'request_plan.dart';
import 'response_envelope.dart';
import 'safe_http_client.dart';

const _crossOriginSafeHeaders = {'accept', 'accept-language', 'user-agent'};
const _entityHeaders = {'content-length', 'content-type', 'transfer-encoding'};

/// Network grant for one source workflow. Origins use scheme, host and port.
class SourceNetworkPolicy {
  SourceNetworkPolicy({
    required Set<String> allowedOrigins,
    this.allowPrivateAddresses = false,
  }) : allowedOrigins = Set.unmodifiable(allowedOrigins);

  final Set<String> allowedOrigins;
  final bool allowPrivateAddresses;
}

enum SourceTransportErrorKind {
  invalidUrl,
  originDenied,
  timeout,
  cancelled,
  redirect,
  httpStatus,
  tooLarge,
  invalidEncoding,
  network,
}

class SourceTransportException implements Exception {
  const SourceTransportException(this.kind, this.message, {this.statusCode});

  final SourceTransportErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Executes request plans under explicit destination and resource budgets.
class SourceTransport {
  SourceTransport({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = 2 * 1024 * 1024,
    this.maxRedirects = 4,
  }) : _client = client ?? createSafeHttpClient();

  final http.Client _client;
  final Duration timeout;
  final int maxResponseBytes;
  final int maxRedirects;

  void close() => _client.close();

  Future<ResponseEnvelope> execute(
    RequestPlan plan, {
    required SourceNetworkPolicy policy,
    Future<void>? abortTrigger,
    bool decodeText = true,
  }) async {
    final abort = Completer<void>();
    var cancelled = false;
    var timedOut = false;
    abortTrigger?.then(
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

    final requestUri = plan.uri;
    var uri = requestUri;
    var method = plan.method.toUpperCase();
    var body = plan.body;
    var headers = {
      for (final entry in plan.headers.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final redirects = <Uri>[];

    try {
      for (var redirectCount = 0; ; redirectCount++) {
        _checkUri(uri, policy);
        final request = http.AbortableRequest(
          method,
          uri,
          abortTrigger: abort.future,
        )..followRedirects = false;
        request.headers.addAll(headers);
        if (body != null && method != 'GET' && method != 'HEAD') {
          request.bodyBytes = body;
        }
        final response = await Future.any<http.StreamedResponse>([
          _client.send(request),
          abort.future.then<http.StreamedResponse>((_) {
            if (timedOut) {
              throw const SourceTransportException(
                SourceTransportErrorKind.timeout,
                '书源请求超时。',
              );
            }
            if (cancelled) {
              throw const SourceTransportException(
                SourceTransportErrorKind.cancelled,
                '书源请求已取消。',
              );
            }
            throw const SourceTransportException(
              SourceTransportErrorKind.network,
              '书源请求已中止。',
            );
          }),
        ]);
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          await response.stream.listen((_) {}).cancel();
          final location = response.headers['location'];
          if (location == null || redirectCount >= maxRedirects) {
            throw const SourceTransportException(
              SourceTransportErrorKind.redirect,
              '书源重定向无效或次数过多。',
            );
          }
          final next = uri.resolve(location);
          if (uri.scheme == 'https' && next.scheme != 'https') {
            throw const SourceTransportException(
              SourceTransportErrorKind.redirect,
              '书源重定向不能从 HTTPS 降级到 HTTP。',
            );
          }
          _checkUri(next, policy);
          final crossOrigin = next.origin != uri.origin;
          if (crossOrigin) {
            if ({307, 308}.contains(response.statusCode) && body != null) {
              throw const SourceTransportException(
                SourceTransportErrorKind.redirect,
                '书源请求正文不能跨来源重放。',
              );
            }
            headers = Map.of(headers)
              ..removeWhere(
                (name, _) => !_crossOriginSafeHeaders.contains(name),
              );
          }
          if ({301, 302, 303}.contains(response.statusCode) &&
              method != 'GET' &&
              method != 'HEAD') {
            method = 'GET';
            body = null;
            headers = Map.of(headers)
              ..removeWhere((name, _) => _entityHeaders.contains(name));
          }
          uri = next;
          redirects.add(next);
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.stream.listen((_) {}).cancel();
          throw SourceTransportException(
            SourceTransportErrorKind.httpStatus,
            '书源返回 HTTP ${response.statusCode}。',
            statusCode: response.statusCode,
          );
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (builder.length + chunk.length > maxResponseBytes) {
            throw SourceTransportException(
              SourceTransportErrorKind.tooLarge,
              '书源响应超过 $maxResponseBytes 字节。',
            );
          }
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        // Image responses share transport policy and budgets but are not text.
        final text = decodeText
            ? _decodeText(bytes, response.headers['content-type'])
            : '';
        return ResponseEnvelope(
          requestUri: requestUri,
          finalUri: uri,
          statusCode: response.statusCode,
          headers: response.headers,
          bytes: bytes,
          text: text,
          redirects: redirects,
        );
      }
    } on SourceTransportException {
      rethrow;
    } on http.RequestAbortedException {
      if (timedOut) {
        throw const SourceTransportException(
          SourceTransportErrorKind.timeout,
          '书源请求超时。',
        );
      }
      if (cancelled) {
        throw const SourceTransportException(
          SourceTransportErrorKind.cancelled,
          '书源请求已取消。',
        );
      }
      throw const SourceTransportException(
        SourceTransportErrorKind.network,
        '书源请求已中止。',
      );
    } on UnsafeNetworkAddressException catch (error) {
      throw SourceTransportException(
        SourceTransportErrorKind.originDenied,
        error.message,
      );
    } on FormatException {
      throw const SourceTransportException(
        SourceTransportErrorKind.invalidEncoding,
        '书源响应不是有效的 UTF-8。',
      );
    } catch (_) {
      throw const SourceTransportException(
        SourceTransportErrorKind.network,
        '无法连接书源。',
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  static String _decodeText(Uint8List bytes, String? contentType) {
    final declared = RegExp(
      r'''charset\s*=\s*["']?([^;\s"']+)''',
      caseSensitive: false,
    ).firstMatch(contentType ?? '')?[1]?.toLowerCase();
    final headerCharset = declared?.replaceAll('_', '-');
    if (headerCharset != null &&
        headerCharset != 'utf-8' &&
        headerCharset != 'utf8' &&
        headerCharset != 'us-ascii') {
      if ({'gbk', 'gb2312', 'cp936', 'windows-936'}.contains(headerCharset)) {
        return gbk.decode(bytes, allowMalformed: false);
      }
      throw SourceTransportException(
        SourceTransportErrorKind.invalidEncoding,
        '暂不支持书源响应编码 $declared。',
      );
    }

    // 响应头没声明编码时不能直接假定 UTF-8：中文站常用 GBK，而且不少站点
    // 只在页面 meta 里写编码。顺序是「响应头 → 页面 meta → UTF-8 → GBK」，
    // 只有明确判定不是 UTF-8 才换 GBK，避免把正常页面解成乱码。
    final sniffed = _sniffMetaCharset(bytes);
    if (sniffed != null &&
        {'gbk', 'gb2312', 'cp936', 'windows-936'}.contains(sniffed)) {
      return gbk.decode(bytes, allowMalformed: false);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      // 最后一道兜底：真实书源里偶尔有既非 UTF-8 也非严格 GBK 的脏字节，
      // 与其整章报错，不如用替换字符解码，让用户至少能读到正文。
      return gbk.decode(bytes, allowMalformed: true);
    }
  }

  /// 从响应体前 2 KB 的 `<meta charset>` / `<meta http-equiv>` 里嗅探编码。
  static String? _sniffMetaCharset(Uint8List bytes) {
    final head = latin1.decode(
      bytes.length > 2048 ? bytes.sublist(0, 2048) : bytes,
    );
    final match = RegExp(
      r'''charset\s*=\s*["']?\s*([\w-]+)''',
      caseSensitive: false,
    ).firstMatch(head);
    return match?[1]?.toLowerCase().replaceAll('_', '-');
  }

  static void _checkUri(Uri uri, SourceNetworkPolicy policy) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const SourceTransportException(
        SourceTransportErrorKind.invalidUrl,
        '书源请求必须是无账号密码的 HTTP(S) 地址。',
      );
    }
    if (!policy.allowedOrigins.contains(uri.origin)) {
      throw SourceTransportException(
        SourceTransportErrorKind.originDenied,
        '书源没有访问 ${uri.origin} 的授权。',
      );
    }
    if (!policy.allowPrivateAddresses &&
        NetworkAddressPolicy.isForbiddenHost(uri.host)) {
      throw const SourceTransportException(
        SourceTransportErrorKind.originDenied,
        '书源不能访问本机或私有网络地址。',
      );
    }
  }
}
