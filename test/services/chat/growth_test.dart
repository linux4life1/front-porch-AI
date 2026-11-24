// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Growth Rings engine tests (docs/design/boons-and-bogies.md): deterministic
// physics (tiers, reinforcement, fade, cap victim, injection prefixes),
// both op transports (XML tags + tool calls) with forgiving parsing, the
// store's DB half (cap trim, receipts merge, fade-to-retire, legacy-blob
// archive/discard, fork copy, cast re-key, cursor), the shared pass-owner
// resolution (1:1 guests grow, journal excludes them), and the pass itself
// (rings from XML, distill migration, cursor advance, review-first parking,
// no-op on empty windows). Mirrors journal_test.dart's factory style: real
// in-memory AppDatabase, fake LLM closures, live cbs.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/growth_bb_pass.dart';
import 'package:front_porch_ai/services/chat/growth_boons_bogies.dart';
import 'package:front_porch_ai/services/chat/growth_ops.dart';
import 'package:front_porch_ai/services/chat/growth_physics.dart';
import 'package:front_porch_ai/services/chat/growth_prompt.dart';
import 'package:front_porch_ai/services/chat/growth_review.dart';
import 'package:front_porch_ai/services/chat/growth_service.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/llm_service.dart'
    show LlmToolCall, LlmToolResponse;
import 'package:drift/drift.dart' show Value;

