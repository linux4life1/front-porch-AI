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

// TURN ONE HAS TO KNOW WHERE SHE IS STANDING.
//
// Posture moved to the post-generation phase so it could read the reply, which
// is right — but it left the FIRST reply of every conversation with nothing.
// The seed added to fix that was wired to the greeting baseline, which
// `startNewChat` only runs when `frontPorchExtensions == null` and only when
// `_activeGroup == null`. Between them those two gates excluded:
//   * every card authored in Front Porch AI,
//   * every card downloaded from The Stoop,
//   * every group, entirely,
//   * and every chat opened by tapping a character (that path never calls
//     startNewChat at all).
// In other words the seed reached third-party PNGs opened through New Chat and
// almost nothing else, while at HEAD the pre-generation eval had staged every
// card before the first prompt was built.
//
// The maintainer's requirement is both halves, verbatim: "we need the part
// that informs the character where they are when they start their turn. and
// the post gen portion that comes after their response so they know where they
// moved to." So each test here asserts BOTH: the opening prompt carries a
// position, AND the post-reply pass still owns every turn after it.
//
// The scripted backend answers posture per CHARACTER and per CALL, which is
// what makes the group case meaningful — a fix that seeded one stance for the
// whole cast, or let the first speaker's position leak onto the second, would
// hand back a name that does not match.
//
// NO SETTLING SLEEP: the seed is awaited inside the pre-turn dance and the
// post-reply pass is awaited inside _finalizeGenerationTurn, so every value
// read here is final the moment sendMessage/triggerNextCharacter returns.
//
// PROVEN TO FAIL FIRST — with `await _seedOpeningPosture()` commented out of
// chat_service_realism_dance.dart, every test in this file failed, each on the
// assertion it exists for (recorded per test below).

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
          return Directory.systemTemp.createTempSync('fpai_posture_seed_').path;
        }
        return null;
      });
}

/// A backend that answers the posture question the way the feature assumes a
/// real model does: **about the character it was asked about**, and differently
/// each time the scene has moved on.
///
/// [postures] is per character name, consumed in order (the last entry repeats).
/// So `postures['Nia']![0]` is the answer to Nia's OPENING seed and
/// `postures['Nia']![1]` the answer to the pass that reads her first reply —
/// which is what lets these tests tell the two halves apart by value alone
/// instead of by counting calls.
class _ScriptedLlm extends LLMService {
  _ScriptedLlm({required this.chatReplies, required this.postures});

  /// One per conversational turn, consumed in order; the last repeats.
  final List<String> chatReplies;
  int _chatIndex = 0;

  final Map<String, List<String>> postures;
  final Map<String, int> _postureCalls = {};

  /// Every conversational prompt (system + user block), in order.
  final List<String> chatPrompts = [];

  /// Character name of every posture pass, in order.
  final List<String> postureAsked = [];

  /// The posture prompt bodies, in order.
  final List<String> posturePrompts = [];

  int postureCallsFor(String name) => _postureCalls[name] ?? 0;

  static final _who = RegExp(
    r"What is (.+?)'s current physical position and stance",
  );

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

