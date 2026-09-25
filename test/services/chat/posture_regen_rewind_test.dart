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

// REROLLING THE FIRST REPLY MUST NOT MOVE HER.
//
// posture_after_reply_test already covers a regen — but the SECOND reply of a
// chat, which is the easy case: the turn before it left an accepted message
// carrying a realism snapshot, and the revert restores the position out of
// that. The FIRST reply has no such message, and that is where the feature
// broke when posture became a post-generation write.
//
// The snapshot stamped on a reply is captured BEFORE generation and then
// overwritten with the position the reply ENDED in (the restamp — correct, and
// what makes swiping between alternatives move her to where that alternative
// left her). So after a reply exists, nothing anywhere remembered where its
// turn had STARTED. On turn two that did not matter, because the previous
// accepted message's snapshot happens to hold the same value. On turn one
// there is no previous accepted message: the greeting only carries a snapshot
// on one entry path (1:1 + New Chat + a card with no frontPorchExtensions),
// which is neither the ordinary way a chat is opened, nor the common card
// shape, nor a group. Everywhere else the revert found nothing, left the
// rejected reply's position standing, and the replacement turn was written
// from a place invented by the reply the user had just thrown away — drifting
// one room further with every press of Regenerate.
//
// CLAUDE.md names this class of failure outright: "a regen is SUPPOSED to
// reproduce the same deltas … two regens disagreeing is a rewind bug — some
// state the turn changed was not put back".
//
// EVERY ASSERTION HERE READS THE DATABASE. The sibling suites proved the live
// scalar and the phase; the persisted session row (1:1) and the persisted
// per-member blob (group) are what a reload — and the next prompt — actually
// see, and they are what a half-fix would leave wrong.
//
// PRE-FIX RESULTS ARE RECORDED PER TEST. Each was run against the tree with
// the two-line fix reverted (the `kSpatialStancePreTurn` receipt in
// _restampRealismSnapshotPostGen and its read in the regen revert) and each
// one failed there.
//
// NO SETTLING SLEEP, deliberately — same reasoning as the sibling suites: the
// posture pass and the save that carries it are AWAITED inside
// _finalizeGenerationTurn, and regenerateLastMessage awaits that whole turn.

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
          return Directory.systemTemp
              .createTempSync('fpai_posture_regen_')
              .path;
        }
        return null;
      });
}

/// Word planted in a message → the posture a model reading it would report.
const _rooms = <String, String>{
  'armchair': 'curled in the armchair',
  'porch': 'leaning on the porch rail',
};

/// A scripted backend that answers the posture pass the way the pass's own
/// prompt tells a model to: *"Within the same scene, maintain natural
/// continuity (don't jump locations)"*.
///
///   * if the newest message in the window says where she went, follow it;
///   * otherwise she is still wherever the prompt's "Recent position
///     reference" says she was;
///   * with neither, fall back to the last room the window mentions at all
///     (this is the opening-seed case, where no reference exists yet).
///
/// That second rule is what makes this suite able to see the bug at all. A
/// reply that says nothing about position leaves the app's own belief as the
/// only input, so the stored answer after a regenerate IS the position the
/// regenerate started from — no white-box peeking required.
class _ScriptedLlm extends LLMService {
  _ScriptedLlm(this.chatReplies);

  /// One per conversational turn, consumed in order; the last repeats.
  final List<String> chatReplies;
  int _chatIndex = 0;

  /// Every conversational prompt (system + user block), in order.
  final List<String> chatPrompts = [];

  /// Every posture-pass prompt, in order.
  final List<String> posturePrompts = [];

  static final _referenceRe = RegExp(
    r'Recent position reference:[^"]*"([^"]+)"',
  );

  /// The transcript block the pass was handed — the lines between
  /// "Recent conversation:" and the blank line before the output instruction.
  static List<String> _transcript(String prompt) {
    final at = prompt.indexOf('Recent conversation:\n');
    if (at < 0) return const [];
    final lines = prompt
        .substring(at + 'Recent conversation:\n'.length)
        .split('\n');
    final out = <String>[];
    for (final l in lines) {
      if (l.trim().isEmpty) break;
      out.add(l);
    }
    return out;
  }

