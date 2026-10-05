// The wire is the one call to the engine that is open now, so Stop can cut
// it. Requests go out one at a time, so through the service a call that has
// ended never finds a newer one on the wire; the rule that a finished call
// lets go only of its own hold is pinned here, on the wire itself, with real
// calls to a real loopback server.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/services.dart' show KoboldWire;

/// A call that is open to the loopback server until something closes it.
class _Call {
  _Call._(this.client);

  final http.Client client;
  final Completer<void> _over = Completer<void>();

  /// Completes when the call is over, however it ended.
  Future<void> get over => _over.future;
  bool get ended => _over.isCompleted;

  static Future<_Call> open(HttpServer server) async {
    final call = _Call._(http.Client());
    final response = await call.client.send(
      http.Request('GET', Uri.parse('http://127.0.0.1:${server.port}/')),
    );
    void end([Object? _, StackTrace? _]) {
      if (!call._over.isCompleted) call._over.complete();
    }

    response.stream.listen((_) {}, onDone: end, onError: end);
    return call;
  }
}

void main() {
  late HttpServer server;
  late KoboldWire wire;

  setUp(() async {
    // The test binding answers every request 400 unless told otherwise.
    HttpOverrides.global = null;
    wire = KoboldWire();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // Each call gets its first chunk and is then held open: only a cut ends
    // it.
    server.listen((request) async {
      final response = request.response..bufferOutput = false;
      response.write('data: open\n');
      await response.flush();
    });
    addTearDown(() => server.close(force: true));
  });

  /// Whether the call was cut within a few seconds.
  Future<bool> cutSoon(_Call call) => call.over
      .then((_) => true)
      .timeout(const Duration(seconds: 5), onTimeout: () => false);

  Future<void> aWhile() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  test('a call that ends after a newer one took the wire leaves the newer '
      'one to be cut', () async {
    final older = await _Call.open(server);
    wire.hold(older.client);
    final newer = await _Call.open(server);
    wire.hold(newer.client);

    wire.release(older.client); // the older call's late teardown
    wire.cut(); // Stop

    expect(
      await cutSoon(newer),
      isTrue,
      reason:
          'Stop did not reach the newer call: the older one let go of '
          'a hold that was not its own',
    );
    await aWhile();
    expect(older.ended, isFalse, reason: 'Stop cut a call that was not held');
    older.client.close();
  });

  test('Stop cuts the call on the wire, and a call that has ended has '
      'nothing left to cut', () async {
    final first = await _Call.open(server);
    wire.hold(first.client);
    wire.cut();
    expect(
      await cutSoon(first),
      isTrue,
      reason: 'Stop did not cut the call on the wire',
    );

    final second = await _Call.open(server);
    wire.hold(second.client);
    wire.release(second.client); // it ended on its own
    wire.cut();
    await aWhile();
    expect(second.ended, isFalse, reason: 'an ended call was still held');
    second.client.close();
  });
}
