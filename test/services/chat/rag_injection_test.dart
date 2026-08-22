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

// THE RAG INJECTION LEAF (rag_injection.dart, 2026-08-10 memory review).
//
// Temporal grounding + the retrieval receipt: a retrieved line used to be
// injected naked, so a Day-2 "I never want to see you again" read exactly
// like the scene's present and contradicted the recap's chronology. These
// pin the pure pieces: the story-day resolver, the display order (cross-chat
// first, then own-chat oldest → newest — display ONLY; packing stays by
// relevance), the line stamps, and the receipt wire shape.
//
// Guards proven to fail before passing:
//   * make storyDayAt read only the span (drop the backward walk) → the
//     nearest-earlier test goes red
//   * make chronologicalRagOrder return its input → the ordering tests go red
//   * drop the stamp from formatRagLine → the stamp tests go red
//   * truncate nothing in buildRagReceipt → the preview-cap test goes red

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/memory_service.dart'
    show RetrievedMemory;

ChatMessage _msg(String text, {int? day}) => ChatMessage(
  text: text,
  sender: 'Nia',
  isUser: false,
  metadata: day == null
      ? null
      : {
          'realism_state': {'dayCount': day},
        },
);

RetrievedMemory _mem(
  String content, {
  required String sessionId,
  required int pos,
  int? end,
  double score = 0.9,
}) => RetrievedMemory(
  content: content,
  characterId: 'c1',
  sessionId: sessionId,
  positionStart: pos,
  positionEnd: end ?? pos,
  score: score,
);

