// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The plan gate reads the speaker's work fields the way the cast word,
// the turn skip and the behavioral injection read them: through the group
// store, member copy first, blanks falling back to the library card. A
// group copy with no job of its own used to read as free mid-shift, so
// the gate injected "Today's plan" over a shift the model was elsewhere
// told she was working (docs/design/held-away-presence-reads.md, the
// declared scope of the first pass).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/plan_injection.dart';

PlanInjection _gate({required CharacterCard speaker, required bool held}) =>
    PlanInjection(
      getTodayLine: () => 'Restock the pantry.',
      getPlannerEnabled: () => true,
      getClockMinutes: () => 14 * 60 + 30,
      getActiveCharacter: () => speaker,
      getIsGroupNonObserverMode: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getGroupCharacters: () => const [],
      getCharacterIdFromCard: (c) => c.name,
      getHeldAway: () => held,
      // What the wired store hands back: the member copy is blank, the
      // library card carries the job. 9am–5pm is open at 14:30.
      getOccupation: () => 'clerk',
      getHours: () => '9am–5pm',
      getWorkDays: () => const [1, 2, 3, 4, 5],
    );

void main() {
  // The copy carries no job of its own; only the store's fallback does.
  final blankCopy = CharacterCard(name: 'Ada');

  test('a mid-shift speaker whose job lives on the library card gets no '
      'plan line (the gate resolved its fields)', () {
    expect(
      _gate(speaker: blankCopy, held: false).buildPlanInjection(),
      isEmpty,
      reason:
          'THE BUG: the gate read the card copy only, so a blank '
          'copy meant no shift, and the plan line went out over an '
          'open shift every other surface calls work',
    );
  });

  test('the same held mid-shift still gets the plan line (the hold '
      'outranks the resolved shift, H1)', () {
    expect(
      _gate(speaker: blankCopy, held: true).buildPlanInjection(),
      contains('Restock the pantry.'),
    );
  });

  test('with no store to ask, the gate still reads the card itself '
      '(1:1 and test callers keep today\'s read)', () {
    final onCard = CharacterCard(
      name: 'Ada',
      frontPorchExtensions: FrontPorchExtensions(
        occupation: 'clerk',
        hours: '9am–5pm',
      ),
    );
    final text = PlanInjection(
      getTodayLine: () => 'Restock the pantry.',
      getPlannerEnabled: () => true,
      getClockMinutes: () => 14 * 60 + 30,
      getActiveCharacter: () => onCard,
      getIsGroupNonObserverMode: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getGroupCharacters: () => const [],
      getCharacterIdFromCard: (c) => c.name,
    ).buildPlanInjection();
    expect(text, isEmpty);
  });
}
