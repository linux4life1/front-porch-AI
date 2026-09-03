// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// THE FUSED REPLY-FACTS CALL: one round trip for climax + pockets + posture.
//
// The composition contract this file pins, clause by clause:
//
//   1. Each feature's question appears in the fused prompt ONLY when that
//      feature's own gate is on, and it is the standalone prompt's own
//      fragment, verbatim — so the fused and standalone transports cannot
//      drift (the RealismPromptBuilder parity-by-construction pattern).
//   2. The composed tool schema DEMANDS exactly the live features' fields
//      (the is_climax lesson: optional means never emitted) while every
//      field stays DEFINED (the converter registry is a fixed contract).
//   3. One fused answer feeds all three of the features' existing key-scoped
//      parsers — the appliers do not move.
//   4. With fewer than two features live there is NO fusion: the single live
//      feature fires its own standalone call, byte-for-byte as before.
//   5. A fused answer that fired and failed reads as "skip" for every pass
//      (the empty-carrier protocol), never as a cue to pay fallback calls.
//
// The scripted-ChatService group at the bottom proves clause 1/3/4 through a
// real turn: two features live -> exactly one bookkeeping call; one feature
// live -> the standalone call and no fused one.
//
// Proven-to-fail note (the mandatory negative check, run 2026-08-10 before
// this file was allowed to land): (a) making _runPocketsPass ignore the fused
// carrier and always fire its own call turned "exactly one bookkeeping call"
// red; (b) dropping 'inventory_ops' from the computed required list turned
// the schema group red; (c) re-inlining the climax rubric with a one-word
// change turned the fragment-parity group red. All three were then restored
// and the suite went green again.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_replyfacts_').path;
        }
        return null;
      });
}

/// The marker only the fused prompt carries (its opening line).
const _fusedMarker = 'independent bookkeeping questions';

