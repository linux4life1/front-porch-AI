// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// H1/H2 (docs/design/held-away-presence-reads.md): the plan gate feeds the
// Away hold to its presence read, so a held member mid-shift is not treated
// as at work (and their plan line is not swallowed).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/plan_injection.dart';

void main() {
  test('a held member mid-shift keeps the plan line (the hold outranks the '
      'shift)', () {
    final clerk = CharacterCard(
      name: 'Ada',
      frontPorchExtensions: FrontPorchExtensions(
        occupation: 'clerk',
        hours: '9am–5pm',
      ),
    );
    final text = PlanInjection(
      getTodayLine: () => 'Finish the log.',
      getPlannerEnabled: () => true,
      getClockMinutes: () => 14 * 60 + 30,
      getActiveCharacter: () => clerk,
      getIsGroupNonObserverMode: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getGroupCharacters: () => const [],
      getCharacterIdFromCard: (c) => c.name,
      getHeldAway: () => true,
    ).buildPlanInjection();
    expect(text, contains('Finish the log.'));
  });
}
