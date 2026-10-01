// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guards for the Tess failure: Check re-boosted one ring (0.55 → 0.95),
// the pass log counted proposals, and the prompt preferred reinforce.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/growth_ops.dart';
import 'package:front_porch_ai/services/chat/growth_physics.dart';
import 'package:front_porch_ai/services/chat/growth_prompt.dart';
import 'package:front_porch_ai/services/chat/growth_review.dart';
import 'package:front_porch_ai/services/chat/growth_service.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';

ChatMessage _msg(
  String sender,
  String text, {
  bool isUser = false,
  String? charId,
}) => ChatMessage(
  text: text,
  sender: sender,
  isUser: isUser,
  characterId: charId,
);

void main() {
  group('growth pass guards', () {
    late AppDatabase db;
    late GrowthStore store;
    late GrowthReview review;
    final host = CharacterCard(name: 'Mira', personality: 'Wry, guarded.');
    var passRunning = false;
    String? xmlReply;

    final chatty = [
      _msg('You', 'I trust you with this', isUser: true),
      _msg('Mira', 'Then I will not waste it', charId: 'mira'),
      _msg('You', 'thank you', isUser: true),
      _msg('Mira', 'Always', charId: 'mira'),
    ];

    GrowthService makeService({List<ChatMessage> messages = const []}) {
      review = GrowthReview(
        store: store,
        getSessionId: () => 's1',
        getIsGroup: () => false,
        onApplied: () async {},
        onNotify: () {},
      );
      return GrowthService(
        store: store,
        review: review,
        probe: (ToolTransportProbe()..markXmlOnly('fake')),
        fireLLMEval: (prompt) async => xmlReply,
        fireToolEval: (p, t) async => null,
        stripThinkBlocks: (t) => t,
        getBackendIdentity: () => 'fake',
        getSessionId: () => 's1',
        getActiveCharacter: () => host,
        getActiveGroup: () => null,
        getGroupCharacters: () => const [],
        getSceneGuestCards: () => const [],
        getCharacterIdFromCard: (c) => c.name.toLowerCase(),
        getMessages: () => messages,
        getUserName: () => 'You',
        getRecap: () => '',
        getJournalCards: (s, c) async => const [],
        getGrowthEnabled: () => true,
        getReviewFirst: () => false,
        getIsPassRunning: () => passRunning,
        setIsPassRunning: (v) => passRunning = v,
        refreshCache: () =>
            store.refresh('s1', charIds: ['mira'], activeCharId: 'mira'),
        onNotify: () {},
      );
    }

    setUp(() async {
      db = AppDatabase.forTesting(sameIsolate: true);
      store = GrowthStore(getDb: () => db);
      passRunning = false;
      xmlReply = null;
      await db.insertSession(SessionsCompanion.insert(id: 's1'));
    });

    tearDown(() async => db.close());

    test(
      'forced Check on a caught-up cursor cannot reinforce already-read messages',
      () async {
        await store.addRing(
          sessionId: 's1',
          characterId: 'mira',
          content: 'tightens bonds when exhausted',
          category: 'habit',
          strength: 0.55,
          sourcePositions: const [1],
        );
        await store.setCursor('s1', chatty.length);
        xmlReply = '<ring action="reinforce" id="1" src="3"/>';
        await makeService(messages: chatty).runGrowthPass(force: true);
        final ring = (await store.ringsFor('s1', 'mira')).single;
        expect(ring.strength, closeTo(0.55, 1e-9));
        expect(GrowthStore.receiptsOf(ring), [1]);
      },
    );

    test(
      'forced Check still adds new rings but does not fade the others',
      () async {
        await store.addRing(
          sessionId: 's1',
          characterId: 'mira',
          content: 'existing ring',
          category: 'trait',
          strength: 0.5,
        );
        await store.setCursor('s1', chatty.length);
        xmlReply = '<ring action="add">Learned on the re-check</ring>';
        await makeService(messages: chatty).runGrowthPass(force: true);
        final rings = await store.ringsFor('s1', 'mira');
        expect(rings, hasLength(2));
        final old = rings.firstWhere((r) => r.content == 'existing ring');
        expect(old.strength, closeTo(0.5, 1e-9));
      },
    );

    test(
      'a reinforce citing only the ring\'s own receipts is not a new step',
      () async {
        await store.addRing(
          sessionId: 's1',
          characterId: 'mira',
          content: 'existing ring',
          category: 'trait',
          strength: 0.5,
          sourcePositions: const [3],
        );
        xmlReply = '<ring action="reinforce" id="1" src="3"/>';
        await makeService(messages: chatty).runGrowthPass();
        final ring = (await store.ringsFor('s1', 'mira')).single;
        expect(ring.strength, closeTo(0.45, 1e-9));
      },
    );

    test('the pass log names applied adds vs reinforces', () async {
      final logs = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        xmlReply = '<ring action="add" src="1">Grew a little</ring>';
        await makeService(messages: chatty).runGrowthPass();
      } finally {
        debugPrint = previous;
      }
      expect(
        logs,
        contains(
          '[Growth] ✓ Mira: 1 op(s) (+1 add, 0 reinforce, 0 revise, 0 retire)',
        ),
      );
    });

    test(
      'a ring gains at most one reinforce inside one growth interval',
      () async {
        final messages = <ChatMessage>[
          for (var i = 0; i < 8; i++)
            _msg(i.isEven ? 'You' : 'Mira', 'line $i', isUser: i.isEven),
        ];
        await store.addRing(
          sessionId: 's1',
          characterId: 'mira',
          content: 'existing habit',
          category: 'habit',
          strength: 0.55,
        );
        xmlReply = '<ring action="reinforce" id="1" src="6"/>';
        final svc = makeService(messages: messages);
        await svc.runGrowthPass();
        expect(
          (await store.ringsFor('s1', 'mira')).single.strength,
          closeTo(0.75, 1e-9),
        );

        messages.addAll([
          for (var i = 8; i < 12; i++)
            _msg(i.isEven ? 'You' : 'Mira', 'line $i', isUser: i.isEven),
        ]);
        xmlReply = '<ring action="reinforce" id="1" src="10"/>';
        await svc.runGrowthPass();
        final held = (await store.ringsFor('s1', 'mira')).single;
        expect(held.strength, closeTo(0.75, 1e-9));
        expect(GrowthStore.receiptsOf(held), [6]);

        messages.addAll([
          for (var i = 12; i < 20; i++)
            _msg(i.isEven ? 'You' : 'Mira', 'line $i', isUser: i.isEven),
        ]);
        xmlReply = '<ring action="reinforce" id="1" src="18"/>';
        await svc.runGrowthPass();
        final later = (await store.ringsFor('s1', 'mira')).single;
        expect(later.strength, closeTo(0.95, 1e-9));
        expect(GrowthStore.receiptsOf(later), [6, 18]);
      },
    );

    test(
      'a full interval of user messages lets the next pass reinforce',
      () async {
        // Cite 8, then ten alternating lines (five of them from the user),
        // then cite 18. Counting transcript slots blocks that step; counting
        // user messages does not.
        final messages = <ChatMessage>[
          for (var i = 0; i <= 18; i++)
            _msg(i.isEven ? 'You' : 'Mira', 'line $i', isUser: i.isEven),
        ];
        await store.addRing(
          sessionId: 's1',
          characterId: 'mira',
          content: 'existing habit',
          category: 'habit',
          strength: 0.55,
          sourcePositions: const [8],
        );
        await store.setCursor('s1', 9);
        xmlReply = '<ring action="reinforce" id="1" src="18"/>';
        await makeService(messages: messages).runGrowthPass();
        final ring = (await store.ringsFor('s1', 'mira')).single;
        expect(ring.strength, closeTo(0.75, 1e-9));
        expect(GrowthStore.receiptsOf(ring), [8, 18]);
      },
    );

    test(
      'a forced Check on a caught-up chat does not reinforce an old cite',
      () async {
        final messages = <ChatMessage>[
          for (var i = 0; i < 20; i++)
            _msg(i.isEven ? 'You' : 'Mira', 'line $i', isUser: i.isEven),
        ];
        await store.addRing(
          sessionId: 's1',
          characterId: 'mira',
          content: 'existing habit',
          category: 'habit',
          strength: 0.55,
          sourcePositions: const [1],
        );
        await store.setCursor('s1', 20);
        xmlReply = '<ring action="reinforce" id="1" src="18"/>';
        await makeService(messages: messages).runGrowthPass(force: true);
        final ring = (await store.ringsFor('s1', 'mira')).single;
        expect(ring.strength, closeTo(0.55, 1e-9));
        expect(GrowthStore.receiptsOf(ring), [1]);
      },
    );

    test('the pass log counts applied adds, not every proposal', () async {
      final cap = GrowthPhysics.kMaxNewRingsPerPass;
      final logs = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        xmlReply = [
          for (var i = 0; i < cap + 2; i++) '<ring action="add">Ring $i</ring>',
        ].join();
        await makeService(messages: chatty).runGrowthPass();
      } finally {
        debugPrint = previous;
      }
      final line = logs.singleWhere((entry) => entry.startsWith('[Growth] ✓'));
      expect(line, startsWith('[Growth] ✓ Mira: $cap op(s) (+$cap add,'));
    });
  });

  test('the growth prompt asks for a new ring, not another reinforce', () {
    final prompt = buildGrowthPrompt(
      ownerName: 'Tess',
      userName: 'You',
      basePersonality: 'Quiet.',
      recap: '',
      activeRings: const [],
      journalCards: const [],
      window: const [],
      windowStart: 0,
      legacyBlob: '',
      toolsMode: false,
    );
    expect(
      prompt,
      contains(
        'Reinforce a ring only when a NEW message in this window shows it '
        'again',
      ),
    );
    expect(
      prompt,
      contains('A different change, even a related one, is a new ring.'),
    );
    expect(
      prompt,
      contains('If nothing durable changed, emit nothing at all.'),
    );
    expect(prompt, isNot(contains('Prefer reinforcing')));
    expect(prompt, isNot(contains('most checks should find no new growth')));

    final reinforce = kGrowthTools
        .map((tool) => tool['function'] as Map<String, dynamic>)
        .firstWhere((fn) => fn['name'] == 'reinforce_ring');
    expect(
      reinforce['description'] as String,
      contains('Cite at least one message from this window.'),
    );
  });
}