void main() {
  group('storyDayAt', () {
    test('reads the first day inside the span', () {
      final msgs = [_msg('a'), _msg('b', day: 2), _msg('c', day: 3)];
      expect(storyDayAt(msgs, 1, 2), 2);
    });

    test('falls back to the nearest EARLIER day when the span has none', () {
      final msgs = [_msg('a', day: 4), _msg('b'), _msg('c')];
      expect(
        storyDayAt(msgs, 1, 2),
        4,
        reason:
            'day only moves forward, so the nearest realism_state before the '
            'span is the day the span happened on — a span-only read leaves '
            'metadata-sparse histories unstamped for no reason',
      );
    });

    test('no realism_state anywhere → null (no false precision)', () {
      expect(storyDayAt([_msg('a'), _msg('b')], 0, 1), isNull);
    });

    test('out-of-range spans clamp instead of throwing', () {
      final msgs = [_msg('a', day: 1)];
      expect(storyDayAt(msgs, 0, 99), 1);
      expect(storyDayAt(const [], 0, 0), isNull);
    });
  });

  group('chronologicalRagOrder', () {
    test('cross-chat lines lead; own-chat lines run oldest → newest', () {
      final ordered = chronologicalRagOrder([
        _mem('own-new', sessionId: 's1', pos: 50, score: 0.95),
        _mem('other', sessionId: 's2', pos: 7, score: 0.9),
        _mem('own-old', sessionId: 's1', pos: 3, score: 0.85),
      ], 's1');
      expect(ordered.map((m) => m.content).toList(), [
        'other',
        'own-old',
        'own-new',
      ]);
    });

    test('is display-only: the input list is not mutated', () {
      final input = [
        _mem('b', sessionId: 's1', pos: 9),
        _mem('a', sessionId: 's1', pos: 1),
      ];
      chronologicalRagOrder(input, 's1');
      expect(
        input.first.content,
        'b',
        reason:
            'packing trims by relevance from the ORIGINAL order — a sort '
            'that mutated its input would make chronology decide which '
            'memories survive the budget',
      );
    });
  });

  group('formatRagLine', () {
    test('own-chat line carries its story day', () {
      expect(
        formatRagLine('Nia: the swing creaked', day: 3, otherChat: false),
        '- (Day 3) Nia: the swing creaked',
      );
    });

    test('cross-chat line says so instead of borrowing this story\'s days', () {
      expect(
        formatRagLine('You: the red kite', day: null, otherChat: true),
        '- (another chat) You: the red kite',
      );
    });

    test('unknown day → unstamped, not a guess', () {
      expect(
        formatRagLine('Nia: hm', day: null, otherChat: false),
        '- Nia: hm',
      );
    });
  });

  group('buildRagReceipt', () {
    test('wire shape: counts + per-line pos/day/other_chat/preview', () {
      final own = _mem('short own line', sessionId: 's1', pos: 12);
      final other = _mem('other chat line', sessionId: 's2', pos: 4);
      final r = buildRagReceipt(
        found: 5,
        journalDeduped: 2,
        budgetTrimmed: 1,
        injected: [other, own],
        days: {own: 3, other: null},
        currentSessionId: 's1',
      );
      expect(r['found'], 5);
      expect(r['journal_deduped'], 2);
      expect(r['budget_trimmed'], 1);
      // audit P2.17 — successful search is status ok (never null/missing lie)
      expect(r['status'], kRagReceiptOk);
      final lines = r['injected'] as List;
      expect(lines, hasLength(2));
      expect(lines[0], {
        'pos': 4,
        'day': null,
        'other_chat': true,
        'preview': 'other chat line',
      });
      expect(lines[1], {
        'pos': 12,
        'day': 3,
        'other_chat': false,
        'preview': 'short own line',
      });
    });

    test('previews are capped — receipts are a glance, not a copy', () {
      final long = _mem('x' * 500, sessionId: 's1', pos: 0);
      final r = buildRagReceipt(
        found: 1,
        journalDeduped: 0,
        budgetTrimmed: 0,
        injected: [long],
        days: {long: 1},
        currentSessionId: 's1',
      );
      final preview =
          ((r['injected'] as List).single as Map)['preview'] as String;
      expect(preview.length, kRagReceiptPreviewChars + 1); // +1 for the '…'
      expect(preview.endsWith('…'), isTrue);
    });

    test('error and not_operational statuses are distinct wire values', () {
      // audit P2.17 — panel must never say "no lookup needed" after a failed
      // or non-operational attempt; status is what distinguishes them.
      final err = buildRagReceipt(
        found: 0,
        journalDeduped: 0,
        budgetTrimmed: 0,
        injected: const [],
        days: const {},
        currentSessionId: 's1',
        status: kRagReceiptError,
      );
      final dead = buildRagReceipt(
        found: 0,
        journalDeduped: 0,
        budgetTrimmed: 0,
        injected: const [],
        days: const {},
        currentSessionId: 's1',
        status: kRagReceiptNotOperational,
      );
      expect(err['status'], kRagReceiptError);
      expect(dead['status'], kRagReceiptNotOperational);
      expect(err['status'], isNot(dead['status']));
    });
  });

  group('composeRagQuery', () {
    test('is not the last-3 live lines alone', () {
      final q = composeRagQuery(
        emotion: 'wistful',
        fixation: 'the broken promise',
        hotJournalLine: 'I still think about the lighthouse',
        lastWords: 'You: that photo was from our last trip',
      );
      expect(q, contains('feeling wistful'));
      expect(q, contains('on the mind: the broken promise'));
      expect(q, contains('remembered: I still think about the lighthouse'));
      expect(q, contains('You: that photo was from our last trip'));
      expect(
        q,
        isNot(equals('You: that photo was from our last trip')),
        reason: 'cues must ride WITH last words, not be replaced by them',
      );
    });

    test('omits empty cues so a cue-less beat is just last words', () {
      expect(composeRagQuery(lastWords: 'You: evening'), 'You: evening');
    });

    test('HOLD leftover: cue-less beat must not retrieve like last-1', () {
      expect(ragHasCues(), isFalse);
      expect(
        ragHasCues(emotion: '', fixation: '', hotJournalLine: ''),
        isFalse,
      );
      expect(ragHasCues(emotion: 'wistful'), isTrue);
      expect(ragHasCues(fixation: 'the spare key'), isTrue);
      expect(ragHasCues(hotJournalLine: 'I still think about the key'), isTrue);
      expect(
        shouldRetrieveRag(hasCues: false, reachingForQuote: false),
        isFalse,
        reason: 'cue-less sit-down skips last-1 search',
      );
      expect(
        shouldRetrieveRag(hasCues: false, reachingForQuote: true),
        isTrue,
        reason: 'quote-reach still retrieves',
      );
      expect(shouldRetrieveRag(hasCues: true, reachingForQuote: false), isTrue);
    });
  });

  group('lastWordsFromMessages', () {
    test(
      'keeps the latest line and nearby photo markers, not a last-3 dump',
      () {
        final msgs = [
          ChatMessage(text: 'old one', sender: 'Nia', isUser: false),
          ChatMessage(
            text: 'look',
            sender: 'You',
            isUser: true,
            metadata: {
              'is_user_image': true,
              'image_caption': 'a red kite over the bay',
            },
          ),
          ChatMessage(text: 'nice', sender: 'Nia', isUser: false),
          ChatMessage(
            text: 'That photo was from our last trip',
            sender: 'You',
            isUser: true,
          ),
        ];
        final words = lastWordsFromMessages(msgs);
        expect(words, contains('That photo was from our last trip'));
        expect(words, contains('[shared a photo: a red kite over the bay]'));
        expect(words, isNot(contains('old one')));
        expect(words, isNot(contains('You: look\nnice')));
      },
    );

    test(
      'HOLD leftover: quote-ask reads last spoken line, not photo captions',
      () {
        final msgs = [
          ChatMessage(
            text: 'look',
            sender: 'You',
            isUser: true,
            metadata: {
              'is_user_image': true,
              'image_caption': 'remember our beach day',
            },
          ),
          ChatMessage(text: 'Mind if I sit?', sender: 'You', isUser: true),
        ];
        final words = lastWordsFromMessages(msgs);
        expect(words, contains('remember our beach day'));
        expect(isReachingForQuote(words), isTrue);
        final spoken = lastSpokenLineFromMessages(msgs);
        expect(spoken, contains('Mind if I sit?'));
        expect(spoken, isNot(contains('remember our beach day')));
        expect(isReachingForQuote(spoken), isFalse);
      },
    );
  });

  group('isReachingForQuote / capRagWindows / dropCoveredRagWindows', () {
    test('remember/said/vows count as quote-reach; a plain beat does not', () {
      expect(isReachingForQuote('You: remember our wedding vows?'), isTrue);
      expect(isReachingForQuote('You: evening. mind if I sit?'), isFalse);
      expect(
        isReachingForQuote('You: I told you the tomatoes came in'),
        isFalse,
      );
      expect(isReachingForQuote('Nia: she said the cicadas started'), isFalse);
      expect(isReachingForQuote('You: Remember to lock the door?'), isFalse);
      expect(
        isReachingForQuote('You: Remember the tomatoes came in early?'),
        isFalse,
      );
      expect(isReachingForQuote('You: can you quote that'), isTrue);
      expect(isReachingForQuote('You: remember what you said'), isTrue);
      expect(isReachingForQuote('You: what did I promise'), isTrue);
      expect(isReachingForQuote('You: exact words'), isTrue);
      expect(isReachingForQuote('You: vows?'), isTrue);
    });

    test('normal path keeps one uncovered window; quote-reach keeps all', () {
      final a = _mem('Nia: the porch swing creaked', sessionId: 's1', pos: 2);
      final b = _mem('You: the red kite', sessionId: 's2', pos: 7);
      expect(capRagWindows([a, b], reachingForQuote: false), [a]);
      expect(capRagWindows([a, b], reachingForQuote: true), [a, b]);
    });

    test('a journal card that covers the beat drops that RAG window', () {
      final covered = _mem(
        'Nia: I still think about the lighthouse on the cliff',
        sessionId: 's1',
        pos: 4,
      );
      final leftover = _mem(
        'You: remember the red kite on the pier',
        sessionId: 's1',
        pos: 9,
      );
      final kept = dropCoveredRagWindows(
        [covered, leftover],
        ['I still think about the lighthouse on the cliff'],
      );
      expect(kept.map((m) => m.content).toList(), [leftover.content]);
    });

    test('an uncovered fact that left history still retrieves', () {
      final leftHistory = _mem(
        'Nia: the spare key lives under the third flowerpot',
        sessionId: 's1',
        pos: 3,
      );
      final kept = dropCoveredRagWindows(
        [leftHistory],
        ['I felt safe on the porch tonight'],
      );
      expect(kept, [leftHistory]);
    });

    test(
      'HOLD: filler still/think/about with a lighthouse card does not eat the flowerpot fact',
      () {
        final fact = _mem(
          'Nia: I still think about the spare key under the third flowerpot',
          sessionId: 's1',
          pos: 1,
        );
        final kept = dropCoveredRagWindows(
          [fact],
          ['I still think about the lighthouse'],
        );
        expect(
          kept,
          [fact],
          reason:
              'cover overlap must be content (flowerpot / lighthouse), not '
              'filler — this is the cabinet-card false drop',
        );
      },
    );

    test('HOLD lock: front-porch compound is not cover', () {
      final swing = _mem(
        'Nia: the front porch swing creaked tonight',
        sessionId: 's1',
        pos: 2,
      );
      final feeling = 'I felt safe on the front porch tonight';
      expect(
        coverContentTokens(
          feeling,
        ).intersection(coverContentTokens(swing.content)),
        {'frontporch'},
      );
      expect(dropCoveredRagWindows([swing], [feeling]), [
        swing,
      ], reason: 'shared place-compound {front, porch} is not cover');
    });

    test(
      'HOLD lock: leftover 2-token overlap is not cover — hallway keeps',
      () {
        const gist =
            'I still think about the spare key under the third flowerpot';
        final hallway = _mem(
          'Nia: the spare key lives in the hallway drawer',
          sessionId: 's1',
          pos: 2,
        );
        expect(
          coverContentTokens(
            hallway.content,
          ).intersection(coverContentTokens(gist)).length,
          greaterThanOrEqualTo(2),
          reason:
              'hallway shares leftover tokens ≥ 2 with the flowerpot gist — '
              'if that were the cover rule this window would drop',
        );
        expect(
          dropCoveredRagWindows([hallway], [gist]),
          [hallway],
          reason:
              'shared leftover tokens ≥ 2 is NOT cover — hallway is not a '
              'near-substring of the flowerpot card. A source-scan for '
              '2-token intersection as the cover rule MUST FAIL.',
        );
        final flower = _mem(
          'Nia: I still think about the spare key under the third flowerpot',
          sessionId: 's1',
          pos: 1,
        );
        expect(
          dropCoveredRagWindows([flower], [gist]),
          isEmpty,
          reason:
              'same-beat flowerpot gist DROPS because the card names the '
              'flowerpot in the window (near-substring), not 2-token overlap',
        );
      },
    );

    test(
      'HOLD lock: cover-drop source is near-substring, not leftover tokens',
      () {
        final src = File(
          'lib/services/chat/rag_injection.dart',
        ).readAsStringSync();
        final coveredAt = src.indexOf('bool _ragCoveredByJournal(');
        expect(coveredAt, greaterThanOrEqualTo(0));
        final coveredSlice = src.substring(
          coveredAt,
          (coveredAt + 280).clamp(0, src.length),
        );
        expect(src.contains('bool _nearCover('), isTrue);
        expect(src.contains('_kJournalBoilerplate'), isTrue);
        expect(src.contains('containsAll'), isTrue);
        expect(src.contains('longD.difference(shortD)'), isTrue);
        expect(
          src.contains('longer.contains(shorter)'),
          isFalse,
          reason: 'unanchored contains() is the key-inside-keyboard hole',
        );
        expect(
          coveredSlice.contains('.intersection('),
          isFalse,
          reason:
              'a source-scan for 2-token intersection as the cover rule '
              'MUST FAIL — product must not use shared-content-tokens ≥ 2',
        );
        expect(coveredSlice.contains('_nearCover('), isTrue);
        final fillerAt = src.indexOf('const _kCoverFiller = {');
        expect(fillerAt, greaterThanOrEqualTo(0));
        final filler = src.substring(fillerAt, src.indexOf('};', fillerAt));
        for (final w in ['garden', 'balcony', 'driveway']) {
          expect(
            filler.contains("'$w'"),
            isFalse,
            reason:
                "'$w' must not appear on the setting-noun / cover-filler "
                'place list',
          );
        }
      },
    );

    test('HOLD hole: short leftover and mixed span', () {
      final died = _mem('Nia: the spare key died', sessionId: 's1', pos: 2);
      expect(dropCoveredRagWindows([died], ['the spare key']), [
        died,
      ], reason: 'died is leftover even though length < 5');
      final gone = _mem('Nia: the spare key is gone', sessionId: 's1', pos: 3);
      expect(dropCoveredRagWindows([gone], ['the spare key']), [
        gone,
      ], reason: 'gone is leftover even though length < 5');
      final fell = _mem(
        'Nia: the third flowerpot fell',
        sessionId: 's1',
        pos: 4,
      );
      expect(dropCoveredRagWindows([fell], ['third flowerpot']), [
        fell,
      ], reason: 'fell is leftover — third flowerpot does not cover it');
      for (final verb in ['hid', 'ran']) {
        final m = _mem('Nia: the spare key $verb', sessionId: 's1', pos: 20);
        expect(dropCoveredRagWindows([m], ['the spare key']), [
          m,
        ], reason: '$verb is leftover even though length < 5');
      }
      const gist =
          'I still think about the spare key under the third flowerpot';
      final creakedSame = _mem(
        'Nia: I still think about the spare key under the third flowerpot that creaked',
        sessionId: 's1',
        pos: 5,
      );
      expect(
        dropCoveredRagWindows([creakedSame], [gist]),
        [creakedSame],
        reason:
            'suffix leftover is an extra fact — that creaked is not '
            'same-beat just because creaked used to be on a list',
      );
      final mixed = _mem(
        'Nia: I still think about the spare key under the third flowerpot\n'
        'Nia: the swing creaked',
        sessionId: 's1',
        pos: 6,
      );
      final kept = dropCoveredRagWindows([mixed], [gist]);
      expect(kept, hasLength(1));
      expect(
        kept.first.content,
        contains('swing'),
        reason: 'uncovered swing line must reach the prompt',
      );
      expect(
        kept.first.content,
        isNot(contains('flowerpot')),
        reason: 'covered flowerpot line is stripped, not the whole span',
      );
      final both = _mem(
        'You: the spare key lives under the third flowerpot\n'
        'Nia: I still think about the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 7,
      );
      final keptBoth = dropCoveredRagWindows([both], [gist]);
      expect(keptBoth, hasLength(1));
      expect(
        keptBoth.first.content,
        contains('lives'),
        reason: 'lives is leftover — leftover-empty only, so this line KEEPS',
      );
      expect(
        keptBoth.first.content,
        contains('You: the spare key lives under the third flowerpot'),
        reason: 'two-line lives-under: the lives line KEEPS',
      );
      expect(
        keptBoth.first.content,
        isNot(contains('I still think about')),
        reason: 'exact gist line still strips from the two-line window',
      );
    });

    test('HOLD hole: extra fact on the line and stripped span', () {
      const gist =
          'I still think about the spare key under the third flowerpot';
      final andSwing = _mem(
        'Nia: the spare key under the third flowerpot and the swing creaked',
        sessionId: 's1',
        pos: 2,
      );
      expect(
        dropCoveredRagWindows([andSwing], [gist]),
        [andSwing],
        reason:
            'swing creaked is a second fact — 3 shared distinctive tokens '
            'must not drop it',
      );
      final keyboard = _mem(
        'Nia: the spare keyboard sits on the third flowerpot',
        sessionId: 's1',
        pos: 3,
      );
      expect(dropCoveredRagWindows([keyboard], [gist]), [
        keyboard,
      ], reason: 'key is not keyboard — 3 shared tokens must not skip that');
      final mixed = _mem(
        'Nia: I still think about the spare key under the third flowerpot\n'
        'Nia: the swing creaked',
        sessionId: 's1',
        pos: 2,
        end: 3,
      );
      final kept = dropCoveredRagWindows([mixed], [gist]);
      expect(kept, hasLength(1));
      expect(kept.first.content, contains('swing'));
      expect(kept.first.positionStart, 3);
      expect(kept.first.positionEnd, 3);
      expect(
        RetrievedMemory.excludingPositions(kept, {2}, currentSessionId: 's1'),
        hasLength(1),
        reason:
            'stripped flowerpot line must not keep pos 2 — receipt / '
            'excludingPositions treat the swing as this retrieval',
      );
      expect(
        RetrievedMemory.excludingPositions(
          [mixed],
          {2},
          currentSessionId: 's1',
        ),
        isEmpty,
        reason: 'the unstripped 2–3 span still overlaps the flowerpot line',
      );
    });

    test('HOLD hole: leftover kind, remap gap, two-word paraphrase', () {
      const gist =
          'I still think about the spare key under the third flowerpot';
      final burned = _mem(
        'Nia: I still think about the spare key under the third flowerpot burned',
        sessionId: 's1',
        pos: 2,
      );
      expect(dropCoveredRagWindows([burned], [gist]), [
        burned,
      ], reason: 'burned is a one-word second fact, not paraphrase');
      final lighthouse = _mem(
        'Nia: I still think about the spare key under the third flowerpot lighthouse',
        sessionId: 's1',
        pos: 3,
      );
      expect(dropCoveredRagWindows([lighthouse], [gist]), [
        lighthouse,
      ], reason: 'lighthouse is a one-word second fact, not paraphrase');
      final hidden = _mem(
        'Nia: the spare key lives hidden under the third flowerpot',
        sessionId: 's1',
        pos: 4,
      );
      expect(
        dropCoveredRagWindows([hidden], [gist]),
        isNot(isEmpty),
        reason: 'lives hidden has leftover — leftover-empty only, so KEEP',
      );
      final gapped = _mem(
        'Nia: the porch swing creaked tonight\n'
        'Nia: I still think about the spare key under the third flowerpot\n'
        'Nia: I sat on the front garden',
        sessionId: 's1',
        pos: 10,
        end: 12,
      );
      final gapKept = dropCoveredRagWindows([gapped], [gist]);
      expect(gapKept, hasLength(2));
      expect(gapKept.map((m) => m.positionStart).toList(), [10, 12]);
      expect(
        gapKept.any((m) => m.positionStart <= 11 && m.positionEnd >= 11),
        isFalse,
        reason: 'middle covered pos must not stay inside a first-to-last span',
      );
      final wide = _mem(
        'Nia: I still think about the spare key under the third flowerpot\n'
        'Nia: the swing creaked',
        sessionId: 's1',
        pos: 10,
        end: 13,
      );
      final wideKept = dropCoveredRagWindows([wide], [gist]);
      expect(wideKept, hasLength(1));
      expect(wideKept.first.positionStart, 12);
      expect(wideKept.first.positionEnd, 13);
      expect(
        RetrievedMemory.excludingPositions(wideKept, {
          10,
          11,
        }, currentSessionId: 's1'),
        hasLength(1),
        reason: 'span ≠ line count must not keep the flowerpot pos',
      );
    });

    test('HOLD hole: interior restatement, suffix extra fact, no verb list', () {
      const gist =
          'I still think about the spare key under the third flowerpot';
      for (final verb in ['tucked', 'buried', 'stays', 'rests']) {
        final m = _mem(
          'Nia: the spare key $verb under the third flowerpot',
          sessionId: 's1',
          pos: 8,
        );
        expect(
          dropCoveredRagWindows([m], [gist]),
          isNot(isEmpty),
          reason: '"$verb under" has leftover — leftover-empty only, so KEEP',
        );
      }
      final potCreaked = _mem(
        'Nia: the spare key under the third flowerpot creaked',
        sessionId: 's1',
        pos: 9,
      );
      expect(dropCoveredRagWindows([potCreaked], [gist]), [
        potCreaked,
      ], reason: 'the pot creaked is a suffix extra fact');
      final died = _mem(
        'Nia: I still think about the spare key under the third flowerpot died',
        sessionId: 's1',
        pos: 11,
      );
      expect(dropCoveredRagWindows([died], [gist]), [
        died,
      ], reason: 'short suffix leftover on a 3-D gist is an extra fact');
      final sat = _mem(
        'Nia: I still think about the spare key under the third flowerpot sat',
        sessionId: 's1',
        pos: 12,
      );
      expect(dropCoveredRagWindows([sat], [gist]), [
        sat,
      ], reason: 'sat on the complete gist is an extra fact');

      for (final verb in [
        'hidden',
        'tucked',
        'buried',
        'stays',
        'rests',
        'lives',
      ]) {
        final suffix = _mem(
          'Nia: the spare key under the third flowerpot $verb',
          sessionId: 's1',
          pos: 13,
        );
        expect(
          dropCoveredRagWindows([suffix], [gist]),
          isNot(isEmpty),
          reason: '$verb as suffix has leftover — leftover-empty only, so KEEP',
        );
      }
      expect(
        dropCoveredRagWindows(
          [
            _mem(
              'Nia: the spare key under the third flowerpot lives hidden',
              sessionId: 's1',
              pos: 14,
            ),
          ],
          [gist],
        ),
        isNot(isEmpty),
        reason:
            'lives hidden as suffix has leftover — leftover-empty only, so KEEP',
      );
      for (final extra in [
        'burned',
        'lighthouse',
        'creaked',
        'died',
        'sat',
        'fell',
        'hid',
        'stolen',
        'broken',
        'locked',
        'rusty',
        'moved',
        'taken',
        'yellow',
      ]) {
        final interior = _mem(
          'Nia: the spare key $extra under the third flowerpot',
          sessionId: 's1',
          pos: 15,
        );
        expect(dropCoveredRagWindows([interior], [gist]), [
          interior,
        ], reason: '$extra as interior is still an extra fact');
      }
      for (final extra in ['hid', 'sat', 'died']) {
        final prefix = _mem(
          'Nia: $extra the spare key under the third flowerpot',
          sessionId: 's1',
          pos: 16,
        );
        expect(dropCoveredRagWindows([prefix], [gist]), [
          prefix,
        ], reason: 'short prefix leftover $extra is an extra fact');
      }
      for (final verb in [
        'hidden',
        'tucked',
        'buried',
        'stays',
        'rests',
        'lives',
      ]) {
        final prefix = _mem(
          'Nia: $verb the spare key under the third flowerpot',
          sessionId: 's1',
          pos: 17,
        );
        expect(
          dropCoveredRagWindows([prefix], [gist]),
          isNot(isEmpty),
          reason: '$verb as prefix has leftover — leftover-empty only, so KEEP',
        );
      }
      expect(
        dropCoveredRagWindows(
          [
            _mem(
              'Nia: lives hidden the spare key under the third flowerpot',
              sessionId: 's1',
              pos: 18,
            ),
          ],
          [gist],
        ),
        isNot(isEmpty),
        reason:
            'lives hidden as prefix has leftover — leftover-empty only, so KEEP',
      );
      final interiorHidden = _mem(
        'Nia: the spare key hidden under the third flowerpot',
        sessionId: 's1',
        pos: 19,
      );
      expect(dropCoveredRagWindows([interiorHidden], [gist]), [
        interiorHidden,
      ], reason: 'interior hidden has leftover — leftover-empty only, so KEEP');
      final interiorLives = _mem(
        'Nia: the spare key lives under the third flowerpot',
        sessionId: 's1',
        pos: 21,
      );
      expect(dropCoveredRagWindows([interiorLives], [gist]), [
        interiorLives,
      ], reason: 'interior lives has leftover — leftover-empty only, so KEEP');
    });

    test('HOLD hole: filler lists do not erase cover leftover', () {
      const gist =
          'I still think about the spare key under the third flowerpot';
      for (final extra in ['safe', 'felt', 'remember']) {
        final win = _mem(
          'Nia: I still think about the spare key under the third flowerpot $extra',
          sessionId: 's1',
          pos: 22,
        );
        expect(
          dropCoveredRagWindows([win], [gist]),
          [win],
          reason: 'boilerplate leftover $extra must KEEP — not leftover-empty',
        );
      }
      for (final extra in ['yesterday', 'tomorrow', 'morning', 'evening']) {
        final win = _mem(
          'Nia: I still think about the spare key under the third flowerpot $extra',
          sessionId: 's1',
          pos: 23,
        );
        expect(dropCoveredRagWindows([win], [gist]), [
          win,
        ], reason: 'time leftover $extra must KEEP — not leftover-empty');
      }
      const porch = 'Nia: the porch swing creaked tonight';
      final tomorrow = _mem(
        'Nia: the porch swing creaked tomorrow',
        sessionId: 's1',
        pos: 24,
      );
      expect(dropCoveredRagWindows([tomorrow], [porch]), [
        tomorrow,
      ], reason: 'porch-swing × tomorrow is leftover, not leftover-empty');
      final withoutWin = _mem(
        'Nia: I still think about the spare key without the third flowerpot',
        sessionId: 's1',
        pos: 25,
      );
      expect(
        dropCoveredRagWindows([withoutWin], [gist]),
        isEmpty,
        reason:
            'without vs under still DROPS — both are function words. '
            'Do not grow the set to make without KEEP',
      );
    });

    test('HOLD hole: prefix card does not cover a bigger fact', () {
      final gardenSwing = _mem(
        'Nia: the front garden swing creaked tonight',
        sessionId: 's1',
        pos: 2,
      );
      expect(dropCoveredRagWindows([gardenSwing], ['the front garden']), [
        gardenSwing,
      ], reason: 'front garden must not drop front-garden-swing');
      final swingAndPot = _mem(
        'Nia: the porch swing creaked by the flowerpot',
        sessionId: 's1',
        pos: 3,
      );
      expect(
        dropCoveredRagWindows([swingAndPot], ['The porch swing.']),
        [swingAndPot],
        reason: 'porch swing must not drop a window that also names flowerpot',
      );
      final frontPorchSwing = _mem(
        'Nia: I sat on the front porch swing',
        sessionId: 's1',
        pos: 4,
      );
      expect(
        dropCoveredRagWindows([frontPorchSwing], ['I sat on her porch swing']),
        [frontPorchSwing],
        reason: '{porch, swing} must not drop front porch swing',
      );
      final lovedPot = _mem(
        'Nia: I loved the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 1,
      );
      expect(dropCoveredRagWindows([lovedPot], ['I loved it']), [
        lovedPot,
      ], reason: 'mood-only loved must not cover a flowerpot fact');
      final worryPot = _mem(
        'Nia: I worry about the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 5,
      );
      expect(dropCoveredRagWindows([worryPot], ['I worry']), [
        worryPot,
      ], reason: 'mood-only worry must not cover a flowerpot fact');
      final flower = _mem(
        'Nia: I still think about the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 6,
      );
      expect(
        dropCoveredRagWindows(
          [flower],
          ['I still think about the spare key under the third flowerpot'],
        ),
        isEmpty,
        reason: 'same-beat flowerpot gist still drops',
      );
    });

    test('HOLD hole: whole tokens + distinctive — key is not keyboard', () {
      final keyboard = _mem(
        'Nia: I still think about the spare keyboard in the attic',
        sessionId: 's1',
        pos: 2,
      );
      expect(
        dropCoveredRagWindows(
          [keyboard],
          ['I still think about the spare key'],
        ),
        [keyboard],
        reason: 'key is not inside keyboard — whole tokens only',
      );
      final gardenKey = _mem(
        'Nia: I felt safe on the front garden until the spare key went missing',
        sessionId: 's1',
        pos: 3,
      );
      expect(dropCoveredRagWindows([gardenKey], ['I felt safe tonight']), [
        gardenKey,
      ], reason: 'mood-only felt/safe must not cover a longer beat');
      final flower = _mem(
        'Nia: I still think about the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 1,
      );
      expect(dropCoveredRagWindows([flower], ['I still think about it']), [
        flower,
      ], reason: 'still/think boilerplate must not eat the flowerpot window');
      expect(
        dropCoveredRagWindows(
          [flower],
          ['I still think about the spare key under the third flowerpot'],
        ),
        isEmpty,
        reason: 'same-beat flowerpot gist still drops',
      );
    });

    test('HOLD hole: garden/balcony/driveway + his/her are not a new list', () {
      for (final phrase in ['front garden', 'back balcony', 'side driveway']) {
        final feeling = 'I felt safe on the $phrase tonight';
        final swing = _mem(
          'Nia: the $phrase swing creaked tonight',
          sessionId: 's1',
          pos: 2,
        );
        expect(
          coverContentTokens(feeling),
          isNot(contains(phrase.replaceAll(' ', ''))),
        );
        expect(dropCoveredRagWindows([swing], [feeling]), [
          swing,
        ], reason: 'feeling × $phrase swing must not cover-drop');
      }
      expect(
        coverContentTokens('his porch swing'),
        isNot(contains('hisporch')),
      );
      expect(
        coverContentTokens('her porch swing'),
        isNot(contains('herporch')),
      );
      expect(
        coverContentTokens('that porch swing'),
        isNot(contains('thatporch')),
      );
      expect(coverContentTokens('off the porch'), isNot(contains('offporch')));
      expect(coverContentTokens('in the porch'), isNot(contains('inporch')));
      expect(coverContentTokens('at the porch'), isNot(contains('atporch')));
      final fact = _mem(
        'Nia: I still think about the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 1,
      );
      expect(
        dropCoveredRagWindows(
          [fact],
          ['I still think about the spare key under the third flowerpot'],
        ),
        isEmpty,
        reason: 'same-beat flowerpot gist still drops',
      );
    });

    test('HOLD hole: setting nouns are filler — not a longer noun list', () {
      for (final phrase in [
        'front steps',
        'back patio',
        'front walk',
        'back path',
      ]) {
        final feeling = 'I felt safe on the $phrase tonight';
        final swing = _mem(
          'Nia: the $phrase swing creaked tonight',
          sessionId: 's1',
          pos: 2,
        );
        expect(
          coverContentTokens(feeling),
          isNot(contains(phrase.split(' ').last)),
        );
        expect(
          coverContentTokens(feeling),
          isNot(contains(phrase.replaceAll(' ', ''))),
        );
        expect(dropCoveredRagWindows([swing], [feeling]), [
          swing,
        ], reason: 'feeling × $phrase swing must not cover-drop');
      }
      for (final noun in [
        'porch',
        'yard',
        'lawn',
        'deck',
        'stoop',
        'steps',
        'patio',
        'walk',
        'path',
      ]) {
        expect(
          coverContentTokens('felt safe $noun'),
          isNot(contains(noun)),
          reason: '$noun is setting-noun filler — not a longer fold list',
        );
      }
      expect(
        coverContentTokens('this porch swing'),
        isNot(contains('thisporch')),
      );
      expect(coverContentTokens('my porch swing'), isNot(contains('myporch')));
      expect(
        coverContentTokens('our porch swing'),
        isNot(contains('ourporch')),
      );
      expect(
        coverContentTokens('your porch swing'),
        isNot(contains('yourporch')),
      );
      expect(coverContentTokens('I sat on porch'), isNot(contains('onporch')));
      const gist = 'Nia: the porch swing creaked tonight';
      expect(
        dropCoveredRagWindows(
          [
            _mem(
              'Nia: this porch swing creaked tonight',
              sessionId: 's1',
              pos: 2,
            ),
          ],
          [gist],
        ),
        isEmpty,
        reason: 'same-beat this-porch swing still drops',
      );
      expect(
        dropCoveredRagWindows(
          [
            _mem(
              'Nia: my porch swing creaked tonight',
              sessionId: 's1',
              pos: 3,
            ),
          ],
          [gist],
        ),
        isEmpty,
        reason: 'same-beat my-porch swing still drops',
      );
      expect(
        dropCoveredRagWindows(
          [
            _mem(
              'Nia: our porch swing creaked tonight',
              sessionId: 's1',
              pos: 5,
            ),
          ],
          [gist],
        ),
        isEmpty,
        reason: 'same-beat our-porch swing still drops',
      );
      expect(
        dropCoveredRagWindows(
          [
            _mem(
              'Nia: your porch swing creaked tonight',
              sessionId: 's1',
              pos: 6,
            ),
          ],
          [gist],
        ),
        isEmpty,
        reason: 'same-beat your-porch swing still drops',
      );
      expect(
        dropCoveredRagWindows(
          [
            _mem(
              'I sat on porch; the swing creaked tonight',
              sessionId: 's1',
              pos: 4,
            ),
          ],
          [gist],
        ),
        isNot(isEmpty),
        reason: 'short leftover sat is an extra fact, not same-beat',
      );
      final fact = _mem(
        'Nia: I still think about the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 1,
      );
      expect(
        dropCoveredRagWindows(
          [fact],
          ['I still think about the spare key under the third flowerpot'],
        ),
        isEmpty,
        reason: 'same-beat flowerpot gist still drops',
      );
    });

    test('HOLD hole: any token before a place noun folds — screened porch', () {
      for (final phrase in [
        'screened porch',
        'covered porch',
        'wraparound porch',
        'wraparound deck',
      ]) {
        final folded = phrase.replaceAll(' ', '');
        final feeling = 'I felt safe on the $phrase tonight';
        final swing = _mem(
          'Nia: the $phrase swing creaked tonight',
          sessionId: 's1',
          pos: 2,
        );
        expect(coverContentTokens(feeling), contains(folded));
        expect(
          coverContentTokens(feeling),
          isNot(contains(phrase.split(' ').first)),
        );
        expect(coverContentTokens('the porch'), isNot(contains('porch')));
        expect(coverContentTokens('the porch'), isNot(contains('theporch')));
        expect(dropCoveredRagWindows([swing], [feeling]), [
          swing,
        ], reason: 'feeling × $phrase swing must not cover-drop');
      }
      for (final article in ['the', 'a', 'an']) {
        expect(
          coverContentTokens('$article porch'),
          isNot(contains('porch')),
          reason: '$article stays filler and porch is setting-noun filler',
        );
        expect(
          coverContentTokens('$article porch'),
          isNot(contains('${article}porch')),
          reason: 'do not fold "$article porch" into ${article}porch',
        );
      }
      final fact = _mem(
        'Nia: I still think about the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 1,
      );
      expect(
        dropCoveredRagWindows(
          [fact],
          ['I still think about the spare key under the third flowerpot'],
        ),
        isEmpty,
        reason: 'same-beat flowerpot gist still drops',
      );
    });

    test('HOLD hole: side porch and front lawn fold — not two more pairs', () {
      for (final phrase in [
        'side porch',
        'front lawn',
        'side deck',
        'back stoop',
      ]) {
        final folded = phrase.replaceAll(' ', '');
        final feeling = 'I felt safe on the $phrase tonight';
        final swing = _mem(
          'Nia: the $phrase swing creaked tonight',
          sessionId: 's1',
          pos: 2,
        );
        expect(coverContentTokens(feeling), contains(folded));
        expect(
          coverContentTokens(feeling),
          isNot(contains(phrase.split(' ').first)),
        );
        expect(dropCoveredRagWindows([swing], [feeling]), [
          swing,
        ], reason: 'feeling × $phrase swing must not cover-drop');
      }
      final fact = _mem(
        'Nia: I still think about the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 1,
      );
      expect(
        dropCoveredRagWindows(
          [fact],
          ['I still think about the spare key under the third flowerpot'],
        ),
        isEmpty,
        reason: 'same-beat flowerpot gist still drops',
      );
    });

    test('HOLD lock: front/back porch and yard fold to one token', () {
      const compounds = {
        'front porch': 'frontporch',
        'back porch': 'backporch',
        'front yard': 'frontyard',
        'back yard': 'backyard',
      };
      for (final e in compounds.entries) {
        final phrase = e.key;
        final folded = e.value;
        final feeling = 'I felt safe on the $phrase tonight';
        final swing = _mem(
          'Nia: the $phrase swing creaked tonight',
          sessionId: 's1',
          pos: 2,
        );
        expect(
          coverContentTokens(feeling),
          contains(folded),
          reason: '"$phrase" must fold to one token ($folded)',
        );
        expect(
          coverContentTokens(feeling),
          isNot(contains(phrase.split(' ').first)),
          reason: '"$phrase" must not stay two tokens',
        );
        expect(
          coverContentTokens(
            feeling,
          ).intersection(coverContentTokens(swing.content)),
          {folded},
        );
        expect(dropCoveredRagWindows([swing], [feeling]), [
          swing,
        ], reason: 'feeling × $phrase swing is not cover');
      }
    });

    test('HOLD r2: porch feeling does not eat a porch-swing fact', () {
      final swing = _mem(
        'Nia: the porch swing creaked',
        sessionId: 's1',
        pos: 2,
      );
      final kept = dropCoveredRagWindows(
        [swing],
        ['I felt safe on the porch tonight'],
      );
      expect(kept, [
        swing,
      ], reason: 'one shared place/noun (porch) is not cover');
    });

    test('HOLD leftover: porch+tonight is setting+time, not cover', () {
      final swing = _mem(
        'Nia: the porch swing creaked tonight',
        sessionId: 's1',
        pos: 2,
      );
      expect(
        coverContentTokens('I felt safe on the porch tonight'),
        isNot(contains('tonight')),
      );
      expect(
        coverContentTokens('Nia: the porch swing creaked tonight'),
        isNot(contains('tonight')),
      );
      final kept = dropCoveredRagWindows(
        [swing],
        ['I felt safe on the porch tonight'],
      );
      expect(kept, [
        swing,
      ], reason: 'tonight/today/night are filler — porch+tonight is not cover');
    });

    test(
      'HOLD leftover: tonight/today/night/morning/evening are cover filler',
      () {
        const words = ['tonight', 'today', 'night', 'morning', 'evening'];
        for (final w in words) {
          expect(
            coverContentTokens('porch $w'),
            isNot(contains(w)),
            reason: '$w is time filler — must not count as cover',
          );
          final swing = _mem(
            'Nia: the porch swing creaked $w',
            sessionId: 's1',
            pos: 2,
          );
          final kept = dropCoveredRagWindows(
            [swing],
            ['I felt safe on the porch $w'],
          );
          expect(
            kept,
            [swing],
            reason:
                'Porch feeling × porch swing creaked $w must not drop the '
                'window — $w is filler, one shared noun (porch) is not cover',
          );
        }
      },
    );

    test('HOLD r2: one shared spare token is not cover', () {
      final fact = _mem(
        'Nia: I still think about the spare key under the third flowerpot',
        sessionId: 's1',
        pos: 1,
      );
      final kept = dropCoveredRagWindows(
        [fact],
        ['I still think about the spare room'],
      );
      expect(kept, [fact], reason: 'one shared noun (spare) is not cover');
    });

    test(
      'HOLD r2: same-beat flowerpot gist still drops the covered window',
      () {
        final fact = _mem(
          'Nia: I still think about the spare key under the third flowerpot',
          sessionId: 's1',
          pos: 1,
        );
        expect(
          dropCoveredRagWindows(
            [fact],
            ['I still think about the spare key under the third flowerpot'],
          ),
          isEmpty,
          reason: 'same-beat flowerpot gist must still drop that window',
        );
      },
    );

    test(
      'HOLD: empty cover (Journal off / no gist this beat) does not cover-drop',
      () {
        final fact = _mem(
          'Nia: the spare key lives under the third flowerpot',
          sessionId: 's1',
          pos: 1,
        );
        expect(dropCoveredRagWindows([fact], const []), [fact]);
      },
    );
  });

  group('buildRagMemoriesBlock', () {
    test(
      'default frame is remembered-from-earlier, not Exact earlier lines',
      () {
        final m = _mem('Nia: the swing creaked', sessionId: 's1', pos: 2);
        final block = buildRagMemoriesBlock(
          memories: [m],
          currentSessionId: 's1',
          days: {m: 1},
          reachingForQuote: false,
        );
        expect(block, contains(kRagRememberedHeader.trim()));
        expect(block, contains('- (Day 1) the swing creaked'));
        expect(block, isNot(contains('Nia:')));
        expect(block, isNot(contains('Exact earlier lines')));
      },
    );

    test(
      'HOLD leftover: plain turn is one remembered line, not the transcript',
      () {
        final m = _mem(
          'You: the spare key lives under the third flowerpot\n'
          'Nia: I still think about the spare key under the third flowerpot',
          sessionId: 's1',
          pos: 1,
        );
        final plain = buildRagMemoriesBlock(
          memories: [m],
          currentSessionId: 's1',
          days: {m: 1},
          reachingForQuote: false,
        );
        expect(plain, contains(kRagRememberedHeader.trim()));
        expect(plain, contains('spare key'));
        expect(plain, contains('flowerpot'));
        expect(plain, isNot(contains('You: the spare key')));
        expect(plain.split('\n').where((l) => l.startsWith('- ')).length, 1);
        final quoted = buildRagMemoriesBlock(
          memories: [m],
          currentSessionId: 's1',
          days: {m: 1},
          reachingForQuote: true,
        );
        expect(quoted, contains(kRagQuoteHeader.trim()));
        expect(
          quoted,
          contains('You: the spare key lives under the third flowerpot'),
        );
        expect(
          quoted,
          contains(
            'Nia: I still think about the spare key under the third flowerpot',
          ),
          reason: 'quote-reach still gets the raw You:/Nia: window',
        );
      },
    );

    test(
      'HOLD leftover: rememberedLineFromWindow is one body, not the tape',
      () {
        const window =
            'You: the spare key lives under the third flowerpot\n'
            'Nia: I still think about the spare key under the third flowerpot';
        final line = rememberedLineFromWindow(window);
        expect(line.contains('\n'), isFalse);
        expect(line, isNot(contains('You:')));
        expect(line, isNot(contains('Nia:')));
        expect(line, contains('flowerpot'));
        expect(line, contains('spare key'));
      },
    );

    test('HOLD lock: single-line window strips the speaker prefix too', () {
      expect(
        rememberedLineFromWindow('Nia: the swing creaked'),
        'the swing creaked',
      );
      expect(
        rememberedLineFromWindow('Nia:the swing creaked'),
        'the swing creaked',
        reason: 'optional space after the colon — Nia:the must strip',
      );
      final m = _mem('Nia: the swing creaked', sessionId: 's1', pos: 2);
      final block = buildRagMemoriesBlock(
        memories: [m],
        currentSessionId: 's1',
        days: {m: 1},
        reachingForQuote: false,
      );
      expect(block, contains('- (Day 1) the swing creaked'));
      expect(block, isNot(contains('Nia:')));
      final quoted = buildRagMemoriesBlock(
        memories: [m],
        currentSessionId: 's1',
        days: {m: 2},
        reachingForQuote: true,
      );
      expect(quoted, contains('Nia: the swing creaked'));
    });

    test('quote-reach uses the quote header; day stamp stays display-only', () {
      final m = _mem(
        'Nia: I never want to see you again',
        sessionId: 's1',
        pos: 2,
      );
      final block = buildRagMemoriesBlock(
        memories: [m],
        currentSessionId: 's1',
        days: {m: 2},
        reachingForQuote: true,
      );
      expect(block, contains(kRagQuoteHeader.trim()));
      expect(block, contains('(Day 2)'));
      expect(block, isNot(contains('Exact earlier lines')));
    });
  });
}
