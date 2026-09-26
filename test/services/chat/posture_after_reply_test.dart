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

// SPATIAL STANCE IS ABOUT THE REPLY, SO IT IS SCORED AFTER THE REPLY.
//
// The feature exists to stop characters teleporting: the position is injected
// imperatively into the next reply ("Position: X — ground actions in this").
// It used to be produced by the pre-generation scene-time eval, which cannot
// possibly see a position the character establishes in her own words — so the
// prompt asserted where she WAS one exchange ago while the reply had already
// walked her somewhere else. Maintainer ruling 2026-08-08: "spatial awareness
// check should run post character message, otherwise how could it check where
// she moved or what she is doing".
//
// These drive the REAL ChatService through a scripted LLM, so what is proven
// is the wiring — which phase of the turn fires the pass, what the pass can
// see, where the answer is stored per speaker, and whether a regenerate puts
// the previous position back before replacing the turn.
//
// NO SETTLING SLEEP, deliberately. The posture pass is AWAITED inside
// _finalizeGenerationTurn, so every value asserted here is final the moment
// sendMessage/triggerNextCharacter returns. A fixed delay would have been a
// timing dependency pretending to be a guard (the wardrobe suite's note on
// `await Future.delayed(50ms)` — green alone, red at --concurrency=4).
//
// COUNTING NOTE (2026-08-08): the two "one posture pass per reply" guards
// originally counted every posture prompt. They were written before the
// opening SEED existed, and the seed is a posture prompt too — so on turn one
// the raw count is legitimately 2 (seed, then pass) and the old assertion was
// measuring the wrong thing rather than catching anything. They now count
// `postureAfterReply`, which is the pass alone, and one of them additionally
// pins the raw total at exactly 2 so "something asked twice" still fails.
//
// Every guard here was proven to fail before it was allowed to pass, each
// against the specific thing it guards:
//   * fire the pass from the pre-generation dance (the old placement)
//     → the reply-window, regen and group guards go red
//   * put the posture ask back into the pre-generation clock prompt
//     → the "clock no longer asks" guard goes red
//   * restore the old Continue skip (score '' on continue_) → the Continue
//     guard goes red (contract reversed 2026-08-12 — see that test's note)
//   * drop the spatialStance line from the post-gen snapshot restamp
//     → the regen-rewind guard goes red
//   * drop setGroupSpatialStance from the per-speaker persist
//     → the group guard goes red

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_posture_').path;
        }
        return null;
      });
}

/// The rooms a scripted reply can move her to. Key = a word planted in the
/// reply text; value = the posture a model would report having read it.
const _rooms = <String, String>{
  'windowsill': 'sitting on the windowsill',
  'porch': 'leaning on the porch rail',
  'armchair': 'curled in the armchair',
  'doorway': 'standing in the doorway',
};

/// A scripted backend that answers each eval by the keys its prompt asks for,
/// and — crucially — answers the POSTURE pass by reading the transcript it was
/// handed. That is the whole experiment: if the pass runs before the reply
/// exists, the reply's room word simply is not in its prompt and the answer
/// cannot name it.
class _ScriptedLlm extends LLMService {
  _ScriptedLlm(this.chatReplies);

  /// One per conversational turn, consumed in order; the last repeats.
  final List<String> chatReplies;
  int _chatIndex = 0;

  /// Every posture-pass prompt, in order.
  final List<String> posturePrompts = [];

  /// Only the POST-REPLY posture passes.
  ///
  /// A chat's opening turn also fires the seed (the "where is she when she
  /// starts her first turn" half of the maintainer's requirement), and that is
  /// a posture prompt too — so a bare count of [posturePrompts] measures
  /// "seeds + passes" and cannot say anything about the pass alone. A posture
  /// prompt that arrives before any reply has been generated is a seed by
  /// construction; every later one is a pass.
  final List<String> postureAfterReply = [];

  /// Every conversational prompt (system + user block), in order.
  final List<String> chatPrompts = [];

  /// Every scene-time (clock) prompt, in order.
  final List<String> timePrompts = [];

  /// The room word the pass could see, latest-mentioned first. Null when the
  /// transcript it was given contains none of them.
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

