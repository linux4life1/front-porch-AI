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

// THE POSTURE THE REPLY ESTABLISHED HAS TO REACH THE DISK ON THAT TURN.
//
// posture_after_reply_test.dart proves the pass runs in the right PHASE and
// writes the right in-memory scalar. It never looked at the database — and
// that is exactly where the bug lived: the pass had moved to AFTER
// _finalizeGenerationTurn's `await _saveChat()`, so on the ordinary 1:1 path
// nothing ever wrote the value out. Live memory said "curled in the armchair"
// while the session row, the reload and the next prompt all still said
// "sitting on the windowsill" — the character teleported back one exchange,
// which is the precise failure the whole feature exists to prevent.
//
// Worse, whether it survived at all depended on the NEEDS simulation switch,
// because the only save that could follow the pass was the one hidden inside
// _attachNeedsDeltaChipToLastMessage — a method that returns on its first line
// when Needs is off. Two unrelated features must not be wired together
// (docs/design/feature-independence.md).
//
// So every assertion in this file reads the DATABASE, not a scalar. Each guard
// was run against the pre-fix tree first and each one failed there; the
// results are recorded per test.
//
// NO SETTLING SLEEP, deliberately — same reasoning as the sibling suite: the
// posture pass and the save that carries it are AWAITED inside
// _finalizeGenerationTurn, so the row is final the moment sendMessage returns.
// A fixed delay here would be a timing dependency pretending to be a guard.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_posture_db_').path;
        }
        return null;
      });
}

/// Room word planted in a scripted reply → the posture a model reading that
/// reply would report.
const _rooms = <String, String>{
  'windowsill': 'sitting on the windowsill',
  'porch': 'leaning on the porch rail',
  'armchair': 'curled in the armchair',
};

class _ScriptedLlm extends LLMService {
  _ScriptedLlm(this.chatReplies);

  final List<String> chatReplies;
  int _chatIndex = 0;

  final List<String> posturePrompts = [];
  final List<String> chatPrompts = [];

  String? _latestRoom(String prompt) {
    String? best;
    var bestAt = -1;
    _rooms.forEach((word, _) {
      final at = prompt.toLowerCase().lastIndexOf(word);
      if (at > bestAt) {
        bestAt = at;
        best = word;
      }
    });
    return best;
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;

    if (params.systemPrompt != null) {
      chatPrompts.add('${params.systemPrompt}\n$p');
      final reply =
          chatReplies[_chatIndex < chatReplies.length
              ? _chatIndex
              : chatReplies.length - 1];
      _chatIndex++;
      yield reply;
      return;
    }

    // The post-generation posture pass — no other prompt asks this.
    if (p.contains('current physical position and stance')) {
      posturePrompts.add(p);
      final room = _latestRoom(p);
      yield jsonEncode({'posture': room == null ? 'none' : _rooms[room]!});
      return;
    }
    // The fused one-shot evaluation carries BOTH keys; the standalone clock
    // eval carries only minutes_elapsed. Order matters.
    if (p.contains('minutes_elapsed') && p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,"bond_reason":"steady",'
          '"trust_reason":"steady","emotion":"neutral",'
          '"emotion_intensity":"mild","minutes_elapsed":5,"new_day":false,'
          '"proposed_objective":"none","fixation_topic":"none",'
          '"reason":"scene"}';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  Future<void> boot(
    List<String> replies, {
    Map<String, Object> prefs = const {},
  }) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      ...prefs,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm(replies);
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
  }

  CharacterCard porchCard(String name, String id, {bool needs = false}) =>
      CharacterCard(
        name: name,
        description: 'Exists only inside the posture-persistence test.',
        firstMessage: 'She is already out on the porch when you arrive.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: needs,
          chaosModeEnabled: false,
        ),
      )..dbId = id;

