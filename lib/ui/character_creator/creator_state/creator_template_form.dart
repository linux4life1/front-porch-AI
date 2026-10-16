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

import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';

// The desktop's side of the template form (docs/design/creator-templates.md,
// "What a template holds"): which `CreatorState` field each canonical key
// is. Read and write share these tables, so a key cannot be saved and
// never loaded.

typedef _Field<T> = (String key, T Function() read, void Function(T) write);

/// The text boxes, by key.
Map<String, TextEditingController> _boxes(CreatorState s) => {
  'age': s.ageController,
  'sex': s.sexController,
  'automatedKeywords': s.keywordsController,
  'quickScenario': s.quickScenarioController,
  'guidedVision': s.guidedVisionController,
  'guidedBuild': s.guidedAppearanceController,
  'guidedHair': s.guidedHairController,
  'guidedFeatures': s.guidedFeaturesController,
  'guidedRace': s.guidedRaceController,
  'guidedPersonality': s.guidedPersonalityController,
  'guidedSpeech': s.guidedSpeechController,
  'guidedSecret': s.guidedSecretController,
  'guidedOrigin': s.guidedOriginController,
  'guidedSetting': s.guidedSettingController,
  'guidedTone': s.guidedToneController,
  'guidedRelationship': s.guidedRelDynamicController,
  'guidedScenario': s.guidedRelScenarioController,
  'guidedNsfwBody': s.guidedNsfwBodyController,
  'guidedNsfwExperience': s.guidedNsfwExpController,
  'guidedNsfwDominance': s.guidedNsfwDomController,
  'guidedNsfwKinks': s.guidedNsfwKinksController,
  'guidedNsfwClothing': s.guidedNsfwClothingController,
  'guidedNsfwPersonality': s.guidedNsfwPersonalityController,
  'customRace': s.customRaceController,
  'customKinks': s.customKinksController,
  'backstoryNotes': s.backstoryNotesController,
  // The desktop's custom relationship box. `CreatorState.customRelationship`
  // is a field nothing shows.
  'customRelationship': s.relationshipController,
};

/// The single-choice pickers and settings held as text.
List<_Field<String>> _choices(CreatorState s) => [
  ('greetingLength', () => s.greetingLength, (v) => s.greetingLength = v),
  ('generationDetail', () => s.generationDetail, (v) => s.generationDetail = v),
  (
    'narrativePerspective',
    () => s.narrativePerspective,
    (v) => s.narrativePerspective = v,
  ),
  ('narrativeTense', () => s.narrativeTense, (v) => s.narrativeTense = v),
  ('loreDepth', () => s.loreDepth, (v) => s.loreDepth = v),
  ('race', () => s.race, (v) => s.race = v),
  ('bodyType', () => s.bodyType, (v) => s.bodyType = v),
  ('hairLength', () => s.hairLength, (v) => s.hairLength = v),
  ('hairStyle', () => s.hairStyle, (v) => s.hairStyle = v),
  ('skinTone', () => s.skinTone, (v) => s.skinTone = v),
  ('absCore', () => s.absCore, (v) => s.absCore = v),
  ('thighs', () => s.thighs, (v) => s.thighs = v),
  ('hips', () => s.hips, (v) => s.hips = v),
  ('shoulders', () => s.shoulders, (v) => s.shoulders = v),
  ('waist', () => s.waist, (v) => s.waist = v),
  ('chestSize', () => s.chestSize, (v) => s.chestSize = v),
  ('buttSize', () => s.buttSize, (v) => s.buttSize = v),
  ('experience', () => s.experience, (v) => s.experience = v),
  ('dominance', () => s.dominance, (v) => s.dominance = v),
  ('outfitVibe', () => s.outfitVibe, (v) => s.outfitVibe = v),
  ('backstoryOrigin', () => s.backstoryOrigin, (v) => s.backstoryOrigin = v),
  ('backstoryTone', () => s.backstoryTone, (v) => s.backstoryTone = v),
  ('backstoryEra', () => s.backstoryEra, (v) => s.backstoryEra = v),
  ('artStyle', () => s.artStyle, (v) => s.artStyle = v),
  ('personaId', () => s.selectedPersonaId, (v) => s.selectedPersonaId = v),
  ('archetype', () => s.selectedArchetype, (v) => s.selectedArchetype = v),
];

