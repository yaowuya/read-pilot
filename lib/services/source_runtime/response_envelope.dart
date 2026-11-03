import 'dart:typed_data';

/// Transport result retains both wire metadata and decoded text.
class ResponseEnvelope {
  ResponseEnvelope({
    required this.requestUri,
    required this.finalUri,
    required this.statusCode,
    required Map<String, String> headers,
    required this.bytes,
    required this.text,
    required Iterable<Uri> redirects,
  }) : headers = Map.unmodifiable(headers),
       redirects = List.unmodifiable(redirects);

  final Uri requestUri;
  final Uri finalUri;
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bytes;
  final String text;
  final List<Uri> redirects;
}
