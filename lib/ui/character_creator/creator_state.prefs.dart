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

import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_templates.dart';

/// Loads, saves, and clears the wizard form through SharedPreferences.
/// Saves run one after another through [_saveQueue].
class CreatorFormPrefs {
  static const _prefName = 'chargen_name';
  static const _prefConcept = 'chargen_concept';
  static const _prefKeywords = 'chargen_keywords';
  static const _prefArtStyle = 'chargen_art_style';
  static const _prefModel = 'chargen_model';
  static const _prefGreetingLength = 'chargen_greeting_length';
  static const _prefAltCount = 'chargen_alt_count';
  static const _prefTone = 'chargen_tone';
  static const _prefLorebook = 'chargen_lorebook';
  static const _prefAge = 'chargen_age';
  static const _prefSex = 'chargen_sex';
  static const _prefRelationship = 'chargen_relationship';
  static const _prefPersona = 'chargen_persona';
  static const _prefQuickScenario = 'chargen_quick_scenario';
  static const _prefLoreCategories = 'chargen_lore_categories';
  static const _prefLoreDepth = 'chargen_lore_depth';
  static const _prefDynamicMacros = 'chargen_dynamic_macros';
  static const _prefNarrativePerspective = 'chargen_narrative_perspective';
  static const _prefNarrativeTense = 'chargen_narrative_tense';
  static const _prefRelationships = 'chargen_relationships';
  static const _prefCustomRelationship = 'chargen_custom_relationship';
  static const _prefNsfwEnabled = 'chargen_nsfw_enabled';
  static const _prefRealismVerificationEnabled =
      'chargen_realism_verification_enabled';
  static const _prefRealismVerificationMax = 'chargen_realism_verification_max';
  static const _prefRealismVerificationStrict =
      'chargen_realism_verification_strict';
  static const _prefRealismNeedsDirectorAuthority =
      'chargen_realism_needs_director_authority';
  static const _prefBodyType = 'chargen_body_type';
  static const _prefRace = 'chargen_race';
  static const _prefCustomRace = 'chargen_custom_race';
  static const _prefHairLength = 'chargen_hair_length';
  static const _prefHairStyle = 'chargen_hair_style';
  static const _prefSkinTone = 'chargen_skin_tone';
  static const _prefNotableFeatures = 'chargen_notable_features';
  static const _prefAbsCore = 'chargen_abs_core';
  static const _prefThighs = 'chargen_thighs';
  static const _prefHips = 'chargen_hips';
  static const _prefShoulders = 'chargen_shoulders';
  static const _prefWaist = 'chargen_waist';
  static const _prefChestSize = 'chargen_chest_size';
  static const _prefButtSize = 'chargen_butt_size';
  static const _prefExperience = 'chargen_experience';
  static const _prefDominance = 'chargen_dominance';
  static const _prefKinks = 'chargen_kinks';
  static const _prefCustomKinks = 'chargen_custom_kinks';
  static const _prefOutfitVibe = 'chargen_outfit_vibe';
  static const _prefGenerationDetail = 'chargen_generation_detail';
  static const _prefBackstoryOrigin = 'chargen_backstory_origin';
  static const _prefBackstoryTone = 'chargen_backstory_tone';
  static const _prefBackstoryEra = 'chargen_backstory_era';
  static const _prefBackstoryNotes = 'chargen_backstory_notes';
  static const _prefConceptGenerated = 'chargen_concept_generated';
  static const _prefCreatorMode = 'chargen_creator_mode';
  static const _prefGuidedVision = 'chargen_guided_vision';
  static const _prefGuidedAppearance = 'chargen_guided_appearance';
  static const _prefGuidedHair = 'chargen_guided_hair';
  static const _prefGuidedFeatures = 'chargen_guided_features';
  static const _prefGuidedRace = 'chargen_guided_race';
  static const _prefGuidedPersonality = 'chargen_guided_personality';
  static const _prefGuidedSpeech = 'chargen_guided_speech';
  static const _prefGuidedSecret = 'chargen_guided_secret';
  static const _prefGuidedOrigin = 'chargen_guided_origin';
  static const _prefGuidedSetting = 'chargen_guided_setting';
  static const _prefGuidedTone = 'chargen_guided_tone';
  static const _prefGuidedRelDynamic = 'chargen_guided_rel_dynamic';
  static const _prefGuidedRelScenario = 'chargen_guided_rel_scenario';
  static const _prefGuidedNsfwBody = 'chargen_guided_nsfw_body';
  static const _prefGuidedNsfwExp = 'chargen_guided_nsfw_exp';
  static const _prefGuidedNsfwDom = 'chargen_guided_nsfw_dom';
  static const _prefGuidedNsfwKinks = 'chargen_guided_nsfw_kinks';
  static const _prefGuidedNsfwClothing = 'chargen_guided_nsfw_clothing';
  static const _prefGuidedNsfwPersonality = 'chargen_guided_nsfw_personality';

