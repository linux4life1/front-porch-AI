// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Group speaker costume helpers (docs/design/group-speaker-card-swap.md).
// Proven red: implement the roster as "join every persona" and the names-only
// test fails.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  test('roster is names only', () {
    final line = buildGroupRosterLine(
      memberNames: const ['Zinna', 'Senjumaru'],
      userName: 'Alex',
    );
    expect(line, contains('Also present:'));
    expect(line, contains('Zinna'));
    expect(line, contains('Senjumaru'));
    expect(line, contains('Alex'));
    expect(line, isNot(contains('Persona:')));
    expect(line, isNot(contains('ZINNA_PERSONA_MARKER')));
  });

  test('roster is stable across speakers', () {
    final zinnaTurn = buildGroupRosterLine(
      memberNames: const ['Zinna', 'Senjumaru'],
      userName: 'Alex',
    );
    final senjuTurn = buildGroupRosterLine(
      memberNames: const ['Zinna', 'Senjumaru'],
      userName: 'Alex',
    );
    expect(zinnaTurn, senjuTurn);
  });

  test('observer roster omits the user', () {
    final line = buildGroupRosterLine(
      memberNames: const ['Zinna', 'Senjumaru'],
      userName: 'Alex',
      observerMode: true,
    );
    expect(line, contains('Zinna'));
    expect(line, contains('Senjumaru'));
    expect(line, isNot(contains('Alex')));
  });

  test('slap names the speaker and bans the rest', () {
    final note = buildSpeakerTurnNote(
      speakerName: 'Senjumaru',
      otherMemberNames: const ['Zinna'],
      userName: 'Alex',
    );
    expect(note, contains('You are Senjumaru'));
    expect(note, contains('You are not Zinna'));
    expect(note, contains('You are not Alex'));
    expect(note, contains('Reply ONLY as Senjumaru'));
    expect(note, contains('dialogue, actions, and thoughts'));
    expect(note, contains('Do NOT write, speak, or narrate anything for'));
    expect(note, contains('Zinna or Alex'));
  });

  test('slap sanitizes brackets in names', () {
    final note = buildSpeakerTurnNote(
      speakerName: 'Senj[umaru]',
      otherMemberNames: const ['Zin[na]'],
      userName: 'Al[ex]',
    );
    expect(note, contains('You are Senj(umaru)'));
    expect(note, contains('You are not Zin(na)'));
    expect(note, contains('You are not Al(ex)'));
    expect(note, isNot(contains('Senj[umaru]')));
    expect(note, isNot(contains('Zin[na]')));
    expect(note, isNot(contains('Al[ex]')));
  });

  test('observer slap omits the user', () {
    final note = buildSpeakerTurnNote(
      speakerName: 'Senjumaru',
      otherMemberNames: const ['Zinna'],
      userName: 'Alex',
      observerMode: true,
    );
    expect(note, contains('You are Senjumaru'));
    expect(note, contains('You are not Zinna'));
    expect(note, isNot(contains('Alex')));
  });

  test('persona line is speaker only', () {
    expect(
      buildSpeakerPersonaLine(name: 'Senjumaru', personality: 'tall and quiet'),
      "Senjumaru's Persona: tall and quiet",
    );
  });
}