GrowthRingData _ring({
  String id = 'r1',
  double strength = 0.5,
  bool pinned = false,
  bool retired = false,
  String category = 'trait',
  String? receipts,
  String? metadata,
  int advanceCount = 0,
  int bogeyPressure = 0,
  int bogeyCooldown = 0,
  bool bogeyDelivered = false,
  bool masterDeclined = false,
}) => GrowthRingData(
  id: id,
  sessionId: 's1',
  characterId: 'c1',
  content: 'Has started guarding {{user}}\'s sleep',
  category: category,
  strength: strength,
  pinned: pinned,
  retired: retired,
  sourceMessageIds: receipts,
  createdAt: DateTime(2026),
  lastReinforcedAt: DateTime(2026),
  updatedAt: DateTime(2026),
  metadata: metadata,
  advanceCount: advanceCount,
  bogeyPressure: bogeyPressure,
  bogeyCooldown: bogeyCooldown,
  bogeyDelivered: bogeyDelivered,
  masterDeclined: masterDeclined,
);

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
  group('growthPassIsDue', () {
    test(
      'under interval with no kick does not fire — even on a hot window',
      () {
        expect(
          growthPassIsDue(
            userMessagesSincePass: 1,
            interval: 5,
            kickPending: false,
          ),
          isFalse,
        );
      },
    );

    test('interval due fires without a kick', () {
      expect(
        growthPassIsDue(
          userMessagesSincePass: 5,
          interval: 5,
          kickPending: false,
        ),
        isTrue,
      );
    });

    test(
      'gated kick fires immediately when there is at least one user message',
      () {
        expect(
          growthPassIsDue(
            userMessagesSincePass: 1,
            interval: 5,
            kickPending: true,
          ),
          isTrue,
        );
      },
    );

    test('no user messages never fires, even with a kick', () {
      expect(
        growthPassIsDue(
          userMessagesSincePass: 0,
          interval: 5,
          kickPending: true,
        ),
        isFalse,
      );
    });

    test('tiers derive from strength; established/pinned never fade', () {
      expect(GrowthPhysics.tierOf(_ring(strength: 0.2)), 'emerging');
      expect(GrowthPhysics.tierOf(_ring(strength: 0.5)), 'developing');
      expect(GrowthPhysics.tierOf(_ring(strength: 0.85)), 'established');
      expect(GrowthPhysics.fadedStrength(_ring(strength: 0.85)), 0.85);
      expect(
        GrowthPhysics.fadedStrength(_ring(strength: 0.5, pinned: true)),
        0.5,
      );
      expect(
        GrowthPhysics.fadedStrength(_ring(strength: 0.5)),
        closeTo(0.5 - GrowthPhysics.kFadePerPass, 1e-9),
      );
      expect(GrowthPhysics.reinforced(0.95), 1.0); // clamped
    });

    test(
      'capVictim picks weakest unpinned non-established; null when all protected',
      () {
        final weak = _ring(id: 'weak', strength: 0.31);
        final rings = [
          _ring(id: 'est', strength: 0.9),
          _ring(id: 'pin', strength: 0.1, pinned: true),
          weak,
          _ring(id: 'mid', strength: 0.6),
        ];
        expect(GrowthPhysics.capVictim(rings)!.id, 'weak');
        expect(
          GrowthPhysics.capVictim([
            _ring(id: 'a', strength: 0.9),
            _ring(id: 'b', pinned: true),
          ]),
          isNull,
        );
      },
    );

    test('injectionSelection reserves prompt slots for in-progress growth', () {
      // 8 or fewer active rings: everything injects, no reserve needed.
      final few = [for (var i = 0; i < 5; i++) _ring(id: 'r$i', strength: 0.9)];
      expect(GrowthPhysics.injectionSelection(few), few);

      // A settled cast (10 established) + 2 in-progress: the fresh pair takes
      // the reserved slots instead of being crowded out forever (established
      // rings never fade, so without the reserve the prompt would freeze).
      final est = [
        for (var i = 0; i < 10; i++) _ring(id: 'e$i', strength: 1.0),
      ];
      final fresh = [
        _ring(id: 'dev', strength: 0.5),
        _ring(id: 'new', strength: 0.3),
      ];
      final selected = GrowthPhysics.injectionSelection([...est, ...fresh]);
      expect(selected, hasLength(GrowthPhysics.kInjectedRings));
      expect(selected.map((r) => r.id), containsAll(['dev', 'new']));
      // Strength ordering is preserved: established first, freshest last.
      expect(selected.take(6).map((r) => r.id), [
        'e0',
        'e1',
        'e2',
        'e3',
        'e4',
        'e5',
      ]);
      expect(selected.last.id, 'new');

      // Overflow with no in-progress rings at all: plain top-8 take.
      final all = [
        for (var i = 0; i < 12; i++) _ring(id: 'a$i', strength: 1.0 - i * 0.01),
      ];
      expect(GrowthPhysics.injectionSelection(all).map((r) => r.id), [
        for (var i = 0; i < 8; i++) 'a$i',
      ]);
    });

    test(
      'injection lines get deterministic tier prefixes; names keep their capital',
      () {
        expect(
          GrowthPhysics.injectionLine(_ring(strength: 0.9)),
          'Has started guarding {{user}}\'s sleep',
        );
        expect(
          GrowthPhysics.injectionLine(_ring(strength: 0.5)),
          startsWith('Increasingly, has started'),
        );
        expect(
          GrowthPhysics.injectionLine(_ring(strength: 0.2)),
          startsWith('Lately, has started'),
        );
        // A ring opening with the owner's name is never case-folded.
        final named = _ring(
          strength: 0.2,
        ).copyWith(content: 'Mira hums while cooking');
        expect(
          GrowthPhysics.injectionLine(named, charName: 'Mira'),
          'Lately, Mira hums while cooking',
        );
      },
    );
  });

  group('growth ops — XML transport', () {
    test('parses add/reinforce/revise/retire + bare tag as add', () {
      final ops = parseGrowthOps('''
Some prose the model wrote.
<ring action="add" category="stance" src="12,14">Trusts {{user}} now</ring>
<ring action="reinforce" id="3" src="18"/>
<ring action="revise" id="2">Reworded text</ring>
<ring action="retire" id="1"/>
<ring category="habit">Bare tag counts as add</ring>
''');
      expect(ops, hasLength(5));
      expect(ops[0].action, GrowthOpAction.add);
      expect(ops[0].category, 'stance');
      expect(ops[0].sourcePositions, [12, 14]);
      expect(ops[1].action, GrowthOpAction.reinforce);
      expect(ops[1].handle, 3);
      expect(ops[1].sourcePositions, [18]);
      expect(ops[2].action, GrowthOpAction.revise);
      expect(ops[2].text, 'Reworded text');
      expect(ops[3].action, GrowthOpAction.retire);
      expect(ops[4].action, GrowthOpAction.add);
      expect(ops[4].category, 'habit');
    });

    test(
      'forgiving: unknown categories normalize, garbage yields zero ops',
      () {
        expect(normalizeGrowthCategory('attitude'), 'stance');
        expect(normalizeGrowthCategory('trauma'), 'scar');
        expect(normalizeGrowthCategory('nonsense'), 'trait');
        expect(parseGrowthOps('no tags at all'), isEmpty);
        // Missing handle / empty text ops are dropped, not thrown.
        expect(
          parseGrowthOps('<ring action="retire"/><ring action="add"></ring>'),
          isEmpty,
        );
      },
    );

    test('tool-call transport normalizes to the same ops', () {
      final ops = parseGrowthToolCalls([
        const LlmToolCall(
          name: 'add_ring',
          arguments: {
            'content': 'Learned to read {{user}}\'s silences',
            'category': 'skill',
            'src': [7, '9'],
          },
        ),
        const LlmToolCall(
          name: 'reinforce_ring',
          arguments: {
            'id': '2',
            'src': [11],
          },
        ),
        const LlmToolCall(name: 'retire_ring', arguments: {'id': 1}),
        const LlmToolCall(name: 'unknown_tool', arguments: {}),
      ]);
      expect(ops, hasLength(3));
      expect(ops[0].action, GrowthOpAction.add);
      expect(ops[0].sourcePositions, [7, 9]);
      expect(ops[1].handle, 2);
      expect(ops[2].action, GrowthOpAction.retire);
    });
  });

  group('resolveGrowthMacros', () {
    test(
      'resolves char/user case-insensitively, tolerates spacing, idempotent',
      () {
        expect(
          resolveGrowthMacros(
            '{{char}} trusts {{ USER }} and {{Char}} knows it',
            charName: 'Mira',
            userName: 'Alex',
          ),
          'Mira trusts Alex and Mira knows it',
        );
        // Unknown owner: {{char}} kept (no guessing), {{user}} still resolves.
        expect(
          resolveGrowthMacros('{{char}} met {{user}}', userName: 'Alex'),
          '{{char}} met Alex',
        );
        expect(hasGrowthMacros('plain text'), isFalse);
        expect(hasGrowthMacros('hi {{user}}'), isTrue);
      },
    );
  });

  group('resolvePassOwners (shared with the Journal)', () {
    final host = CharacterCard(name: 'Mira');
    final guest = CharacterCard(name: 'Rook');
    String idOf(CharacterCard c) => c.name.toLowerCase();

    test(
      '1:1 with guests: guests who spoke are owners (growth); journal passes none',
      () {
        final window = [
          _msg('You', 'hi', isUser: true),
          _msg('Rook', 'hello', charId: 'rook'),
        ];
        final withGuests = resolvePassOwners(
          window: window,
          group: null,
          members: const [],
          active: host,
          idOf: idOf,
          guests: [guest],
        );
        expect(withGuests.map((c) => c.name), ['Mira', 'Rook']);
        // Journal-style call (no guests) → host only.
        final journalStyle = resolvePassOwners(
          window: window,
          group: null,
          members: const [],
          active: host,
          idOf: idOf,
        );
        expect(journalStyle.map((c) => c.name), ['Mira']);
        // A guest who did NOT speak in the window is not an owner.
        final silent = resolvePassOwners(
          window: [_msg('You', 'hi', isUser: true)],
          group: null,
          members: const [],
          active: host,
          idOf: idOf,
          guests: [guest],
        );
        expect(silent.map((c) => c.name), ['Mira']);
      },
    );
  });

  group('GrowthStore (real in-memory DB)', () {
    late AppDatabase db;
    late GrowthStore store;

    setUp(() {
      db = AppDatabase.forTesting(sameIsolate: true);
      store = GrowthStore(getDb: () => db);
    });

    tearDown(() async => db.close());

    Future<void> seedSession(String id, {String pers = '', String scen = ''}) =>
        db.insertSession(
          SessionsCompanion.insert(
            id: id,
            evolvedPersonality: Value(pers),
            evolvedScenario: Value(scen),
          ),
        );

    test(
      'cap trim retires the weakest unpinned ring on over-cap insert',
      () async {
        for (var i = 0; i < GrowthPhysics.kMaxActiveRings; i++) {
          await store.addRing(
            sessionId: 's1',
            characterId: 'c1',
            content: 'ring $i',
            category: 'trait',
            strength: 0.3 + i * 0.01,
          );
        }
        await store.addRing(
          sessionId: 's1',
          characterId: 'c1',
          content: 'over cap',
          category: 'trait',
        );
        final rings = await store.ringsFor('s1', 'c1');
        final active = rings.where((r) => !r.retired);
        final retired = rings.where((r) => r.retired);
        expect(active.length, GrowthPhysics.kMaxActiveRings);
        expect(retired.single.content, 'ring 0'); // the weakest
      },
    );

    test(
      'invalidateRingsCitingFrom purges rings that cite rewritten history',
      () async {
        await store.addRing(
          sessionId: 's1',
          characterId: 'c1',
          content: 'cites discarded beat',
          category: 'trait',
          sourcePositions: [10, 12],
        );
        await store.addRing(
          sessionId: 's1',
          characterId: 'c1',
          content: 'manual plant — no receipts',
          category: 'trait',
          sourcePositions: const [],
        );
        await store.addRing(
          sessionId: 's1',
          characterId: 'c1',
          content: 'only older receipts',
          category: 'habit',
          sourcePositions: [2, 3],
        );
        final removed = await store.invalidateRingsCitingFrom('s1', 10);
        expect(removed, 1);
        final left = await store.ringsFor('s1', 'c1');
        expect(left.map((r) => r.content).toSet(), {
          'manual plant — no receipts',
          'only older receipts',
        });
      },
    );

    test(
      'window start caps unconditionally (stuck cursor twin of Journal)',
      () {
        // Calls the same pure helper runGrowthPass uses — a reimplemented
        // formula would stay green if the service drifted (second-look).
        expect(
          growthPassWindowStart(590, 9488),
          9488 - JournalPhysics.kFirstPassCap,
          reason: 'stuck cursor must jump the gap like Journal',
        );
        expect(
          growthPassWindowStart(0, 200),
          200 - JournalPhysics.kFirstPassCap,
          reason: 'virgin long chat still capped',
        );
        expect(
          growthPassWindowStart(5, 20),
          5,
          reason: 'under the cap is unchanged',
        );
      },
    );

    test(
      'reinforce merges receipts and bumps strength; fade retires at zero',
      () async {
        await store.addRing(
          sessionId: 's1',
          characterId: 'c1',
          content: 'young ring',
          category: 'habit',
          sourcePositions: [3],
          strength: GrowthPhysics.kFadePerPass, // one fade from death
        );
        var ring = (await store.ringsFor('s1', 'c1')).single;
        await store.reinforceRing(ring, sourcePositions: [9, 3]);
        ring = (await store.ringsFor('s1', 'c1')).single;
        expect(GrowthStore.receiptsOf(ring), [3, 9]);
        expect(
          ring.strength,
          closeTo(
            GrowthPhysics.kFadePerPass + GrowthPhysics.kReinforceStep,
            1e-9,
          ),
        );

        // Fade it without reinforcement until it dies.
        while (true) {
          final current = (await store.ringsFor('s1', 'c1')).single;
          if (current.retired) break;
          await store.fadeUnreinforced('s1', 'c1', const {});
        }
        expect((await store.ringsFor('s1', 'c1')).single.retired, isTrue);
      },
    );

    test(
      'archiveLegacyBlob writes a pinned retired archive ring and clears the 1:1 columns',
      () async {
        await seedSession(
          's1',
          pers: 'old evolved personality',
          scen: 'old scenario',
        );
        await store.refresh('s1', charIds: ['c1'], activeCharId: 'c1');
        expect(store.legacyBlobFor('s1', 'c1'), isNotNull);

        await store.archiveLegacyBlob('s1', 'c1', isGroup: false);
        final rings = await store.ringsFor('s1', 'c1');
        final archive = rings.single;
        expect(archive.category, GrowthPhysics.kArchiveCategory);
        expect(archive.pinned, isTrue);
        expect(archive.retired, isTrue);
        expect(archive.content, contains('old evolved personality'));
        expect(archive.content, contains('old scenario'));
        final session = await db.getSessionById('s1');
        expect(session!.evolvedPersonality, isEmpty);
        expect(session.evolvedScenario, isEmpty);
        expect(store.legacyBlobFor('s1', 'c1'), isNull);
      },
    );

    test(
      'copySessionTo carries rings + cursor + legacy columns into a fork',
      () async {
        await seedSession('parent', pers: 'legacy text');
        await seedSession('fork');
        await store.addRing(
          sessionId: 'parent',
          characterId: 'c1',
          content: 'carried ring',
          category: 'stance',
          strength: 0.7,
        );
        await store.copySessionTo('parent', 'fork', cursor: 42);
        final copied = await store.ringsFor('fork', 'c1');
        expect(copied.single.content, 'carried ring');
        expect(await store.cursorFor('fork'), 42);
        expect(
          (await db.getSessionById('fork'))!.evolvedPersonality,
          'legacy text',
        );
        // Parent untouched.
        expect((await store.ringsFor('parent', 'c1')).length, 1);
      },
    );

    test(
      'write-time resolution + refresh self-heal fix macro-bearing rings',
      () async {
        final resolving = GrowthStore(
          getDb: () => db,
          resolveMacros: (charId, text) =>
              resolveGrowthMacros(text, charName: 'Mira', userName: 'Alex'),
        );
        await seedSession('s1');
        // Write path: addRing resolves before storing.
        await resolving.addRing(
          sessionId: 's1',
          characterId: 'c1',
          content: '{{char}} leans on {{user}} now',
          category: 'stance',
        );
        expect(
          (await resolving.ringsFor('s1', 'c1')).single.content,
          'Mira leans on Alex now',
        );
        // Self-heal path: a pre-fix ring written with raw macros (direct DB
        // insert bypasses the choke point) gets healed by refresh.
        await db.insertGrowthRing(
          GrowthRingsCompanion(
            sessionId: const Value('s1'),
            characterId: const Value('c1'),
            content: const Value(
              '{{char}} has developed attachment to {{user}}',
            ),
            category: const Value('trait'),
          ),
        );
        await resolving.refresh('s1', charIds: ['c1'], activeCharId: 'c1');
        final healed = resolving.allRingsFor('s1', 'c1');
        expect(healed.any((r) => hasGrowthMacros(r.content)), isFalse);
        expect(
          healed.map((r) => r.content),
          contains('Mira has developed attachment to Alex'),
        );
        // Healed in the DB too, not just the cache.
        final persisted = await db.getGrowthRings('s1', 'c1');
        expect(persisted.any((r) => hasGrowthMacros(r.content)), isFalse);
      },
    );

    test(
      'reassignGrowthRings re-keys an owner within a session (collapse)',
      () async {
        await store.addRing(
          sessionId: 's1',
          characterId: 'member-id',
          content: 'ring',
          category: 'trait',
        );
        await db.reassignGrowthRings('member-id', 'origin-id', sessionId: 's1');
        expect(await store.ringsFor('s1', 'member-id'), isEmpty);
        expect(
          (await store.ringsFor('s1', 'origin-id')).single.content,
          'ring',
        );
      },
    );
  });

  group('GrowthService pass (fake LLM, real DB)', () {
    late AppDatabase db;
    late GrowthStore store;
    late GrowthReview review;
    final host = CharacterCard(
      name: 'Mira',
      personality: 'Wry, guarded, loyal.',
    );
    var passRunning = false;
    var reviewFirst = false;
    String? xmlReply;

    GrowthService makeService({
      List<ChatMessage> messages = const [],
      ToolTransportProbe? probe,
      Future<LlmToolResponse?> Function(String, List<Map<String, dynamic>>)?
      fireToolEval,
    }) {
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
        probe:
            probe ?? (ToolTransportProbe()..markXmlOnly('fake')), // XML direct
        fireLLMEval: (prompt) async => xmlReply,
        fireToolEval: fireToolEval ?? (p, t) async => null,
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
        getReviewFirst: () => reviewFirst,
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
      reviewFirst = false;
      xmlReply = null;
      await db.insertSession(SessionsCompanion.insert(id: 's1'));
    });

    tearDown(() async => db.close());

    final chatty = [
      _msg('You', 'I trust you with this', isUser: true),
      _msg('Mira', 'Then I will not waste it', charId: 'mira'),
      _msg('You', 'thank you', isUser: true),
      _msg('Mira', 'Always', charId: 'mira'),
    ];

    test(
      'XML reply becomes a ring (macros resolved), cursor advances, injection updates',
      () async {
        xmlReply =
            '<ring action="add" category="stance" src="1">{{char}} has stopped testing {{user}}</ring>';
        final svc = makeService(messages: chatty);
        await svc.runGrowthPass();
        final rings = await store.ringsFor('s1', 'mira');
        // {{char}}/{{user}} resolve to real names before the ring is stored —
        // the timeline displays content verbatim (the "{{char}} has developed…"
        // display bug).
        expect(rings.single.content, 'Mira has stopped testing You');
        expect(rings.single.strength, GrowthPhysics.kNewRingStrength);
        expect(await store.cursorFor('s1'), chatty.length);
        expect(
          svc.effectivePersonality(host),
          allOf(
            contains('Wry, guarded, loyal.'),
            contains('[Character Growth'),
            contains('Lately, Mira has stopped testing You'),
          ),
        );
      },
    );

    test(
      'tools transport failure → XML this round, probe left untested',
      () async {
        xmlReply = '<ring action="add">Grew through the glitch</ring>';
        var toolAttempts = 0;
        final probe = ToolTransportProbe(); // untested — tools path armed
        final svc = makeService(
          messages: chatty,
          probe: probe,
          fireToolEval: (p, t) async {
            toolAttempts++;
            // Connection torn down mid-call (e.g. character creation fired an
            // app-wide abortGeneration): a network event, not a capability
            // verdict.
            throw Exception('SocketException: Connection reset by peer');
          },
        );
        await svc.runGrowthPass();
        expect(toolAttempts, 1);
        // The round still landed over the XML fallback…
        expect(
          (await store.ringsFor('s1', 'mira')).single.content,
          'Grew through the glitch',
        );
        // …but the backend was NOT branded XML-only for the run.
        expect(probe.isXmlOnly('fake'), isFalse);
      },
    );

    test(
      'EMPTY tools answer (server-side abort shape) → probe left untested',
      () async {
        xmlReply = '<ring action="add">Survived the abort</ring>';
        final probe = ToolTransportProbe();
        final svc = makeService(
          messages: chatty,
          probe: probe,
          // A KoboldCpp /api/extra/abort completes an in-flight tool call as a
          // clean HTTP 200 with zero tokens and no tool_calls — no exception
          // for the transport classifier. This was the surviving "pill falls
          // off after a Scene Guest joins" hole.
          fireToolEval: (p, t) async =>
              const LlmToolResponse(calls: [], text: ''),
        );
        await svc.runGrowthPass();
        // The round still landed over the XML fallback…
        expect(
          (await store.ringsFor('s1', 'mira')).single.content,
          'Survived the abort',
        );
        // …and the backend was NOT branded: empty is never a verdict.
        expect(probe.isXmlOnly('fake'), isFalse);
      },
    );

    test(
      'prose answer with no tool call and no tags DOES brand XML-only',
      () async {
        xmlReply = '<ring action="add">Prose evidence</ring>';
        final probe = ToolTransportProbe();
        final svc = makeService(
          messages: chatty,
          probe: probe,
          fireToolEval: (p, t) async => const LlmToolResponse(
            calls: [],
            text: 'I would rather just describe their growth in plain words.',
          ),
        );
        await svc.runGrowthPass();
        expect(
          probe.isXmlOnly('fake'),
          isTrue,
          reason: 'words-instead-of-tools is real capability evidence',
        );
      },
    );

    test('empty window (cursor caught up) does not fire; force does', () async {
      xmlReply = '<ring action="add">Bare growth</ring>';
      await store.setCursor('s1', chatty.length);
      final svc = makeService(messages: chatty);
      await svc.runGrowthPass();
      expect(await store.ringsFor('s1', 'mira'), isEmpty);
      await svc.runGrowthPass(force: true);
      expect(await store.ringsFor('s1', 'mira'), hasLength(1));
    });

    test('add cap holds even when the model floods (non-distill: 2)', () async {
      xmlReply = List.generate(
        5,
        (i) => '<ring action="add">Flood ring $i</ring>',
      ).join('\n');
      await makeService(messages: chatty).runGrowthPass();
      final rings = await store.ringsFor('s1', 'mira');
      expect(rings.length, GrowthPhysics.kMaxNewRingsPerPass);
    });

    test(
      'distill: legacy blob raises the cap, seeds developing, archives + clears',
      () async {
        await db.patchSession(
          SessionsCompanion(
            id: const Value('s1'),
            evolvedPersonality: const Value('She grew braver over many chats.'),
          ),
        );
        xmlReply =
            '<ring action="add" category="trait">Braver than she was</ring>'
            '<ring action="add" category="stance">Leans on {{user}} now</ring>'
            '<ring action="add" category="habit">Hums while cooking</ring>';
        await makeService(messages: chatty).runGrowthPass();
        final rings = await store.ringsFor('s1', 'mira');
        final active = rings.where((r) => !r.retired).toList();
        final archive = rings.where((r) => r.retired).toList();
        expect(active, hasLength(3)); // above the normal 2-cap
        expect(
          active.every((r) => r.strength == GrowthPhysics.kDistillSeedStrength),
          isTrue,
        );
        expect(archive.single.category, GrowthPhysics.kArchiveCategory);
        expect((await db.getSessionById('s1'))!.evolvedPersonality, isEmpty);
      },
    );

    test(
      'review-first parks instead of applying; apply commits, cursor moves',
      () async {
        reviewFirst = true;
        xmlReply =
            '<ring action="add" category="scar">Flinches at slammed doors</ring>';
        final svc = makeService(messages: chatty);
        await svc.runGrowthPass();
        expect(
          await store.ringsFor('s1', 'mira'),
          isEmpty,
        ); // parked, not applied
        expect(review.hasPendingFor('s1'), isTrue);
        expect(await store.cursorFor('s1'), 0); // cursor waits for the user

        // A second auto pass is blocked while the batch is parked.
        await svc.runGrowthPass();
        expect(review.pending!.totalProposals, 1);

        await review.apply();
        expect(
          (await store.ringsFor('s1', 'mira')).single.content,
          'Flinches at slammed doors',
        );
        expect(await store.cursorFor('s1'), chatty.length);
      },
    );

    test(
      'reinforce op strengthens the handled ring and exempts it from fade',
      () async {
        await store.addRing(
          sessionId: 's1',
          characterId: 'mira',
          content: 'existing ring',
          category: 'trait',
          strength: 0.5,
        );
        xmlReply = '<ring action="reinforce" id="1" src="3"/>';
        await makeService(messages: chatty).runGrowthPass();
        final ring = (await store.ringsFor('s1', 'mira')).single;
        // +0.20 reinforce, no -0.05 fade (engaged rings are exempt).
        expect(ring.strength, closeTo(0.7, 1e-9));
        expect(GrowthStore.receiptsOf(ring), [3]);
      },
    );

    test('retire op is refused for user-pinned rings', () async {
      await store.addRing(
        sessionId: 's1',
        characterId: 'mira',
        content: 'pinned ring',
        category: 'trait',
        strength: 0.5,
        pinned: true,
      );
      xmlReply = '<ring action="retire" id="1"/>';
      await makeService(messages: chatty).runGrowthPass();
      final ring = (await store.ringsFor('s1', 'mira')).single;
      expect(ring.retired, isFalse); // pinned = permanent; diary UI only
    });

    test('LLM failure leaves cursor unmoved (auto-retry semantics)', () async {
      xmlReply = null;
      await makeService(messages: chatty).runGrowthPass();
      expect(await store.cursorFor('s1'), 0);
      expect(passRunning, isFalse); // finally released the guard
    });
  });

  // ── Boons & Bogies (docs/design/boons-and-bogies.md phase 2) ──────────

  group('Boons & Bogies physics', () {
    GrowthRingData bb({
      String id = 'bb1',
      String category = 'skill',
      String? metadata,
      double strength = 0.5,
      int advance = 0,
      bool pinned = false,
      String content = 'Moves through a guarded room unseen',
    }) => GrowthRingData(
      id: id,
      sessionId: 's1',
      characterId: 'c1',
      content: content,
      category: category,
      strength: strength,
      pinned: pinned,
      retired: false,
      createdAt: DateTime(2026),
      lastReinforcedAt: DateTime(2026),
      updatedAt: DateTime(2026),
      metadata: metadata,
      advanceCount: advance,
      bogeyPressure: 0,
      bogeyCooldown: 0,
      bogeyDelivered: false,
      masterDeclined: false,
    );

    test('a boon is a tagged skill; a plain skill stays ordinary', () {
      final boon = bb(metadata: BoonsBogies.boonMetadata());
      expect(BoonsBogies.isBoon(boon), isTrue);
      expect(BoonsBogies.isBogey(boon), isFalse);
      expect(BoonsBogies.isBoon(bb()), isFalse);
      expect(
        BoonsBogies.isBoon(
          bb(category: 'trait', metadata: BoonsBogies.boonMetadata()),
        ),
        isFalse,
      );
    });

    test('boon tiers require both used passes and strength', () {
      String tier(int passes, double strength) => BoonsBogies.tierOf(
        bb(
          metadata: BoonsBogies.boonMetadata(),
          advance: passes,
          strength: strength,
        ),
      );
      expect(tier(2, 0.9), 'novice');
      expect(tier(3, 0.4), 'novice');
      expect(tier(3, 0.5), 'skilled');
      // Master is held one step below until the milestone surface ships.
      expect(tier(8, 0.9), 'skilled');
    });

    test('bogey tiers are fire-count only and Master is held', () {
      String tier(int fires) => BoonsBogies.tierOf(
        bb(
          category: 'bogey',
          metadata: BoonsBogies.bogeyMetadata(),
          advance: fires,
        ),
      );
      expect(tier(3), 'novice');
      expect(tier(4), 'skilled');
      expect(tier(11), 'skilled');
      expect(tier(12), 'skilled'); // guard until the milestone surface
    });

    test('bogey strength follows the fire count, clamped', () {
      expect(BoonsBogies.bogeyStrength(0), closeTo(0.30, 1e-9));
      expect(BoonsBogies.bogeyStrength(4), closeTo(0.50, 1e-9));
      expect(BoonsBogies.bogeyStrength(12), closeTo(0.90, 1e-9));
      expect(BoonsBogies.bogeyStrength(40), closeTo(0.90, 1e-9));
    });

    test('advance counters stop one below Master before the surface ships', () {
      expect(BoonsBogies.nextBoonAdvance(2), 3);
      expect(BoonsBogies.nextBoonAdvance(7), 7);
      expect(BoonsBogies.nextBogeyAdvance(11), 11);
      expect(BoonsBogies.fadedBogeyAdvance(0), 0);
      expect(BoonsBogies.fadedBogeyAdvance(3), 2);
    });

    test('the undo snapshot round-trips strength, count and text', () {
      final before = bb(
        metadata: BoonsBogies.boonMetadata(),
        strength: 0.7,
        advance: 3,
        content: 'Picks a lock by feel',
      );
      final withUndo = bb(
        metadata: BoonsBogies.metadataWithUndo(before, at: 12),
        strength: 0.7,
        advance: 3,
        content: 'Picks a lock by feel',
      );
      final undo = BoonsBogies.undoOf(withUndo)!;
      expect(undo.strength, 0.7);
      expect(undo.advance, 3);
      expect(undo.text, 'Picks a lock by feel');
      expect(undo.at, 12);
      expect(BoonsBogies.kindOf(withUndo), 'boon'); // kind survives
      expect(
        BoonsBogies.undoOf(
          bb(metadata: BoonsBogies.metadataWithoutUndo(withUndo)),
        ),
        isNull,
      );
    });

    test('the chat injection drops bogeys — the roll is the only door', () {
      final rings = [
        bb(id: 'boon'),
        bb(
          id: 'flaw',
          category: 'bogey',
          metadata: BoonsBogies.bogeyMetadata(),
        ),
      ];
      expect(GrowthPhysics.injectionSelection(rings).map((r) => r.id), [
        'boon',
      ]);
    });
  });

  group('Boons & Bogies transport + prompt', () {
    test('a bogey parses from XML and aliases normalize to it', () {
      final ops = parseGrowthOps(
        '<ring action="add" category="bogey" src="5">Flinches at fire</ring>',
      );
      expect(ops.single.category, 'bogey');
      expect(normalizeGrowthCategory('flaw'), 'bogey');
      expect(normalizeGrowthCategory('weakness'), 'bogey');
      expect(normalizeGrowthCategory('something-new'), 'trait');
    });

    test('the tool schema offers the bogey category', () {
      final add = kGrowthTools.first['function']! as Map<String, dynamic>;
      final params = add['parameters']! as Map<String, dynamic>;
      final props = params['properties']! as Map<String, dynamic>;
      final category = props['category']! as Map<String, dynamic>;
      expect(category['enum'], contains('bogey'));
    });

    String prompt({required bool boonsBogies}) => buildGrowthPrompt(
      ownerName: 'Mira',
      userName: 'Sam',
      basePersonality: 'Quiet.',
      recap: '',
      activeRings: const [],
      journalCards: const [],
      window: [_msg('Sam', 'hello', isUser: true)],
      windowStart: 0,
      legacyBlob: '',
      toolsMode: false,
      boonsBogies: boonsBogies,
    );

    test('the prompt asks for bogeys only when the feature is on', () {
      expect(prompt(boonsBogies: false), isNot(contains('bogey')));
      final on = prompt(boonsBogies: true);
      expect(on, contains('bogey'));
      expect(on, contains('Never reinforce a bogey'));
      expect(on, contains('Never retire a bogey'));
    });
  });

  group('Boons & Bogies applier (real DB)', () {
    late AppDatabase db;
    late GrowthStore store;
    late GrowthReview review;
    var boonsBogiesOn = true;

    setUp(() {
      db = AppDatabase.forTesting(sameIsolate: true);
      store = GrowthStore(getDb: () => db);
      boonsBogiesOn = true;
      review = GrowthReview(
        store: store,
        getSessionId: () => 's1',
        getIsGroup: () => false,
        getBoonsBogiesEnabled: () => boonsBogiesOn,
        onApplied: () async {},
        onNotify: () {},
      );
    });

    tearDown(() async => db.close());

    GrowthOwnerProposals owner(List<GrowthProposedOp> ops) =>
        GrowthOwnerProposals(ownerId: 'c1', ownerName: 'Mira', ops: ops);

    Future<GrowthRingData> seed({
      required String category,
      required String content,
      String? metadata,
      double strength = 0.5,
      int advance = 0,
      bool pinned = false,
    }) async {
      await store.addRing(
        sessionId: 's1',
        characterId: 'c1',
        content: content,
        category: category,
        strength: strength,
        pinned: pinned,
        metadata: metadata,
      );
      final ring = (await store.ringsFor(
        's1',
        'c1',
      )).firstWhere((r) => r.content == content);
      if (advance > 0) {
        await db.updateGrowthRing(
          ring.id,
          GrowthRingsCompanion(advanceCount: Value(advance)),
        );
      }
      return (await store.ringsFor(
        's1',
        'c1',
      )).firstWhere((r) => r.content == content);
    }

    test('a new skill becomes a tagged boon while the feature is on', () async {
      await review.applyOwnerProposals(
        's1',
        owner([
          GrowthProposedOp(
            action: GrowthOpAction.add,
            category: 'skill',
            text: 'Reads a lock by feel in the dark',
          ),
        ]),
      );
      final ring = (await store.ringsFor('s1', 'c1')).single;
      expect(BoonsBogies.isBoon(ring), isTrue);
    });

    test('with the feature off a new skill stays an ordinary ring', () async {
      boonsBogiesOn = false;
      await review.applyOwnerProposals(
        's1',
        owner([
          GrowthProposedOp(
            action: GrowthOpAction.add,
            category: 'skill',
            text: 'Reads a lock by feel in the dark',
          ),
        ]),
      );
      final ring = (await store.ringsFor('s1', 'c1')).single;
      expect(BoonsBogies.isBoon(ring), isFalse);
    });

    test('the fourth active bogey is dropped, not trimmed', () async {
      for (var i = 0; i < BoonsBogies.kMaxActiveBogies; i++) {
        await seed(
          category: 'bogey',
          content: 'flaw $i',
          metadata: BoonsBogies.bogeyMetadata(),
        );
      }
      await review.applyOwnerProposals(
        's1',
        owner([
          GrowthProposedOp(
            action: GrowthOpAction.add,
            category: 'bogey',
            text: 'A fourth flaw',
          ),
        ]),
      );
      final rings = await store.ringsFor('s1', 'c1');
      expect(
        rings.where(BoonsBogies.isBogey).length,
        BoonsBogies.kMaxActiveBogies,
      );
      expect(rings.any((r) => r.content == 'A fourth flaw'), isFalse);
    });

    test('a boon advances once per pass even with two reinforces', () async {
      final ring = await seed(
        category: 'skill',
        content: 'Shadow Step',
        metadata: BoonsBogies.boonMetadata(),
        strength: 0.5,
        advance: 2,
      );
      await review.applyOwnerProposals(
        's1',
        owner([
          GrowthProposedOp(
            action: GrowthOpAction.reinforce,
            ringId: ring.id,
            sourcePositions: [3],
          ),
          GrowthProposedOp(
            action: GrowthOpAction.reinforce,
            ringId: ring.id,
            sourcePositions: [4],
          ),
        ]),
      );
      final after = (await store.ringsFor('s1', 'c1')).single;
      expect(after.advanceCount, 3);
      expect(BoonsBogies.undoOf(after), isNotNull);
    });

    test('a bogey reinforce raises the count and derives strength', () async {
      final ring = await seed(
        category: 'bogey',
        content: 'Clumsy with anything breakable',
        metadata: BoonsBogies.bogeyMetadata(),
        strength: 0.40,
        advance: 2,
      );
      await review.applyOwnerProposals(
        's1',
        owner([
          GrowthProposedOp(
            action: GrowthOpAction.reinforce,
            ringId: ring.id,
            sourcePositions: [7],
          ),
        ]),
      );
      final after = (await store.ringsFor('s1', 'c1')).single;
      expect(after.advanceCount, 3);
      expect(after.strength, closeTo(0.45, 1e-9));
    });

    test('silence holds a bogey; a cited cope lowers an unpinned one '
        '(floor 0)', () async {
      final ring = await seed(
        category: 'bogey',
        content: 'Afraid of heights',
        metadata: BoonsBogies.bogeyMetadata(),
        strength: 0.45,
        advance: 3,
      );
      // Absence is not coping (§3 amendment, #764): a pass that said
      // nothing about the flaw leaves it exactly as it was.
      await store.fadeUnreinforced('s1', 'c1', const {});
      final held = (await store.ringsFor('s1', 'c1')).single;
      expect(held.advanceCount, 3);
      expect(held.strength, closeTo(0.45, 1e-9));
      // A coping verdict wears it down one step, with an undo snapshot.
      await store.bogeys.cope('s1', 'c1', {ring.id});
      final after = (await store.ringsFor('s1', 'c1')).single;
      expect(after.advanceCount, 2);
      expect(after.strength, closeTo(0.40, 1e-9));
      expect(BoonsBogies.undoOf(after), isNotNull);
      // A pinned bogey never fades.
      await db.updateGrowthRing(
        ring.id,
        const GrowthRingsCompanion(pinned: Value(true)),
      );
      await store.bogeys.cope('s1', 'c1', {ring.id});
      final pinned = (await store.ringsFor('s1', 'c1')).single;
      expect(pinned.advanceCount, 2);
    });

    test('undo restores strength, count and text together', () async {
      final ring = await seed(
        category: 'skill',
        content: 'Picks a lock by feel',
        metadata: BoonsBogies.boonMetadata(),
        strength: 0.5,
        advance: 2,
      );
      await review.applyOwnerProposals(
        's1',
        owner([
          GrowthProposedOp(
            action: GrowthOpAction.revise,
            ringId: ring.id,
            text: 'Picks any lock by feel',
          ),
        ]),
      );
      final revised = (await store.ringsFor('s1', 'c1')).single;
      expect(revised.content, 'Picks any lock by feel');
      expect(await review.undoBoonBogey('s1', 'c1', ring.id), isTrue);
      final restored = (await store.ringsFor('s1', 'c1')).single;
      expect(restored.content, 'Picks a lock by feel');
      expect(restored.strength, closeTo(0.5, 1e-9));
      expect(restored.advanceCount, 2);
      expect(BoonsBogies.undoOf(restored), isNull);
    });

    test('the model cannot retire a bogey (overcome asks first)', () async {
      final ring = await seed(
        category: 'bogey',
        content: 'Cannot resist showing off',
        metadata: BoonsBogies.bogeyMetadata(),
      );
      await review.applyOwnerProposals(
        's1',
        owner([
          GrowthProposedOp(action: GrowthOpAction.retire, ringId: ring.id),
        ]),
      );
      final after = (await store.ringsFor('s1', 'c1')).single;
      expect(after.retired, isFalse);
    });
  });

  group('Boons & Bogies coping verdict — transport (#764)', () {
    test('a cope tag parses on its own reader; the ring ops reader '
        'ignores it', () {
      const raw =
          '<ring action="cope" id="2" src="7"/>'
          '<ring action="reinforce" id="1" src="7"/>';
      final copes = parseGrowthCopes(raw);
      expect(copes.single.handle, 2);
      expect(copes.single.sourcePositions, [7]);
      expect(parseGrowthOps(raw).single.action, GrowthOpAction.reinforce);
    });

    test('the cope tool parses into the same verdict', () {
      final copes = parseGrowthToolCopes(const [
        LlmToolCall(
          name: 'cope_with_ring',
          arguments: {
            'id': 3,
            'src': [4, 5],
          },
        ),
        LlmToolCall(name: 'retire_ring', arguments: {'id': 1}),
      ]);
      expect(copes.single.handle, 3);
      expect(copes.single.sourcePositions, [4, 5]);
    });
  });

  group('Boons & Bogies in a Growth pass (fake LLM, real DB)', () {
    late AppDatabase db;
    late GrowthStore store;
    var bbOn = true;
    String? xmlReply;
    var lastPrompt = '';
    final host = CharacterCard(name: 'Mira', personality: 'Wry, guarded.');
    final chatty = [
      _msg('You', 'Hold the ladder for me?', isUser: true),
      _msg('Mira', 'She steadies it and climbs anyway', charId: 'mira'),
      _msg('You', 'thank you', isUser: true),
      _msg('Mira', 'Always', charId: 'mira'),
    ];

    setUp(() async {
      db = AppDatabase.forTesting(sameIsolate: true);
      store = GrowthStore(getDb: () => db);
      bbOn = true;
      xmlReply = null;
      lastPrompt = '';
      await db.insertSession(SessionsCompanion.insert(id: 's1'));
    });

    tearDown(() async => db.close());

    GrowthService makeService() {
      var running = false;
      final review = GrowthReview(
        store: store,
        getSessionId: () => 's1',
        getIsGroup: () => false,
        getBoonsBogiesEnabled: () => true,
        onApplied: () async {},
        onNotify: () {},
      );
      return GrowthService(
        store: store,
        review: review,
        probe: ToolTransportProbe()..markXmlOnly('fake'),
        fireLLMEval: (prompt) async {
          lastPrompt = prompt;
          return xmlReply;
        },
        fireToolEval: (p, t) async => null,
        stripThinkBlocks: (t) => t,
        getBackendIdentity: () => 'fake',
        getSessionId: () => 's1',
        getActiveCharacter: () => host,
        getActiveGroup: () => null,
        getGroupCharacters: () => const [],
        getSceneGuestCards: () => const [],
        getCharacterIdFromCard: (c) => c.name.toLowerCase(),
        getMessages: () => chatty,
        getUserName: () => 'You',
        getRecap: () => '',
        getJournalCards: (s, c) async => const [],
        getGrowthEnabled: () => true,
        getReviewFirst: () => false,
        getIsPassRunning: () => running,
        setIsPassRunning: (v) => running = v,
        refreshCache: () =>
            store.refresh('s1', charIds: ['mira'], activeCharId: 'mira'),
        onNotify: () {},
        getBoonsBogiesEnabled: () => true,
        getBbEnabledFor: (_) => bbOn,
      );
    }

    Future<GrowthRingData> seed(
      String content, {
      String category = 'trait',
      String? metadata,
      double strength = 0.5,
      int advance = 0,
    }) async {
      await store.addRing(
        sessionId: 's1',
        characterId: 'mira',
        content: content,
        category: category,
        strength: strength,
        metadata: metadata,
      );
      final ring = (await store.ringsFor(
        's1',
        'mira',
      )).firstWhere((r) => r.content == content);
      if (advance > 0) {
        await db.updateGrowthRing(
          ring.id,
          GrowthRingsCompanion(advanceCount: Value(advance)),
        );
      }
      return ring;
    }

    Future<GrowthRingData> ring(String content) async => (await store.ringsFor(
      's1',
      'mira',
    )).firstWhere((r) => r.content == content);

    /// The `[N]` handle the prompt gave [content] — handles are what the
    /// model writes back.
    int handleOf(String content) {
      final m = RegExp(
        r'\[(\d+)\] \([^)]*\) ' + RegExp.escape(content),
      ).firstMatch(lastPrompt);
      return int.parse(m!.group(1)!);
    }

    test('silence holds a bogey; only a cope citing this window wears one '
        'down', () async {
      await seed(
        'Freezes on ladders',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
        strength: 0.45,
        advance: 3,
      );
      await seed(
        'Hoards spare keys',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
        strength: 0.45,
        advance: 3,
      );
      await seed(
        'Snaps when tired',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
        strength: 0.45,
        advance: 3,
      );
      // Handles are 1-based positions in the list the pass shows the model.
      final shown = growthBbView(
        await store.ringsFor('s1', 'mira'),
        bbOn: true,
      ).shown;
      int handle(String content) =>
          shown.indexWhere((r) => r.content == content) + 1;
      xmlReply =
          '<ring action="cope" id="${handle('Freezes on ladders')}" src="1"/>'
          '<ring action="cope" id="${handle('Snaps when tired')}" src="99"/>';
      await makeService().runGrowthPass(force: true);
      expect(lastPrompt, contains('action="cope"'));
      expect(
        handleOf('Freezes on ladders'),
        handle('Freezes on ladders'),
        reason: 'the prompt numbered the rings as the test did',
      );

      expect(
        (await ring('Freezes on ladders')).advanceCount,
        2,
        reason: 'a cited cope inside the window wears the flaw down',
      );
      expect(
        (await ring('Hoards spare keys')).advanceCount,
        3,
        reason: 'silence is "not offered" and holds',
      );
      expect(
        (await ring('Snaps when tired')).advanceCount,
        3,
        reason: 'a cope citing no message in this window is not evidence',
      );
    });

    test('an opted-out owner: ordinary rings still grow; boons and bogies '
        'freeze and none are added', () async {
      bbOn = false;
      await seed('Trusts slowly', strength: 0.5);
      await seed(
        'Picks any lock',
        category: 'skill',
        metadata: BoonsBogies.boonMetadata(),
        strength: 0.5,
        advance: 2,
      );
      await seed(
        'Freezes on ladders',
        category: 'bogey',
        metadata: BoonsBogies.bogeyMetadata(),
        strength: 0.45,
        advance: 3,
      );
      xmlReply =
          '<ring action="reinforce" id="1" src="1"/>'
          '<ring action="add" category="bogey" src="1">Flinches at noise</ring>'
          '<ring action="add" category="skill" src="1">Rides well</ring>';
      await makeService().runGrowthPass(force: true);

      expect(lastPrompt, isNot(contains('Picks any lock')));
      expect(lastPrompt, isNot(contains('Freezes on ladders')));
      expect(lastPrompt, isNot(contains('bogey')));
      expect(
        (await ring('Trusts slowly')).strength,
        greaterThan(0.5),
        reason: 'ruling 10: ordinary rings keep their physics',
      );
      final boon = await ring('Picks any lock');
      expect(boon.strength, closeTo(0.5, 1e-9), reason: 'frozen: no fade');
      expect(boon.advanceCount, 2);
      expect((await ring('Freezes on ladders')).advanceCount, 3);
      final rings = await store.ringsFor('s1', 'mira');
      expect(rings.where((r) => r.content == 'Flinches at noise'), isEmpty);
      final skill = rings.firstWhere((r) => r.content == 'Rides well');
      expect(BoonsBogies.isBoon(skill), isFalse);
    });
  });
}
