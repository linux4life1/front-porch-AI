// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Growth Rings engine tests (docs/design/growth-rings.md): deterministic
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
import 'package:front_porch_ai/services/chat/growth_ops.dart';
import 'package:front_porch_ai/services/chat/growth_physics.dart';
import 'package:front_porch_ai/services/chat/growth_review.dart';
import 'package:front_porch_ai/services/chat/growth_service.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/llm_service.dart' show LlmToolCall;
import 'package:drift/drift.dart' show Value;

GrowthRingData _ring({
  String id = 'r1',
  double strength = 0.5,
  bool pinned = false,
  bool retired = false,
  String category = 'trait',
  String? receipts,
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
  metadata: null,
);

ChatMessage _msg(String sender, String text, {bool isUser = false, String? charId}) =>
    ChatMessage(text: text, sender: sender, isUser: isUser, characterId: charId);

void main() {
  group('GrowthPhysics', () {
    test('tiers derive from strength; established/pinned never fade', () {
      expect(GrowthPhysics.tierOf(_ring(strength: 0.2)), 'emerging');
      expect(GrowthPhysics.tierOf(_ring(strength: 0.5)), 'developing');
      expect(GrowthPhysics.tierOf(_ring(strength: 0.85)), 'established');
      expect(GrowthPhysics.fadedStrength(_ring(strength: 0.85)), 0.85);
      expect(GrowthPhysics.fadedStrength(_ring(strength: 0.5, pinned: true)), 0.5);
      expect(
        GrowthPhysics.fadedStrength(_ring(strength: 0.5)),
        closeTo(0.5 - GrowthPhysics.kFadePerPass, 1e-9),
      );
      expect(GrowthPhysics.reinforced(0.95), 1.0); // clamped
    });

    test('capVictim picks weakest unpinned non-established; null when all protected', () {
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
    });

    test('injectionSelection reserves prompt slots for in-progress growth', () {
      // 8 or fewer active rings: everything injects, no reserve needed.
      final few = [for (var i = 0; i < 5; i++) _ring(id: 'r$i', strength: 0.9)];
      expect(GrowthPhysics.injectionSelection(few), few);

      // A settled cast (10 established) + 2 in-progress: the fresh pair takes
      // the reserved slots instead of being crowded out forever (established
      // rings never fade, so without the reserve the prompt would freeze).
      final est = [for (var i = 0; i < 10; i++) _ring(id: 'e$i', strength: 1.0)];
      final fresh = [
        _ring(id: 'dev', strength: 0.5),
        _ring(id: 'new', strength: 0.3),
      ];
      final selected = GrowthPhysics.injectionSelection([...est, ...fresh]);
      expect(selected, hasLength(GrowthPhysics.kInjectedRings));
      expect(selected.map((r) => r.id), containsAll(['dev', 'new']));
      // Strength ordering is preserved: established first, freshest last.
      expect(selected.take(6).map((r) => r.id), ['e0', 'e1', 'e2', 'e3', 'e4', 'e5']);
      expect(selected.last.id, 'new');

      // Overflow with no in-progress rings at all: plain top-8 take.
      final all = [
        for (var i = 0; i < 12; i++) _ring(id: 'a$i', strength: 1.0 - i * 0.01),
      ];
      expect(
        GrowthPhysics.injectionSelection(all).map((r) => r.id),
        [for (var i = 0; i < 8; i++) 'a$i'],
      );
    });

    test('injection lines get deterministic tier prefixes; names keep their capital', () {
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
      final named = _ring(strength: 0.2).copyWith(
        content: 'Mira hums while cooking',
      );
      expect(
        GrowthPhysics.injectionLine(named, charName: 'Mira'),
        'Lately, Mira hums while cooking',
      );
    });
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

    test('forgiving: unknown categories normalize, garbage yields zero ops', () {
      expect(normalizeGrowthCategory('attitude'), 'stance');
      expect(normalizeGrowthCategory('trauma'), 'scar');
      expect(normalizeGrowthCategory('nonsense'), 'trait');
      expect(parseGrowthOps('no tags at all'), isEmpty);
      // Missing handle / empty text ops are dropped, not thrown.
      expect(parseGrowthOps('<ring action="retire"/><ring action="add"></ring>'), isEmpty);
    });

    test('tool-call transport normalizes to the same ops', () {
      final ops = parseGrowthToolCalls([
        const LlmToolCall(name: 'add_ring', arguments: {
          'content': 'Learned to read {{user}}\'s silences',
          'category': 'skill',
          'src': [7, '9'],
        }),
        const LlmToolCall(name: 'reinforce_ring', arguments: {'id': '2', 'src': [11]}),
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
    test('resolves char/user case-insensitively, tolerates spacing, idempotent', () {
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
    });
  });

  group('resolvePassOwners (shared with the Journal)', () {
    final host = CharacterCard(name: 'Mira');
    final guest = CharacterCard(name: 'Rook');
    String idOf(CharacterCard c) => c.name.toLowerCase();

    test('1:1 with guests: guests who spoke are owners (growth); journal passes none', () {
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
    });
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

    test('cap trim retires the weakest unpinned ring on over-cap insert', () async {
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
    });

    test('reinforce merges receipts and bumps strength; fade retires at zero', () async {
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
      expect(ring.strength, closeTo(GrowthPhysics.kFadePerPass + GrowthPhysics.kReinforceStep, 1e-9));

      // Fade it without reinforcement until it dies.
      while (true) {
        final current = (await store.ringsFor('s1', 'c1')).single;
        if (current.retired) break;
        await store.fadeUnreinforced('s1', 'c1', const {});
      }
      expect((await store.ringsFor('s1', 'c1')).single.retired, isTrue);
    });

    test('archiveLegacyBlob writes a pinned retired archive ring and clears the 1:1 columns', () async {
      await seedSession('s1', pers: 'old evolved personality', scen: 'old scenario');
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
    });

    test('copySessionTo carries rings + cursor + legacy columns into a fork', () async {
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
      expect((await db.getSessionById('fork'))!.evolvedPersonality, 'legacy text');
      // Parent untouched.
      expect((await store.ringsFor('parent', 'c1')).length, 1);
    });

    test('write-time resolution + refresh self-heal fix macro-bearing rings', () async {
      final resolving = GrowthStore(
        getDb: () => db,
        resolveMacros: (charId, text) => resolveGrowthMacros(
          text,
          charName: 'Mira',
          userName: 'Alex',
        ),
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
          content: const Value('{{char}} has developed attachment to {{user}}'),
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
    });

    test('reassignGrowthRings re-keys an owner within a session (collapse)', () async {
      await store.addRing(
        sessionId: 's1',
        characterId: 'member-id',
        content: 'ring',
        category: 'trait',
      );
      await db.reassignGrowthRings('member-id', 'origin-id', sessionId: 's1');
      expect(await store.ringsFor('s1', 'member-id'), isEmpty);
      expect((await store.ringsFor('s1', 'origin-id')).single.content, 'ring');
    });
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
        probe: ToolTransportProbe()..markXmlOnly('fake'), // XML path directly
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
        getReviewFirst: () => reviewFirst,
        getIsPassRunning: () => passRunning,
        setIsPassRunning: (v) => passRunning = v,
        refreshCache: () => store.refresh(
          's1',
          charIds: ['mira'],
          activeCharId: 'mira',
        ),
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

    test('XML reply becomes a ring (macros resolved), cursor advances, injection updates', () async {
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
    });

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

    test('distill: legacy blob raises the cap, seeds developing, archives + clears', () async {
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
    });

    test('review-first parks instead of applying; apply commits, cursor moves', () async {
      reviewFirst = true;
      xmlReply = '<ring action="add" category="scar">Flinches at slammed doors</ring>';
      final svc = makeService(messages: chatty);
      await svc.runGrowthPass();
      expect(await store.ringsFor('s1', 'mira'), isEmpty); // parked, not applied
      expect(review.hasPendingFor('s1'), isTrue);
      expect(await store.cursorFor('s1'), 0); // cursor waits for the user

      // A second auto pass is blocked while the batch is parked.
      await svc.runGrowthPass();
      expect(review.pending!.totalProposals, 1);

      await review.apply();
      expect((await store.ringsFor('s1', 'mira')).single.content,
          'Flinches at slammed doors');
      expect(await store.cursorFor('s1'), chatty.length);
    });

    test('reinforce op strengthens the handled ring and exempts it from fade', () async {
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
    });

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
}
