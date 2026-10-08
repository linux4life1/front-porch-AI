// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// THE PHONE'S GREETINGS STEP (#370), through the real relay.
//
// The routes run in process on the real router, the hub on a real WebSocket,
// the character in a real repository and database; only the model is the
// scripted LLMService the chargen tests use. A steered rewrite of the first
// message is saved to the card with {{char}} and the steer reaches the model
// as a direction; while one greeting is written a second waits (409); Stop
// saves nothing; Delete takes an alternate and its starting state together;
// Add writes new alternates up to 5 and then refuses; the first message
// cannot be deleted.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/chargen_facade.dart';
import 'package:front_porch_ai/services/web/routes/chargen_routes.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

import '../../golden/support/fakes.dart';

const _name = 'Aria Vale';

/// Greeting prompts get [next]; one can be held after its first words, and
/// abortGeneration (what Stop sends) lets it go, as a closed connection would.
class _GreetingLlm extends LLMService {
  final List<String> prompts = [];
  String next = '*$_name waves from the jetty.*';
  bool holdNext = false;
  Completer<void>? _held;

  @override
  void abortGeneration() {
    final held = _held;
    if (held != null && !held.isCompleted) held.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    prompts.add(params.prompt);
    final text = next;
    if (holdNext) {
      holdNext = false;
      yield text.substring(0, 12);
      final held = _held = Completer<void>();
      await held.future;
      yield text.substring(12);
      return;
    }
    yield text;
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'scripted-test';
}

class _Provider extends FakeLLMProvider {
  _Provider(this.svc);
  final LLMService svc;

