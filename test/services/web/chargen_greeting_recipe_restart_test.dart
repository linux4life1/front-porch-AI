// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A GREETING REWRITTEN AFTER A RESTART STILL MATCHES HOW THE CHARACTER WAS
// CREATED (#370, Grok review).
//
// The relay kept the creation's greeting recipe (tones, length, world lore,
// interview) only in memory, so a phone that reloaded ?greetings=<id>, an app
// restart, or eight later creates left a rewrite on the plain default:
// Neutral, Medium, no lore. The recipe is now stamped on the card beside the
// narrative voice. Here a character is created through the real create route,
// the app "restarts" (a fresh repository reads the card back from its PNG, a
// fresh relay has nothing in memory), and alternate 1 is rewritten: the model
// must see the creation's second tone, its Long length and its world lore.
//
// The model is the scripted LLMService the chargen tests use, answering each
// stage by what its prompt asks for.

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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/facade/chargen_facade.dart';
import 'package:front_porch_ai/services/web/routes/chargen_routes.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

import '../../golden/support/fakes.dart';

const _lore = 'The tide-bell of Saltmere rings once at every dawn.';

/// Answers each chargen stage by what its prompt asks for.
class _CreationLlm extends LLMService {
  final List<String> greetingPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('Write an opening roleplay message')) {
      greetingPrompts.add(p);
      yield '*Aria Vale rings the tide-bell.* "Opening ${greetingPrompts.length}."';
    } else if (p.contains('Seed Porch Life identity')) {
      yield '{"worn": ["oilskin coat"], "carrying": ["brass spyglass"]}';
    } else if (p.contains('completely different meeting scenarios')) {
      yield '{"scenarios": ["a storm on the jetty"]}';
    } else {
      yield jsonEncode({
        'description': '{{char}} keeps the lighthouse on a wind-scoured cape.',
        'personality': 'Patient, dry-humored, never leaves a lamp unlit.',
        'scenario': '{{user}} climbs the tower stairs at dusk.',
        'tags': ['lighthouse'],
      });
    }
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
          return Directory.systemTemp.createTempSync('fpai_recipe_').path;
        }
        return null;
      });

  test('a rewrite after a restart keeps the tone, length and lore', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final storage = StorageService();
    await storage.setRootPath(
      Directory.systemTemp.createTempSync('fpai_recipe_root_').path,
    );
    final tokens = StreamController<String>.broadcast();
    final hub = StreamHub(tokens.stream, () => false);
    final llm = _CreationLlm();
    final provider = _Provider(llm);
    addTearDown(() async {
      await hub.dispose();
      await tokens.close();
      provider.dispose();
    });

    // One relay process: routes, and the hub on a real WebSocket.
    Router relay(CharacterRepository repo) {
      final router = Router()
        ..get(
          '/api/ws',
          webSocketHandler((WebSocketChannel c, String? _) => hub.register(c)),
        );
      WebChargenRoutes(
        ChargenFacade(
          provider,
          CharacterFacade(db, storage, null, null, repo),
          hub,
        ),
        router,
      );
      return router;
    }

    final first = relay(CharacterRepository(db, storage));
    final server = await shelf_io.serve(first.call, 'localhost', 0);
    addTearDown(() => server.close(force: true));
    final ws = WebSocketChannel.connect(
      Uri.parse('ws://localhost:${server.port}/api/ws'),
    );
    await ws.ready;
    addTearDown(ws.sink.close);
    final events = StreamController<Map<String, dynamic>>.broadcast();
    ws.stream.listen(
      (m) => events.add(jsonDecode(m as String) as Map<String, dynamic>),
    );
    Future<Map<String, dynamic>> next(String event) => events.stream
        .firstWhere((e) => e['event'] == event)
        .timeout(const Duration(seconds: 20));

    Future<int> post(Router r, String path, Object body) async {
      final res = await r.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost$path'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        ),
      );
      return res.statusCode;
    }

    // Created on the phone: two tones, Long greetings, world lore.
    final created = next('chargen_done');
    expect(
      await post(first, '/api/chargen/create', {
        'name': 'Aria Vale',
        'mode': 'quick',
        'concept': 'A lighthouse keeper who collects shipwreck tales.',
        'greetingLength': 'Long (4-6 paragraphs)',
        'greetingTones': ['Neutral', 'Romantic'],
        'altGreetingCount': 1,
        'generateLorebook': false,
        'worldLore': _lore,
      }),
      200,
    );
    final id = (await created)['id'].toString();
    final atCreation = llm.greetingPrompts.last;
    expect(atCreation, contains('Tone: Romantic'), reason: 'sanity');
    expect(atCreation, contains(_lore), reason: 'sanity');

    // The app restarts: the library is read back from disk, and the relay
    // remembers nothing of the create.
    final reloaded = CharacterRepository(db, storage);
    await reloaded.loadCharacters();
    final restarted = relay(reloaded);

    final done = next('chargen_greeting_done');
    expect(
      await post(restarted, '/api/chargen/greeting', {
        'characterId': id,
        'index': 1,
      }),
      200,
    );
    await done;
    final rewrite = llm.greetingPrompts.last;
    expect(
      rewrite,
      contains('Tone: Romantic'),
      reason: 'alternate 1 keeps the second tone it was created with',
    );
    expect(
      rewrite,
      contains('Write at least 600 words across 5-6 full paragraphs'),
      reason: 'the Long length it was created with',
    );
    expect(rewrite, contains(_lore), reason: 'the world lore it was made in');
  });
}