    if (p.contains('current physical position and stance')) {
      posturePrompts.add(p);
      final name = _who.firstMatch(p)?.group(1) ?? '<unnamed>';
      postureAsked.add(name);
      final answers = postures[name];
      if (answers == null || answers.isEmpty) {
        yield jsonEncode({'posture': 'none'});
        return;
      }
      final i = _postureCalls[name] ?? 0;
      _postureCalls[name] = i + 1;
      yield jsonEncode({
        'posture': answers[i < answers.length ? i : answers.length - 1],
      });
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

  Future<void> boot({
    required List<String> replies,
    required Map<String, List<String>> postures,
  }) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm(chatReplies: replies, postures: postures);
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

  // ── (a) a card WITH frontPorchExtensions ─────────────────────────────────
  //
  // The overwhelming majority of real cards: everything the in-app creator
  // writes and everything The Stoop serves. This is the population the shipped
  // seed skipped, because startNewChat gates the greeting baseline on
  // `frontPorchExtensions == null`.
  test('authored card (frontPorchExtensions): the FIRST prompt is staged, and '
      'the post-reply pass still owns every turn after it', () async {
    // PRE-FIX RESULT: FAILED at the first `Position:` assertion — the opening
    // prompt carried no Position line at all (posture only ever ran after the
    // reply, and this card never reaches the greeting baseline).
    await boot(
      replies: [
        '*She crosses to the window.*',
        '*She drifts back to the chair.*',
      ],
      postures: {
        'Nia': [
          'rocking on the porch swing', // 0 — the opening seed
          'standing at the window', // 1 — after reply one
          'curled in the armchair', // 2 — after reply two
        ],
      },
    );
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Nia',
        description: 'Authored in Front Porch AI — carries realism setup.',
        firstMessage: 'She is rocking on the porch swing when you walk up.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-seed-ext',
    );
    expect(
      chat.activeCharacter!.frontPorchExtensions,
      isNotNull,
      reason: 'this guard is specifically about the authored-card shape',
    );

    await chat.sendMessage('Morning.');

    expect(
      llm.chatPrompts.first,
      contains('Position: rocking on the porch swing'),
      reason:
          'THE REGRESSION. Turn one must be staged before the first prompt '
          'is built — "the part that informs the character where they are '
          'when they start their turn". At HEAD the pre-generation eval did '
          'this for every card; the replacement seed reached almost none.',
    );
    expect(
      chat.relationshipService.spatialStance,
      'standing at the window',
      reason:
          'and the post-reply pass still runs and still wins — the seed is '
          'an opening baseline, not a return to pre-generation evaluation',
    );

    await chat.sendMessage('Stay a while.');

    expect(
      llm.chatPrompts[1],
      contains('Position: standing at the window'),
      reason:
          'turn two is grounded in where the REPLY left her, not in the seed',
    );
    expect(
      (await row()).spatialStance,
      'curled in the armchair',
      reason:
          'and turn two\'s post-reply answer still reaches the database, '
          'which is where a reload and every later prompt read it from',
    );
    expect(
      llm.postureCallsFor('Nia'),
      3,
      reason:
          'exactly one seed for the conversation plus one pass per reply. A '
          'seed that re-fired every turn would be the pre-generation '
          'evaluation this design removed, and would overwrite the '
          'post-reply answer it just wrote.',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  // ── (b) a card WITHOUT frontPorchExtensions ──────────────────────────────
  //
  // The plain imported PNG. It was the ONLY shape the shipped seed served, and
  // only through New Chat — opening one by tapping it in the library (this
  // path) never calls startNewChat, so it was unstaged too.
  test(
    'plain imported card (no extensions): the FIRST prompt is staged, and the '
    'post-reply pass still owns every turn after it',
    () async {
      // PRE-FIX RESULT: FAILED at the first `Position:` assertion.
      await boot(
        replies: ['*She keeps rocking.*', '*She stands up at last.*'],
        postures: {
          'Rue': [
            'rocking in the armchair', // 0 — the opening seed
            'still in the armchair', // 1 — after reply one
            'standing by the door', // 2 — after reply two
          ],
        },
      );
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Rue',
          description: 'A plain PNG — no Front Porch extensions at all.',
          firstMessage: 'She is rocking in the armchair when you walk in.',
        )..dbId = 'char-seed-plain',
      );
      expect(chat.activeCharacter!.frontPorchExtensions, isNull);
      expect(
        chat.realismEnabled,
        isTrue,
        reason: 'the global Realism default turns a plain card on',
      );

      await chat.sendMessage('Morning.');

      expect(
        llm.chatPrompts.first,
        contains('Position: rocking in the armchair'),
        reason:
            'the opening scene is right there in the greeting; the first reply '
            'must be grounded in it',
      );

      await chat.sendMessage('Comfortable?');

      expect(
        llm.chatPrompts[1],
        contains('Position: still in the armchair'),
        reason: 'post-reply re-evaluation still drives every later turn',
      );
      expect((await row()).spatialStance, 'standing by the door');
      expect(
        llm.postureCallsFor('Rue'),
        3,
        reason: 'one seed for the conversation, one pass per reply',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  // ── (c) a group ──────────────────────────────────────────────────────────
  //
  // Groups lost the opening position outright: startNewChat's baseline is
  // gated on `_activeGroup == null` and so is setRealismEnabled's retroactive
  // branch, so neither seed path could ever reach a cast member. This is also
  // a 1:1-vs-group divergence in a mandatory-parity area.
  test(
    'group: EVERY member gets their own opening position in their own slot',
    () async {
      // PRE-FIX RESULT: FAILED at Nia's `Position:` assertion — the group's
      // first prompt carried no Position line at all.
      await boot(
        replies: [
          '*Nia moves to the window.*',
          '*Rue gets up off the floor.*',
          '*Nia sits back down.*',
        ],
        postures: {
          'Nia': [
            'perched on the porch rail', // 0 — Nia's opening seed
            'standing at the window', // 1 — after Nia's reply
            'back on the porch rail', // 2 — after Nia's second reply
          ],
          'Rue': [
            'sprawled on the rug', // 0 — Rue's opening seed
            'leaning against the doorframe', // 1 — after Rue's reply
          ],
        },
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-seed',
          name: 'The Porch',
          firstMessage: const Value(
            'Nia is perched on the porch rail; Rue is sprawled on the rug.',
          ),
        ),
      );
      for (final m in const [('mem-nia', 'Nia'), ('mem-rue', 'Rue')]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: m.$1,
            groupId: 'grp-seed',
            name: m.$2,
            frontPorchExtensions: const Value(
              '{"realism_engine":{"realism_enabled":true}}',
            ),
          ),
        );
      }
      await chat.setActiveGroup(
        GroupChat(id: 'grp-seed', name: 'The Porch'),
        groupRepo: GroupChatRepository(storage, db),
      );
      await chat.setRealismEnabled(true);

      // Plain round-robin: Nia answers the user, then the group advances.
      await chat.sendMessage('Make yourselves comfortable.');
      expect(chat.messages.last.sender, 'Nia');

      expect(
        llm.chatPrompts.first,
        contains('Position: perched on the porch rail'),
        reason:
            'THE REGRESSION, group edition. Neither seed path could reach a '
            'group at all, so the first speaker in every group chat wrote '
            'their opening line with no staging.',
      );

      await chat.triggerNextCharacter();
      expect(chat.messages.last.sender, 'Rue');

      expect(
        llm.chatPrompts[1],
        contains('Position: sprawled on the rug'),
        reason:
            'the SECOND member needs their own opening too — their first line '
            'is just as unstaged as the first member\'s was',
      );
      expect(
        llm.chatPrompts[1],
        isNot(contains('Position: standing at the window')),
        reason:
            'and it must not be the first speaker\'s position. The seed runs '
            'after the per-speaker scalar load, so the stance it reads and '
            'writes is this member\'s own _groupRealism slot.',
      );
      expect(
        llm.postureAsked,
        containsAllInOrder(['Nia', 'Nia', 'Rue', 'Rue']),
        reason:
            'each pass names the member it is about — seed then post-reply for '
            'Nia, seed then post-reply for Rue',
      );

      final nia = chat.groupCharacters.firstWhere((c) => c.name == 'Nia');
      final rue = chat.groupCharacters.firstWhere((c) => c.name == 'Rue');
      String? liveStance(CharacterCard c) =>
          chat.getRealismStateForGroupCharacter(c)?['spatialStance'] as String?;

      expect(liveStance(nia), 'standing at the window');
      expect(
        liveStance(rue),
        'leaning against the doorframe',
        reason: 'one slot per member, and the post-reply pass still owns both',
      );

      // Turn two for Nia: no second seed, and the position she is handed is
      // the one HER last reply established.
      await chat.triggerNextCharacter();
      expect(chat.messages.last.sender, 'Nia');
      expect(
        llm.chatPrompts[2],
        contains('Position: standing at the window'),
        reason:
            'Nia\'s second turn is grounded in her own post-reply answer, not '
            're-seeded and not handed Rue\'s',
      );
      expect(
        llm.postureCallsFor('Nia'),
        3,
        reason: 'one seed, then one pass per reply — the seed does not repeat',
      );

      // And it is all on disk: the per-member blob is what a reload reads.
      final blob =
          jsonDecode((await row()).groupRealismState) as Map<String, dynamic>;
      final perChar = blob['perChar'] as Map<String, dynamic>;
      String? storedStance(CharacterCard c) =>
          (perChar[groupMemberStoreId(c)]
                  as Map<String, dynamic>?)?['spatialStance']
              as String?;

      expect(storedStance(nia), 'back on the porch rail');
      expect(
        storedStance(rue),
        'leaning against the doorframe',
        reason:
            'post-reply re-evaluation still persists per member — the seed did '
            'not displace it, it only filled the opening',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
