abstract final class LocalBookId {
  static int _lastMicros = 0;
  static int _sequence = 0;

  static String next() {
    final observed = DateTime.now().microsecondsSinceEpoch;
    if (observed > _lastMicros) {
      _lastMicros = observed;
      _sequence = 0;
    } else {
      _sequence++;
    }
    return 'local-${_lastMicros.toRadixString(36)}-${_sequence.toRadixString(36)}';
  }
}
