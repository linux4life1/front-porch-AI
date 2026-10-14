// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AI creator relay, as the phone meets it: the real router in process,
// the hub on a real WebSocket, characters in a real repository and
// database, the pending profile in a real file. Only the model is scripted.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/chargen_facade.dart';
import 'package:front_porch_ai/services/web/routes/chargen_routes.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

import '../../../golden/support/fakes.dart';
import '../../chargen/support/marker_chargen_llm.dart';

/// [MarkerChargenLlm], except that a prompt containing [streamMarker]
/// is answered in [chunks] a little apart (so throttled progress shows
/// each), and with [holdNext] waits after the first chunk until
/// abortGeneration lets it go, as a closed connection would.
class StreamingChargenLlm extends MarkerChargenLlm {
  StreamingChargenLlm({super.toolAnswers, super.textAnswers});

  String streamMarker = '';
  List<String> chunks = const [];
  bool holdNext = false;
  Completer<void>? _held;

  @override
  void abortGeneration() {
    final held = _held;
    if (held != null && !held.isCompleted) held.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (streamMarker.isEmpty || !params.prompt.contains(streamMarker)) {
      yield* super.generateStream(params);
      return;
    }
    prompts.add(params.prompt);
    for (var i = 0; i < chunks.length; i++) {
      yield chunks[i];
      if (i == 0 && holdNext) {
        holdNext = false;
        final held = _held = Completer<void>();
        await held.future;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 160));
      }
    }
  }
}

class _Provider extends FakeLLMProvider {
  _Provider(this.svc);
  final LLMService svc;

  @override
  LLMService get activeService => svc;
}

/// One relay for one test; everything is torn down with the test.
class ChargenRelay {
  ChargenRelay._(
    this.router,
    this.characters,
    this.storage,
    this._provider,
    this._hub,
  );

  final Router router;
  final CharacterFacade characters;
  final StorageService storage;
  final _Provider _provider;
  final StreamHub _hub;

  /// Every hub event, in order.
  final List<Map<String, dynamic>> events = [];
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  static Future<ChargenRelay> start(LLMService llm) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final storage = StorageService();
    await storage.setRootPath(
      Directory.systemTemp.createTempSync('fpai_chargen_relay_').path,
    );
    final repo = CharacterRepository(db, storage);
    final characters = CharacterFacade(db, storage, null, null, repo);
    final tokens = StreamController<String>.broadcast();
    final hub = StreamHub(tokens.stream, () => false);
    final provider = _Provider(llm);
    addTearDown(() async {
      await hub.dispose();
      await tokens.close();
      provider.dispose();
    });
    final router = Router()
      ..get(
        '/api/ws',
        webSocketHandler((WebSocketChannel ch, String? _) => hub.register(ch)),
      );
    WebChargenRoutes(
      ChargenFacade(provider, characters, hub, null, storage),
      router,
    );
    final relay = ChargenRelay._(router, characters, storage, provider, hub);
    final server = await shelf_io.serve(router.call, 'localhost', 0);
    addTearDown(() => server.close(force: true));
    final ws = WebSocketChannel.connect(
      Uri.parse('ws://localhost:${server.port}/api/ws'),
    );
    await ws.ready;
    ws.stream.listen((m) {
      final e = jsonDecode(m as String) as Map<String, dynamic>;
      relay.events.add(e);
      relay._events.add(e);
    });
    addTearDown(ws.sink.close);
    return relay;
  }

  /// A second relay over the same library and hub, as after a restart: a
  /// fresh facade that has seen nothing and must read what it needs.
  Router restarted() {
    final r = Router();
    WebChargenRoutes(
      ChargenFacade(_provider, characters, _hub, null, storage),
      r,
    );
    return r;
  }

  /// Requests go through the router in process (dart:io's client is mocked
  /// under the test binding); the hub is a real WebSocket.
  Future<(int, Map<String, dynamic>)> post(String path, Object body) =>
      _send(router, 'POST', path, jsonEncode(body));

  Future<(int, Map<String, dynamic>)> get(String path, {Router? on}) =>
      _send(on ?? router, 'GET', path, null);

  Future<(int, Map<String, dynamic>)> _send(
    Router r,
    String method,
    String path,
    String? body,
  ) async {
    final res = await r.call(
      shelf.Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: body,
      ),
    );
    final text = await res.readAsString();
    return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
  }

  /// The next [event] (from now), or a timeout failure.
  Future<Map<String, dynamic>> next(String event, {int seconds = 20}) => _events
      .stream
      .firstWhere((e) => e['event'] == event)
      .timeout(
        Duration(seconds: seconds),
        onTimeout: () => fail('no $event; the hub said: ${_said()}'),
      );

  /// What the hub sent so far, for a failure to say.
  String _said() => [
    for (final e in events)
      '${e['event']}${e['error'] != null ? ' (${e['error']})' : ''}',
  ].join(', ');

  /// Every [event] until [until] arrives, [until] last.
  Future<List<Map<String, dynamic>>> collect(String event, String until) {
    final seen = <Map<String, dynamic>>[];
    final done = Completer<List<Map<String, dynamic>>>();
    late final StreamSubscription<Map<String, dynamic>> sub;
    sub = _events.stream.listen((e) {
      if (e['event'] == event) seen.add(e);
      if (e['event'] == until) {
        seen.add(e);
        sub.cancel();
        done.complete(seen);
      }
    });
    return done.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('no $until; the hub said: ${_said()}'),
    );
  }
}
