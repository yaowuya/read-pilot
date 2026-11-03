import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'network_address_policy.dart';

typedef HostLookup = Future<List<InternetAddress>> Function(String host);

Future<List<InternetAddress>> _defaultLookup(String host) =>
    InternetAddress.lookup(host, type: InternetAddressType.any);

http.Client createSafeHttpClient() => PinnedHttpClient();

final class AddressConnectionAttempt<T> {
  AddressConnectionAttempt({
    required this.value,
    required void Function() onCancel,
  }) : _onCancel = onCancel {
    value.ignore();
  }

  final Future<T> value;
  final void Function() _onCancel;
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }
}

Future<({InternetAddress address, T value})> connectFirstAddress<T>(
  List<InternetAddress> addresses,
  Future<AddressConnectionAttempt<T>> Function(InternetAddress address) start, {
  Duration staggerDelay = const Duration(milliseconds: 250),
  Future<void>? abortTrigger,
  Object abortError = const SocketException('Connection cancelled.'),
}) {
  if (addresses.isEmpty) {
    return Future.error(
      const SocketException('No resolved address was available.'),
    );
  }

  final result = Completer<({InternetAddress address, T value})>();
  final attempts = <AddressConnectionAttempt<T>>[];
  Timer? nextTimer;
  var nextIndex = 0;
  var outstanding = 0;
  Object? lastError;
  StackTrace? lastStack;

  void cancelQuietly(AddressConnectionAttempt<T> attempt) {
    try {
      attempt.cancel();
    } catch (_) {}
  }

  void abort() {
    if (result.isCompleted) return;
    nextTimer?.cancel();
    nextTimer = null;
    for (final attempt in attempts) {
      cancelQuietly(attempt);
    }
    result.completeError(abortError, StackTrace.current);
  }

  abortTrigger?.then<void>((_) => abort(), onError: (_, _) => abort());

  void completeFailureIfDone() {
    if (result.isCompleted || nextIndex < addresses.length || outstanding > 0) {
      return;
    }
    final error = lastError;
    if (error != null) {
      result.completeError(error, lastStack!);
    } else {
      result.completeError(
        const SocketException('No resolved address was available.'),
      );
    }
  }

  late void Function() launchNext;

  void fail(Object error, StackTrace stack) {
    lastError = error;
    lastStack = stack;
    if (result.isCompleted) return;
    if (nextIndex < addresses.length) {
      nextTimer?.cancel();
      nextTimer = null;
      launchNext();
    } else {
      completeFailureIfDone();
    }
  }

  void scheduleNext() {
    if (result.isCompleted || nextIndex >= addresses.length) return;
    nextTimer = Timer(staggerDelay, () {
      nextTimer = null;
      launchNext();
    });
  }

  launchNext = () {
    if (result.isCompleted || nextIndex >= addresses.length) return;
    nextTimer?.cancel();
    nextTimer = null;
    final address = addresses[nextIndex++];
    outstanding++;

    Future.sync(() => start(address)).then(
      (attempt) {
        attempts.add(attempt);
        if (result.isCompleted) {
          outstanding--;
          cancelQuietly(attempt);
          return;
        }
        attempt.value.then(
          (value) {
            outstanding--;
            if (result.isCompleted) {
              cancelQuietly(attempt);
              return;
            }
            nextTimer?.cancel();
            nextTimer = null;
            result.complete((address: address, value: value));
            for (final loser in attempts) {
              if (!identical(loser, attempt)) cancelQuietly(loser);
            }
          },
          onError: (Object error, StackTrace stack) {
            outstanding--;
            cancelQuietly(attempt);
            fail(error, stack);
          },
        );
      },
      onError: (Object error, StackTrace stack) {
        outstanding--;
        fail(error, stack);
      },
    );

    scheduleNext();
  };

  launchNext();
  return result.future;
}

typedef SocketConnectionStarter =
    Future<AddressConnectionAttempt<Socket>> Function(
      Uri url,
      InternetAddress address,
    );

Future<AddressConnectionAttempt<Socket>> _defaultConnectionStarter(
  Uri url,
  InternetAddress address,
) async {
  final task = await Socket.startConnect(address, url.port);
  Socket? rawSocket;
  Socket? connectedSocket;
  final value = () async {
    try {
      rawSocket = await task.socket;
      connectedSocket = url.scheme == 'https'
          ? await SecureSocket.secure(rawSocket!, host: url.host)
          : rawSocket;
      return connectedSocket!;
    } catch (_) {
      connectedSocket?.destroy();
      if (!identical(rawSocket, connectedSocket)) rawSocket?.destroy();
      rethrow;
    }
  }();
  return AddressConnectionAttempt<Socket>(
    value: value,
    onCancel: () {
      task.cancel();
      connectedSocket?.destroy();
      if (!identical(rawSocket, connectedSocket)) rawSocket?.destroy();
    },
  );
}

final class _ResolvedAddressState {
  _ResolvedAddressState(List<InternetAddress> candidates)
    : candidates = List.unmodifiable(candidates);

  final List<InternetAddress> candidates;
  InternetAddress? pinned;
  int generation = 0;
}

final class _ConnectionContext {
  const _ConnectionContext({
    required this.key,
    required this.state,
    required this.abortTrigger,
  });

  final String key;
  final _ResolvedAddressState state;
  final Future<void> abortTrigger;
}

final _connectionContextZoneKey = Object();

