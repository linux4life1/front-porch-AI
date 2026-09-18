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

part of 'creator_state.dart';

/// Load, save, and reset the wizard form through SharedPreferences.
extension CreatorStatePrefs on CreatorState {
  // Load / Save / Reset (pure lift, adapted for notifier)
  Future<void> loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    nameController.text = prefs.getString(CreatorState._prefName) ?? '';
    conceptController.text = prefs.getString(CreatorState._prefConcept) ?? '';
    keywordsController.text = prefs.getString(CreatorState._prefKeywords) ?? '';
    artStyle = prefs.getString(CreatorState._prefArtStyle) ?? 'Anime';
    selectedModelId = prefs.getString(CreatorState._prefModel) ?? '';
    greetingLength =
        prefs.getString(CreatorState._prefGreetingLength) ??
        'Medium (2-4 paragraphs)';
    altGreetingCount = prefs.getInt(CreatorState._prefAltCount) ?? 2;
    final savedTones = prefs.getString(CreatorState._prefTone) ?? 'Neutral';
    selectedTones = savedTones.split(',').where((t) => t.isNotEmpty).toSet();
    if (selectedTones.isEmpty) selectedTones = {'Neutral'};
    generateLorebook = prefs.getBool(CreatorState._prefLorebook) ?? true;
    ageController.text = prefs.getString(CreatorState._prefAge) ?? '';
    sexController.text = prefs.getString(CreatorState._prefSex) ?? '';
    relationshipController.text =
        prefs.getString(CreatorState._prefRelationship) ?? '';
    selectedPersonaId = prefs.getString(CreatorState._prefPersona) ?? '';
    quickScenarioController.text =
        prefs.getString(CreatorState._prefQuickScenario) ?? '';

    final savedCategories =
        prefs.getString(CreatorState._prefLoreCategories) ?? '';
    selectedLoreCategories = savedCategories
        .split(',')
        .where((c) => c.isNotEmpty)
        .toSet();
    loreDepth = prefs.getString(CreatorState._prefLoreDepth) ?? 'Standard';
    includeDynamicMacros =
        prefs.getBool(CreatorState._prefDynamicMacros) ?? false;
    narrativePerspective =
        prefs.getString(CreatorState._prefNarrativePerspective) ?? 'first';
    if (narrativePerspective != 'first' && narrativePerspective != 'third') {
      narrativePerspective = 'first';
    }
    narrativeTense =
        prefs.getString(CreatorState._prefNarrativeTense) ?? 'present';
    if (narrativeTense != 'present' && narrativeTense != 'past') {
      narrativeTense = 'present';
    }
    final savedRelationships =
        prefs.getString(CreatorState._prefRelationships) ?? '';
    selectedRelationships = savedRelationships
        .split(',')
        .where((r) => r.isNotEmpty)
        .toSet();
    customRelationship =
        prefs.getString(CreatorState._prefCustomRelationship) ?? '';
    nsfwEnabled = prefs.getBool(CreatorState._prefNsfwEnabled) ?? false;
    realismVerificationEnabled =
        prefs.getBool(CreatorState._prefRealismVerificationEnabled) ?? false;
    realismVerificationMaxReprocesses =
        prefs.getInt(CreatorState._prefRealismVerificationMax) ?? 1;
    realismVerificationStrictness =
        prefs.getInt(CreatorState._prefRealismVerificationStrict) ?? 3;
    realismNeedsDirectorAuthority =
        prefs.getBool(CreatorState._prefRealismNeedsDirectorAuthority) ?? false;
    bodyType = prefs.getString(CreatorState._prefBodyType) ?? '';
    race = prefs.getString(CreatorState._prefRace) ?? '';
    customRaceController.text =
        prefs.getString(CreatorState._prefCustomRace) ?? '';
    hairLength = prefs.getString(CreatorState._prefHairLength) ?? '';
    hairStyle = prefs.getString(CreatorState._prefHairStyle) ?? '';
    skinTone = prefs.getString(CreatorState._prefSkinTone) ?? '';
    final savedFeatures =
        prefs.getString(CreatorState._prefNotableFeatures) ?? '';
    notableFeatures = savedFeatures
        .split(',')
        .where((f) => f.isNotEmpty)
        .toSet();
    absCore = prefs.getString(CreatorState._prefAbsCore) ?? '';
    thighs = prefs.getString(CreatorState._prefThighs) ?? '';
    hips = prefs.getString(CreatorState._prefHips) ?? '';
    shoulders = prefs.getString(CreatorState._prefShoulders) ?? '';
    waist = prefs.getString(CreatorState._prefWaist) ?? '';
    chestSize = prefs.getString(CreatorState._prefChestSize) ?? '';
    buttSize = prefs.getString(CreatorState._prefButtSize) ?? '';
    experience = prefs.getString(CreatorState._prefExperience) ?? '';
    dominance = prefs.getString(CreatorState._prefDominance) ?? '';
    final savedKinks = prefs.getString(CreatorState._prefKinks) ?? '';
    selectedKinks = savedKinks.split(',').where((k) => k.isNotEmpty).toSet();
    customKinksController.text =
        prefs.getString(CreatorState._prefCustomKinks) ?? '';
    outfitVibe = prefs.getString(CreatorState._prefOutfitVibe) ?? '';
    generationDetail =
        prefs.getString(CreatorState._prefGenerationDetail) ?? 'Standard';
    backstoryOrigin = prefs.getString(CreatorState._prefBackstoryOrigin) ?? '';
    backstoryTone = prefs.getString(CreatorState._prefBackstoryTone) ?? '';
    backstoryEra = prefs.getString(CreatorState._prefBackstoryEra) ?? '';
    backstoryNotesController.text =
        prefs.getString(CreatorState._prefBackstoryNotes) ?? '';
    conceptGenerated =
        prefs.getBool(CreatorState._prefConceptGenerated) ?? false;

