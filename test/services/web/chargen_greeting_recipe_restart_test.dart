// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A GREETING REWRITTEN AFTER A RESTART STILL MATCHES HOW THE CHARACTER'S
// GREETINGS WERE WRITTEN (#370, Grok review).
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
// An AI Enhance copy is a duplicate, so it inherited that stamp even when its
// greetings were Enhance's (one neutral tone, Enhance's length, no lore). The
// second case runs the real web Enhance on the same character, applies the
// proposal the way the phone does (duplicate, then the character update with
// the accepted greetings), restarts, and rewrites a greeting on the copy.
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
const _long = 'Write at least 600 words across 5-6 full paragraphs';
const _medium = 'Write at least 350 words across 3-4 paragraphs';

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

/// A remote backend, so Enhance's grounding budget asks no KoboldCpp.
class _Provider extends FakeLLMProvider {
  _Provider(this.svc) : super(activeBackend: BackendType.openRouter);
  final LLMService svc;

  @override
  LLMService get activeService => svc;

  @override
  LLMService? serviceForModel(String selectedModelId) => svc;
}

/// The app's relay as the phone reaches it: chargen routes over [db], the
/// hub on a real WebSocket. [relay] builds a fresh relay process over a
/// repository, as a restart does.
class _App {
  _App(this.db, this.storage, this.llm, this.hub, this.provider);

  final AppDatabase db;
  final StorageService storage;
  final _CreationLlm llm;
  final StreamHub hub;
  final _Provider provider;
  final events = StreamController<Map<String, dynamic>>.broadcast();

  static Future<_App> start(AppDatabase db) async {
    final storage = StorageService();
    await storage.setRootPath(
      Directory.systemTemp.createTempSync('fpai_recipe_root_').path,
    );
    final tokens = StreamController<String>.broadcast();
    final llm = _CreationLlm();
    final app = _App(
      db,
      storage,
      llm,
      StreamHub(tokens.stream, () => false),
      _Provider(llm),
    );
    addTearDown(() async {
      await app.hub.dispose();
      await tokens.close();
      app.provider.dispose();
    });
    final router = Router()
      ..get(
        '/api/ws',
        webSocketHandler(
          (WebSocketChannel c, String? _) => app.hub.register(c),
        ),
      );
    final server = await shelf_io.serve(router.call, 'localhost', 0);
    addTearDown(() => server.close(force: true));
    final ws = WebSocketChannel.connect(
      Uri.parse('ws://localhost:${server.port}/api/ws'),
    );
    await ws.ready;
    addTearDown(ws.sink.close);
    ws.stream.listen(
      (m) => app.events.add(jsonDecode(m as String) as Map<String, dynamic>),
    );
    return app;
  }

  Router relay(CharacterRepository repo) {
    final router = Router();
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

  /// Created on the phone: two tones, Long greetings, world lore.
  Future<String> create(Router r) async {
    final created = next('chargen_done');
    expect(
      await post(r, '/api/chargen/create', {
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
    return (await created)['id'].toString();
  }

  /// Rewrite alternate 1 of [id] through [r]; the prompt the model saw.
  Future<String> rewriteAlternate1(Router r, String id) async {
    final done = next('chargen_greeting_done');
    expect(
      await post(r, '/api/chargen/greeting', {'characterId': id, 'index': 1}),
      200,
    );
    await done;
    return llm.greetingPrompts.last;
  }

  /// The library read back from disk, as after a restart.
  Future<CharacterRepository> restart() async {
    final repo = CharacterRepository(db, storage);
    await repo.loadCharacters();
    return repo;
  }
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
    final app = await _App.start(db);

    final first = app.relay(CharacterRepository(db, app.storage));
    final id = await app.create(first);
    final atCreation = app.llm.greetingPrompts.last;
    expect(atCreation, contains('Tone: Romantic'), reason: 'sanity');
    expect(atCreation, contains(_lore), reason: 'sanity');

    // The app restarts: the library is read back from disk, and the relay
    // remembers nothing of the create.
    final restarted = app.relay(await app.restart());
    final rewrite = await app.rewriteAlternate1(restarted, id);
    expect(
      rewrite,
      contains('Tone: Romantic'),
      reason: 'alternate 1 keeps the second tone it was created with',
    );
    expect(
      rewrite,
      contains(_long),
      reason: 'the Long length it was created with',
    );
    expect(rewrite, contains(_lore), reason: 'the world lore it was made in');
  });

  test(
    'an Enhanced copy rewrites the way Enhance wrote its greetings',
    () async {
      SharedPreferences.setMockInitialValues({});
      // Enhance reads the chat it grows from through the open database.
      final db = await AppDatabase.instance();
      addTearDown(AppDatabase.closeAndReset);
      final app = await _App.start(db);
      final repo = CharacterRepository(db, app.storage);
      final relay = app.relay(repo);
      final id = await app.create(relay);

      // The real web Enhance, greetings only (a chat with nothing in it).
      final enhanced = app.next('chargen_enhance_done');
      expect(
        await app.post(relay, '/api/chargen/enhance', {
          'characterId': id,
          'sessionId': 'a-chat-with-no-lines',
          'fields': {
            'description': false,
            'personality': false,
            'exampleDialogue': false,
            'greetings': true,
          },
        }),
        200,
      );
      final proposal = (await enhanced)['proposal'] as Map<String, dynamic>;

      // Applied as the phone applies it: a duplicate, then the character
      // update with the accepted greetings (buildApplyBody's greetings part).
      final original = repo.characters.firstWhere((c) => c.dbId == id);
      final copy = (await repo.duplicateCharacter(
        original,
        newNameOverride: 'Aria Vale (Enhanced)',
      ))!;
      final characters = CharacterFacade(db, app.storage, null, null, repo);
      expect(
        await characters.update(copy.dbId!, {
          'firstMessage': proposal['firstMessage'],
          'alternateGreetings': proposal['alternateGreetings'],
          if (proposal.containsKey('greetingRecipe'))
            'greetingRecipe': proposal['greetingRecipe'],
        }),
        isTrue,
      );

      final restarted = app.relay(await app.restart());
      final onCopy = await app.rewriteAlternate1(restarted, copy.dbId!);
      expect(
        onCopy,
        isNot(contains('Tone: Romantic')),
        reason: "the copy's greetings were written in Enhance's neutral tone",
      );
      expect(onCopy, contains(_medium), reason: "Enhance's length, not Long");
      expect(onCopy, isNot(contains(_lore)), reason: 'Enhance used no lore');

      final onOriginal = await app.rewriteAlternate1(restarted, id);
      expect(
        onOriginal,
        contains('Tone: Romantic'),
        reason: 'the original keeps its own',
      );
      expect(onOriginal, contains(_lore));
    },
  );
}
