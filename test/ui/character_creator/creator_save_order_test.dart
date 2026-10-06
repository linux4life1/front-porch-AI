// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// #371: creator saves take turns. A save writes only the keys that changed,
// so a save started while another was still writing skipped the keys the
// first had already written, got ahead of it, and the first then put its
// older text back. On Windows the first save of a fresh profile takes long
// enough for a typing pause to start a second one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/ui/character_creator/character_creator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a save started during another never ends on the older text', () async {
    SharedPreferences.setMockInitialValues({});
    final state = CreatorState();
    addTearDown(state.dispose);
    final boxes = <TextEditingController>[
      state.nameController,
      state.conceptController,
      state.keywordsController,
      state.ageController,
      state.sexController,
      state.relationshipController,
      state.quickScenarioController,
      state.customRaceController,
      state.customKinksController,
      state.backstoryNotesController,
      state.guidedVisionController,
      state.guidedAppearanceController,
      state.guidedHairController,
      state.guidedFeaturesController,
      state.guidedRaceController,
      state.guidedPersonalityController,
      state.guidedSpeechController,
      state.guidedSecretController,
      state.guidedOriginController,
      state.guidedSettingController,
      state.guidedToneController,
      state.guidedRelDynamicController,
      state.guidedRelScenarioController,
      state.guidedNsfwBodyController,
      state.guidedNsfwExpController,
      state.guidedNsfwDomController,
      state.guidedNsfwKinksController,
      state.guidedNsfwClothingController,
      state.guidedNsfwPersonalityController,
    ];

    for (final box in boxes) {
      box.text = 'older';
    }
    final first = state.saveState();
    for (final box in boxes) {
      box.text = 'newer';
    }
    final second = state.saveState();
    await Future.wait([first, second]);

    final prefs = await SharedPreferences.getInstance();
    final stored = [for (final key in prefs.getKeys()) prefs.get(key)];
    expect(stored.where((v) => v == 'newer'), hasLength(boxes.length));
    expect(stored, isNot(contains('older')));
  });
}