    // Stored as the enum's own name so every mode round-trips. Quick Create
    // used to collapse to 'automated' on BOTH sides of this pair, so picking
    // it and reopening the wizard silently put the user back on the automated
    // form. Unknown/legacy values still fall back to automated.
    final savedMode =
        prefs.getString(CreatorState._prefCreatorMode) ?? 'automated';
    _creatorMode = switch (savedMode) {
      'guided' => CreatorMode.guided,
      'quick' => CreatorMode.quick,
      _ => CreatorMode.automated,
    };
    guidedVisionController.text =
        prefs.getString(CreatorState._prefGuidedVision) ?? '';
    guidedAppearanceController.text =
        prefs.getString(CreatorState._prefGuidedAppearance) ?? '';
    guidedHairController.text =
        prefs.getString(CreatorState._prefGuidedHair) ?? '';
    guidedFeaturesController.text =
        prefs.getString(CreatorState._prefGuidedFeatures) ?? '';
    guidedRaceController.text =
        prefs.getString(CreatorState._prefGuidedRace) ?? '';
    guidedPersonalityController.text =
        prefs.getString(CreatorState._prefGuidedPersonality) ?? '';
    guidedSpeechController.text =
        prefs.getString(CreatorState._prefGuidedSpeech) ?? '';
    guidedSecretController.text =
        prefs.getString(CreatorState._prefGuidedSecret) ?? '';
    guidedOriginController.text =
        prefs.getString(CreatorState._prefGuidedOrigin) ?? '';
    guidedSettingController.text =
        prefs.getString(CreatorState._prefGuidedSetting) ?? '';
    guidedToneController.text =
        prefs.getString(CreatorState._prefGuidedTone) ?? '';
    guidedRelDynamicController.text =
        prefs.getString(CreatorState._prefGuidedRelDynamic) ?? '';
    guidedRelScenarioController.text =
        prefs.getString(CreatorState._prefGuidedRelScenario) ?? '';
    guidedNsfwBodyController.text =
        prefs.getString(CreatorState._prefGuidedNsfwBody) ?? '';
    guidedNsfwExpController.text =
        prefs.getString(CreatorState._prefGuidedNsfwExp) ?? '';
    guidedNsfwDomController.text =
        prefs.getString(CreatorState._prefGuidedNsfwDom) ?? '';
    guidedNsfwKinksController.text =
        prefs.getString(CreatorState._prefGuidedNsfwKinks) ?? '';
    guidedNsfwClothingController.text =
        prefs.getString(CreatorState._prefGuidedNsfwClothing) ?? '';
    guidedNsfwPersonalityController.text =
        prefs.getString(CreatorState._prefGuidedNsfwPersonality) ?? '';

