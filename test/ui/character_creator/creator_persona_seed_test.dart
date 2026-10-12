// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Make a Character" → AI Assist: the persona becomes Quick mode's brief,
// over whatever half-finished draft the creator had saved, and its picture
// is what the first save writes.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a persona seed lands on Quick mode over a saved draft', () async {
    SharedPreferences.setMockInitialValues({
      'chargen_name': 'Old Draft',
      'chargen_concept': 'Something half-written',
    });
    final state = CreatorState();
    addTearDown(state.disposeControllers);
    await state.loadSavedState();
    expect(state.nameController.text, 'Old Draft');
    state.selectedPersonaId = 'someone';
    state.quickScenarioController.text = 'leftover scenario';

    const seed = PersonaCharacterSeed(
      name: 'Jo',
      description: '{{char}} keeps bees for {{user}}.',
      birthday: '1988-03-02',
      portraitPath: '/pics/jo.png',
    );
    state.applyPersonaSeed(seed);

    expect(state.creatorMode, CreatorMode.quick);
    expect(state.nameController.text, 'Jo');
    expect(state.conceptController.text, seed.aiConcept);
    expect(state.quickScenarioController.text, isEmpty);
    expect(
      state.selectedPersonaId,
      isEmpty,
      reason: 'the character must not be told it is meeting itself',
    );
    expect(state.realismBirthday, '1988-03-02');
    expect(state.portraitSourcePath, '/pics/jo.png');

    state.resetAllFields();
    expect(state.portraitSourcePath, isNull);
  });

  test('a seeded session leaves the saved draft alone, both ways', () async {
    SharedPreferences.setMockInitialValues({
      'chargen_name': 'Old Draft',
      'chargen_concept': 'Something half-written',
      'chargen_age': '41',
      'chargen_sex': 'Female',
    });
    final state = CreatorState();
    addTearDown(state.disposeControllers);
    await state.loadSavedState();
    state.applyPersonaSeed(
      const PersonaCharacterSeed(name: 'Jo', description: 'Keeps bees.'),
    );

    expect(state.ageController.text, isEmpty, reason: 'no draft leaks in');
    expect(state.sexController.text, isEmpty);

    state.nameController.text = 'Jo the Beekeeper';
    await state.saveState();
    await state.clearSavedFormPrefsAfterSave();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chargen_name'), 'Old Draft');
    expect(prefs.getString('chargen_concept'), 'Something half-written');
    expect(prefs.getString('chargen_age'), '41');
  });
}
