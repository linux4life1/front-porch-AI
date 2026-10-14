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
import 'support/chargen_relay.dart';

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

  // ── THE PHONE'S PROFILE STEP: create pauses after the profile ──────────
  // A create asked to pause writes the profile and the facts, then waits:
  // nothing is saved until Next. The pause is on disk, so a relay that
  // restarts still has it. Next writes the rest from the texts and facts as
  // the phone left them, saves, and the pause is gone.
  test(
    'create pauses at the profile; a restart keeps it; Next saves',
    () async {
      final llm = StreamingChargenLlm(
        toolAnswers: {
          kIdentityFactsToolName: {
            'occupation': 'lighthouse keeper',
            'hours': '18:00-06:00',
            'current_task': 'Trim the wick before the storm.',
            'ambitions': ['keep the light one more winter'],
            'likes': ['salt wind'],
            'dislikes': ['fog'],
            'creator_notes': 'Aria Vale keeps the light.',
          },
        },
      );
      final relay = await ChargenRelay.start(llm);
      final profiled = relay.next('chargen_profile', seconds: 60);
      var (code, body) = await relay.post('/api/chargen/create', {
        'name': _name,
        'mode': 'guided',
        'concept': 'A lighthouse keeper on a wet rock.',
        'pauseAtProfile': true,
      });
      expect(code, 200, reason: '$body');
      expect(body, {'status': 'started', 'phase': 'profile'});
      final profile = await profiled;
      expect(profile['description'], contains('ZZSENTINELZZ'));
      expect(profile['mode'], 'guided');
      expect(profile['transcriptQuestions'], greaterThan(0));
      expect((profile['facts'] as Map)['occupation'], 'lighthouse keeper');

      // Nothing downstream ran and nothing was saved.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(relay.events.where((e) => e['event'] == 'chargen_done'), isEmpty);
      expect(llm.sent('Write example dialogue exchanges'), isFalse);

      (code, body) = await relay.get('/api/chargen/profile');
      expect((body['pending'] as Map)['description'], profile['description']);
      expect((body['pending'] as Map)['writing'], isNull);

      // A relay that restarts reads the pause back from its file.
      (code, body) = await relay.get(
        '/api/chargen/profile',
        on: relay.restarted(),
      );
      expect(code, 200);
      expect(
        (body['pending'] as Map?)?['description'],
        profile['description'],
        reason: 'the pending run survives a restart',
      );

      // Next: the texts and facts as the phone left them, then the rest.
      final facts = Map<String, dynamic>.from(profile['facts'] as Map)
        ..['likes'] = ['hot tea']
        ..['ambitions'] = <String>[];
      final done = relay.next('chargen_done', seconds: 60);
      (code, body) = await relay.post('/api/chargen/continue', {
        'description': 'EDITED {{char}} has salt-cracked hands.',
        'personality': profile['personality'],
        'scenario': profile['scenario'],
        'facts': facts,
      });
      expect(code, 200, reason: '$body');
      expect(body, {'status': 'started', 'phase': 'complete'});
      final id = (await done)['id'].toString();
      final saved = relay.characters.cardByDbId(id)!;
      expect(saved.description, 'EDITED {{char}} has salt-cracked hands.');
      expect(saved.frontPorchExtensions!.likes, ['hot tea']);
      expect(
        saved.frontPorchExtensions!.ambitions,
        isEmpty,
        reason: 'a list the author emptied stays empty',
      );
      expect(saved.frontPorchExtensions!.occupation, 'lighthouse keeper');
      expect(saved.mesExample, isNotEmpty, reason: 'Next wrote the rest');
      expect(saved.firstMessage, isNotEmpty);
      (code, body) = await relay.get('/api/chargen/profile');
      expect(body['pending'], isNull);
      (code, body) = await relay.get(
        '/api/chargen/profile',
        on: relay.restarted(),
      );
      expect(body['pending'], isNull, reason: 'the file went with the save');
      (code, body) = await relay.post('/api/chargen/continue', {
        'description': 'x',
        'personality': 'y',
        'scenario': 'z',
      });
      expect(code, 404, reason: 'nothing is waiting any more');
    },
  );

  // ── The profile rewrite streams into its boxes; Stop keeps the old text;
  // Re-read refreshes the facts ──────────────────────────────────────────
  test(
    'a steered rewrite streams, Stop keeps the text, Re-read reads facts',
    () async {
      final factsAnswer = <String, dynamic>{
        'occupation': 'lighthouse keeper',
        'likes': ['salt wind'],
      };
      final llm = StreamingChargenLlm(
        toolAnswers: {kIdentityFactsToolName: factsAnswer},
      );
      final relay = await ChargenRelay.start(llm);
      final profiled = relay.next('chargen_profile', seconds: 60);
      await relay.post('/api/chargen/create', {
        'name': _name,
        'mode': 'quick',
        'concept': 'A lighthouse keeper.',
        'pauseAtProfile': true,
      });
      final profile = await profiled;

      // A steered rewrite: the description arrives first, then personality.
      llm
        ..streamMarker = 'ZZSTEER'
        ..chunks = const [
          '{"description": "ZZNEW {{char}} is tall',
          ' and windburnt, with salt-cracked hands and dark hair she cuts '
              'herself, and a coat that smells of lamp oil and tar.", '
              '"personality": "ZZNEW Blunt',
          ' and exact; she answers questions with questions and hides care '
              'inside practical help, a dry coat or a full kettle.", '
              '"scenario": "ZZNEW The storm has closed the harbor for three '
              'days and the lamp room is the only warm place left."}',
        ];
      final streamed = relay.collect(
        'chargen_profile_progress',
        'chargen_profile_done',
      );
      var (code, body) = await relay.post('/api/chargen/profile/rewrite', {
        'description': profile['description'],
        'personality': profile['personality'],
        'scenario': profile['scenario'],
        'direction': 'make her colder ZZSTEER',
      });
      expect(code, 200, reason: '$body');
      final seen = await streamed;
      final progress = seen.where(
        (e) => e['event'] == 'chargen_profile_progress',
      );
      expect(
        progress.any(
          (e) =>
              e['field'] == 'description' &&
              (e['description'] as String).startsWith('ZZNEW') &&
              e['personality'] == '',
        ),
        isTrue,
        reason: 'the description streams before personality starts: $progress',
      );
      expect(progress.any((e) => e['field'] == 'personality'), isTrue);
      final done = seen.last;
      expect(
        done['description'],
        startsWith('ZZNEW {{char}} is tall and windburnt, with salt-cracked'),
      );
      expect(llm.promptWith('ZZSTEER'), contains('DIRECTION FROM THE AUTHOR'));
      (code, body) = await relay.get('/api/chargen/profile');
      expect((body['pending'] as Map)['description'], done['description']);

      // Stop: the second rewrite is held after its first words; a second call
      // waits; Stop keeps the text the profile had.
      llm
        ..holdNext = true
        ..chunks = const [
          '{"description": "NEVER SAVED',
          ' text that runs long enough to be taken as a real description by '
              'the rewrite, so only Stop can keep it out of the profile.", '
              '"personality": "NEVER SAVED either, though it too is long '
              'enough that the rewrite would take it as a personality.", '
              '"scenario": "NEVER SAVED: a scenario long enough to pass the '
              'floor the rewrite holds a scenario to."}',
        ];
      final firstWords = relay.next('chargen_profile_progress');
      (code, body) = await relay.post('/api/chargen/profile/rewrite', {
        'description': done['description'],
        'personality': done['personality'],
        'scenario': done['scenario'],
        'direction': 'again ZZSTEER',
      });
      expect(code, 200);
      await firstWords;
      (code, body) = await relay.get('/api/chargen/profile');
      expect((body['pending'] as Map)['writing'], 'rewrite');
      (code, body) = await relay.post('/api/chargen/profile/facts', {
        'description': done['description'],
        'personality': done['personality'],
        'scenario': done['scenario'],
      });
      expect(code, 409, reason: 'one model call at a time');
      final stopped = relay.next('chargen_profile_stopped');
      (code, body) = await relay.post('/api/chargen/profile/stop', const {});
      expect(body['stopped'], isTrue);
      await stopped;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      (code, body) = await relay.get('/api/chargen/profile');
      expect(
        (body['pending'] as Map)['description'],
        done['description'],
        reason: 'Stop keeps the old text',
      );
      expect(
        relay.events.where((e) => e['event'] == 'chargen_profile_done'),
        hasLength(1),
      );
      expect(
        relay.events.where((e) => e['event'] == 'chargen_profile_error'),
        isEmpty,
        reason: 'a Stop is not an error',
      );

      // Re-read: the facts come back from the profile as it is now.
      factsAnswer['occupation'] = 'harbour pilot';
      final facts = relay.next('chargen_facts_done');
      (code, body) = await relay.post('/api/chargen/profile/facts', {
        'description': done['description'],
        'personality': done['personality'],
        'scenario': done['scenario'],
      });
      expect(code, 200, reason: '$body');
      expect(((await facts)['facts'] as Map)['occupation'], 'harbour pilot');
      (code, body) = await relay.get('/api/chargen/profile');
      expect(
        ((body['pending'] as Map)['facts'] as Map)['occupation'],
        'harbour pilot',
      );
    },
  );

  // ── The review rewrites and the profile-changed hint, on a saved card ──
  test(
    'dialogue and lorebook rewrites save; hand edits stay; the hint',
    () async {
      final llm = StreamingChargenLlm(
        textAnswers: {
          'Generate WORLD-BUILDING lorebook entries': jsonEncode({
            'lorebook': [
              {
                'name': 'The Rock',
                'category': 'premise',
                'key': 'rock, sea',
                'content': 'ZZLORE A wet rock two miles out.',
              },
              {
                'name': 'The Harbor',
                'category': 'location',
                'key': 'harbor, town',
                'content': 'ZZLORE A harbor town of gulls and tar.',
              },
            ],
          }),
        },
      );
      final relay = await ChargenRelay.start(llm);
      final generated = LorebookEntry(
        name: 'Old Lore',
        keys: ['old'],
        content: 'Written by the generator.',
      );
      final edited = LorebookEntry(
        name: 'My Pub',
        keys: ['pub'],
        content: 'Written by the generator.',
      );
      final book = Lorebook(entries: [generated, edited]);
      stampLoreFingerprints(book);
      edited.content = 'The pub I wrote myself.';
      final card = CharacterCard(
        name: _name,
        description: 'D1 {{char}} keeps the lighthouse.',
        personality: 'P1 Patient and dry.',
        scenario: '{{user}} climbs the stairs.',
        firstMessage: '*{{char}} trims the wick.*',
        alternateGreetings: const ['ALT ONE'],
        lorebook: book,
      );
      stampGreetingRecipe(
        card,
        GreetingRecipe(
          interviewTranscript: 'Q: Who are you?\nA: The keeper.',
          profileFingerprint: profileFingerprintOf(
            'D0 an older description',
            'P1 Patient and dry.',
            name: _name,
          ),
        ),
      );
      final id = (await relay.characters.persistNewCard(
        card,
      ))!['id'].toString();
      CharacterCard saved() => relay.characters.cardByDbId(id)!;
      Future<Object?> changed() async => (await relay.get(
        '/api/chargen/greeting/status?characterId=$id',
      )).$2['profileChanged'];

      // ── The hint: derived from the fingerprint, never from an action ──
      expect(await changed(), isTrue);
      var (code, body) = await relay.post(
        '/api/chargen/greeting/keep-profile',
        {'characterId': id},
      );
      expect(body['ok'], isTrue);
      expect(await changed(), isFalse, reason: 'Keep them re-stamps');
      await relay.characters.update(id, {'description': 'D2 a hand edit.'});
      expect(await changed(), isTrue, reason: 'a hand edit raises it too');

      // ── Rewrite the greetings from it: every greeting, in order ──
      final run = relay.collect(
        'chargen_greeting_done',
        'chargen_greetings_rewritten',
      );
      (code, body) = await relay.post('/api/chargen/greeting/rewrite-all', {
        'characterId': id,
      });
      expect(code, 200, reason: '$body');
      expect(body['count'], 2);
      final written = await run;
      expect(
        [
          for (final e in written)
            if (e['event'] == 'chargen_greeting_done') e['index'],
        ],
        [0, 1],
      );
      expect(await changed(), isFalse, reason: 'written from this profile');

      // ── Example dialogue, steered, saved ──
      final dialogue = relay.next('chargen_rewrite_done');
      (code, body) = await relay.post('/api/chargen/rewrite/dialogue', {
        'characterId': id,
        'direction': 'shorter lines ZZDLG',
      });
      expect(code, 200, reason: '$body');
      final d = await dialogue;
      expect(d['field'], 'mesExample');
      expect(d['text'], contains('mapped every one of them twice'));
      expect(saved().mesExample, d['text']);
      expect(llm.promptWith('ZZDLG'), contains('DIRECTION FROM THE AUTHOR'));

      // ── The lorebook: the generator's entry goes, the hand-edited stays ──
      final lore = relay.next('chargen_rewrite_done');
      (code, body) = await relay.post('/api/chargen/rewrite/lorebook', {
        'characterId': id,
        'direction': 'more about the harbor',
      });
      expect(code, 200, reason: '$body');
      final l = await lore;
      expect(l['field'], 'lorebook');
      final entries = saved().lorebook!.entries;
      expect(
        entries.map((e) => e.content),
        contains('The pub I wrote myself.'),
        reason: 'the hand-edited entry is kept as written',
      );
      expect(
        entries.map((e) => e.content),
        isNot(contains('Written by the generator.')),
      );
      expect(entries.any((e) => e.content.startsWith('ZZLORE')), isTrue);
      final rows = (l['lorebook'] as List).cast<Map>();
      expect(
        rows.firstWhere((r) => r['name'] == 'My Pub')['handEdited'],
        isTrue,
      );
      (code, body) = await relay.get('/api/chargen/review?characterId=$id');
      expect(body['mesExample'], d['text']);
      expect((body['lorebook'] as List), hasLength(entries.length));
    },
  );
}