  /// The Interview card's list: `''` is the standard set.
  static const _prefInterviewQuestions = 'chargen_interview_questions';

  // Quick's own tones, count and 18+, and the rest a template holds.
  static const _prefQuickNsfw = 'chargen_quick_nsfw';
  static const _prefQuickTones = 'chargen_quick_tones';
  static const _prefQuickGreetingCount = 'chargen_quick_greeting_count';
  static const _prefReasoning = 'chargen_reasoning';
  static const _prefArchetype = 'chargen_archetype';
  static const _prefLoreUrls = 'chargen_lore_urls';

  /// The `Started from` mark: `''` for none.
  static const _prefTemplateStartedFrom = 'chargen_template_started_from';

  /// The last save in line. Saves write one after another: a slow first
  /// save (every key missing) could otherwise finish after a newer one and
  /// put older text back.
  Future<void> _saveQueue = Future<void>.value();

  /// Reads every saved field into [s]. The saved mode goes to [applyMode]:
  /// the state owns that field. The caller notifies once loading is done.
  Future<void> load(
    CreatorState s, {
    required void Function(CreatorMode mode) applyMode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    s.nameController.text = prefs.getString(_prefName) ?? '';
    s.conceptController.text = prefs.getString(_prefConcept) ?? '';
    s.keywordsController.text = prefs.getString(_prefKeywords) ?? '';
    s.artStyle = prefs.getString(_prefArtStyle) ?? 'Anime';
    s.selectedModelId = prefs.getString(_prefModel) ?? '';
    s.greetingLength =
        prefs.getString(_prefGreetingLength) ?? 'Medium (2-4 paragraphs)';
    s.altGreetingCount = prefs.getInt(_prefAltCount) ?? 2;
    final savedTones = prefs.getString(_prefTone) ?? 'Neutral';
    s.selectedTones = savedTones.split(',').where((t) => t.isNotEmpty).toSet();
    if (s.selectedTones.isEmpty) s.selectedTones = {'Neutral'};
    s.generateLorebook = prefs.getBool(_prefLorebook) ?? true;
    s.ageController.text = prefs.getString(_prefAge) ?? '';
    s.sexController.text = prefs.getString(_prefSex) ?? '';
    s.relationshipController.text = prefs.getString(_prefRelationship) ?? '';
    s.selectedPersonaId = prefs.getString(_prefPersona) ?? '';
    s.quickScenarioController.text = prefs.getString(_prefQuickScenario) ?? '';

    final savedCategories = prefs.getString(_prefLoreCategories) ?? '';
    s.selectedLoreCategories = savedCategories
        .split(',')
        .where((c) => c.isNotEmpty)
        .toSet();
    s.loreDepth = prefs.getString(_prefLoreDepth) ?? 'Standard';
    s.includeDynamicMacros = prefs.getBool(_prefDynamicMacros) ?? false;
    s.narrativePerspective =
        prefs.getString(_prefNarrativePerspective) ?? 'first';
    if (s.narrativePerspective != 'first' &&
        s.narrativePerspective != 'third') {
      s.narrativePerspective = 'first';
    }
    s.narrativeTense = prefs.getString(_prefNarrativeTense) ?? 'present';
    if (s.narrativeTense != 'present' && s.narrativeTense != 'past') {
      s.narrativeTense = 'present';
    }
    final savedRelationships = prefs.getString(_prefRelationships) ?? '';
    s.selectedRelationships = savedRelationships
        .split(',')
        .where((r) => r.isNotEmpty)
        .toSet();
    s.customRelationship = prefs.getString(_prefCustomRelationship) ?? '';
    s.nsfwEnabled = prefs.getBool(_prefNsfwEnabled) ?? false;
    s.realismVerificationEnabled =
        prefs.getBool(_prefRealismVerificationEnabled) ?? false;
    s.realismVerificationMaxReprocesses =
        prefs.getInt(_prefRealismVerificationMax) ?? 1;
    s.realismVerificationStrictness =
        prefs.getInt(_prefRealismVerificationStrict) ?? 3;
    s.realismNeedsDirectorAuthority =
        prefs.getBool(_prefRealismNeedsDirectorAuthority) ?? false;
    s.bodyType = prefs.getString(_prefBodyType) ?? '';
    s.race = prefs.getString(_prefRace) ?? '';
    s.customRaceController.text = prefs.getString(_prefCustomRace) ?? '';
    s.hairLength = prefs.getString(_prefHairLength) ?? '';
    s.hairStyle = prefs.getString(_prefHairStyle) ?? '';
    s.skinTone = prefs.getString(_prefSkinTone) ?? '';
    final savedFeatures = prefs.getString(_prefNotableFeatures) ?? '';
    s.notableFeatures = savedFeatures
        .split(',')
        .where((f) => f.isNotEmpty)
        .toSet();
    s.absCore = prefs.getString(_prefAbsCore) ?? '';
    s.thighs = prefs.getString(_prefThighs) ?? '';
    s.hips = prefs.getString(_prefHips) ?? '';
    s.shoulders = prefs.getString(_prefShoulders) ?? '';
    s.waist = prefs.getString(_prefWaist) ?? '';
    s.chestSize = prefs.getString(_prefChestSize) ?? '';
    s.buttSize = prefs.getString(_prefButtSize) ?? '';
    s.experience = prefs.getString(_prefExperience) ?? '';
    s.dominance = prefs.getString(_prefDominance) ?? '';
    final savedKinks = prefs.getString(_prefKinks) ?? '';
    s.selectedKinks = savedKinks.split(',').where((k) => k.isNotEmpty).toSet();
    s.customKinksController.text = prefs.getString(_prefCustomKinks) ?? '';
    s.outfitVibe = prefs.getString(_prefOutfitVibe) ?? '';
    s.generationDetail = prefs.getString(_prefGenerationDetail) ?? 'Standard';
    s.backstoryOrigin = prefs.getString(_prefBackstoryOrigin) ?? '';
    s.backstoryTone = prefs.getString(_prefBackstoryTone) ?? '';
    s.backstoryEra = prefs.getString(_prefBackstoryEra) ?? '';
    s.backstoryNotesController.text =
        prefs.getString(_prefBackstoryNotes) ?? '';
    s.conceptGenerated = prefs.getBool(_prefConceptGenerated) ?? false;

    // Stored as the enum's own name so every mode round-trips. Quick Create
    // used to collapse to 'automated' on BOTH sides of this pair, so picking
    // it and reopening the wizard silently put the user back on the automated
    // form. Unknown/legacy values still fall back to automated.
    final savedMode = prefs.getString(_prefCreatorMode) ?? 'automated';
    applyMode(switch (savedMode) {
      'guided' => CreatorMode.guided,
      'quick' => CreatorMode.quick,
      _ => CreatorMode.automated,
    });
    s.guidedVisionController.text = prefs.getString(_prefGuidedVision) ?? '';
    s.guidedAppearanceController.text =
        prefs.getString(_prefGuidedAppearance) ?? '';
    s.guidedHairController.text = prefs.getString(_prefGuidedHair) ?? '';
    s.guidedFeaturesController.text =
        prefs.getString(_prefGuidedFeatures) ?? '';
    s.guidedRaceController.text = prefs.getString(_prefGuidedRace) ?? '';
    s.guidedPersonalityController.text =
        prefs.getString(_prefGuidedPersonality) ?? '';
    s.guidedSpeechController.text = prefs.getString(_prefGuidedSpeech) ?? '';
    s.guidedSecretController.text = prefs.getString(_prefGuidedSecret) ?? '';
    s.guidedOriginController.text = prefs.getString(_prefGuidedOrigin) ?? '';
    s.guidedSettingController.text = prefs.getString(_prefGuidedSetting) ?? '';
    s.guidedToneController.text = prefs.getString(_prefGuidedTone) ?? '';
    s.guidedRelDynamicController.text =
        prefs.getString(_prefGuidedRelDynamic) ?? '';
    s.guidedRelScenarioController.text =
        prefs.getString(_prefGuidedRelScenario) ?? '';
    s.guidedNsfwBodyController.text =
        prefs.getString(_prefGuidedNsfwBody) ?? '';
    s.guidedNsfwExpController.text = prefs.getString(_prefGuidedNsfwExp) ?? '';
    s.guidedNsfwDomController.text = prefs.getString(_prefGuidedNsfwDom) ?? '';
    s.guidedNsfwKinksController.text =
        prefs.getString(_prefGuidedNsfwKinks) ?? '';
    s.guidedNsfwClothingController.text =
        prefs.getString(_prefGuidedNsfwClothing) ?? '';
    s.guidedNsfwPersonalityController.text =
        prefs.getString(_prefGuidedNsfwPersonality) ?? '';
    s.interview.restore(prefs.getString(_prefInterviewQuestions) ?? '');
    s.quickNsfwEnabled = prefs.getBool(_prefQuickNsfw) ?? false;
    final quickTones = (prefs.getString(_prefQuickTones) ?? 'Neutral')
        .split(',')
        .where((t) => t.isNotEmpty)
        .toList();
    s.quickSelectedTones = quickTones.isEmpty ? ['Neutral'] : quickTones;
    s.quickGreetingCount = prefs.getInt(_prefQuickGreetingCount) ?? 0;
    s.reasoningEnabled = prefs.getBool(_prefReasoning) ?? false;
    s.selectedArchetype = prefs.getString(_prefArchetype) ?? '';
    s.loreUrlsController.text = prefs.getString(_prefLoreUrls) ?? '';
    s.templates.startedFrom = TemplateStart.fromPrefs(
      prefs.getString(_prefTemplateStartedFrom) ?? '',
    );
  }

  /// Every saved wizard field, keyed by its preference. Read in one go,
  /// before any await, so a save started as the wizard closes still sees the
  /// text of controllers that are about to be disposed.
  Map<String, Object> _savedFields(CreatorState s) => {
    _prefName: s.nameController.text,
    _prefConcept: s.conceptController.text,
    _prefKeywords: s.keywordsController.text,
    _prefArtStyle: s.artStyle,
    _prefModel: s.selectedModelId,
    _prefGreetingLength: s.greetingLength,
    _prefAltCount: s.altGreetingCount,
    _prefTone: s.selectedTones.join(','),
    _prefLorebook: s.generateLorebook,
    _prefAge: s.ageController.text,
    _prefSex: s.sexController.text,
    _prefRelationship: s.relationshipController.text,
    _prefPersona: s.selectedPersonaId,
    _prefQuickScenario: s.quickScenarioController.text,
    _prefLoreCategories: s.selectedLoreCategories.join(','),
    _prefLoreDepth: s.loreDepth,
    _prefDynamicMacros: s.includeDynamicMacros,
    _prefNarrativePerspective: s.narrativePerspective,
    _prefNarrativeTense: s.narrativeTense,
    _prefRelationships: s.selectedRelationships.join(','),
    _prefCustomRelationship: s.customRelationship,
    _prefNsfwEnabled: s.nsfwEnabled,
    _prefRealismVerificationEnabled: s.realismVerificationEnabled,
    _prefRealismVerificationMax: s.realismVerificationMaxReprocesses,
    _prefRealismVerificationStrict: s.realismVerificationStrictness,
    _prefRealismNeedsDirectorAuthority: s.realismNeedsDirectorAuthority,
    _prefBodyType: s.bodyType,
    _prefRace: s.race,
    _prefCustomRace: s.customRaceController.text,
    _prefHairLength: s.hairLength,
    _prefHairStyle: s.hairStyle,
    _prefSkinTone: s.skinTone,
    _prefNotableFeatures: s.notableFeatures.join(','),
    _prefAbsCore: s.absCore,
    _prefThighs: s.thighs,
    _prefHips: s.hips,
    _prefShoulders: s.shoulders,
    _prefWaist: s.waist,
    _prefChestSize: s.chestSize,
    _prefButtSize: s.buttSize,
    _prefExperience: s.experience,
    _prefDominance: s.dominance,
    _prefKinks: s.selectedKinks.join(','),
    _prefCustomKinks: s.customKinksController.text,
    _prefOutfitVibe: s.outfitVibe,
    _prefGenerationDetail: s.generationDetail,
    _prefBackstoryOrigin: s.backstoryOrigin,
    _prefBackstoryTone: s.backstoryTone,
    _prefBackstoryEra: s.backstoryEra,
    _prefBackstoryNotes: s.backstoryNotesController.text,
    _prefConceptGenerated: s.conceptGenerated,
    _prefCreatorMode: s.creatorMode.name,
    _prefGuidedVision: s.guidedVisionController.text,
    _prefGuidedAppearance: s.guidedAppearanceController.text,
    _prefGuidedHair: s.guidedHairController.text,
    _prefGuidedFeatures: s.guidedFeaturesController.text,
    _prefGuidedRace: s.guidedRaceController.text,
    _prefGuidedPersonality: s.guidedPersonalityController.text,
    _prefGuidedSpeech: s.guidedSpeechController.text,
    _prefGuidedSecret: s.guidedSecretController.text,
    _prefGuidedOrigin: s.guidedOriginController.text,
    _prefGuidedSetting: s.guidedSettingController.text,
    _prefGuidedTone: s.guidedToneController.text,
    _prefGuidedRelDynamic: s.guidedRelDynamicController.text,
    _prefGuidedRelScenario: s.guidedRelScenarioController.text,
    _prefGuidedNsfwBody: s.guidedNsfwBodyController.text,
    _prefGuidedNsfwExp: s.guidedNsfwExpController.text,
    _prefGuidedNsfwDom: s.guidedNsfwDomController.text,
    _prefGuidedNsfwKinks: s.guidedNsfwKinksController.text,
    _prefGuidedNsfwClothing: s.guidedNsfwClothingController.text,
    _prefGuidedNsfwPersonality: s.guidedNsfwPersonalityController.text,
    _prefInterviewQuestions: s.interview.toPrefs(),
    _prefQuickNsfw: s.quickNsfwEnabled,
    _prefQuickTones: s.quickSelectedTones.join(','),
    _prefQuickGreetingCount: s.quickGreetingCount,
    _prefReasoning: s.reasoningEnabled,
    _prefArchetype: s.selectedArchetype,
    _prefLoreUrls: s.loreUrlsController.text,
    _prefTemplateStartedFrom: TemplateStart.toPrefs(s.templates.startedFrom),
  };

  /// Writes only the fields whose value changed. On Windows and Linux every
  /// preference write rewrites the whole preferences file on the UI thread,
  /// so writing all of them per keystroke stalled typing (#371). The check
  /// is a read of the in-memory cache. The fields are read now; the writes
  /// wait for any save still running.
  Future<void> save(CreatorState s) {
    final fields = _savedFields(s);
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

  /// Clear the core saved-form prefs after a character is successfully created,
  /// so the next visit starts fresh. Mirrors the original review-step save.
  /// The `Started from` mark goes too: the next character starts unmarked.
  Future<void> clearAfterSave() => _queuePrefsWrite((prefs) async {
    for (final key in [
      _prefName,
      _prefConcept,
      _prefKeywords,
      _prefArtStyle,
      _prefTemplateStartedFrom,
    ]) {
      await prefs.remove(key);
    }
  });
}