  /// The session row exactly as a reload would find it.
  Future<Session> row() async =>
      (await db.getSessionById(chat.currentSessionId!))!;

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'Needs OFF: the reply\'s posture is in the session row when the turn ends',
    () async {
      // PRE-FIX RESULT: FAILED — row said '' (nothing had ever written it).
      await boot(['*She crosses the room and settles on the windowsill.*']);
      await chat.setActiveCharacter(porchCard('Nia', 'char-pp-1'));
      expect(
        chat.needsSimEnabled,
        isFalse,
        reason: 'this guard is specifically about the Needs switch being OFF',
      );

      await chat.sendMessage('Where did you get to?');

      expect(
        chat.relationshipService.spatialStance,
        'sitting on the windowsill',
        reason: 'sanity: the live scalar was already right before the fix',
      );
      expect(
        (await row()).spatialStance,
        'sitting on the windowsill',
        reason:
            'THE BUG. The pass runs after _finalizeGenerationTurn\'s save, so '
            'unless the turn saves again the position only exists in RAM: the '
            'reload, the next prompt and every later turn all read the '
            'PREVIOUS exchange\'s position back out of this column — the '
            'teleport, restored through the persistence door.',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the persisted message snapshot carries the POST-reply position',
    () async {
      // PRE-FIX RESULT: FAILED — the stored realism_state said ''.
      await boot(['*She crosses the room and settles on the windowsill.*']);
      await chat.setActiveCharacter(porchCard('Nia', 'char-pp-snap'));

      await chat.sendMessage('Where did you get to?');

      final rows = await db.getMessagesForSession(chat.currentSessionId!);
      final reply = rows.last;
      final meta = jsonDecode(reply.metadata ?? '{}') as Map<String, dynamic>;
      final rs = meta['realism_state'] as Map<String, dynamic>?;
      expect(rs, isNotNull, reason: 'the reply must carry a realism snapshot');
      expect(
        rs!['spatialStance'],
        'sitting on the windowsill',
        reason:
            'the snapshot is the rewind baseline a regenerate/swipe/delete '
            'restores from. Restamped but never saved, it hands the next '
            'replacement turn a position one exchange stale.',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the Needs switch does not decide whether posture survives the turn',
    () async {
      // PRE-FIX RESULT: FAILED on the Needs-OFF leg only — which IS the
      // coupling: the sole save that could follow the pass lived inside
      // _attachNeedsDeltaChipToLastMessage, behind `if (!_needsSimEnabled)`.
      await boot(
        ['*She crosses the room and settles on the windowsill.*'],
        prefs: {'needs_sim_default': true},
      );
      await chat.setActiveCharacter(
        porchCard('Nia', 'char-pp-needs-on', needs: true),
      );
      expect(chat.needsSimEnabled, isTrue);
      await chat.sendMessage('Where did you get to?');
      final withNeeds = (await row()).spatialStance;

      await disposeChatThenCloseDb(chat, db);

      await boot(['*She crosses the room and settles on the windowsill.*']);
      await chat.setActiveCharacter(porchCard('Nia', 'char-pp-needs-off'));
      expect(chat.needsSimEnabled, isFalse);
      await chat.sendMessage('Where did you get to?');
      final withoutNeeds = (await row()).spatialStance;

      expect(withNeeds, 'sitting on the windowsill');
      expect(
        withoutNeeds,
        withNeeds,
        reason:
            'Needs and spatial stance are unrelated features. A user with the '
            'Sims needs simulation switched off must still get a character '
            'who stays where she walked.',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'group: the persisted per-member blob carries each speaker\'s own posture',
    () async {
      // PRE-FIX RESULT: FAILED — the blob held "" for both members while the
      // in-memory map (which posture_after_reply_test reads) was correct.
      await boot([
        '*Nia settles on the windowsill.*',
        '*Rue leans on the porch rail.*',
      ]);
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-pp', name: 'The Porch'),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-nia',
          groupId: 'grp-pp',
          name: 'Nia',
          frontPorchExtensions: const Value(
            '{"realism_engine":{"realism_enabled":true}}',
          ),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-rue',
          groupId: 'grp-pp',
          name: 'Rue',
          frontPorchExtensions: const Value(
            '{"realism_engine":{"realism_enabled":true}}',
          ),
        ),
      );
      await chat.setActiveGroup(
        GroupChat(id: 'grp-pp', name: 'The Porch'),
        groupRepo: GroupChatRepository(storage, db),
      );
      await chat.setRealismEnabled(true);

      await chat.sendMessage('Make yourselves comfortable.');
      expect(chat.messages.last.sender, 'Nia');
      await chat.triggerNextCharacter();
      expect(chat.messages.last.sender, 'Rue');

      final blob =
          jsonDecode((await row()).groupRealismState) as Map<String, dynamic>;
      final perChar = blob['perChar'] as Map<String, dynamic>;
      // `stableGroupId` is the key ChatService writes _groupRealism under.
      String? stanceOf(String name) {
        final card = chat.groupCharacters.firstWhere((c) => c.name == name);
        final mine = perChar[card.stableGroupId] as Map<String, dynamic>?;
        return mine?['spatialStance'] as String?;
      }

      expect(
        stanceOf('Nia'),
        'sitting on the windowsill',
        reason:
            'the per-speaker save writes the scalar into _groupRealism, but '
            'only _saveChat serializes that map into group_realism_state',
      );
      expect(
        stanceOf('Rue'),
        'leaning on the porch rail',
        reason: 'and the second speaker must not overwrite the first',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'one-shot and the four-call path persist the SAME post-reply posture',
    () async {
      // The parity evidence this replaces was vacuous: one_shot_parity_test
      // compares observable()['stance'], which is now '' on both paths because
      // posture left the pre-generation evals entirely. It passes by emptiness
      // and cannot catch a relapse. This compares the value that actually
      // ships — the one on disk after a real generated turn.
      //
      // PRE-FIX RESULT: FAILED on both legs (both rows were '').
      Future<String> stanceAfterTurn({required bool oneShot}) async {
        await boot(['*She crosses the room and settles on the windowsill.*']);
        await storage.realismSettings.setRealismOneShotEval(oneShot);
        await chat.setActiveCharacter(porchCard('Nia', 'char-pp-os-$oneShot'));
        await chat.sendMessage('Where did you get to?');
        final stance = (await row()).spatialStance;
        await disposeChatThenCloseDb(chat, db);
        return stance;
      }

      final multi = await stanceAfterTurn(oneShot: false);
      final single = await stanceAfterTurn(oneShot: true);

      // Re-boot so tearDown has a live service/db to close.
      await boot(['unused']);

      expect(
        multi,
        'sitting on the windowsill',
        reason: 'the four-call path must land the reply\'s position on disk',
      );
      expect(
        single,
        multi,
        reason:
            'one-shot is a token optimisation. Posture is no longer inside the '
            'fused JSON — it is its own post-generation pass — so both modes '
            'must reach the identical stored position.',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('turn one has a position: the greeting baseline seeds it', () async {
    // PRE-FIX RESULT: FAILED — no posture prompt fired at the baseline and
    // the first reply's prompt carried no Position line at all, because the
    // baseline's _evaluatePhysicalStateCall() now only advances the clock.
    await boot(['*She keeps rocking.*']);
    final plain = CharacterCard(
      name: 'Nia',
      description: 'No Front Porch extensions — the imported-card shape.',
      firstMessage: 'She is rocking in the armchair when you walk in.',
    )..dbId = 'char-pp-greet';
    await chat.setActiveCharacter(plain);
    await chat.setRealismEnabled(true);
    await chat.startNewChat();

    // The baseline is fire-and-forget behind the greeting overlay flag.
    for (var i = 0; i < 200 && chat.isProcessingGreeting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(
      chat.relationshipService.spatialStance,
      'curled in the armchair',
      reason:
          'the maintainer asked for "the part that informs the character '
          'where they are when they start their turn" — with posture moved '
          'to post-generation, turn one has no answer unless the greeting '
          'baseline seeds one from the opening scene',
    );

    await chat.sendMessage('Morning.');
    expect(
      llm.chatPrompts.first,
      contains('Position: curled in the armchair'),
      reason: 'and the very first reply must be grounded in it',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('switching Realism on mid-chat seeds a position too', () async {
    // PRE-FIX RESULT: FAILED — the retroactive scan fired the clock eval and
    // nothing else, so the next reply had no Position line.
    await boot(['*She keeps rocking.*', '*Still rocking.*']);
    final plain = CharacterCard(
      name: 'Nia',
      description: 'No Front Porch extensions.',
      firstMessage: 'She is rocking in the armchair when you walk in.',
    )..dbId = 'char-pp-retro';
    await chat.setActiveCharacter(plain);
    await chat.setRealismEnabled(false);
    await chat.sendMessage('Morning.');

    await chat.setRealismEnabled(true);
    for (var i = 0; i < 200 && chat.isProcessingGreeting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(
      chat.relationshipService.spatialStance,
      isNotEmpty,
      reason:
          'the retroactive scan exists so the engine catches up on the whole '
          'visible history; a blank position means the next reply is written '
          'with no staging at all',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
