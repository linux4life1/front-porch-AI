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

import 'package:front_porch_ai/ui/character_creator/creator_state.dart';

/// Clears every wizard field of [s] back to its default, except the step
/// and mode, which [CreatorState.resetAllFields] resets itself. Does not
/// notify.
void clearCreatorForm(CreatorState s) {
  // Basic info controllers
  s.nameController.clear();
  s.conceptController.clear();
  s.keywordsController.clear();
  s.ageController.clear();
  s.sexController.clear();
  s.relationshipController.clear();
  s.backstoryNotesController.clear();
  s.customRaceController.clear();
  s.customKinksController.clear();

  // Guided mode controllers
  s.guidedVisionController.clear();
  s.guidedAppearanceController.clear();
  s.guidedHairController.clear();
  s.guidedFeaturesController.clear();
  s.guidedRaceController.clear();
  s.guidedPersonalityController.clear();
  s.guidedSpeechController.clear();
  s.guidedSecretController.clear();
  s.guidedOriginController.clear();
  s.guidedSettingController.clear();
  s.guidedToneController.clear();
  s.guidedRelDynamicController.clear();
  s.guidedRelScenarioController.clear();
  s.guidedNsfwBodyController.clear();
  s.guidedNsfwExpController.clear();
  s.guidedNsfwDomController.clear();
  s.guidedNsfwKinksController.clear();
  s.guidedNsfwClothingController.clear();
  s.guidedNsfwPersonalityController.clear();
  s.loreUrlsController.clear();
  s.loreFiles.clear();

  // Greetings step: stop a write first, so nothing lands in a box below.
  s.greetings.reset();
  s.profile.reset();
  s.review.reset();
  s.realismCurrentTask = '';

  // Review controllers
  s.descController.clear();
  s.personalityController.clear();
  s.scenarioController.clear();
  s.firstMessageController.clear();
  s.exampleDialogueController.clear();
  s.systemPromptController.clear();
  for (final c in s.altGreetingControllers) {
    c.dispose();
  }
  s.altGreetingControllers = [];
  s.greetingSeeds = [];

  // Chip/toggle selections
  s.selectedTones = {'Neutral'};
  s.selectedLoreCategories = {};
  s.selectedRelationships = {};
  s.customRelationship = '';
  s.selectedArchetype = '';
  s.selectedKinks = {};
  s.notableFeatures = {};
  s.nsfwEnabled = false;
  s.realismVerificationEnabled = false;
  s.realismVerificationMaxReprocesses = 1;
  s.realismVerificationStrictness = 3;
  s.realismNeedsDirectorAuthority = false;

  // Appearance dropdowns
  s.race = '';
  s.bodyType = '';
  s.hairLength = '';
  s.hairStyle = '';
  s.skinTone = '';
  s.absCore = '';
  s.thighs = '';
  s.hips = '';
  s.shoulders = '';
  s.waist = '';

  // NSFW appearance
  s.chestSize = '';
  s.buttSize = '';
  s.experience = '';
  s.dominance = '';
  s.outfitVibe = '';

  // Backstory
  s.backstoryOrigin = '';
  s.backstoryTone = '';
  s.backstoryEra = '';
  s.conceptGenerated = false;

  // Generation config defaults
  s.artStyle = 'Anime';
  s.greetingLength = 'Medium (2-4 paragraphs)';
  s.altGreetingCount = 2;
  s.generateLorebook = true;
  s.loreDepth = 'Standard';
  s.includeDynamicMacros = false;
  s.narrativePerspective = 'first';
  s.narrativeTense = 'present';
  s.generationDetail = 'Standard';

  // Generation state
  s.generationStatus = '';
  s.generationPreview = '';
  s.isGenerating = false;
  s.progress = 0.0;

  // Generated results
  s.generatedCard = null;
  s.imagePrompt = null;
  s.lorebookEntryEnabled = {};

  // Persona
  s.selectedPersonaId = '';
  s.portraitSourcePath = null;

  // Active gen service
  s.activeGenService = null;

  // Model state reset (light)
  s.selectedLocalModelPath = '';
  s.koboldStatus = '';
  s.selectedModelId = '';
}
