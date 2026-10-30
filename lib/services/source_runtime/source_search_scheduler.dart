/// Runs independent source operations while preserving input order.
class SourceSearchScheduler {
  const SourceSearchScheduler({this.maxConcurrent = 4})
    : assert(maxConcurrent > 0);

  final int maxConcurrent;

  Future<List<R>> run<T, R>(
    Iterable<T> values,
    Future<R> Function(T value) operation, {
    Future<void>? abortTrigger,
  }) async {
    final inputs = List<T>.of(values);
    if (inputs.isEmpty) return [];
    final outputs = List<R?>.filled(inputs.length, null);
    final completed = List<bool>.filled(inputs.length, false);
    var nextIndex = 0;
    var cancelled = false;
    abortTrigger?.then(
      (_) => cancelled = true,
      onError: (_) => cancelled = true,
    );

    Future<void> worker() async {
      while (!cancelled && nextIndex < inputs.length) {
        final index = nextIndex++;
        if (cancelled) return;
        outputs[index] = await operation(inputs[index]);
        completed[index] = true;
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
