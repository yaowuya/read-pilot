import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:read_pilot/services/source_runtime/network_address_policy.dart';
import 'package:read_pilot/services/source_runtime/safe_http_client_io.dart';

Future<AddressConnectionAttempt<Socket>> _connectToServer(
  HttpServer server,
) async {
  final socket = await Socket.connect(server.address, server.port);
  return AddressConnectionAttempt<Socket>(
    value: Future.value(socket),
    onCancel: socket.destroy,
  );
}

void main() {
  test('blocks private and non-canonical numeric address forms', () {
    for (final host in [
      '127.0.0.1',
      '127.1',
      '2130706433',
      '0x7f000001',
      '10.0.0.1',
      '169.254.169.254',
      '192.168.1.1',
      '::',
      '::1',
      '::ffff:127.0.0.1',
      '64:ff9b::127.0.0.1',
      'fc00::1',
      'fe80::1',
      'ff02::1',
    ]) {
      expect(NetworkAddressPolicy.isForbiddenHost(host), isTrue, reason: host);
    }
  });

  test('allows public literals and ordinary DNS names', () {
    for (final host in [
      '8.8.8.8',
      '1.1.1.1',
      '2606:4700:4700::1111',
      'fcbooks.example',
      'fd-reader.example',
      'books.example',
    ]) {
      expect(NetworkAddressPolicy.isForbiddenHost(host), isFalse, reason: host);
    }
  });

  test(
    'pinned native client rejects private DNS answers before connect',
    () async {
      for (final answers in [
        [InternetAddress('127.0.0.1')],
        [InternetAddress('8.8.8.8'), InternetAddress('10.0.0.1')],
        [InternetAddress('::ffff:127.0.0.1')],
      ]) {
        final client = PinnedHttpClient(lookup: (_) async => answers);
        addTearDown(client.close);

        await expectLater(
          client.send(
            http.Request('GET', Uri.parse('https://books.example/data')),
          ),
          throwsA(isA<UnsafeNetworkAddressException>()),
          reason: answers.join(','),
        );
      }
    },
  );

  test('validated addresses fall back without another DNS lookup', () async {
    final first = InternetAddress('2606:4700:4700::1111');
    final second = InternetAddress('1.1.1.1');
    final attempts = <InternetAddress>[];

    final result = await connectFirstAddress<String>([first, second], (
      address,
    ) async {
      attempts.add(address);
      return AddressConnectionAttempt(
        value: address == first
            ? Future.error(const SocketException('unreachable'))
            : Future.value('connected'),
        onCancel: () {},
      );
    });

    expect(attempts, [first, second]);
    expect(result.address, second);
    expect(result.value, 'connected');
  });

  test('staggered connection cancels a stalled losing attempt', () async {
    final first = InternetAddress('2606:4700:4700::1111');
    final second = InternetAddress('1.1.1.1');
    final stalled = Completer<String>();
    final attempts = <InternetAddress>[];
    var firstCancelled = false;
    var secondCancelled = false;

    final result = await connectFirstAddress<String>([first, second], (
      address,
    ) async {
      attempts.add(address);
      return AddressConnectionAttempt(
        value: address == first ? stalled.future : Future.value('connected'),
        onCancel: () {
          if (address == first) {
            firstCancelled = true;
          } else {
            secondCancelled = true;
          }
        },
      );
    }, staggerDelay: const Duration(milliseconds: 1));

    expect(attempts, [first, second]);
    expect(result.address, second);
    expect(result.value, 'connected');
    expect(firstCancelled, isTrue);
    expect(secondCancelled, isFalse);
  });

  test('pre-cancelled requests stop before DNS lookup', () async {
    final abort = Completer<void>()..complete();
    var lookups = 0;
    final client = PinnedHttpClient(
      lookup: (_) async {
        lookups++;
        return [InternetAddress('127.0.0.1')];
      },
    );
    addTearDown(client.close);

    await expectLater(
      client.send(
        http.AbortableRequest(
          'GET',
          Uri.parse('https://books.example/data'),
          abortTrigger: abort.future,
        ),
      ),
      throwsA(isA<http.RequestAbortedException>()),
    );
    expect(lookups, 0);
  });

  test('request abort cancels every black-holed address attempt', () async {
    final first = InternetAddress('2606:4700:4700::1111');
    final second = InternetAddress('1.1.1.1');
    final abort = Completer<void>();
    final bothStarted = Completer<void>();
    final started = <InternetAddress>[];
    final cancelled = <InternetAddress>{};
    final client = PinnedHttpClient(
      lookup: (_) async => [first, second],
      connectionStaggerDelay: const Duration(milliseconds: 1),
      connectionStarter: (uri, address) async {
        started.add(address);
        if (started.length == 2) bothStarted.complete();
        return AddressConnectionAttempt<Socket>(
          value: Completer<Socket>().future,
          onCancel: () => cancelled.add(address),
        );
      },
    );
    addTearDown(client.close);

    final response = client.send(
      http.AbortableRequest(
        'GET',
        Uri.parse('https://books.example/data'),
        abortTrigger: abort.future,
      ),
    );
    await bothStarted.future.timeout(const Duration(seconds: 1));
    abort.complete();

    await expectLater(response, throwsA(isA<http.RequestAbortedException>()));
    expect(started, [first, second]);
    expect(cancelled, {first, second});
  });

  test(
    'late abort cannot close a pooled connection used by another request',
    () async {
      final secondSeen = Completer<void>();
      final releaseSecond = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/second') {
          secondSeen.complete();
          await releaseSecond.future;
        }
        final body = utf8.encode(request.uri.path);
        request.response
          ..persistentConnection = true
          ..contentLength = body.length
          ..add(body);
        await request.response.close();
      });
      var starterCalls = 0;
      final client = PinnedHttpClient(
        lookup: (_) async => [InternetAddress('8.8.8.8')],
        connectionStarter: (_, _) async {
          starterCalls++;
          return _connectToServer(server);
        },
      );
      addTearDown(() async {
        if (!releaseSecond.isCompleted) releaseSecond.complete();
        client.close();
        await server.close(force: true);
      });

      final firstAbort = Completer<void>();
      final first = await client.send(
        http.AbortableRequest(
          'GET',
          Uri.parse('http://books.example/first'),
          abortTrigger: firstAbort.future,
        ),
      );
      expect(await utf8.decodeStream(first.stream), '/first');
      await Future<void>.delayed(Duration.zero);

      final secondFuture = client.send(
        http.Request('GET', Uri.parse('http://books.example/second')),
      );
      await secondSeen.future.timeout(const Duration(seconds: 1));
      expect(starterCalls, 1);
      firstAbort.complete();
      releaseSecond.complete();

      final second = await secondFuture.timeout(const Duration(seconds: 1));
      expect(await utf8.decodeStream(second.stream), '/second');
    },
  );

  test('an aborted peer cannot discard another request pin', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write('ok');
      await request.response.close();
    });
    final stalledStarted = Completer<void>();
    var lookups = 0;
    final client = PinnedHttpClient(
      lookup: (_) async {
        lookups++;
        return [InternetAddress('8.8.8.8')];
      },
      connectionStarter: (uri, _) async {
        if (uri.path == '/stalled') {
          stalledStarted.complete();
          return AddressConnectionAttempt<Socket>(
            value: Completer<Socket>().future,
            onCancel: () {},
          );
        }
        return _connectToServer(server);
      },
    );
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });

    final stalledAbort = Completer<void>();
    final stalled = client.send(
      http.AbortableRequest(
        'GET',
        Uri.parse('http://books.example/stalled'),
        abortTrigger: stalledAbort.future,
      ),
    );
    await stalledStarted.future.timeout(const Duration(seconds: 1));

    final successful = await client.send(
      http.Request('GET', Uri.parse('http://books.example/success')),
    );
    await successful.stream.drain<void>();
    stalledAbort.complete();
    await expectLater(stalled, throwsA(isA<http.RequestAbortedException>()));

    final after = await client.send(
      http.Request('GET', Uri.parse('http://books.example/after')),
    );
    await after.stream.drain<void>();
    expect(lookups, 1);
  });
}
