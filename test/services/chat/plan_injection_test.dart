// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live plan injection is on only when the planner flag is on.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/plan_injection.dart';

PlanInjection make(
  CharacterCard? card, {
  String? held,
  bool plannerOn = false,
}) => PlanInjection(
  getTodayLine: () => held,
  getPlannerEnabled: () => plannerOn,
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
  test('buildPlanInjection is empty when the flag is off', () {
    expect(
      make(
        who('Ada'),
        held: 'Finish the log.',
        plannerOn: false,
      ).buildPlanInjection(),
      isEmpty,
    );
  });

  test('buildPlanInjection is empty with no card even when the flag is on', () {
    expect(
      make(null, held: 'Finish the log.', plannerOn: true).buildPlanInjection(),
      isEmpty,
    );
  });

  test('flag on and no held line is empty', () {
    expect(make(who('Ada'), plannerOn: true).buildPlanInjection(), isEmpty);
  });

  test('flag on and a held line injects the sentence without a tag', () {
    final text = make(
      who('Ada'),
      held: 'Finish the log.',
      plannerOn: true,
    ).buildPlanInjection();
    expect(text, contains('Finish the log.'));
    expect(text, isNot(contains('[today:')));
  });

  test('At work suppresses the today plan so the two cannot fight', () {
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
    ).buildPlanInjection();
    expect(text, isEmpty);
  });
}
