import 'dart:async';

/// Runs independent source operations while preserving input order.
class SourceSearchScheduler {
  const SourceSearchScheduler({this.maxConcurrent = 4})
    : assert(maxConcurrent > 0);

  final int maxConcurrent;

  /// [onResult] reports each finished operation with the running count of
  /// processed inputs so callers can surface search progress while the
  /// remaining sources are still in flight. No new callback starts after an
  /// abort; a callback already running when cancellation arrives may finish,
  /// so UI callers must also guard their own late updates. Async callbacks are
  /// awaited deliberately to let a bounded downstream queue apply backpressure.
  Future<List<R>> run<T, R>(
    Iterable<T> values,
    Future<R> Function(T value) operation, {
    Future<void>? abortTrigger,
    FutureOr<void> Function(R value, int processed, int total)? onResult,
  }) async {
    final inputs = List<T>.of(values);
    if (inputs.isEmpty) return [];
    final outputs = List<R?>.filled(inputs.length, null);
    final completed = List<bool>.filled(inputs.length, false);
    var nextIndex = 0;
    var processed = 0;
    var cancelled = false;
    abortTrigger?.then(
      (_) => cancelled = true,
      onError: (_) => cancelled = true,
    );

    Future<void> worker() async {
      while (!cancelled && nextIndex < inputs.length) {
        final index = nextIndex++;
        if (cancelled) return;
        final value = await operation(inputs[index]);
        outputs[index] = value;
        completed[index] = true;
        processed++;
        if (!cancelled) {
          await onResult?.call(value, processed, inputs.length);
        }
      }
    }

    final workerCount = inputs.length < maxConcurrent
        ? inputs.length
        : maxConcurrent;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    return [
      for (var index = 0; index < outputs.length; index++)
        if (completed[index]) outputs[index] as R,
    ];
  }
}