List<_Field<bool>> _flags(CreatorState s) => [
  (
    'includeDynamicMacros',
    () => s.includeDynamicMacros,
    (v) => s.includeDynamicMacros = v,
  ),
  ('generateLorebook', () => s.generateLorebook, (v) => s.generateLorebook = v),
  ('reasoningEnabled', () => s.reasoningEnabled, (v) => s.reasoningEnabled = v),
  ('conceptWritten', () => s.conceptGenerated, (v) => s.conceptGenerated = v),
];

/// The multi-choice chip rows, in the order they were picked.
List<_Field<Set<String>>> _sets(CreatorState s) => [
  (
    'loreCategories',
    () => s.selectedLoreCategories,
    (v) => s.selectedLoreCategories = v,
  ),
  ('notableFeatures', () => s.notableFeatures, (v) => s.notableFeatures = v),
  ('kinks', () => s.selectedKinks, (v) => s.selectedKinks = v),
  (
    'relationships',
    () => s.selectedRelationships,
    (v) => s.selectedRelationships = v,
  ),
];

/// The lore URL box as the engine reads it: comma-separated.
List<String> _urls(String text) => [
  for (final u in text.split(','))
    if (u.trim().isNotEmpty) u.trim(),
];

/// The form [s] holds as a template, every key the desktop shows. The one
/// concept box is both Quick's and Automated's; Quick's own tones, count
/// and 18+ stand in for the shared ones while Quick is the mode. The name,
/// the Setup step, lore files and the Realism step on are not in it.
Map<String, Object?> creatorTemplateForm(CreatorState s) {
  final quick = s.creatorMode == CreatorMode.quick;
  final questions = s.interview.forRun;
  return {
    'mode': s.creatorMode.name,
    'nsfw': quick ? s.quickNsfwEnabled : s.nsfwEnabled,
    'altGreetingCount': quick ? s.quickGreetingCount : s.altGreetingCount,
    'greetingTones': quick
        ? List<String>.of(s.quickSelectedTones)
        : s.selectedTones.toList(),
    'interviewQuestions': questions == null
        ? null
        : InterviewQuestion.listToJson(questions),
    'quickConcept': s.conceptController.text,
    'automatedConcept': s.conceptController.text,
    'loreUrls': _urls(s.loreUrlsController.text),
    for (final MapEntry(:key, :value) in _boxes(s).entries) key: value.text,
    for (final (key, read, _) in _choices(s)) key: read(),
    for (final (key, read, _) in _flags(s)) key: read(),
    for (final (key, read, _) in _sets(s)) key: read().toList(),
  };
}

/// Fills every desktop field of [s] from [form]; a key it lacks gets its
/// default. Returns the form's mode for the caller to set: the state owns
/// that field, and its setter notifies. The concept box takes the mode's
/// own concept; both sets of tones, count and 18+ are filled. Leaves the
/// name and the Setup step alone, clears the lore files (they belong to one
/// machine) and does not notify.
CreatorMode applyCreatorTemplateForm(
  CreatorState s,
  Map<String, Object?> form,
) {
  final mode = CreatorMode.values.byName(form.text('mode'));
  s.conceptController.text = form.text(
    mode == CreatorMode.quick ? 'quickConcept' : 'automatedConcept',
  );
  final nsfw = form.flag('nsfw');
  s.nsfwEnabled = nsfw;
  s.quickNsfwEnabled = nsfw;
  final count = form.count('altGreetingCount');
  s.altGreetingCount = count;
  s.quickGreetingCount = count;
  // One tone per greeting at most, as the tone picker keeps it.
  var tones = form.words('greetingTones').take(count + 1).toList();
  if (tones.isEmpty) tones = ['Neutral'];
  s.selectedTones = tones.toSet();
  s.quickSelectedTones = List<String>.of(tones);
  s.interview.restoreList(form.interview());
  s.loreUrlsController.text = form.words('loreUrls').join(', ');
  s.loreFiles.clear();
  for (final MapEntry(:key, :value) in _boxes(s).entries) {
    value.text = form.text(key);
  }
  for (final (key, _, write) in _choices(s)) {
    write(form.text(key));
  }
  for (final (key, _, write) in _flags(s)) {
    write(form.flag(key));
  }
  for (final (key, _, write) in _sets(s)) {
    write(form.words(key).toSet());
  }
  return mode;
}