    // The conversational turn is the only call that carries a system prompt.
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

    // The post-generation posture pass — no other prompt in the app asks the
    // question in these words.
    if (p.contains('current physical position and stance')) {
      posturePrompts.add(p);
      if (chatPrompts.isNotEmpty) postureAfterReply.add(p);
      final room = _latestRoom(p);
      yield jsonEncode({'posture': room == null ? 'none' : _rooms[room]!});
      return;
    }
    if (p.contains('minutes_elapsed')) {
      timePrompts.add(p);
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
    // Background passes (journal, growth, cast detection, …) get nothing to
    // parse, which is a clean no-op for all of them.
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

  Future<void> boot(List<String> replies) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
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
          // setActiveGroup returns early without one, so the group case would
          // resolve zero members and quietly assert nothing.
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    // StorageService loads its settings asynchronously from its constructor;
    // await the real signal rather than a sleep.
    await storage.initialized;
  }

  CharacterCard porchCard(String name, String id) => CharacterCard(
    name: name,
    description: 'Exists only inside the posture-placement test.',
    firstMessage: 'The screen door bangs shut behind you.',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: true,
      needsSimEnabled: false,
      chaosModeEnabled: false,
    ),
  )..dbId = id;

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'the posture pass reads the reply, and the NEXT turn is grounded in it',
    () async {
      await boot([
        '*She crosses the room and settles on the windowsill.*',
        '*She says nothing for a while.*',
      ]);
      await chat.setActiveCharacter(porchCard('Nia', 'char-posture-1'));

      await chat.sendMessage('Where did you get to?');

      expect(
        llm.postureAfterReply,
        hasLength(1),
        reason: 'exactly one posture PASS per generated reply',
      );
      expect(
        llm.posturePrompts,
        hasLength(2),
        reason:
            'and exactly two posture prompts on the opening turn in total: '
            'the one-off seed that stages the first reply, then the pass that '
            'reads it. A third would mean something is asking twice.',
      );
      expect(
        llm.postureAfterReply.single,
        contains('settles on the windowsill'),
        reason:
            'THE BUG. The pass must run after the reply was written, so the '
            'reply is inside the window it reads. Fired pre-generation it '
            'sees only the exchange before, and a position she establishes '
            'in her own words is invisible until the turn after — which is '
            'the teleporting this feature exists to prevent.',
      );
      expect(
        chat.relationshipService.spatialStance,
        'sitting on the windowsill',
        reason: 'the pass stores what it read',
      );

      // And the payoff: the position reaches the very next reply's prompt.
      await chat.sendMessage('Stay there a moment.');

      expect(llm.chatPrompts, hasLength(2));
      expect(
        llm.chatPrompts[1],
        contains('Position: sitting on the windowsill'),
        reason:
            'the anti-teleport injection must name where the LAST reply left '
            'her, not where she was before it',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('the pre-generation clock eval no longer asks for posture', () async {
    await boot(['*She lingers in the doorway.*']);
    await chat.setActiveCharacter(porchCard('Nia', 'char-posture-clock'));

    await chat.sendMessage('Come in.');

    expect(llm.timePrompts, isNotEmpty, reason: 'the clock still advances');
    for (final p in llm.timePrompts) {
      expect(
        p.contains('posture'),
        isFalse,
        reason:
            'time stays pre-generation, posture does not — a pre-generation '
            'prompt that still asked for posture would overwrite the '
            'post-generation answer on the very next turn, and the move '
            'would buy nothing',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'Continue re-asks — a continuation that moves her moves the stance',
    () async {
      // CONTRACT REVERSED 2026-08-12 (maintainer-directed). This test used
      // to pin "Continue does not re-run the pass", and that skip was the
      // teleport hole reborn through one button: a continuation that walked
      // her to the porch left next turn's "Position:" line asserting the
      // windowsill — the exact bug that moved this pass post-generation in
      // the first place. Continue now runs the same post-gen family on the
      // NEW text only (double-apply impossible; posture is absolute anyway),
      // so the old "exactly one pass" assertion is false by design, not
      // merely inconvenient. The replacement pins both halves of the new
      // contract: the pass fires once more, and the continuation's room is
      // what sticks.
      await boot([
        '*She settles on the windowsill.*',
        ' *Then drifts out to the porch after all.*',
      ]);
      await chat.setActiveCharacter(porchCard('Nia', 'char-posture-cont'));

      await chat.sendMessage('Where did you get to?');
      expect(llm.postureAfterReply, hasLength(1));
      expect(
        chat.relationshipService.spatialStance,
        'sitting on the windowsill',
      );

      await chat.continueGeneration();

      expect(
        llm.postureAfterReply,
        hasLength(2),
        reason:
            'the continuation is new reply text the pre-continue pass never '
            'saw — skipping it is how she teleported back to the windowsill '
            'on the next turn',
      );
      expect(
        chat.relationshipService.spatialStance,
        'leaning on the porch rail',
        reason: 'the position she establishes via Continue must stick',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a regenerate puts the pre-reply position back before replacing the turn',
    () async {
      await boot([
        '*She settles on the windowsill.*', // turn 1
        '*She wanders out to the porch.*', // turn 2 (to be rejected)
        '*She curls into the armchair instead.*', // the regenerated turn 2
      ]);
      await chat.setActiveCharacter(porchCard('Nia', 'char-posture-regen'));

      await chat.sendMessage('Where did you get to?');
      expect(
        chat.relationshipService.spatialStance,
        'sitting on the windowsill',
      );

      await chat.sendMessage('Not staying?');
      expect(
        chat.relationshipService.spatialStance,
        'leaning on the porch rail',
      );

      await chat.regenerateLastMessage();

      // The replacement turn must be written from where she was BEFORE the
      // rejected reply moved her. Without the rewind the prompt still says
      // "porch rail" — a position from a reply that no longer exists.
      final regenPrompt = llm.chatPrompts.last;
      expect(
        regenPrompt,
        contains('Position: sitting on the windowsill'),
        reason:
            'the regen baseline is the previous accepted message\'s snapshot, '
            'and that snapshot must carry the POST-reply position — the '
            'restamp is what makes the rewind honest now that the write '
            'happens after the snapshot is first taken',
      );
      expect(
        regenPrompt,
        isNot(contains('Position: leaning on the porch rail')),
        reason: 'the rejected reply must not steer its own replacement',
      );

      expect(
        chat.relationshipService.spatialStance,
        'curled in the armchair',
        reason: 'and the accepted swipe ends where ITS reply left her',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('group: each speaker keeps their own position (1:1 parity)', () async {
    await boot([
      '*Nia settles on the windowsill.*',
      '*Rue leans on the porch rail.*',
    ]);
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-posture', name: 'The Porch'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-nia',
        groupId: 'grp-posture',
        name: 'Nia',
        frontPorchExtensions: const Value(
          '{"realism_engine":{"realism_enabled":true}}',
        ),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-rue',
        groupId: 'grp-posture',
        name: 'Rue',
        frontPorchExtensions: const Value(
          '{"realism_engine":{"realism_enabled":true}}',
        ),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-posture', name: 'The Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
    // A group created without per-member realism seeds enters with the
    // master flag off; the switch is the same one the sidebar shows.
    await chat.setRealismEnabled(true);

    final nia = chat.groupCharacters.firstWhere((c) => c.name == 'Nia');
    final rue = chat.groupCharacters.firstWhere((c) => c.name == 'Rue');

    // Plain round-robin: Nia answers the user, then the group advances to
    // Rue. No forced speaker — the natural flow is what ships.
    await chat.sendMessage('Make yourselves comfortable.');
    expect(chat.messages.last.sender, 'Nia');

    await chat.triggerNextCharacter();
    expect(chat.messages.last.sender, 'Rue');

    String? stanceOf(CharacterCard c) =>
        chat.getRealismStateForGroupCharacter(c)?['spatialStance'] as String?;

    expect(
      stanceOf(nia),
      'sitting on the windowsill',
      reason:
          'the post-gen save persists the speaker\'s own scalar into their '
          'own _groupRealism entry — the same door bond and needs use',
    );
    expect(
      stanceOf(rue),
      'leaning on the porch rail',
      reason: 'and the second speaker\'s answer must not land on the first',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
