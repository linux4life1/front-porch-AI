// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live plan injection is parked. Always ''.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/plan_injection.dart';

PlanInjection make(CharacterCard? card, {String? held}) => PlanInjection(
      getTodayLine: () => held,
      getActiveCharacter: () => card,
      getIsGroupNonObserverMode: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getGroupCharacters: () => const [],
      getCharacterIdFromCard: (c) => c.name,
    );

CharacterCard who(String name) => CharacterCard(
      name: name,
      frontPorchExtensions: FrontPorchExtensions(
        planLines: const ['Finish the lighthouse log before the tide turns.'],
      ),
    );

void main() {
  test('buildPlanInjection is empty with no card', () {
    expect(make(null, held: 'Finish the log.').buildPlanInjection(), isEmpty);
  });

  test('buildPlanInjection is empty with a card and held line', () {
    expect(
      make(who('Ada'), held: 'Finish the log.').buildPlanInjection(),
      isEmpty,
    );
  });

  test('buildPlanInjection is empty with a card and no held line', () {
    expect(make(who('Ada')).buildPlanInjection(), isEmpty);
  });
}
