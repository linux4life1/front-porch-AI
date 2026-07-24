// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for The Journal (docs/design/journal-memory.md):
// - journal_ops.dart — XML transport parsing (forgiving, garbage-safe)
// - journal_store.dart — per-(session, character) card persistence, cap
//   enforcement, feelings-that-heal revision, session cascade
// - journal_maintenance.dart — the one periodic pass: ops applied with
//   emotion stamped deterministically from message metadata, recap from the
//   first owner only, cursor semantics, session-switch abort, group
//   multi-owner loop (1:1 ↔ group parity by construction).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/chat/journal_maintenance.dart';
import 'package:front_porch_ai/services/chat/journal_ops.dart';
import 'package:front_porch_ai/services/chat/journal_review.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/llm_service.dart'
    show LlmToolCall, LlmToolResponse;

ChatMessage _msg(
  String sender,
  String text, {
  bool isUser = false,
  String? characterId,
  Map<String, dynamic>? metadata,
}) => ChatMessage(
  text: text,
  sender: sender,
  isUser: isUser,
  characterId: characterId,
  metadata: metadata,
);

void main() {
  group('journal_ops parsing', () {
    test('parses add with category and msgs', () {
      final ops = parseJournalOps(
        'Some prose the model added.\n'
        '<memory action="add" category="promise" msgs="12,14">I promised him '
        'I would stay.</memory>',
      );
      expect(ops, hasLength(1));
      expect(ops.first.action, JournalOpAction.add);
      expect(ops.first.category, 'promise');
      expect(ops.first.sourcePositions, [12, 14]);
      expect(ops.first.text, 'I promised him I would stay.');
    });

    test('parses revise with handle and feeling', () {
      final ops = parseJournalOps(
        '<memory action="revise" id="3" feeling="proud">He quit the '
        'hospital.</memory>',
      );
      expect(ops.single.action, JournalOpAction.revise);
      expect(ops.single.handle, 3);
      expect(ops.single.feeling, 'proud');
    });

    test('parses self-closing retire and pin', () {
      final ops = parseJournalOps(
        '<memory action="retire" id="2"/>\n<memory action="pin" id="5"/>',
      );
      expect(ops, hasLength(2));
      expect(ops[0].action, JournalOpAction.retire);
      expect(ops[0].handle, 2);
      expect(ops[1].action, JournalOpAction.pin);
      expect(ops[1].handle, 5);
    });

    test('accepts action aliases and unquoted attributes', () {
      final ops = parseJournalOps(
        '<memory action=delete id=2/>\n'
        "<memory action='update' id='1'>new text</memory>",
      );
      expect(ops[0].action, JournalOpAction.retire);
      expect(ops[1].action, JournalOpAction.revise);
    });

    test('drops invalid ops instead of throwing', () {
      final ops = parseJournalOps(
        '<memory action="explode" id="1">boom</memory>\n' // unknown action
        '<memory action="revise">no handle</memory>\n' // revise without id
        '<memory action="add" category="moment"></memory>\n' // empty add
        'total garbage <memory <<>> not even a tag',
      );
      expect(ops, isEmpty);
    });

    test('normalizes unknown categories to moment', () {
      final ops = parseJournalOps(
        '<memory action="add" category="banana">Something happened.</memory>',
      );
      expect(ops.single.category, 'moment');
    });

    test('clamps overlong memory text', () {
      final long = 'x' * 1000;
      final ops = parseJournalOps('<memory action="add">$long</memory>');
      expect(
        ops.single.text.length,
        lessThanOrEqualTo(kJournalMemoryMaxChars),
      );
    });

    test('parses paired recap and strips stray tags', () {
      final recap = parseRecap(
        '<memory action="retire" id="1"/>'
        '<recap>We are <b>close</b> now.</recap>',
      );
      expect(recap, 'We are close now.');
    });

    test('recovers an unclosed recap (local-model floor)', () {
      final recap = parseRecap('<recap>Things stand well between us');
      expect(recap, 'Things stand well between us');
    });

    test('returns null recap for garbage', () {
      expect(parseRecap('no tags here at all'), isNull);
    });

    test('tool calls parse into the same validated ops (phase 4)', () {
      final (ops, recap) = parseJournalToolCalls([
        const LlmToolCall(
          name: 'add_memory',
          arguments: {
            'content': 'He fixed the porch light.',
            'category': 'about-user', // dash variant → normalized
            'msgs': [3, '4'], // mixed int/string positions tolerated
          },
        ),
        const LlmToolCall(
          name: 'revise_memory',
          arguments: {'id': '2', 'content': 'He quit.', 'feeling': 'Proud'},
        ),
        const LlmToolCall(name: 'retire_memory', arguments: {'id': 1}),
        const LlmToolCall(name: 'pin_memory', arguments: {'id': 3}),
        const LlmToolCall(
          name: 'write_recap',
          arguments: {'text': 'We are close now.'},
        ),
      ]);
      expect(ops, hasLength(4));
      expect(ops[0].action, JournalOpAction.add);
      expect(ops[0].category, 'about_user');
      expect(ops[0].sourcePositions, [3, 4]);
      expect(ops[1].action, JournalOpAction.revise);
      expect(ops[1].handle, 2);
      expect(ops[1].feeling, 'proud');
      expect(ops[2].action, JournalOpAction.retire);
      expect(ops[3].action, JournalOpAction.pin);
      expect(recap, 'We are close now.');
    });

    test('unknown tools and invalid tool arguments are dropped', () {
      final (ops, recap) = parseJournalToolCalls([
        const LlmToolCall(name: 'explode', arguments: {'boom': true}),
        const LlmToolCall(name: 'add_memory', arguments: {}), // no content
        const LlmToolCall(
          name: 'revise_memory',
          arguments: {'content': 'x'}, // no id
        ),
        const LlmToolCall(name: 'write_recap', arguments: {'text': '   '}),
      ]);
      expect(ops, isEmpty);
      expect(recap, isNull);
    });
  });

  group('JournalStore', () {
    late AppDatabase db;
    late JournalStore store;

    setUp(() {
      db = AppDatabase.forTesting();
      store = JournalStore(getDb: () => db);
    });

    tearDown(() async {
      await db.close();
    });

    test('cards are strictly scoped per (session, character)', () async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'A',
        category: 'moment',
        maxCards: 10,
      );
      await store.addCard(
        sessionId: 's2',
        characterId: 'mara',
        content: 'B',
        category: 'moment',
        maxCards: 10,
      );
      await store.addCard(
        sessionId: 's1',
        characterId: 'liv',
        content: 'C',
        category: 'moment',
        maxCards: 10,
      );

      final s1Mara = await store.cardsFor('s1', 'mara');
      expect(s1Mara.map((c) => c.content), ['A']); // no cross-chat leakage
      expect(await store.cardsFor('s2', 'mara'), hasLength(1));
      expect(await store.cardsFor('s1', 'liv'), hasLength(1));
      expect(await store.cardsFor('s3', 'mara'), isEmpty);
    });

    test('cap retires the coldest unpinned card (oldest on equal heat)',
        () async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'oldest-pinned',
        category: 'moment',
        maxCards: 10,
      );
      final first = (await store.cardsFor('s1', 'mara')).single;
      await store.setPinned(first.id, true);
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'old-unpinned',
        category: 'moment',
        maxCards: 10,
      );
      // Cap of 2 → adding a third must drop 'old-unpinned', not the pin.
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'newest',
        category: 'moment',
        maxCards: 2,
      );
      final cards = await store.cardsFor('s1', 'mara');
      expect(cards.map((c) => c.content).toSet(), {'oldest-pinned', 'newest'});
    });

    test('revise preserves the original feeling once', () async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'Sam works nights.',
        category: 'about_user',
        emotionLabel: 'sad',
        emotionIntensity: 'moderate',
        maxCards: 10,
      );
      var card = (await store.cardsFor('s1', 'mara')).single;
      await store.reviseCard(card, content: 'Sam quit.', feeling: 'proud');
      card = (await store.cardsFor('s1', 'mara')).single;
      expect(card.content, 'Sam quit.');
      expect(card.emotionLabel, 'proud');
      expect(card.originalEmotionLabel, 'sad'); // feelings that heal

      // A second revision must NOT overwrite the original imprint.
      await store.reviseCard(card, feeling: 'joyful');
      card = (await store.cardsFor('s1', 'mara')).single;
      expect(card.emotionLabel, 'joyful');
      expect(card.originalEmotionLabel, 'sad');
    });

    test('pinned cards sort first', () async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'first',
        category: 'moment',
        maxCards: 10,
      );
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'second',
        category: 'moment',
        maxCards: 10,
      );
      final second = (await store.cardsFor('s1', 'mara'))
          .firstWhere((c) => c.content == 'second');
      await store.setPinned(second.id, true);
      final cards = await store.cardsFor('s1', 'mara');
      expect(cards.first.content, 'second');
    });

    test('deleting a session cascades to its journal cards', () async {
      // Session row must exist for the delete to make sense end-to-end.
      await db.insertSession(SessionsCompanion.insert(id: 's1'));
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'gone with the chat',
        category: 'moment',
        maxCards: 10,
      );
      await db.deleteSessionById('s1');
      expect(await store.cardsFor('s1', 'mara'), isEmpty);
      expect(await db.countJournalCards('s1', 'mara'), 0);
    });
  });

  group('JournalMaintenance', () {
    late AppDatabase db;
    late JournalStore store;

    setUp(() {
      db = AppDatabase.forTesting();
      store = JournalStore(getDb: () => db);
    });

    tearDown(() async {
      await db.close();
    });

    JournalMaintenance build({
      required List<String?> responses, // consumed in order; null = failure
      required List<ChatMessage> messages,
      CharacterCard? activeChar,
      GroupChat? group,
      List<CharacterCard> groupChars = const [],
      String? Function()? getSessionId,
      List<String>? prompts,
      void Function(String)? onRecap,
      void Function(int)? onCursor,
      int cursor = 0,
      String recap = '',
      // Phase 4 — tools transport + review-first (defaults preserve the
      // classic XML/immediate behavior every pre-phase-4 test asserts).
      Future<LlmToolResponse?> Function(String, List<Map<String, dynamic>>)?
      fireToolEval,
      bool reviewFirst = false,
      JournalReview? review,
    }) {
      var running = false;
      var i = 0;
      final session = getSessionId ?? () => 's1';
      return JournalMaintenance(
        store: store,
        probe: ToolTransportProbe(),
        review:
            review ??
            JournalReview(
              store: store,
              getSessionId: session,
              setRecap: (t) => onRecap?.call(t),
              setCursor: (v) => onCursor?.call(v),
              onSaveChat: () async {},
              onNotify: () {},
              getMaxCards: () => 200,
            ),
        fireLLMEval: (p) async {
          prompts?.add(p);
          return i < responses.length ? responses[i++] : null;
        },
        fireToolEval: fireToolEval ?? (p, t) async => null,
        stripThinkBlocks: (t) => t,
        getSessionId: session,
        getActiveCharacter: () => activeChar,
        getActiveGroup: () => group,
        getGroupCharacters: () => groupChars,
        getCharacterIdFromCard: (c) => c.name.toLowerCase(),
        getMessages: () => messages,
        getUserName: () => 'Sam',
        getCursor: () => cursor,
        setCursor: (v) => onCursor?.call(v),
        getRecap: () => recap,
        setRecap: (t) => onRecap?.call(t),
        getIsPassRunning: () => running,
        setIsPassRunning: (v) => running = v,
        getReviewFirst: () => reviewFirst,
        getBackendIdentity: () => 'test-backend',
        getMaxCards: () => 200,
        onNotify: () {},
        onSaveChat: () async {},
        getCurrentStoryDay: () => 1,
        getCurrentStoryClockIso: () => '2026-06-30T09:00:00.000Z',
      );
    }

    final mara = CharacterCard(
      name: 'Mara',
      description: 'd',
      personality: 'p',
      scenario: 's',
    );
    final liv = CharacterCard(
      name: 'Liv',
      description: 'd',
      personality: 'p',
      scenario: 's',
    );

    test(
      'applies add ops with emotion stamped from cited message metadata',
      () async {
        final messages = [
          _msg('Sam', 'I work nights at the hospital.', isUser: true),
          _msg(
            'Mara',
            'That sounds exhausting…',
            metadata: {
              'emotion_label': 'sad',
              'realism_state': {'emotionIntensity': 'strong'},
            },
          ),
        ];
        final recaps = <String>[];
        final cursors = <int>[];
        final m = build(
          responses: [
            '<memory action="add" category="about_user" msgs="0,1">Sam works '
                'nights at the hospital.</memory>\n'                '<recap>He told me about his job tonight.</recap>',
          ],
          messages: messages,
          activeChar: mara,
          onRecap: recaps.add,
          onCursor: cursors.add,
        );
        await m.runMaintenancePass();

        final cards = await store.cardsFor('s1', 'mara');
        expect(cards, hasLength(1));
        expect(cards.single.category, 'about_user');
        // Feeling read from the engine's own per-message stamp — not asked.
        expect(cards.single.emotionLabel, 'sad');
        expect(cards.single.emotionIntensity, 'strong');
        expect(recaps, ['He told me about his job tonight.']);
        expect(cursors, [2]); // advanced to messages.length
      },
    );

    test('revise/retire/pin resolve 1-based handles from stored order',
        () async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'card one',
        category: 'moment',
        maxCards: 200,
      );
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'card two',
        category: 'moment',
        maxCards: 200,
      );
      final m = build(
        responses: [
          '<memory action="revise" id="1" feeling="warm">card one revised'
              '</memory>\n'
              '<memory action="pin" id="2"/>\n'
              '<recap>ok</recap>',
        ],
        messages: [_msg('Mara', 'hello')],
        activeChar: mara,
      );
      await m.runMaintenancePass(force: true);

      final cards = await store.cardsFor('s1', 'mara');
      // Pinned sorts first now.
      expect(cards.first.content, 'card two');
      expect(cards.first.pinned, isTrue);
      expect(cards.last.content, 'card one revised');
      expect(cards.last.emotionLabel, 'warm');
    });

    test('all-failed pass leaves the cursor untouched (auto-retry)', () async {
      final cursors = <int>[];
      final m = build(
        responses: [null],
        messages: [_msg('Sam', 'hi', isUser: true), _msg('Mara', 'hey')],
        activeChar: mara,
        onCursor: cursors.add,
      );
      await m.runMaintenancePass();
      expect(cursors, isEmpty);
      expect(await store.cardsFor('s1', 'mara'), isEmpty);
    });

    test('session switch mid-pass aborts recap and cursor writes', () async {
      final recaps = <String>[];
      final cursors = <int>[];
      var session = 's1';
      var running = false;
      final m = JournalMaintenance(
        store: store,
        probe: ToolTransportProbe(),
        review: JournalReview(
          store: store,
          getSessionId: () => session,
          setRecap: recaps.add,
          setCursor: cursors.add,
          onSaveChat: () async {},
          onNotify: () {},
          getMaxCards: () => 200,
        ),
        fireLLMEval: (p) async {
          session = 's2'; // the user switched chats during the slow eval
          return '<memory action="add">He said something kind.</memory>'
              '<recap>stale recap from chat A</recap>';
        },
        fireToolEval: (p, t) async => null,
        stripThinkBlocks: (t) => t,
        getSessionId: () => session,
        getActiveCharacter: () => mara,
        getActiveGroup: () => null,
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.name.toLowerCase(),
        getMessages: () => [_msg('Sam', 'hi', isUser: true)],
        getUserName: () => 'Sam',
        getCursor: () => 0,
        setCursor: cursors.add,
        getRecap: () => '',
        setRecap: recaps.add,
        getIsPassRunning: () => running,
        setIsPassRunning: (v) => running = v,
        getReviewFirst: () => false,
        getBackendIdentity: () => 'test-backend',
        getMaxCards: () => 200,
        onNotify: () {},
        onSaveChat: () async {},
        getCurrentStoryDay: () => 1,
        getCurrentStoryClockIso: () => '2026-06-30T09:00:00.000Z',
      );
      await m.runMaintenancePass();

      expect(recaps, isEmpty); // chat B never gets chat A's recap
      expect(cursors, isEmpty);
      // The card write targets the CAPTURED session — safe either way.
      expect(await store.cardsFor('s1', 'mara'), hasLength(1));
    });

    test('group: one pass per speaking member, recap from the first only',
        () async {
      final group = GroupChat(id: 'g1', name: 'The Porch');
      final messages = [
        _msg('Sam', 'evening, you two', isUser: true),
        _msg('Mara', 'evening!', characterId: 'mara', metadata: {
          'emotion_label': 'joy',
        }),
        _msg('Liv', 'hm.', characterId: 'liv', metadata: {
          'emotion_label': 'annoyance',
        }),
      ];
      final prompts = <String>[];
      final recaps = <String>[];
      final m = build(
        responses: [
          '<memory action="add" msgs="1">He greeted us warmly.</memory>'
              '<recap>A warm evening together.</recap>',
          '<memory action="add" msgs="2">He interrupted my reading.</memory>'
              '<recap>should be ignored</recap>',
        ],
        messages: messages,
        group: group,
        groupChars: [mara, liv],
        prompts: prompts,
        onRecap: recaps.add,
      );
      await m.runMaintenancePass();

      expect(prompts, hasLength(2)); // one eval per diary owner
      final maraCards = await store.cardsFor('s1', 'mara');
      final livCards = await store.cardsFor('s1', 'liv');
      expect(maraCards.single.content, 'He greeted us warmly.');
      expect(maraCards.single.emotionLabel, 'joy'); // per-speaker stamp
      expect(livCards.single.content, 'He interrupted my reading.');
      expect(livCards.single.emotionLabel, 'annoyance');
      expect(recaps, ['A warm evening together.']); // first owner only
    });

    test('prompt carries handles, salience annotations, and the rules',
        () async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'An existing memory.',
        category: 'promise',
        emotionLabel: 'hopeful',
        maxCards: 200,
      );
      final prompts = <String>[];
      final m = build(
        responses: ['<recap>ok</recap>'],
        messages: [
          _msg('Sam', 'you okay?', isUser: true),
          _msg('Mara', 'better now', metadata: {
            'emotion_label': 'grateful',
            'bond_delta': 15,
            'bond_reason': 'he checked in',
          }),
        ],
        activeChar: mara,
        prompts: prompts,
      );
      await m.runMaintenancePass();

      final p = prompts.single;
      expect(p, contains('[1] (promise, felt hopeful) An existing memory.'));
      expect(p, contains('#1 Mara: better now'));
      expect(p, contains('felt grateful'));
      expect(p, contains('bond +15 — he checked in'));
      expect(p, contains('<recap>'));
    });

    test('first pass on a long existing chat reads only the recent tail',
        () async {
      final messages = List.generate(
        60,
        (i) =>
            _msg(i.isEven ? 'Sam' : 'Mara', 'line $i', isUser: i.isEven),
      );
      final prompts = <String>[];
      final cursors = <int>[];
      final m = build(
        responses: ['<recap>caught up</recap>'],
        messages: messages,
        activeChar: mara,
        prompts: prompts,
        onCursor: cursors.add,
      );
      await m.runMaintenancePass();

      // Cursor 0 + 60 messages → window capped to the trailing 50 (#10–#59).
      expect(prompts.single, contains('#10 '));
      expect(prompts.single, isNot(contains('#9 ')));
      expect(cursors, [60]);
    });

    test('a successful pass cools the existing cards one step', () async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'a mild memory',
        category: 'moment',
        emotionIntensity: 'mild',
        maxCards: 200,
      );
      final m = build(
        responses: ['<recap>nothing new</recap>'], // zero ops still succeeds
        messages: [_msg('Sam', 'hi', isUser: true), _msg('Mara', 'hey')],
        activeChar: mara,
      );
      await m.runMaintenancePass();
      expect(
        (await store.cardsFor('s1', 'mara')).single.heat,
        closeTo(0.85, 1e-6),
      );

      // A failed pass must NOT cool (it retries the same window later).
      final failing = build(
        responses: [null],
        messages: [_msg('Sam', 'hi', isUser: true), _msg('Mara', 'hey')],
        activeChar: mara,
      );
      await failing.runMaintenancePass();
      expect(
        (await store.cardsFor('s1', 'mara')).single.heat,
        closeTo(0.85, 1e-6),
      );
    });

    test('the pass embeds newly added cards when an embedder is wired',
        () async {
      var embedCalls = 0;
      store = JournalStore(
        getDb: () => db,
        embedText: (text) async {
          embedCalls++;
          return [0.1, 0.2];
        },
      );
      final m = build(
        responses: [
          '<memory action="add" msgs="0">He brought me coffee.</memory>'
              '<recap>ok</recap>',
        ],
        messages: [_msg('Sam', 'coffee?', isUser: true)],
        activeChar: mara,
      );
      await m.runMaintenancePass();

      final card = (await store.cardsFor('s1', 'mara')).single;
      expect(embedCalls, 1);
      expect(card.embedding, isNotNull);
      expect(card.dimensions, 2);
    });

    test('tool transport: calls become ops, XML never fired', () async {
      final xmlPrompts = <String>[];
      final toolPrompts = <String>[];
      final recaps = <String>[];
      final cursors = <int>[];
      final m = build(
        responses: ['<recap>the XML transport must not be used</recap>'],
        messages: [
          _msg('Sam', 'evening', isUser: true),
          _msg('Mara', 'evening!', metadata: {'emotion_label': 'joy'}),
        ],
        activeChar: mara,
        prompts: xmlPrompts,
        onRecap: recaps.add,
        onCursor: cursors.add,
        fireToolEval: (p, tools) async {
          toolPrompts.add(p);
          expect(tools, kJournalTools);
          return const LlmToolResponse(
            calls: [
              LlmToolCall(
                name: 'add_memory',
                arguments: {
                  'content': 'He greeted me warmly.',
                  'msgs': [1],
                },
              ),
              LlmToolCall(
                name: 'write_recap',
                arguments: {'text': 'A warm hello.'},
              ),
            ],
            text: '',
          );
        },
      );
      await m.runMaintenancePass();

      expect(toolPrompts.single, contains('add_memory')); // tools-mode prompt
      expect(xmlPrompts, isEmpty); // no XML round trip at all
      final card = (await store.cardsFor('s1', 'mara')).single;
      expect(card.content, 'He greeted me warmly.');
      expect(card.emotionLabel, 'joy'); // stamp still deterministic
      expect(recaps, ['A warm hello.']);
      expect(cursors, [2]);
    });

    test('tools rejected once → XML fallback, probe not repeated', () async {
      var toolAttempts = 0;
      final xmlPrompts = <String>[];
      final m = build(
        responses: ['<recap>one</recap>', '<recap>two</recap>'],
        messages: [_msg('Sam', 'hi', isUser: true), _msg('Mara', 'hey')],
        activeChar: mara,
        prompts: xmlPrompts,
        fireToolEval: (p, t) async {
          toolAttempts++;
          return null; // backend can't speak tools
        },
      );
      await m.runMaintenancePass();
      await m.runMaintenancePass(force: true);

      expect(toolAttempts, 1); // remembered as XML-only after one probe
      expect(xmlPrompts, hasLength(2)); // both passes journaled over XML
    });

    test('transport failure → XML this round only, probe left untested',
        () async {
      var toolAttempts = 0;
      final xmlPrompts = <String>[];
      final recaps = <String>[];
      final m = build(
        responses: ['<recap>round one</recap>'],
        messages: [_msg('Sam', 'hi', isUser: true), _msg('Mara', 'hey')],
        activeChar: mara,
        prompts: xmlPrompts,
        onRecap: recaps.add,
        fireToolEval: (p, t) async {
          toolAttempts++;
          if (toolAttempts == 1) {
            // Connection torn down mid-call (e.g. character creation fired an
            // app-wide abortGeneration): a network event, not a capability
            // verdict — must NOT brand the backend XML-only for the run.
            throw Exception('SocketException: Connection reset by peer');
          }
          return const LlmToolResponse(
            calls: [
              LlmToolCall(
                name: 'write_recap',
                arguments: {'text': 'Back on tools.'},
              ),
            ],
            text: '',
          );
        },
      );
      await m.runMaintenancePass();
      await m.runMaintenancePass(force: true);

      expect(toolAttempts, 2); // tools re-tried next pass (no XML branding)
      expect(xmlPrompts, hasLength(1)); // failed round fell back to XML once
      expect(recaps, ['round one', 'Back on tools.']);
    });

    test('model ignores tools but writes tags — salvaged, no refire',
        () async {
      final xmlPrompts = <String>[];
      final recaps = <String>[];
      final m = build(
        responses: ['<recap>must stay unused</recap>'],
        messages: [_msg('Sam', 'hi', isUser: true)],
        activeChar: mara,
        prompts: xmlPrompts,
        onRecap: recaps.add,
        fireToolEval: (p, t) async => const LlmToolResponse(
          calls: [],
          text: '<memory action="add">Salvaged from text.</memory>'
              '<recap>Still works.</recap>',
        ),
      );
      await m.runMaintenancePass();

      expect(xmlPrompts, isEmpty);
      expect(
        (await store.cardsFor('s1', 'mara')).single.content,
        'Salvaged from text.',
      );
      expect(recaps, ['Still works.']);
    });

    test('review-first parks proposals without writing anything', () async {
      final recaps = <String>[];
      final cursors = <int>[];
      final prompts = <String>[];
      final review = JournalReview(
        store: store,
        getSessionId: () => 's1',
        setRecap: recaps.add,
        setCursor: cursors.add,
        onSaveChat: () async {},
        onNotify: () {},
        getMaxCards: () => 200,
      );
      final m = build(
        responses: [
          '<memory action="add" msgs="1">He was kind tonight.</memory>'
              '<recap>Kindness is growing.</recap>',
        ],
        messages: [
          _msg('Sam', 'here, I made you tea', isUser: true),
          _msg('Mara', 'oh… thank you', metadata: {'emotion_label': 'gratitude'}),
        ],
        activeChar: mara,
        prompts: prompts,
        onRecap: recaps.add,
        onCursor: cursors.add,
        reviewFirst: true,
        review: review,
      );
      await m.runMaintenancePass();

      // Nothing written, nothing advanced — everything parked.
      expect(await store.cardsFor('s1', 'mara'), isEmpty);
      expect(recaps, isEmpty);
      expect(cursors, isEmpty);
      final batch = review.pending!;
      expect(batch.sessionId, 's1');
      expect(batch.cursorTarget, 2);
      expect(batch.owners.single.ops.single.text, 'He was kind tonight.');
      expect(batch.owners.single.ops.single.emotionLabel, 'gratitude');
      expect(batch.recap, 'Kindness is growing.');

      // The parked batch blocks further automatic passes.
      await m.runMaintenancePass();
      expect(prompts, hasLength(1));
    });

    test('review apply commits only the accepted ops', () async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'the old memory',
        category: 'moment',
        maxCards: 200,
      );
      final recaps = <String>[];
      final cursors = <int>[];
      final review = JournalReview(
        store: store,
        getSessionId: () => 's1',
        setRecap: recaps.add,
        setCursor: cursors.add,
        onSaveChat: () async {},
        onNotify: () {},
        getMaxCards: () => 200,
      );
      final m = build(
        responses: [
          '<memory action="revise" id="1">the old memory, revised</memory>'
              '<memory action="add">an unwanted extra</memory>'
              '<recap>Fresh recap.</recap>',
        ],
        messages: [_msg('Sam', 'hi', isUser: true), _msg('Mara', 'hey')],
        activeChar: mara,
        reviewFirst: true,
        review: review,
      );
      await m.runMaintenancePass();

      final batch = review.pending!;
      // Reject the add, keep the revise and the recap.
      batch.owners.single.ops
          .firstWhere((op) => op.action == JournalOpAction.add)
          .accepted = false;
      await review.apply();

      final cards = await store.cardsFor('s1', 'mara');
      expect(cards.single.content, 'the old memory, revised');
      expect(recaps, ['Fresh recap.']);
      expect(cursors, [2]);
      expect(review.pending, isNull);
    });

    test('review discard writes nothing but settles the window', () async {
      final recaps = <String>[];
      final cursors = <int>[];
      final review = JournalReview(
        store: store,
        getSessionId: () => 's1',
        setRecap: recaps.add,
        setCursor: cursors.add,
        onSaveChat: () async {},
        onNotify: () {},
        getMaxCards: () => 200,
      );
      final m = build(
        responses: [
          '<memory action="add">not wanted at all</memory><recap>nor this</recap>',
        ],
        messages: [_msg('Sam', 'hi', isUser: true), _msg('Mara', 'hey')],
        activeChar: mara,
        reviewFirst: true,
        review: review,
      );
      await m.runMaintenancePass();
      await review.discard();

      expect(await store.cardsFor('s1', 'mara'), isEmpty);
      expect(recaps, isEmpty);
      expect(cursors, [2]); // window handled — not re-proposed forever
      expect(review.pending, isNull);
    });

    test('no session or empty window is a safe no-op', () async {
      final m = build(
        responses: ['<recap>never fired</recap>'],
        messages: [],
        activeChar: mara,
        getSessionId: () => null,
      );
      await m.runMaintenancePass();

      final m2 = build(
        responses: ['<recap>never fired</recap>'],
        messages: [],
        activeChar: mara,
      );
      await m2.runMaintenancePass();
      expect(await store.cardsFor('s1', 'mara'), isEmpty);
    });
  });
}
