import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

import '../../domain/book_source.dart';
import 'request_plan.dart';

const _defaultUserAgent =
    'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36';

const _prohibitedHeaders = {
  'connection',
  'content-length',
  'host',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
};

/// Compiles source templates into transport-ready requests without I/O.
class RequestPlanner {
  const RequestPlanner();

  RequestPlan plan(
    BookSource source,
    String template, {
    Map<String, Object?> variables = const {},
  }) {
    final (urlTemplate, rawOptions) = _splitOptions(template);
    final options = rawOptions == null
        ? <String, dynamic>{}
        : _expandValue(rawOptions, source, variables) as Map<String, dynamic>;
    final charset = _requestCharset(options['charset']);
    final expandedUrl = _expand(
      urlTemplate,
      source,
      variables,
      encodeForUrl: true,
      charset: charset,
    );
    final uri = Uri.parse(source.id).resolve(expandedUrl);
    final method = (options['method']?.toString() ?? 'GET').toUpperCase();
    if (!{'GET', 'POST', 'HEAD'}.contains(method)) {
      throw SourceRuntimeException(
        SourceRuntimeErrorKind.unsupportedCapability,
        '暂不支持 HTTP $method。',
      );
    }

    final headers = <String, String>{...source.headers};
    headers.putIfAbsent('user-agent', () => _defaultUserAgent);
    final optionHeaders = _decodeHeaders(options['headers']);
    headers.addAll(optionHeaders);

    Uint8List? body;
    final bodyValue = options['body'];
    if (bodyValue != null && method != 'POST') {
      throw SourceRuntimeException(
        SourceRuntimeErrorKind.invalidRequest,
        '$method 请求不能携带 body。',
      );
    }
    if (bodyValue != null && method == 'POST') {
      final contentType = headers['content-type']?.toLowerCase();
      if (bodyValue is Map && !(contentType?.contains('json') ?? false)) {
        headers.putIfAbsent(
          'content-type',
          () => 'application/x-www-form-urlencoded; charset=$charset',
        );
        final fields = {
          for (final entry in bodyValue.entries)
            entry.key.toString(): entry.value?.toString() ?? '',
        };
        body = Uint8List.fromList(utf8.encode(_formEncode(fields, charset)));
      } else if (bodyValue is String) {
        headers.putIfAbsent(
          'content-type',
          () => 'text/plain; charset=$charset',
        );
        body = Uint8List.fromList(_encodeText(bodyValue, charset));
      } else {
        if (charset != 'utf-8') {
          throw const SourceRuntimeException(
            SourceRuntimeErrorKind.unsupportedCapability,
            'JSON 请求正文只支持 UTF-8。',
          );
        }
        headers.putIfAbsent('content-type', () => 'application/json');
        body = Uint8List.fromList(utf8.encode(jsonEncode(bodyValue)));
      }
    }

    return RequestPlan(uri: uri, method: method, headers: headers, body: body);
  }

  (String, Map<String, dynamic>?) _splitOptions(String template) {
    var searchBefore = template.length;
    while (true) {
      final comma = template.lastIndexOf(',', searchBefore - 1);
      if (comma < 0) return (template.trim(), null);
      final candidate = template.substring(comma + 1).trim();
      if (candidate.startsWith('{') && candidate.endsWith('}')) {
        try {
          final decoded = jsonDecode(candidate);
          if (decoded is Map) {
            return (
              template.substring(0, comma).trim(),
              Map<String, dynamic>.from(decoded),
            );
          }
        } on FormatException {
          // This comma may be nested inside the trailing JSON object.
        }
      }
      searchBefore = comma;
    }
  }

  dynamic _expandValue(
    dynamic value,
    BookSource source,
    Map<String, Object?> variables,
  ) => switch (value) {
    String() => _expand(value, source, variables, encodeForUrl: false),
    List() => [for (final item in value) _expandValue(item, source, variables)],
    Map() => {
      for (final entry in value.entries)
        entry.key.toString(): _expandValue(entry.value, source, variables),
    },
    _ => value,
  };

