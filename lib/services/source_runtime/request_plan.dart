import 'dart:typed_data';

/// Immutable transport instruction compiled from one source URL definition.
class RequestPlan {
  RequestPlan({
    required this.uri,
    required this.method,
    required Map<String, String> headers,
    this.body,
  }) : headers = Map.unmodifiable(headers);

  final Uri uri;
  final String method;
  final Map<String, String> headers;
  final Uint8List? body;
}

enum SourceRuntimeErrorKind {
  invalidRule,
  invalidRequest,
  unsupportedCapability,
}

class SourceRuntimeException implements Exception {
  const SourceRuntimeException(this.kind, this.message);

  final SourceRuntimeErrorKind kind;
  final String message;

  @override
  String toString() => message;
}