  static String? _roomIn(String text) {
    final lower = text.toLowerCase();
    String? best;
    var bestAt = -1;
    _rooms.forEach((word, posture) {
      final at = lower.lastIndexOf(word);
      if (at > bestAt) {
        bestAt = at;
        best = posture;
      }
    });
    return best;
  }

  String _posture(String prompt) {
    final lines = _transcript(prompt);
    if (lines.isNotEmpty) {
      final fromNewest = _roomIn(lines.last);
      if (fromNewest != null) return fromNewest;
    }
    final ref = _referenceRe.firstMatch(prompt);
    if (ref != null) return ref.group(1)!;
    return _roomIn(lines.join('\n')) ?? 'none';
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;

    // The conversational turn is the only call carrying a system prompt.
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

    if (p.contains('current physical position and stance')) {
      posturePrompts.add(p);
      yield jsonEncode({'posture': _posture(p)});
      return;
    }
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

/// The reply that moves her, then two that do not — so the position the app
/// believes at the start of each reroll is the position that gets stored.
const _movesToThePorch = '*She wanders out to the porch.*';
const _staysPut1 = '*She shrugs, and does not get up.*';
const _staysPut2 = '*She shrugs again, still not getting up.*';

const _opening = 'curled in the armchair';
const _afterReply = 'leaning on the porch rail';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  Future<void> boot() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm([_movesToThePorch, _staysPut1, _staysPut2]);
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

  /// The session row exactly as a reload would find it.
  Future<Session> row() async =>
      (await db.getSessionById(chat.currentSessionId!))!;

  tearDown(() => disposeChatThenCloseDb(chat, db));

  /// Both 1:1 card shapes run the identical journey — the bug was never about
  /// what the card carried, and proving that is half the point.
  Future<void> firstReplyRerollKeepsHerPut(CharacterCard card) async {
    await chat.setActiveCharacter(card);
    await chat.setRealismEnabled(true);
    expect(
      chat.messages,
      hasLength(1),
      reason: 'the greeting is the whole history — this IS turn one',
    );

    await chat.sendMessage('Morning.');

    // The position reply #1 was written from. Read out of the app's own
    // prompt rather than asserted from the outside, so "the pre-reply value"
    // is whatever the app actually believed, not what this test hopes.
    expect(
      llm.chatPrompts.first,
      contains('Position: $_opening'),
      reason:
          'the opening seed reads the greeting scene; without it there is no '
          'pre-reply position to rewind TO and this suite proves nothing',
    );
    expect(
      (await row()).spatialStance,
      _afterReply,
      reason: 'the reply moved her, and the turn stored where it left her',
    );

    await chat.regenerateLastMessage();
    final afterFirstReroll = (await row()).spatialStance;

    await chat.regenerateLastMessage();
    final afterSecondReroll = (await row()).spatialStance;

    expect(
      llm.chatPrompts[1],
      contains('Position: $_opening'),
      reason:
          'THE BUG. The replacement turn must be written from where she was '
          'before the rejected reply moved her. With nothing rewound the '
          'prompt still says "$_afterReply" — a position belonging to a reply '
          'that no longer exists.',
    );
    expect(
      llm.chatPrompts[1],
      isNot(contains('Position: $_afterReply')),
      reason: 'a rejected reply must never steer its own replacement',
    );
    expect(
      llm.chatPrompts[2],
      contains('Position: $_opening'),
      reason:
          'and the second reroll must start from the same place as the first '
          '— rerolls are meant to be alternatives to one moment, not a walk',
    );

    expect(
      afterFirstReroll,
      _opening,
      reason:
          'the stored position after a reroll whose reply does not move her '
          'is the position the reroll STARTED from. On disk, because that is '
          'what the reload and the next prompt read.',
    );
    expect(
      afterSecondReroll,
      afterFirstReroll,
      reason:
          'two rerolls from one point that disagree are a rewind bug by '
          'definition (CLAUDE.md) — the drift compounds one room per press',
    );
  }

  test('a Front Porch card: rerolling the FIRST reply twice starts from the '
      'opening position both times', () async {
    // PRE-FIX RESULT: FAILED — chatPrompts[1] carried
    // "Position: leaning on the porch rail" and the session row read
    // 'leaning on the porch rail' after both rerolls.
    await boot();
    await firstReplyRerollKeepsHerPut(
      CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the posture regen-rewind test.',
        firstMessage: 'She is rocking in the armchair when you walk in.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-regen-ext',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'an imported card with no Front Porch extensions: same journey, same result',
    () async {
      // PRE-FIX RESULT: FAILED identically. Worth its own leg because the one
      // path that DOES stamp the greeting (New Chat, 1:1, no extensions) is
      // this card shape — so a fix that leaned on the greeting snapshot could
      // pass here and still leave every other opening broken. Opening the
      // character the ordinary way never runs that baseline.
      await boot();
      await firstReplyRerollKeepsHerPut(
        CharacterCard(
          name: 'Nia',
          description: 'No Front Porch extensions — the imported-card shape.',
          firstMessage: 'She is rocking in the armchair when you walk in.',
        )..dbId = 'char-regen-plain',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('group: rerolling a member\'s FIRST reply rewinds that member\'s own '
      'position in the persisted blob', () async {
    // PRE-FIX RESULT: FAILED — the per-member blob held 'leaning on the
    // porch rail' after both rerolls. The group case can never be rescued
    // by the greeting baseline: that eval is gated on `_activeGroup == null`
    // outright, so a group's look-back has nothing to find on turn one.
    await boot();
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-regen', name: 'The Cast'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-nia',
        groupId: 'grp-regen',
        name: 'Nia',
        frontPorchExtensions: const Value(
          '{"realism_engine":{"realism_enabled":true}}',
        ),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-rue',
        groupId: 'grp-regen',
        name: 'Rue',
        frontPorchExtensions: const Value(
          '{"realism_engine":{"realism_enabled":true}}',
        ),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-regen', name: 'The Cast'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);

    /// Members have no greeting of their own in a group, so the opening
    /// scene arrives in the user's first line — the same thing the seed
    /// reads either way.
    await chat.sendMessage('I find you curled in the armchair. Morning.');
    expect(chat.messages.last.sender, 'Nia');

    Future<String?> stanceOf(String name) async {
      final card = chat.groupCharacters.firstWhere((c) => c.name == name);
      final blob =
          jsonDecode((await row()).groupRealismState) as Map<String, dynamic>;
      final perChar = blob['perChar'] as Map<String, dynamic>;
      final mine = perChar[card.stableGroupId] as Map<String, dynamic>?;
      return mine?['spatialStance'] as String?;
    }

    expect(await stanceOf('Nia'), _afterReply);

    await chat.regenerateLastMessage();
    final afterFirstReroll = await stanceOf('Nia');

    await chat.regenerateLastMessage();
    final afterSecondReroll = await stanceOf('Nia');

    expect(
      chat.messages.last.sender,
      'Nia',
      reason: 'the reroll must replace the same speaker\'s turn',
    );
    expect(
      afterFirstReroll,
      _opening,
      reason:
          'the rewind has to go through the rejected speaker\'s own '
          '_groupRealism entry and be persisted from there — a bare scalar '
          'restore is overwritten by the next per-speaker load',
    );
    expect(
      afterSecondReroll,
      afterFirstReroll,
      reason: '1:1 and group must reroll identically (parity is mandatory)',
    );
    expect(
      await stanceOf('Rue'),
      anyOf(isNull, isEmpty),
      reason:
          'and rewinding Nia must not write a position onto a member who '
          'has not spoken',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
