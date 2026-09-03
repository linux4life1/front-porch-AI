// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Opening a long chat loads the last 24 rows. Those 24 can all fit in
// context (droppedMessages == 0) while basePosition still hides the rest
// of the story. Recap suppression used droppedMessages == 0 alone, so a
// tail-open send dropped the recap that was covering the unseen start.
// Continue skipped RAG by zeroing droppedMessages; the same tail-open OR
// of basePosition made that skip a no-op.
//
// Proven red: recapIsRedundant ignoring basePosition returns true at
// dropped 0 / base 976; Continue RAG scan fails without the mode branch.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';

void main() {
  group('recapIsRedundant', () {
    test('short chat that all fitted has no unseen history', () {
      expect(recapIsRedundant(dropped: 0, basePosition: 0), isTrue);
    });

    test('in-window drops still need the recap', () {
      expect(recapIsRedundant(dropped: 12, basePosition: 0), isFalse);
    });

    test('tail-open with a fitted 24-row window still needs the recap', () {
      expect(
        recapIsRedundant(dropped: 0, basePosition: 976),
        isFalse,
        reason:
            'THE BUG: droppedCount 0 on a tail-open is not "the whole chat"',
      );
    });
  });

  test('plan suppresses recap only when recapIsRedundant', () {
    final src = File(
      'lib/services/chat/chat_service_generation_plan.dart',
    ).readAsStringSync();
    expect(src, contains('recapIsRedundant('));
    expect(src, contains('basePosition: _history.basePosition'));
    expect(
      src,
      isNot(contains('if (t.droppedMessages == 0) {')),
      reason: 'must not drop the recap on a fitted tail-open window',
    );
  });

  test('Continue RAG skip is a mode branch, not droppedMessages = 0', () {
    final src = File(
      'lib/services/chat/chat_service_generation_rag.dart',
    ).readAsStringSync();
    expect(src, contains('t.mode == GenerationMode.continue_'));
    expect(src, contains('Skipping memory retrieval — Continue'));
    final continueIdx = src.indexOf('t.mode == GenerationMode.continue_');
    final retrieveIdx = src.indexOf(
      't.droppedMessages > 0 || _history.basePosition > 0',
    );
    expect(continueIdx, greaterThanOrEqualTo(0));
    expect(retrieveIdx, greaterThan(continueIdx));
  });
}
