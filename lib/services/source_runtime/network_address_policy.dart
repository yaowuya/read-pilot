class UnsafeNetworkAddressException implements Exception {
  const UnsafeNetworkAddressException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Canonical literal-address checks shared by imports and runtime requests.
class NetworkAddressPolicy {
  const NetworkAddressPolicy._();

  static bool isForbiddenHost(String rawHost) {
    var host = rawHost.trim().toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost')) return true;
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host.contains('%')) return true;
    final bytes = parseLiteral(host);
    if (bytes != null) return isForbiddenAddress(bytes);
    return _looksLikeNumericAddress(host);
  }

  static List<int>? parseLiteral(String host) {
    if (host.contains(':')) return _parseIpv6(host);
    if (host.contains('.')) return _parseIpv4(host);
    return null;
  }

  static bool isForbiddenAddress(List<int> bytes) {
    if (bytes.length == 4) return _isForbiddenIpv4(bytes);
    if (bytes.length != 16) return true;
    final allZero = bytes.every((byte) => byte == 0);
    if (allZero) return true;
    final loopback =
        bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
    if (loopback) return true;

    final mappedIpv4 =
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    final compatibleIpv4 = bytes.take(12).every((byte) => byte == 0);
    final nat64Ipv4 =
        bytes[0] == 0x00 &&
        bytes[1] == 0x64 &&
        bytes[2] == 0xff &&
        bytes[3] == 0x9b &&
        bytes.sublist(4, 12).every((byte) => byte == 0);
    if (mappedIpv4 || compatibleIpv4 || nat64Ipv4) {
      return _isForbiddenIpv4(bytes.sublist(12));
    }

    if ((bytes[0] & 0xfe) == 0xfc) return true;
    if (bytes[0] == 0xfe &&
        ((bytes[1] & 0xc0) == 0x80 || (bytes[1] & 0xc0) == 0xc0)) {
      return true;
    }
    if (bytes[0] == 0xff) return true;
    if (bytes[0] == 0x20 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x0d &&
        bytes[3] == 0xb8) {
      return true;
    }
    return false;
  }

  static bool _isForbiddenIpv4(List<int> value) {
    final a = value[0];
    final b = value[1];
    final c = value[2];
    return a == 0 ||
        a == 10 ||
        a == 127 ||
        a >= 224 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 192 && b == 0 && c == 0) ||
        (a == 192 && b == 0 && c == 2) ||
        (a == 198 && (b == 18 || b == 19)) ||
        (a == 198 && b == 51 && c == 100) ||
        (a == 203 && b == 0 && c == 113);
  }

  static List<int>? _parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final bytes = <int>[];
    for (final part in parts) {
      if (part.isEmpty ||
          (part.length > 1 && part.startsWith('0')) ||
          !RegExp(r'^\d+$').hasMatch(part)) {
        return null;
      }
      final value = int.tryParse(part);
      if (value == null || value > 255) return null;
      bytes.add(value);
    }
    return bytes;
  }

  static List<int>? _parseIpv6(String rawHost) {
    var host = rawHost;
    if (host.contains('.')) {
      final separator = host.lastIndexOf(':');
      if (separator < 0) return null;
      final ipv4 = _parseIpv4(host.substring(separator + 1));
      if (ipv4 == null) return null;
      final high = (ipv4[0] << 8) | ipv4[1];
      final low = (ipv4[2] << 8) | ipv4[3];
      host =
          '${host.substring(0, separator)}:'
          '${high.toRadixString(16)}:${low.toRadixString(16)}';
    }
    if (RegExp(r'::').allMatches(host).length > 1) return null;
    final compressed = host.contains('::');
    final halves = host.split('::');
    final left = halves.first.isEmpty ? <String>[] : halves.first.split(':');
    final right = compressed && halves.length == 2 && halves.last.isNotEmpty
        ? halves.last.split(':')
        : <String>[];
    final missing = 8 - left.length - right.length;
    if ((!compressed && missing != 0) || (compressed && missing < 1)) {
      return null;
    }
    final groups = <int>[];
    for (final part in left) {
      final value = _hexGroup(part);
      if (value == null) return null;
      groups.add(value);
    }
    if (compressed) groups.addAll(List.filled(missing, 0));
    for (final part in right) {
      final value = _hexGroup(part);
      if (value == null) return null;
      groups.add(value);
    }
    if (groups.length != 8) return null;
    return [
      for (final group in groups) ...[group >> 8, group & 0xff],
    ];
  }

  static int? _hexGroup(String value) {
    if (value.isEmpty ||
        value.length > 4 ||
        !RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
      return null;
    }
    return int.tryParse(value, radix: 16);
  }

  static bool _looksLikeNumericAddress(String host) {
    if (host.contains(':')) return true;
    if (RegExp(r'^(?:0x[0-9a-f]+|\d+)$').hasMatch(host)) return true;
    if (!host.contains('.')) return false;
    final parts = host.split('.');
    return parts.every(
      (part) => RegExp(r'^(?:0x[0-9a-f]+|\d+)$').hasMatch(part),
    );
  }
}
