import 'dart:async';

/// Enforces one book source's `concurrentRate` declaration.
///
/// Legado implements this as `ConcurrentRateLimiter` with the same three states:
/// `"0"` or blank means unlimited, `"3/1000"` allows three requests per second,
/// and a bare number such as `"500"` means one request per 500 ms. The window
/// restarts once [interval] has elapsed since the window opened, so a source
/// that declares `3/1000` admits three quick requests and then makes the fourth
/// wait for the remainder of the second.
///
/// A limiter instance belongs to exactly one source origin: the budget is per
/// source, not global, because each source talks to its own host.
class ConcurrentRateLimiter {
  ConcurrentRateLimiter({required this.accessLimit, required this.interval});

  /// Parses legado's `concurrentRate` string.
  ///
  /// Returns `null` when the value is absent, unparseable or explicitly `0`,
  /// which all mean "no limit" in legado as well.
  static ConcurrentRateLimiter? parse(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    final parts = text.split('/');
    final limit = int.tryParse(parts.first.trim());
    if (limit == null || limit <= 0) return null;
    if (parts.length == 1) {
      // A single number is legado's "1 request per N ms" shorthand.
      return ConcurrentRateLimiter(accessLimit: 1, interval: limit);
    }
    final interval = int.tryParse(parts[1].trim());
    if (interval == null || interval <= 0) return null;
    return ConcurrentRateLimiter(accessLimit: limit, interval: interval);
  }

  /// Requests admitted per [interval] window.
  final int accessLimit;

  /// Window length in milliseconds.
  final int interval;

  int _windowStart = 0;
  int _frequency = 0;
  Future<void> _tail = Future<void>.value();

  /// Waits until one more request may start, then admits it.
  ///
  /// Calls are serialised through a tail future so concurrent callers cannot
  /// both observe a free slot; that mirrors legado running the check inside a
  /// `synchronized` block.
  Future<void> acquire() {
    final next = _tail.then((_) => _waitForSlot());
    // Errors never propagate here, but keep the chain alive regardless.
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _waitForSlot() async {
    while (true) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= _windowStart + interval) {
        _windowStart = now;
        _frequency = 0;
      }
      if (_frequency < accessLimit) {
        _frequency++;
        return;
      }
      final wait = _windowStart + interval - now;
      await Future<void>.delayed(Duration(milliseconds: wait <= 0 ? 1 : wait));
    }
  }
}

/// Remembers one [ConcurrentRateLimiter] per book source.
///
/// A search over a thousand sources issues thousands of requests; the limiters
/// have to outlive a single request, so they live here rather than inside the
/// engine. Keyed by the source's declared URL, exactly like Legado's
/// `ConcurrentRateLimiter.getConcurrentRecord(source.bookSourceUrl)`.
class ConcurrentRateLimiters {
  final _limiters = <String, ConcurrentRateLimiter>{};
  final _declared = <String, String>{};

  /// Awaits the rate budget for [sourceKey] declared by [sourceConcurrentRate].
  ///
  /// The declaration is re-read on every call so editing a source's
  /// `concurrentRate` takes effect without restarting the app; when it changes,
  /// the previous window is dropped rather than carried over.
  Future<void> acquire(String sourceKey, String? sourceConcurrentRate) async {
    final raw = (sourceConcurrentRate ?? '').trim();
    if (_declared[sourceKey] != raw) {
      _declared[sourceKey] = raw;
      final limiter = ConcurrentRateLimiter.parse(raw);
      if (limiter == null) {
        _limiters.remove(sourceKey);
      } else {
        _limiters[sourceKey] = limiter;
      }
    }
    await _limiters[sourceKey]?.acquire();
  }

  /// Drops every remembered window, e.g. when the source list is reloaded.
  void clear() {
    _limiters.clear();
    _declared.clear();
  }
}
