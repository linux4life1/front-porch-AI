// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Reprocess Needs only re-evaluates the speaker's ENABLED needs
// (/workspace/sow/rn-spec.md, "Contract" + items 2-3 + AMENDMENT 1).
//
// Every case drives the real ChatService.manualReprocessNeeds (the one
// backend choke point for desktop and web) against an in-memory drift DB. The
// only stand-in is the scripted model in the harness, which records each
// prompt so we can check which needs were asked for. Nothing here uses a
// symbol the fix adds, so on Rawhide these fail on assertions (not compile).
// The resolver API pins live in reprocess_needs_target_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/reprocess_needs_harness.dart';

const _critique = 'She ate a full meal; hunger should rise.';

Map<String, dynamic> _slotVector(ChatMessage m) {
  final slot = m.swipeMetadata[m.swipeIndex]!;
  final rs = slot['realism_state'] as Map;
  return Map<String, dynamic>.from((rs['needs'] as Map)['vector'] as Map);
}

Set<String> _chipKeys(ChatMessage m) =>
    ((m.activeMetadata?['needs_deltas'] as Map?) ?? const {}).keys
        .map((k) => k.toString())
        .toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
  });
  tearDown(() => h.dispose());

  group('1:1 speaker', () {
    test('B1 empty selection with Hygiene+Fun off asks for exactly the 5 '
        'enabled needs', () async {
      final i = await h.oneToOneWithStampedReply(
        needsCard('Mara', needsOff: ['hygiene', 'fun']),
      );
      await h.chat.manualReprocessNeeds(i, _critique);
      expect(h.llm.reprocessPrompts, hasLength(1));
      expect(askedDeltaKeys(h.llm.reprocessPrompts.single), {
        'hunger',
        'bladder',
        'energy',
        'social',
        'comfort',
      }, reason: 'the prompt must name exactly the enabled keys');
      expect(
        h.llm.reprocessPrompts.single,
        isNot(contains('all seven _delta keys')),
      );
      // AMENDMENT 1: a subset goes through the existing scoped onlyNeeds path.
      expect(
        h.llm.reprocessPrompts.single,
        contains('Scope: reconsider ONLY these needs'),
      );
    });

    test('B2 selecting only an off need returns false with zero LLM calls '
        'and no write', () async {
      final i = await h.oneToOneWithStampedReply(
        needsCard('Mara', needsOff: ['hygiene', 'fun']),
      );
      final before = h.storedNeedsFingerprint(i);
      final ok = await h.chat.manualReprocessNeeds(
        i,
        _critique,
        onlyNeeds: {'hygiene'},
      );
      expect(ok, isFalse);
      expect(h.llm.reprocessPrompts, isEmpty);
      expect(h.storedNeedsFingerprint(i), before);
    });

    test('B2c junk + off keys only: false, zero LLM calls, no write', () async {
      final i = await h.oneToOneWithStampedReply(
        needsCard('Mara', needsOff: ['hygiene', 'fun']),
      );
      final before = h.storedNeedsFingerprint(i);
      final ok = await h.chat.manualReprocessNeeds(
        i,
        _critique,
        onlyNeeds: {'not_a_need', 'hygiene'},
      );
      expect(ok, isFalse);
      expect(h.llm.reprocessPrompts, isEmpty);
      expect(h.storedNeedsFingerprint(i), before);
    });

    test('B2b mixed selection drops the off key: only the on key is asked '
        'and the off need is not written', () async {
      final i = await h.oneToOneWithStampedReply(
        needsCard('Mara', needsOff: ['hygiene', 'fun']),
      );
      final hygieneBefore = _slotVector(h.chat.messages[i])['hygiene'];
      final ok = await h.chat.manualReprocessNeeds(
        i,
        _critique,
        onlyNeeds: {'hygiene', 'energy'},
      );
      expect(ok, isTrue);
      expect(askedDeltaKeys(h.llm.reprocessPrompts.single), {'energy'});
      expect(_slotVector(h.chat.messages[i])['hygiene'], hygieneBefore);
      expect(
        _chipKeys(h.chat.messages[i]).intersection({'hygiene', 'fun'}),
        isEmpty,
      );
    });

    test('B3 every need turned off on the card: false, zero LLM calls, no '
        'write', () async {
      final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
      h.chat.activeCharacter!.frontPorchExtensions!.needsOff = List<String>.of(
        kAllNeeds,
      );
      final before = h.storedNeedsFingerprint(i);
      final ok = await h.chat.manualReprocessNeeds(i, _critique);
      expect(ok, isFalse);
      expect(h.llm.reprocessPrompts, isEmpty);
      expect(h.storedNeedsFingerprint(i), before);
    });

    test('B4 Needs turned off after the reply was stamped: false, zero LLM '
        'calls', () async {
      final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
      await h.chat.setNeedsSimEnabled(false);
      final ok = await h.chat.manualReprocessNeeds(i, _critique);
      expect(ok, isFalse);
      expect(h.llm.reprocessPrompts, isEmpty);
    });

    test('B6 a reply that only moves off needs returns false and writes '
        'nothing', () async {
      final i = await h.oneToOneWithStampedReply(
        needsCard('Mara', needsOff: ['hygiene', 'fun']),
      );
      h.llm.reprocessReply =
          '{"hygiene_delta": 20, "fun_delta": 15, "reason": "washed, played"}';
      final before = h.storedNeedsFingerprint(i);
      final ok = await h.chat.manualReprocessNeeds(i, _critique);
      expect(ok, isFalse);
      expect(h.storedNeedsFingerprint(i), before);
    });

    test('B7 guard: all 7 on + empty selection keeps today\'s unscoped prompt '
        'byte-identical', () async {
      final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
      final ok = await h.chat.manualReprocessNeeds(i, _critique);
      expect(ok, isTrue);
      // Captured from origin/Rawhide bb04f0d5 with this exact harness.
      final expected = File(
        'test/fixtures/reprocess_needs/all_seven_unscoped_prompt.txt',
      ).readAsStringSync();
      expect(h.llm.reprocessPrompts.single, expected);
      expect(askedDeltaKeys(expected), kAllNeeds.toSet());
    });

    test('B8 Hunger turned off after a -12 turn: unticked reprocess keeps '
        'stored hunger at 58 (swipe slot and after reload)', () async {
      h.llm.liveNeedsReply =
          '{"hunger_delta": -12, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "skipped lunch"}';
      final i = await h.oneToOneWithStampedReply(
        needsCard('Mara', hungerBaseline: 70),
      );
      expect(
        _slotVector(h.chat.messages[i])['hunger'],
        58,
        reason: 'precondition: the live turn stamped 70 - 12',
      );

      h.chat.activeCharacter!.frontPorchExtensions!.needsOff = ['hunger'];
      h.llm.reprocessReply =
          '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 6, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "rested"}';
      await h.chat.manualReprocessNeeds(i, 'She rested; energy should rise.');

      expect(
        _slotVector(h.chat.messages[i])['hunger'],
        58,
        reason: 'swipe slot: a need switched off must keep its old delta',
      );

      await h.chat.reloadCurrentSession();
      await h.settleTurn();
      expect(
        _slotVector(h.chat.messages[i])['hunger'],
        58,
        reason: 'persisted row after reload',
      );
    });

    test(
      'B8b guard: the recomputed reprocess chip leaves out a need switched off '
      'after the turn',
      () async {
        h.llm.liveNeedsReply =
            '{"hunger_delta": -12, "bladder_delta": 0, "energy_delta": 0, '
            '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
            '"comfort_delta": 0, "reason": "skipped lunch"}';
        final i = await h.oneToOneWithStampedReply(
          needsCard('Mara', hungerBaseline: 70),
        );
        h.chat.activeCharacter!.frontPorchExtensions!.needsOff = ['hunger'];
        h.llm.reprocessReply =
            '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 6, '
            '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
            '"comfort_delta": 0, "reason": "rested"}';
        await h.chat.manualReprocessNeeds(i, 'She rested; energy should rise.');
        expect(_chipKeys(h.chat.messages[i]), isNot(contains('hunger')));
      },
    );

    test('B9 Needs switch OFF: reprocess of the last reply is refused and the '
        'hidden vector + chip stay byte-identical', () async {
      final i = await h.oneToOneWithStampedReply(needsCard('Mara'));
      expect(i, h.chat.messages.length - 1);
      await h.chat.setNeedsSimEnabled(false);
      final vectorBefore = jsonEncode(h.chat.needsSimulation.vector);
      final chipBefore = jsonEncode(
        h.chat.messages[i].activeMetadata?['needs_deltas'],
      );
      final ok = await h.chat.manualReprocessNeeds(i, _critique);
      expect(ok, isFalse);
      expect(jsonEncode(h.chat.needsSimulation.vector), vectorBefore);
      expect(
        jsonEncode(h.chat.messages[i].activeMetadata?['needs_deltas']),
        chipBefore,
      );
    });

    test(
      'scope guard: an empty selection never writes a disabled need into the '
      'chip or the vector',
      () async {
        final i = await h.oneToOneWithStampedReply(
          needsCard('Mara', needsOff: ['hygiene', 'fun']),
        );
        final v0 = _slotVector(h.chat.messages[i]);
        await h.chat.manualReprocessNeeds(i, _critique);
        final v1 = _slotVector(h.chat.messages[i]);
        expect(v1['hygiene'], v0['hygiene']);
        expect(v1['fun'], v0['fun']);
        expect(
          _chipKeys(h.chat.messages[i]).intersection({'hygiene', 'fun'}),
          isEmpty,
        );
      },
    );
  });

  group('group speaker (msg.sender roster card)', () {
    test('B5 A has Social off, B has it on: A\'s prompt has no social, B\'s '
        'does', () async {
      final (a, b) = await h.groupWithTwoReplies();
      await h.chat.manualReprocessNeeds(a, 'critique for Ayla');
      await h.chat.manualReprocessNeeds(b, 'critique for Bram');
      expect(h.llm.reprocessPrompts, hasLength(2));
      expect(
        askedDeltaKeys(h.llm.reprocessPrompts[0]),
        kAllNeeds.toSet().difference({'social'}),
        reason: 'Ayla (Social off)',
      );
      expect(
        askedDeltaKeys(h.llm.reprocessPrompts[1]),
        contains('social'),
        reason: 'Bram (Social on)',
      );
    });

    test(
      'B5b {social} on A returns false with no LLM call; on B it runs',
      () async {
        final (a, b) = await h.groupWithTwoReplies();
        final okA = await h.chat.manualReprocessNeeds(
          a,
          'critique for Ayla',
          onlyNeeds: {'social'},
        );
        expect(okA, isFalse, reason: 'Ayla has Social off');
        expect(h.llm.reprocessPrompts, isEmpty);
        final okB = await h.chat.manualReprocessNeeds(
          b,
          'critique for Bram',
          onlyNeeds: {'social'},
        );
        expect(okB, isTrue, reason: 'Bram has Social on');
        expect(askedDeltaKeys(h.llm.reprocessPrompts.single), {'social'});
      },
    );

    test(
      'B10 guard: the reprocess chip filters by the resolver\'s speaker '
      'card: Bram (Social on) keeps social, Ayla (Social off) does not',
      () async {
        final (a, b) = await h.groupWithTwoReplies();
        // Ayla is the group's _activeCharacter here (Social off), so a filter
        // that read _activeCharacter instead of the speaker card would strip
        // social from Bram's reprocess chip.
        expect(h.chat.activeCharacter?.name, 'Ayla');
        await h.chat.manualReprocessNeeds(b, 'critique for Bram');
        expect(
          _chipKeys(h.chat.messages[b]),
          contains('social'),
          reason: 'Bram has Social on and the reply moved it',
        );
        await h.chat.manualReprocessNeeds(a, 'critique for Ayla');
        expect(
          _chipKeys(h.chat.messages[a]),
          isNot(contains('social')),
          reason: 'Ayla has Social off',
        );
      },
    );
  });
}