Pockets _wornOnly() =>
    Pockets.fromJson(Pockets.cardJsonFrom(worn: const ['sundress'], carrying: const []));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('the composed prompt carries exactly the live features', () {
    test('pockets-only asks the inventory question and nothing else', () {
      final p = ReplyFactsEval.buildPrompt(
        charName: 'Nia',
        reply: 'She pockets the key.',
        recentExchange: '',
        toolsMode: false,
        askClimax: false,
        pockets: _wornOnly(),
      );

      expect(p, contains('You are keeping track of what Nia is wearing'));
      expect(p, isNot(contains('CLIMAX DETECTION')));
      expect(p, isNot(contains('current physical position and stance')));
      expect(p, contains('"inventory_ops"'));
      expect(p, isNot(contains('"is_climax"')));
      expect(p, isNot(contains('"posture"')));
    });

    test('climax + posture compose without any wardrobe talk', () {
      final p = ReplyFactsEval.buildPrompt(
        charName: 'Nia',
        reply: 'She sighs.',
        recentExchange: 'User: hello',
        toolsMode: false,
        askClimax: true,
        askPosture: true,
        displayClock: '9:40 PM',
      );

      expect(p, contains('CLIMAX DETECTION'));
      expect(p, contains('current physical position and stance'));
      expect(p, contains('Current time: 9:40 PM.'));
      expect(p, isNot(contains('You are keeping track of')));
      expect(p, contains('Recent exchange for context:\nUser: hello'));
    });

    test('every section IS the standalone fragment, verbatim', () {
      final fused = ReplyFactsEval.buildPrompt(
        charName: 'Nia',
        reply: 'r',
        recentExchange: '',
        toolsMode: false,
        askClimax: true,
        pockets: _wornOnly(),
        askPosture: true,
        displayClock: '9:40 PM',
      );

      expect(fused, contains(ClimaxEval.rubric('Nia')));
      expect(fused, contains(PocketsEval.wardrobeContext('Nia', _wornOnly())));
      expect(fused, contains(PocketsEval.opsRubric()));
      expect(
        fused,
        contains(TimeService.postureQuestion(charName: 'Nia', displayClock: '9:40 PM')),
      );
    });

    test('the standalone prompts still build FROM those fragments', () {
      // Pins against the fragments being re-inlined into one caller and then
      // edited there — the drift this composition exists to prevent.
      expect(
        ClimaxEval.buildPrompt(
          charName: 'Nia',
          reply: 'r',
          recentExchange: '',
          toolsMode: false,
        ),
        contains(ClimaxEval.rubric('Nia')),
      );
      expect(
        PocketsEval.buildPrompt(
          charName: 'Nia',
          current: _wornOnly(),
          reply: 'r',
          recentExchange: '',
          toolsMode: false,
        ),
        allOf(
          contains(PocketsEval.wardrobeContext('Nia', _wornOnly())),
          contains(PocketsEval.opsRubric()),
        ),
      );
    });
  });

  group('the composed schema demands exactly the live features', () {
    Map<String, dynamic> params(List<Map<String, dynamic>> tools) =>
        tools.single['function']['parameters'] as Map<String, dynamic>;

    test('required follows the gates', () {
      final all = params(
        kReplyFactsToolsFor(askClimax: true, askPockets: true, askPosture: true),
      );
      expect(
        all['required'],
        containsAll(['is_climax', 'refractory_turns', 'inventory_ops', 'posture']),
      );

      final pocketsOnly = params(
        kReplyFactsToolsFor(askClimax: false, askPockets: true, askPosture: false),
      );
      expect(pocketsOnly['required'], ['inventory_ops']);
      expect(
        pocketsOnly['required'],
        isNot(contains('is_climax')),
        reason: 'a disabled feature must never be demanded of the model',
      );
    });

    test('every field stays DEFINED regardless of gates', () {
      // The registry is a fixed contract negotiated once per backend identity;
      // only required-ness varies per turn.
      final props = params(
        kReplyFactsToolsFor(askClimax: false, askPockets: false, askPosture: true),
      )['properties'] as Map;
      expect(
        props.keys,
        containsAll(['is_climax', 'refractory_turns', 'inventory_ops', 'posture']),
      );
    });

    test('the tool is registered in the converter', () {
      expect(
        toolIsRegistered(kReplyFactsToolName),
        isTrue,
        reason: 'unregistered means realismToolCallToJson returns null on '
            'every call, silently using the text transport forever — the '
            'Pockets day-one bug',
      );
    });
  });

  group('one fused answer feeds all three parsers', () {
    final raw = jsonEncode({
      'is_climax': true,
      'refractory_turns': 6,
      'inventory_ops': [
        {'op': 'pickup', 'item': 'brass key'},
        {'op': 'update', 'item': 'sundress', 'state': 'rain-soaked'},
      ],
      'posture': 'sitting on the windowsill',
    });

    test('text lane: each parser reads its slice of the same text', () {
      expect(ClimaxEval.parseRefractory(raw), 6);
      expect(PocketsEval.parseOps(raw), hasLength(2));
      expect(TimeService.parsePosture(raw), 'sitting on the windowsill');
    });

    test('tools lane: the converted call round-trips the same way', () {
      final json = realismToolCallToJson(kReplyFactsToolName, [
        LlmToolCall(
          name: kReplyFactsToolName,
          arguments: jsonDecode(raw) as Map<String, dynamic>,
        ),
      ]);

      expect(json, isNotNull);
      expect(ClimaxEval.parseRefractory(json), 6);
      expect(PocketsEval.parseOps(json), hasLength(2));
      expect(TimeService.parsePosture(json!), 'sitting on the windowsill');
    });

    test('a fired-and-failed fused call reads as skip for every pass', () {
      // The empty-carrier protocol: '' is what the prefetch parks when the
      // fused call fired and came back with nothing.
      expect(ClimaxEval.parseRefractory(''), isNull);
      expect(PocketsEval.parseOps(''), isEmpty);
      expect(TimeService.parsePosture(''), isNull);
    });
  });

  group('the wiring produces before it consumes', () {
    // Structural, and labelled as such: the ORDER (prefetch before the three
    // passes, carrier cleared after them) is the part a green unit suite
    // cannot see, exactly like the afterglow placement guards next door.
    //
    // ANCHOR RENAME (2026-08-12, with the Continue incremental-scoring
    // change): the passes now take `scoredReply` — the full reply on a
    // normal turn, the NEW text only on Continue — so the old
    // `(finalResponse)` anchors no longer exist in the source. The ordering
    // property these tests pin is unchanged and still asserted verbatim;
    // only the anchor strings moved with the argument they name.
    final postgen = File(
      'lib/services/chat/chat_service_generation_postgen.dart',
    ).readAsStringSync();

    test('the prefetch runs before the first consumer', () {
      final prefetch = postgen.indexOf('_prefetchReplyFacts(scoredReply)');
      final climax = postgen.indexOf('_runClimaxPass(scoredReply)');
      expect(prefetch, greaterThan(-1));
      expect(climax, greaterThan(-1));
      expect(
        prefetch,
        lessThan(climax),
        reason: 'a consumer running before the producer silently falls back '
            'to its own standalone call and the fusion buys nothing',
      );
    });

    test('the carrier is cleared inside the same phase', () {
      // Anchor de-bracketed (2026-08-27): the literal used to carry the call's
      // exact line break + indentation, so any dart-format re-indent turned a
      // green suite red (three Rawhide CI runs). Position is what is pinned,
      // not whitespace.
      final pockets = postgen.indexOf('_runPocketsPass(');
      final clear = postgen.indexOf('_replyFactsRaw = null;', pockets);
      expect(pockets, greaterThan(-1));
      expect(
        clear,
        greaterThan(pockets),
        reason: 'a carrier that outlives the passes feeds a STALE answer to '
            'the next turn\'s bookkeeping',
      );
    });
  });

  group('a real turn fuses at two features and not at one', () {
    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;
    late _ScriptedLlm llm;

    Future<void> boot({required bool realismOn}) async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': realismOn,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      llm = _ScriptedLlm();
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage))
            ..testLlmServiceOverride = llm;
      await storage.initialized;
      await storage.realismSettings.setPocketsEnabled(true);
    }

    CharacterCard card(String id, {required bool realism}) => CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the reply-facts fusion test.',
      firstMessage: 'The screen door bangs shut behind you.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: realism,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = id;

    tearDown(() async {
      chat.dispose();
      await db.close();
    });

    test(
      'pockets + posture live -> ONE fused call answers both',
      () async {
        await boot(realismOn: true);
        await chat.setActiveCharacter(card('char-fused-1', realism: true));

        await chat.sendMessage('What did you find?');

        expect(
          llm.fusedPrompts,
          hasLength(1),
          reason: 'two bookkeeping passes were live, so exactly one fused '
              'call must replace their two standalone calls',
        );
        final fused = llm.fusedPrompts.single;
        expect(fused, contains('scoops up the brass key'));
        expect(fused, contains('You are keeping track of what Nia is wearing'));
        expect(fused, contains('current physical position and stance'));
        expect(
          fused,
          isNot(contains('CLIMAX DETECTION')),
          reason: 'Afterglow is off — its question must not be smuggled into '
              'a call another feature paid for',
        );

        expect(
          llm.standalonePocketsPrompts,
          isEmpty,
          reason: 'the standalone pockets call is what the fusion replaced',
        );
        expect(
          llm.standalonePosturePrompts,
          hasLength(1),
          reason: 'only the pre-generation opening SEED fires standalone; '
              'the post-reply pass rode the fused call',
        );

        expect(chat.relationshipService.spatialStance, 'sitting on the windowsill');
        final record = chat.pocketsFor(chat.characterIdFor(
          chat.activeCharacter!,
        ));
        expect(record, isNotNull);
        expect(
          record!.carrying.map((i) => i.name),
          contains('brass key'),
          reason: 'the pockets slice of the fused answer must apply through '
              'the same applier the standalone call feeds',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'pockets alone -> the standalone call, byte-for-byte, and no fusion',
      () async {
        await boot(realismOn: false);
        await chat.setActiveCharacter(card('char-fused-2', realism: false));

        await chat.sendMessage('What did you find?');

        expect(
          llm.fusedPrompts,
          isEmpty,
          reason: 'one live feature means fusion saves nothing — the '
              'standalone path must keep firing unchanged',
        );
        expect(llm.standalonePocketsPrompts, hasLength(1));
        final record = chat.pocketsFor(chat.characterIdFor(
          chat.activeCharacter!,
        ));
        expect(record, isNotNull);
        expect(record!.carrying.map((i) => i.name), contains('brass key'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

/// A scripted backend that recognizes each eval by the words only its prompt
/// carries, and answers the bookkeeping questions (fused or standalone) with
/// the same facts — so the assertions are about WHICH calls fired, never
/// about the model's mood.
class _ScriptedLlm extends LLMService {
  final List<String> fusedPrompts = [];
  final List<String> standalonePocketsPrompts = [];
  final List<String> standalonePosturePrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;

    if (params.systemPrompt != null) {
      yield '*She scoops up the brass key and settles on the windowsill.*';
      return;
    }
    if (p.contains(_fusedMarker)) {
      fusedPrompts.add(p);
      yield jsonEncode({
        'inventory_ops': [
          {'op': 'pickup', 'item': 'brass key'},
        ],
        'posture': 'sitting on the windowsill',
      });
      return;
    }
    if (p.contains('You are keeping track of')) {
      standalonePocketsPrompts.add(p);
      yield jsonEncode({
        'inventory_ops': [
          {'op': 'pickup', 'item': 'brass key'},
        ],
      });
      return;
    }
    if (p.contains('current physical position and stance')) {
      standalonePosturePrompts.add(p);
      yield '{"posture": "none"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}