    notify();
  }

  Future<void> _saveStateImpl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CreatorState._prefName, nameController.text);
    await prefs.setString(CreatorState._prefConcept, conceptController.text);
    await prefs.setString(CreatorState._prefKeywords, keywordsController.text);
    await prefs.setString(CreatorState._prefArtStyle, artStyle);
    await prefs.setString(CreatorState._prefModel, selectedModelId);
    await prefs.setString(CreatorState._prefGreetingLength, greetingLength);
    await prefs.setInt(CreatorState._prefAltCount, altGreetingCount);
    await prefs.setString(CreatorState._prefTone, selectedTones.join(','));
    await prefs.setBool(CreatorState._prefLorebook, generateLorebook);
    await prefs.setString(CreatorState._prefAge, ageController.text);
    await prefs.setString(CreatorState._prefSex, sexController.text);
    await prefs.setString(
      CreatorState._prefRelationship,
      relationshipController.text,
    );
    await prefs.setString(CreatorState._prefPersona, selectedPersonaId);
    await prefs.setString(
      CreatorState._prefQuickScenario,
      quickScenarioController.text,
    );
    await prefs.setString(
      CreatorState._prefLoreCategories,
      selectedLoreCategories.join(','),
    );
    await prefs.setString(CreatorState._prefLoreDepth, loreDepth);
    await prefs.setBool(CreatorState._prefDynamicMacros, includeDynamicMacros);
    await prefs.setString(
      CreatorState._prefNarrativePerspective,
      narrativePerspective,
    );
    await prefs.setString(CreatorState._prefNarrativeTense, narrativeTense);
    await prefs.setString(
      CreatorState._prefRelationships,
      selectedRelationships.join(','),
    );
    await prefs.setString(
      CreatorState._prefCustomRelationship,
      customRelationship,
    );
    await prefs.setBool(CreatorState._prefNsfwEnabled, nsfwEnabled);
    await prefs.setBool(
      CreatorState._prefRealismVerificationEnabled,
      realismVerificationEnabled,
    );
    await prefs.setInt(
      CreatorState._prefRealismVerificationMax,
      realismVerificationMaxReprocesses,
    );
    await prefs.setInt(
      CreatorState._prefRealismVerificationStrict,
      realismVerificationStrictness,
    );
    await prefs.setBool(
      CreatorState._prefRealismNeedsDirectorAuthority,
      realismNeedsDirectorAuthority,
    );
    await prefs.setString(CreatorState._prefBodyType, bodyType);
    await prefs.setString(CreatorState._prefRace, race);
    await prefs.setString(
      CreatorState._prefCustomRace,
      customRaceController.text,
    );
    await prefs.setString(CreatorState._prefHairLength, hairLength);
    await prefs.setString(CreatorState._prefHairStyle, hairStyle);
    await prefs.setString(CreatorState._prefSkinTone, skinTone);
    await prefs.setString(
      CreatorState._prefNotableFeatures,
      notableFeatures.join(','),
    );
    await prefs.setString(CreatorState._prefAbsCore, absCore);
    await prefs.setString(CreatorState._prefThighs, thighs);
    await prefs.setString(CreatorState._prefHips, hips);
    await prefs.setString(CreatorState._prefShoulders, shoulders);
    await prefs.setString(CreatorState._prefWaist, waist);
    await prefs.setString(CreatorState._prefChestSize, chestSize);
    await prefs.setString(CreatorState._prefButtSize, buttSize);
    await prefs.setString(CreatorState._prefExperience, experience);
    await prefs.setString(CreatorState._prefDominance, dominance);
    await prefs.setString(CreatorState._prefKinks, selectedKinks.join(','));
    await prefs.setString(
      CreatorState._prefCustomKinks,
      customKinksController.text,
    );
    await prefs.setString(CreatorState._prefOutfitVibe, outfitVibe);
    await prefs.setString(CreatorState._prefGenerationDetail, generationDetail);
    await prefs.setString(CreatorState._prefBackstoryOrigin, backstoryOrigin);
    await prefs.setString(CreatorState._prefBackstoryTone, backstoryTone);
    await prefs.setString(CreatorState._prefBackstoryEra, backstoryEra);
    await prefs.setString(
      CreatorState._prefBackstoryNotes,
      backstoryNotesController.text,
    );
    await prefs.setBool(CreatorState._prefConceptGenerated, conceptGenerated);
    await prefs.setString(CreatorState._prefCreatorMode, _creatorMode.name);
    await prefs.setString(
      CreatorState._prefGuidedVision,
      guidedVisionController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedAppearance,
      guidedAppearanceController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedHair,
      guidedHairController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedFeatures,
      guidedFeaturesController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedRace,
      guidedRaceController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedPersonality,
      guidedPersonalityController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedSpeech,
      guidedSpeechController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedSecret,
      guidedSecretController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedOrigin,
      guidedOriginController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedSetting,
      guidedSettingController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedTone,
      guidedToneController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedRelDynamic,
      guidedRelDynamicController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedRelScenario,
      guidedRelScenarioController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedNsfwBody,
      guidedNsfwBodyController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedNsfwExp,
      guidedNsfwExpController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedNsfwDom,
      guidedNsfwDomController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedNsfwKinks,
      guidedNsfwKinksController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedNsfwClothing,
      guidedNsfwClothingController.text,
    );
    await prefs.setString(
      CreatorState._prefGuidedNsfwPersonality,
      guidedNsfwPersonalityController.text,
    );
  }

  void resetAllFields() {
    // Step & mode
    _currentStep = 0;
    _creatorMode = CreatorMode.automated;

    // Basic info controllers
    nameController.clear();
    conceptController.clear();
    keywordsController.clear();
    ageController.clear();
    sexController.clear();
    relationshipController.clear();
    backstoryNotesController.clear();
    customRaceController.clear();
    customKinksController.clear();

    // Guided mode controllers
    guidedVisionController.clear();
    guidedAppearanceController.clear();
    guidedHairController.clear();
    guidedFeaturesController.clear();
    guidedRaceController.clear();
    guidedPersonalityController.clear();
    guidedSpeechController.clear();
    guidedSecretController.clear();
    guidedOriginController.clear();
    guidedSettingController.clear();
    guidedToneController.clear();
    guidedRelDynamicController.clear();
    guidedRelScenarioController.clear();
    guidedNsfwBodyController.clear();
    guidedNsfwExpController.clear();
    guidedNsfwDomController.clear();
    guidedNsfwKinksController.clear();
    guidedNsfwClothingController.clear();
    guidedNsfwPersonalityController.clear();
    loreUrlsController.clear();
    loreFiles.clear();

    // Review controllers
    descController.clear();
    personalityController.clear();
    scenarioController.clear();
    firstMessageController.clear();
    exampleDialogueController.clear();
    systemPromptController.clear();
    for (final c in altGreetingControllers) {
      c.dispose();
    }
    altGreetingControllers = [];
    greetingSeeds = [];

    // Chip/toggle selections
    selectedTones = {'Neutral'};
    selectedLoreCategories = {};
    selectedRelationships = {};
    customRelationship = '';
    selectedArchetype = '';
    selectedKinks = {};
    notableFeatures = {};
    nsfwEnabled = false;
    realismVerificationEnabled = false;
    realismVerificationMaxReprocesses = 1;
    realismVerificationStrictness = 3;
    realismNeedsDirectorAuthority = false;

    // Appearance dropdowns
    race = '';
    bodyType = '';
    hairLength = '';
    hairStyle = '';
    skinTone = '';
    absCore = '';
    thighs = '';
    hips = '';
    shoulders = '';
    waist = '';

    // NSFW appearance
    chestSize = '';
    buttSize = '';
    experience = '';
    dominance = '';
    outfitVibe = '';

    // Backstory
    backstoryOrigin = '';
    backstoryTone = '';
    backstoryEra = '';
    conceptGenerated = false;

    // Generation config defaults
    artStyle = 'Anime';
    greetingLength = 'Medium (2-4 paragraphs)';
    altGreetingCount = 2;
    generateLorebook = true;
    loreDepth = 'Standard';
    includeDynamicMacros = false;
    narrativePerspective = 'first';
    narrativeTense = 'present';
    generationDetail = 'Standard';

    // Generation state
    generationStatus = '';
    generationPreview = '';
    isGenerating = false;
    progress = 0.0;

    // Generated results
    generatedCard = null;
    imagePrompt = null;
    lorebookEntryEnabled = {};

    // Persona
    selectedPersonaId = '';

    // Active gen service
    activeGenService = null;

    // Model state reset (light)
    selectedLocalModelPath = '';
    koboldStatus = '';
    selectedModelId = '';

    notify();
  }

  /// Clear the core saved-form prefs after a character is successfully created,
  /// so the next visit starts fresh. Mirrors the original review-step save.
  Future<void> clearSavedFormPrefsAfterSave() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      CreatorState._prefName,
      CreatorState._prefConcept,
      CreatorState._prefKeywords,
      CreatorState._prefArtStyle,
    ]) {
      await prefs.remove(key);
    }
  }
}