  @override
  LLMService get activeService => svc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_greet_').path;
        }
        return null;
      });

  test('rewrite, steer, wait, stop, delete, add to the cap', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final storage = StorageService();
    await storage.setRootPath(
      Directory.systemTemp.createTempSync('fpai_greet_root_').path,
    );
    final repo = CharacterRepository(db, storage);
    final characters = CharacterFacade(db, storage, null, null, repo);
    final tokens = StreamController<String>.broadcast();
    final hub = StreamHub(tokens.stream, () => false);
    final llm = _GreetingLlm();
    final provider = _Provider(llm);
    final facade = ChargenFacade(provider, characters, hub);
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
    WebChargenRoutes(facade, router);
    final server = await shelf_io.serve(router.call, 'localhost', 0);
    addTearDown(() => server.close(force: true));

    final ws = WebSocketChannel.connect(
      Uri.parse('ws://localhost:${server.port}/api/ws'),
    );
    await ws.ready;
    final events = StreamController<Map<String, dynamic>>.broadcast();
    ws.stream.listen(
      (m) => events.add(jsonDecode(m as String) as Map<String, dynamic>),
    );
    addTearDown(ws.sink.close);

    // Requests go through the real router in process (dart:io's client is
    // mocked under the test binding); the hub is a real WebSocket.
    Future<(int, Map<String, dynamic>)> post(String path, Object body) async {
      final res = await router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost$path'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        ),
      );
      final text = await res.readAsString();
      return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
    }

    Future<Map<String, dynamic>> next(String event) => events.stream
        .firstWhere((e) => e['event'] == event)
        .timeout(const Duration(seconds: 10));

    // A saved character with two alternates; the second has a start state.
    final card = CharacterCard(
      name: _name,
      description: '{{char}} keeps the lighthouse.',
      personality: 'Patient and dry.',
      scenario: '{{user}} climbs the tower stairs at dusk.',
      firstMessage: '*{{char}} trims the wick.* "You came."',
      alternateGreetings: const ['ALT ONE', 'ALT TWO'],
      frontPorchExtensions: FrontPorchExtensions(
        greetingSeeds: const [
          null,
          GreetingRealismSeed(characterEmotion: 'wistful'),
        ],
      ),
    );
    stampNarrativeVoice(
      card,
      voice: const NarrativeVoice(perspective: NarrativePerspective.third),
      sex: 'female',
    );
    final id = (await characters.persistNewCard(card))!['id'].toString();
    CharacterCard saved() => characters.cardByDbId(id)!;

    Future<Object?> writing() async {
      final res = await router.call(
        shelf.Request(
          'GET',
          Uri.parse(
            'http://localhost/api/chargen/greeting/status?characterId=$id',
          ),
        ),
      );
      return (jsonDecode(await res.readAsString()) as Map)['writing'];
    }

    // ── A steered rewrite of the first message is saved ──
    llm.next = '*$_name coils a rope on the harbor wall at dawn.* "Early."';
    final done = next('chargen_greeting_done');
    var (code, body) = await post('/api/chargen/greeting', {
      'characterId': id,
      'index': 0,
      'direction': 'start at the harbor at dawn',
    });
    expect(code, 200, reason: '$body');
    final doneFirst = await done;
    expect(doneFirst['index'], 0);
    expect(
      doneFirst['text'],
      '*{{char}} coils a rope on the harbor wall at dawn.* "Early."',
    );
    expect(saved().firstMessage, doneFirst['text']);
    expect(llm.prompts.last, contains('== DIRECTION FROM THE AUTHOR =='));
    expect(llm.prompts.last, contains('start at the harbor at dawn'));
    expect(llm.prompts.last, contains('Third person present tense'));
    expect(saved().alternateGreetings, ['ALT ONE', 'ALT TWO']);

    // ── While one is written, a second waits; Stop saves nothing ──
    llm
      ..holdNext = true
      ..next = '*This text must never be saved anywhere at all.*';
    final progress = next('chargen_greeting_progress');
    (code, body) = await post('/api/chargen/greeting', {
      'characterId': id,
      'index': 1,
    });
    expect(code, 200);
    expect((await progress)['index'], 1);
    expect(await writing(), 1, reason: 'a phone that slept can ask');
    (code, body) = await post('/api/chargen/greeting', {
      'characterId': id,
      'index': 2,
    });
    expect(code, 409, reason: 'one greeting at a time');
    (code, body) = await post('/api/chargen/greeting/delete', {
      'characterId': id,
      'index': 2,
    });
    expect(code, 409, reason: 'no delete while one is written');
    final stopped = next('chargen_greeting_stopped');
    (code, body) = await post('/api/chargen/greeting/stop', {
      'characterId': id,
    });
    expect(body['stopped'], isTrue);
    expect((await stopped)['index'], 1);
    expect(await writing(), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(saved().alternateGreetings, ['ALT ONE', 'ALT TWO']);

    // ── Delete takes an alternate and its starting state together ──
    (code, body) = await post('/api/chargen/greeting/delete', {
      'characterId': id,
      'index': 1,
    });
    expect(code, 200, reason: '$body');
    expect(body['alternateGreetings'], ['ALT TWO']);
    expect(saved().alternateGreetings, ['ALT TWO']);
    expect(
      saved().frontPorchExtensions!.greetingSeeds.map(
        (s) => s?.characterEmotion,
      ),
      ['wistful'],
      reason: 'the start state moves with its greeting',
    );
    (code, body) = await post('/api/chargen/greeting/delete', {
      'characterId': id,
      'index': 0,
    });
    expect(code, 400, reason: 'the first message cannot be deleted');

    // ── Add writes new alternates up to 5, then refuses ──
    for (var n = 2; n <= kMaxAlternateGreetings; n++) {
      llm.next = '*$_name lights the lamp for opening $n.*';
      final added = next('chargen_greeting_done');
      (code, body) = await post('/api/chargen/greeting/add', {
        'characterId': id,
      });
      expect(code, 200, reason: '$body');
      expect(body['index'], n);
      expect((await added)['alternateGreetings'], hasLength(n));
    }
    expect(llm.prompts.last, contains('have ALREADY been written'));
    expect(
      saved().alternateGreetings.last,
      '*{{char}} lights the lamp for opening 5.*',
    );
    expect(
      saved().frontPorchExtensions!.greetingSeeds.first?.characterEmotion,
      'wistful',
    );
    (code, body) = await post('/api/chargen/greeting/add', {'characterId': id});
    expect(code, 400);
    expect(body['error'], contains('5 alternate greetings'));
  });
}