/// Resolves each destination once, rejects unsafe answers, and pins a working IP.
class PinnedHttpClient extends http.BaseClient {
  PinnedHttpClient({
    HostLookup lookup = _defaultLookup,
    SocketConnectionStarter connectionStarter = _defaultConnectionStarter,
    Duration connectionStaggerDelay = const Duration(milliseconds: 250),
  }) : _lookup = lookup,
       _connectionStarter = connectionStarter,
       _connectionStaggerDelay = connectionStaggerDelay {
    _http.findProxy = (_) => 'DIRECT';
    _http.connectionTimeout = const Duration(seconds: 15);
    _http.connectionFactory = (url, proxyHost, proxyPort) {
      if (proxyHost != null || proxyPort != null) {
        return Future.error(
          const UnsafeNetworkAddressException('书源网络请求不允许自定义代理。'),
        );
      }
      final key = _key(url);
      final context =
          Zone.current[_connectionContextZoneKey] as _ConnectionContext?;
      if (context == null || context.key != key) {
        return Future.error(
          const UnsafeNetworkAddressException('书源地址尚未通过安全解析。'),
        );
      }
      final state = context.state;
      final addresses = state.pinned == null
          ? state.candidates
          : [state.pinned!];
      return _connectPinned(
        url,
        addresses,
        (address) {
          final current = _states[key];
          if (current == null || identical(current, state)) {
            state.pinned = address;
            state.generation++;
            _states[key] = state;
          }
        },
        abortTrigger: context.abortTrigger,
        connectionStarter: _connectionStarter,
        staggerDelay: _connectionStaggerDelay,
      );
    };
    _delegate = IOClient(_http);
  }

  final HostLookup _lookup;
  final SocketConnectionStarter _connectionStarter;
  final Duration _connectionStaggerDelay;
  final HttpClient _http = HttpClient();
  late final IOClient _delegate;
  final _states = <String, _ResolvedAddressState>{};

  static Future<ConnectionTask<Socket>> _connectPinned(
    Uri url,
    List<InternetAddress> addresses,
    void Function(InternetAddress address) onConnected, {
    required SocketConnectionStarter connectionStarter,
    required Duration staggerDelay,
    Future<void>? abortTrigger,
  }) async {
    final connectionAbort = Completer<void>();
    var cancelled = false;
    var handedOff = false;

    void cancel() {
      if (cancelled || handedOff) return;
      cancelled = true;
      if (!connectionAbort.isCompleted) connectionAbort.complete();
    }

    abortTrigger?.then<void>((_) => cancel(), onError: (_, _) => cancel());
    final socket =
        connectFirstAddress<Socket>(
          addresses,
          (address) async {
            if (cancelled) throw http.RequestAbortedException(url);
            final attempt = await connectionStarter(url, address);
            if (cancelled) {
              attempt.cancel();
              throw http.RequestAbortedException(url);
            }
            return attempt;
          },
          staggerDelay: staggerDelay,
          abortTrigger: connectionAbort.future,
          abortError: http.RequestAbortedException(url),
        ).then((result) {
          if (cancelled) {
            result.value.destroy();
            throw http.RequestAbortedException(url);
          }
          handedOff = true;
          onConnected(result.address);
          return result.value;
        });
    return ConnectionTask.fromSocket<Socket>(socket, cancel);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    final key = _key(uri);
    final connectionAbort = Completer<void>();
    _ResolvedAddressState? state;
    var generation = -1;

    void abortConnection() {
      if (!connectionAbort.isCompleted) connectionAbort.complete();
    }

    Future<T> abortResult<T>() => connectionAbort.future.then<T>(
      (_) => throw http.RequestAbortedException(uri),
    );

    try {
      if (request case http.Abortable(:final abortTrigger?)) {
        abortTrigger.then<void>(
          (_) => abortConnection(),
          onError: (_, _) => abortConnection(),
        );
        await Future.any<void>([
          Future<void>.delayed(Duration.zero),
          abortResult<void>(),
        ]);
      }

      final existing = _states[key];
      if (existing != null) {
        state = existing;
      } else {
        final literal = InternetAddress.tryParse(uri.host);
        final addresses = literal == null
            ? await Future.any<List<InternetAddress>>([
                _lookup(uri.host),
                abortResult<List<InternetAddress>>(),
              ])
            : [literal];
        if (addresses.isEmpty ||
            addresses.any(
              (address) =>
                  NetworkAddressPolicy.isForbiddenAddress(address.rawAddress),
            )) {
          throw UnsafeNetworkAddressException('书源地址 ${uri.host} 解析到了本机或私有网络。');
        }
        final candidate = _ResolvedAddressState(addresses);
        state = _states.putIfAbsent(key, () => candidate);
      }
      generation = state.generation;
      if (connectionAbort.isCompleted) {
        throw http.RequestAbortedException(uri);
      }
      return await runZoned(
        () => _delegate.send(request),
        zoneValues: {
          _connectionContextZoneKey: _ConnectionContext(
            key: key,
            state: state,
            abortTrigger: connectionAbort.future,
          ),
        },
      );
    } on http.RequestAbortedException {
      rethrow;
    } catch (_) {
      final failedState = state;
      if (failedState != null &&
          identical(_states[key], failedState) &&
          failedState.generation == generation) {
        _states.remove(key);
      }
      rethrow;
    }
  }

  @override
  void close() {
    _delegate.close();
    _http.close(force: true);
  }

  static String _key(Uri uri) => '${uri.host.toLowerCase()}:${uri.port}';
}
