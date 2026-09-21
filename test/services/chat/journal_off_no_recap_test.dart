// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Journal maintenance is gated on journalEnabled. Recap injection was not:
// a stale `_summary` still rode the prompt after the user turned Journal
// off. Guests stay empty. RAG query compose may still run.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/prompt_injection/recap_injection.dart';

void main() {
  test('generation blocks gate recap on journalEnabled', () {
    final src = File(
      'lib/services/chat/chat_service_generation_blocks.dart',
    ).readAsStringSync();
    final recap = src.indexOf('t.summaryBlock');
    expect(recap, greaterThanOrEqualTo(0));
    final rag = src.indexOf('Cued query for journal cold-resurface');
    expect(rag, greaterThan(recap));
    final assignment = src.substring(recap, rag);
    expect(
      assignment.contains('journalEnabled'),
      isTrue,
      reason: 'stale _summary must not inject when Journal is off',
    );
    expect(
      assignment.contains('guestSpeaker'),
      isTrue,
      reason: 'guests never journal; a host recap is a competing claim',
    );
  });

  test('RAG compose stays reachable when Journal is off', () {
    final src = File(
      'lib/services/chat/chat_service_generation_blocks.dart',
    ).readAsStringSync();
    final rag = src.indexOf('Compose even when the Journal toggle is off');
    expect(rag, greaterThanOrEqualTo(0));
    final journalBlock = src.indexOf(
      'if (_storageService.memorySettings.journalEnabled',
      rag,
    );
    expect(
      journalBlock,
      greaterThan(rag),
      reason: 'RAG compose is the ungated sibling; journal cards stay gated',
    );
  });

  test('recapBlockForTurn omits recap when Journal is off', () {
    const recap = 'They met on the porch.';
    expect(
      recapBlockForTurn(recap: recap, journalEnabled: false, isGuest: false),
      isEmpty,
    );
    expect(
      recapBlockForTurn(recap: recap, journalEnabled: true, isGuest: false),
      contains('They met on the porch.'),
    );
    expect(
      recapBlockForTurn(recap: recap, journalEnabled: true, isGuest: true),
      isEmpty,
      reason: 'guests stay empty',
    );
    expect(
      recapBlockForTurn(recap: '', journalEnabled: true, isGuest: false),
      isEmpty,
    );
  });
}
