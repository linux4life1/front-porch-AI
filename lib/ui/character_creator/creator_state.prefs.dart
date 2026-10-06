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

  /// Every saved wizard field, keyed by its preference. Read in one go,
  /// before any await, so a save started as the wizard closes still sees the
  /// text of controllers that are about to be disposed.
  Map<String, Object> _savedFields() => {
    CreatorState._prefName: nameController.text,
    CreatorState._prefConcept: conceptController.text,
    CreatorState._prefKeywords: keywordsController.text,
    CreatorState._prefArtStyle: artStyle,
    CreatorState._prefModel: selectedModelId,
    CreatorState._prefGreetingLength: greetingLength,
    CreatorState._prefAltCount: altGreetingCount,
    CreatorState._prefTone: selectedTones.join(','),
    CreatorState._prefLorebook: generateLorebook,
    CreatorState._prefAge: ageController.text,
    CreatorState._prefSex: sexController.text,
    CreatorState._prefRelationship: relationshipController.text,
    CreatorState._prefPersona: selectedPersonaId,
    CreatorState._prefQuickScenario: quickScenarioController.text,
    CreatorState._prefLoreCategories: selectedLoreCategories.join(','),
    CreatorState._prefLoreDepth: loreDepth,
    CreatorState._prefDynamicMacros: includeDynamicMacros,
    CreatorState._prefNarrativePerspective: narrativePerspective,
    CreatorState._prefNarrativeTense: narrativeTense,
    CreatorState._prefRelationships: selectedRelationships.join(','),
    CreatorState._prefCustomRelationship: customRelationship,
    CreatorState._prefNsfwEnabled: nsfwEnabled,
    CreatorState._prefRealismVerificationEnabled: realismVerificationEnabled,
    CreatorState._prefRealismVerificationMax: realismVerificationMaxReprocesses,
    CreatorState._prefRealismVerificationStrict: realismVerificationStrictness,
    CreatorState._prefRealismNeedsDirectorAuthority:
        realismNeedsDirectorAuthority,
    CreatorState._prefBodyType: bodyType,
    CreatorState._prefRace: race,
    CreatorState._prefCustomRace: customRaceController.text,
    CreatorState._prefHairLength: hairLength,
    CreatorState._prefHairStyle: hairStyle,
    CreatorState._prefSkinTone: skinTone,
    CreatorState._prefNotableFeatures: notableFeatures.join(','),
    CreatorState._prefAbsCore: absCore,
    CreatorState._prefThighs: thighs,
    CreatorState._prefHips: hips,
    CreatorState._prefShoulders: shoulders,
    CreatorState._prefWaist: waist,
    CreatorState._prefChestSize: chestSize,
    CreatorState._prefButtSize: buttSize,
    CreatorState._prefExperience: experience,
    CreatorState._prefDominance: dominance,
    CreatorState._prefKinks: selectedKinks.join(','),
    CreatorState._prefCustomKinks: customKinksController.text,
    CreatorState._prefOutfitVibe: outfitVibe,
    CreatorState._prefGenerationDetail: generationDetail,
    CreatorState._prefBackstoryOrigin: backstoryOrigin,
    CreatorState._prefBackstoryTone: backstoryTone,
    CreatorState._prefBackstoryEra: backstoryEra,
    CreatorState._prefBackstoryNotes: backstoryNotesController.text,
    CreatorState._prefConceptGenerated: conceptGenerated,
    CreatorState._prefCreatorMode: _creatorMode.name,
    CreatorState._prefGuidedVision: guidedVisionController.text,
    CreatorState._prefGuidedAppearance: guidedAppearanceController.text,
    CreatorState._prefGuidedHair: guidedHairController.text,
    CreatorState._prefGuidedFeatures: guidedFeaturesController.text,
    CreatorState._prefGuidedRace: guidedRaceController.text,
    CreatorState._prefGuidedPersonality: guidedPersonalityController.text,
    CreatorState._prefGuidedSpeech: guidedSpeechController.text,
    CreatorState._prefGuidedSecret: guidedSecretController.text,
    CreatorState._prefGuidedOrigin: guidedOriginController.text,
    CreatorState._prefGuidedSetting: guidedSettingController.text,
    CreatorState._prefGuidedTone: guidedToneController.text,
    CreatorState._prefGuidedRelDynamic: guidedRelDynamicController.text,
    CreatorState._prefGuidedRelScenario: guidedRelScenarioController.text,
    CreatorState._prefGuidedNsfwBody: guidedNsfwBodyController.text,
    CreatorState._prefGuidedNsfwExp: guidedNsfwExpController.text,
    CreatorState._prefGuidedNsfwDom: guidedNsfwDomController.text,
    CreatorState._prefGuidedNsfwKinks: guidedNsfwKinksController.text,
    CreatorState._prefGuidedNsfwClothing: guidedNsfwClothingController.text,
    CreatorState._prefGuidedNsfwPersonality:
        guidedNsfwPersonalityController.text,
  };

  /// Writes only the fields whose value changed. On Windows and Linux every
  /// preference write rewrites the whole preferences file on the UI thread,
  /// so writing all of them per keystroke stalled typing (#371). The check
  /// is a read of the in-memory cache. The fields are read now; the writes
  /// wait for any save still running.
  Future<void> _saveStateImpl() {
    final fields = _savedFields();
    return _queuePrefsWrite((prefs) async {
      for (final MapEntry(:key, :value) in fields.entries) {
        if (prefs.get(key) == value) continue;
        await switch (value) {
          final bool v => prefs.setBool(key, v),
          final int v => prefs.setInt(key, v),
          _ => prefs.setString(key, value as String),
        };
      }
    });
  }

  /// Runs [write] once every earlier creator save has finished. A failed
  /// write still fails its own caller's future; the queue just moves on.
  Future<void> _queuePrefsWrite(
    Future<void> Function(SharedPreferences prefs) write,
  ) {
    final run = _saveQueue.then(
      (_) async => write(await SharedPreferences.getInstance()),
    );
    _saveQueue = run.catchError((Object _) {});
    return run;
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

    // Greetings step: stop a write first, so nothing lands in a box below.
    greetings.reset();

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
  Future<void> clearSavedFormPrefsAfterSave() =>
      _queuePrefsWrite((prefs) async {
        for (final key in [
          CreatorState._prefName,
          CreatorState._prefConcept,
          CreatorState._prefKeywords,
          CreatorState._prefArtStyle,
        ]) {
          await prefs.remove(key);
        }
      });
}