  /// Replaces `{{name}}` placeholders with request variables.
  ///
  /// Legado resolves `{{...}}` as JavaScript, which is why a discover category's
  /// info-map values can reach its URL; this runtime has no script engine, so it
  /// resolves the same placeholders from [variables] instead. Any name present in
  /// [variables] is accepted — the info map names are chosen by the source, not
  /// by this app — while `baseUrl` always expands to the source URL and a name
  /// nobody supplied is a real error rather than a silent empty string.
  String _expand(
    String value,
    BookSource source,
    Map<String, Object?> variables, {
    required bool encodeForUrl,
    String charset = 'utf-8',
  }) => value.replaceAllMapped(RegExp(r'\{\{(.*?)\}\}'), (match) {
    final name = match[1]!.trim();
    if (name.isEmpty) {
      throw const SourceRuntimeException(
        SourceRuntimeErrorKind.invalidRule,
        '模板表达式 {{}} 缺少变量名。',
      );
    }
    final raw = name == 'baseUrl' ? source.id : variables[name];
    if (raw == null) {
      throw SourceRuntimeException(
        SourceRuntimeErrorKind.unsupportedCapability,
        '模板表达式 {{$name}} 缺少变量。',
      );
    }
    final text = raw.toString();
    return encodeForUrl && name != 'baseUrl'
        ? _queryEncode(text, charset)
        : text;
  });

  static String _requestCharset(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase().replaceAll(
      '_',
      '-',
    );
    if (normalized == null ||
        normalized.isEmpty ||
        normalized == 'utf-8' ||
        normalized == 'utf8') {
      return 'utf-8';
    }
    if ({'gbk', 'gb2312', 'cp936', 'windows-936'}.contains(normalized)) {
      return 'gbk';
    }
    throw SourceRuntimeException(
      SourceRuntimeErrorKind.unsupportedCapability,
      '暂不支持请求编码 $normalized。',
    );
  }

  static List<int> _encodeText(String value, String charset) {
    try {
      return charset == 'gbk' ? gbk.encode(value) : utf8.encode(value);
    } catch (_) {
      throw SourceRuntimeException(
        SourceRuntimeErrorKind.invalidRequest,
        '文本包含 $charset 无法编码的字符。',
      );
    }
  }

  static String _queryEncode(String value, String charset) {
    final output = StringBuffer();
    for (final byte in _encodeText(value, charset)) {
      final unreserved =
          (byte >= 0x41 && byte <= 0x5a) ||
          (byte >= 0x61 && byte <= 0x7a) ||
          (byte >= 0x30 && byte <= 0x39) ||
          {0x2d, 0x2e, 0x5f, 0x7e}.contains(byte);
      if (unreserved) {
        output.writeCharCode(byte);
      } else if (byte == 0x20) {
        output.write('+');
      } else {
        output
          ..write('%')
          ..write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
    }
    return output.toString();
  }

  static String _formEncode(Map<String, String> fields, String charset) =>
      fields.entries
          .map(
            (entry) =>
                '${_queryEncode(entry.key, charset)}='
                '${_queryEncode(entry.value, charset)}',
          )
          .join('&');

  Map<String, String> _decodeHeaders(dynamic value) {
    if (value == null || value == '') return {};
    dynamic decoded = value;
    if (value is String) {
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        throw const SourceRuntimeException(
          SourceRuntimeErrorKind.invalidRequest,
          '请求 options.headers 不是有效的 JSON 对象。',
        );
      }
    }
    if (decoded is! Map) {
      throw const SourceRuntimeException(
        SourceRuntimeErrorKind.invalidRequest,
        '请求 options.headers 必须是对象。',
      );
    }
    final headers = <String, String>{};
    for (final entry in decoded.entries) {
      final name = entry.key.toString().trim().toLowerCase();
      final value = entry.value?.toString() ?? '';
      if (name.isEmpty ||
          name.contains(RegExp(r'[\r\n]')) ||
          value.contains(RegExp(r'[\r\n]')) ||
          _prohibitedHeaders.contains(name)) {
        throw SourceRuntimeException(
          SourceRuntimeErrorKind.invalidRequest,
          '请求 header ${entry.key} 不安全。',
        );
      }
      headers[name] = value;
    }
    return headers;
  }
}
