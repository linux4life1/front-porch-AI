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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.core.dart';

/// Mode assemblers: each of the three creator modes (Quick/Guided/Automated)
/// builds its own concept/context/backstory strings from [state]'s form
/// fields, then funnels through [CreatorGenerationCore.run].
class CreatorModeAssemblers {
  final CreatorState state;
  final CreatorGenerationCore _core;

  CreatorModeAssemblers(this.state) : _core = CreatorGenerationCore(state);

  // ── Mode assemblers ──────────────────────────────────────────────────

  Future<void> quick(
    LLMProvider llmProvider,
    StorageService storage,
    UserPersonaService personaService,
  ) {
    // Quick mode owns a separate NSFW toggle; sync it into the main flag so the
    // review step and prompts reflect it.
    state.nsfwEnabled = state.quickNsfwEnabled;
    final concept = state.conceptController.text.trim().isNotEmpty
        ? state.conceptController.text.trim()
        : 'Create an interesting, unique character for roleplay.';
    final quickConcept = state.quickNsfwEnabled
        ? '$concept. Adult content enabled: include explicit personality traits and sensual details.'
        : concept;

    return _core.run(
      llmProvider: llmProvider,
      storage: storage,
      personaService: personaService,
      build: (gen, worldLore, persona) => gen.generateCharacter(
        name: state.nameController.text.trim(),
        concept: quickConcept,
        personalityKeywords: '',
        artStyle: state.artStyle,
        greetingLength: 'Medium (2-4 paragraphs)',
        altGreetingCount: state.quickGreetingCount,
        greetingTones: state.quickSelectedTones,
        generateLorebook: true,
        loreCategories: const [],
        loreDepth: 'Standard',
        includeDynamicMacros: state.includeDynamicMacros,
        narrativePerspective: state.narrativePerspective,
        narrativeTense: state.narrativeTense,
        descriptionDetail: '2-3 paragraphs',
        age: '',
        sex: state.sexController.text.trim(),
        relationship: '',
        scenario: state.quickScenarioController.text.trim(),
        backstory: '',
        characterContext: '',
        userPersonaContext: persona,
        worldLore: worldLore,
        generateDescription: true,
        nsfwEnabled: state.nsfwEnabled,
        reasoningEnabled: state.reasoningEnabled,
        imageGenPromptParadigm: storage.imageGenSettings.imageGenPromptParadigm,
        onProgress: _core.onProgress,
        onStatus: _core.onStatus,
        onError: _core.onError,
      ),
    );
  }

  Future<void> guided(
    LLMProvider llmProvider,
    StorageService storage,
    UserPersonaService personaService,
  ) {
    final vision = state.guidedVisionController.text.trim();
    final parts = <String>[vision];
    void add(String label, TextEditingController c) {
      if (c.text.trim().isNotEmpty) parts.add('$label: ${c.text.trim()}');
    }

    add('Physical build', state.guidedAppearanceController);
    add('Hair', state.guidedHairController);
    add('Distinguishing features', state.guidedFeaturesController);
    add('Race/Species', state.guidedRaceController);
    add('Personality', state.guidedPersonalityController);
    add('Speech style', state.guidedSpeechController);
    add('Hidden depth', state.guidedSecretController);
    add('Background', state.guidedOriginController);
    add('Setting', state.guidedSettingController);
    add('Tone', state.guidedToneController);
    add('Relationship to {{user}}', state.guidedRelDynamicController);
    add('Opening scenario', state.guidedRelScenarioController);
    if (state.nsfwEnabled) {
      add('Intimate body details', state.guidedNsfwBodyController);
      add('Sexual experience', state.guidedNsfwExpController);
      add('Dominance', state.guidedNsfwDomController);
      add('Turn-ons/kinks', state.guidedNsfwKinksController);
      add('Clothing aesthetic', state.guidedNsfwClothingController);
      add('Sexual personality', state.guidedNsfwPersonalityController);
    }

    final contextParts = <String>[];
    void addCtx(String label, TextEditingController c) {
      if (c.text.trim().isNotEmpty) {
        contextParts.add('$label: ${c.text.trim()}');
      }
    }

    addCtx('Age', state.ageController);
    addCtx('Sex', state.sexController);
    addCtx('Appearance', state.guidedAppearanceController);
    addCtx('Hair', state.guidedHairController);
    addCtx('Features', state.guidedFeaturesController);
    addCtx('Race/Species', state.guidedRaceController);
    addCtx('Relationship to {{user}}', state.guidedRelDynamicController);
    addCtx('Backstory', state.guidedOriginController);
    addCtx('Setting', state.guidedSettingController);
    addCtx('Tone', state.guidedToneController);
    if (state.nsfwEnabled) {
      final nsfw = <String>[];
      if (state.guidedNsfwExpController.text.trim().isNotEmpty) {
        nsfw.add('Experience: ${state.guidedNsfwExpController.text.trim()}');
      }
      if (state.guidedNsfwDomController.text.trim().isNotEmpty) {
        nsfw.add('Dominance: ${state.guidedNsfwDomController.text.trim()}');
      }
      if (state.guidedNsfwKinksController.text.trim().isNotEmpty) {
        nsfw.add('Kinks: ${state.guidedNsfwKinksController.text.trim()}');
      }
      if (nsfw.isNotEmpty) contextParts.add(nsfw.join(', '));
    }

    return _core.run(
      llmProvider: llmProvider,
      storage: storage,
      personaService: personaService,
      build: (gen, worldLore, persona) => gen.generateCharacter(
        name: state.nameController.text.trim(),
        concept: parts.join('. '),
        personalityKeywords: state.guidedPersonalityController.text.trim(),
        artStyle: state.artStyle,
        greetingLength: state.greetingLength,
        altGreetingCount: state.altGreetingCount,
        greetingTones: state.selectedTones.toList(),
        generateLorebook: state.generateLorebook,
        loreCategories: state.selectedLoreCategories.toList(),
        loreDepth: state.loreDepth,
        includeDynamicMacros: state.includeDynamicMacros,
        narrativePerspective: state.narrativePerspective,
        narrativeTense: state.narrativeTense,
        descriptionDetail:
            CreatorState.generationDetailOptions[state.generationDetail] ??
            '2-3 paragraphs',
        age: state.ageController.text.trim(),
        sex: state.sexController.text.trim(),
        relationship: state.guidedRelDynamicController.text.trim(),
        backstory: [
          if (state.guidedOriginController.text.trim().isNotEmpty)
            state.guidedOriginController.text.trim(),
          if (state.guidedToneController.text.trim().isNotEmpty)
            '${state.guidedToneController.text.trim()} tone',
          if (state.guidedSettingController.text.trim().isNotEmpty)
            '${state.guidedSettingController.text.trim()} setting',
        ].join(', '),
        characterContext: contextParts.join('\n'),
        userPersonaContext: persona,
        worldLore: worldLore,
        generateDescription: true,
        nsfwEnabled: state.nsfwEnabled,
        reasoningEnabled: state.reasoningEnabled,
        imageGenPromptParadigm: storage.imageGenSettings.imageGenPromptParadigm,
        onProgress: _core.onProgress,
        onStatus: _core.onStatus,
        onError: _core.onError,
      ),
    );
  }

  Future<void> automated(
    LLMProvider llmProvider,
    StorageService storage,
    UserPersonaService personaService,
  ) {
    final concept = state.conceptController.text.trim();
    final keywords = state.keywordsController.text.trim();
    final effectiveRace = state.customRaceController.text.trim().isNotEmpty
        ? state.customRaceController.text.trim()
        : state.race;

    final appearance = <String>[];
    if (effectiveRace.isNotEmpty) appearance.add('$effectiveRace race/species');
    if (state.bodyType.isNotEmpty) appearance.add('${state.bodyType} build');
    if (state.hairLength.isNotEmpty) appearance.add('${state.hairLength} hair');
    if (state.hairStyle.isNotEmpty) {
      appearance.add('${state.hairStyle} hair style');
    }
    if (state.skinTone.isNotEmpty) appearance.add('${state.skinTone} skin');
    if (state.notableFeatures.isNotEmpty) {
      appearance.addAll(state.notableFeatures);
    }
    if (state.absCore.isNotEmpty) appearance.add('${state.absCore} abs');
    if (state.thighs.isNotEmpty) appearance.add('${state.thighs} thighs');
    if (state.hips.isNotEmpty) appearance.add('${state.hips} hips');
    if (state.shoulders.isNotEmpty) {
      appearance.add('${state.shoulders} shoulders');
    }
    if (state.waist.isNotEmpty) appearance.add('${state.waist} waist');
    if (state.nsfwEnabled) {
      if (state.chestSize.isNotEmpty) {
        appearance.add('${state.chestSize} chest');
      }
      if (state.buttSize.isNotEmpty) appearance.add('${state.buttSize} butt');
    }

    final nsfwParts = <String>[];
    if (state.nsfwEnabled) {
      if (state.experience.isNotEmpty) {
        nsfwParts.add('Sexual experience: ${state.experience}');
      }
      if (state.dominance.isNotEmpty) {
        nsfwParts.add('Dominance: ${state.dominance}');
      }
      if (state.selectedKinks.isNotEmpty) {
        nsfwParts.add('Kinks: ${state.selectedKinks.join(", ")}');
      }
      if (state.customKinksController.text.trim().isNotEmpty) {
        nsfwParts.add('Also into: ${state.customKinksController.text.trim()}');
      }
      if (state.outfitVibe.isNotEmpty) {
        nsfwParts.add('Typical outfit vibe: ${state.outfitVibe}');
      }
    }

    // Fragments are joined with '. ' only when there is something in front of
    // them: nothing in the wizard requires the concept box to be filled, and
    // appending unconditionally left a description that literally opened with
    // a stray period whenever it was empty.
    String enriched = concept;
    void appendSentence(String fragment) {
      enriched = enriched.isEmpty ? fragment : '$enriched. $fragment';
    }

    if (appearance.isNotEmpty) {
      appendSentence('Physical appearance: ${appearance.join(", ")}');
    }
    if (nsfwParts.isNotEmpty) appendSentence(nsfwParts.join('. '));

    final relationship = [
      ...state.selectedRelationships,
      if (state.relationshipController.text.trim().isNotEmpty)
        state.relationshipController.text.trim(),
    ].join(', ');

    return _core.run(
      llmProvider: llmProvider,
      storage: storage,
      personaService: personaService,
      build: (gen, worldLore, persona) async {
        final card = await gen.generateCharacter(
          name: state.nameController.text.trim(),
          concept: enriched,
          personalityKeywords: keywords,
          artStyle: state.artStyle,
          greetingLength: state.greetingLength,
          altGreetingCount: state.altGreetingCount,
          greetingTones: state.selectedTones.toList(),
          generateLorebook: state.generateLorebook,
          loreCategories: state.selectedLoreCategories.toList(),
          loreDepth: state.loreDepth,
          includeDynamicMacros: state.includeDynamicMacros,
          narrativePerspective: state.narrativePerspective,
          narrativeTense: state.narrativeTense,
          descriptionDetail:
              CreatorState.generationDetailOptions[state.generationDetail] ??
              '2-3 paragraphs',
          age: state.ageController.text.trim(),
          sex: state.sexController.text.trim(),
          worldLore: worldLore,
          relationship: relationship,
          backstory: [
            if (state.backstoryOrigin.isNotEmpty) state.backstoryOrigin,
            if (state.backstoryTone.isNotEmpty) '${state.backstoryTone} tone',
            if (state.backstoryEra.isNotEmpty) '${state.backstoryEra} era',
            if (state.backstoryNotesController.text.trim().isNotEmpty)
              state.backstoryNotesController.text.trim(),
          ].join(', '),
          characterContext: [
            if (effectiveRace.isNotEmpty) 'Race/Species: $effectiveRace',
            if (state.ageController.text.trim().isNotEmpty)
              'Age: ${state.ageController.text.trim()}',
            if (state.sexController.text.trim().isNotEmpty)
              'Sex: ${state.sexController.text.trim()}',
            if (appearance.isNotEmpty) 'Appearance: ${appearance.join(", ")}',
            if (relationship.isNotEmpty)
              'Relationship to {{user}}: $relationship',
            if (state.backstoryOrigin.isNotEmpty)
              'Backstory origin: ${state.backstoryOrigin}',
            if (state.backstoryTone.isNotEmpty)
              'Story tone: ${state.backstoryTone}',
            if (state.backstoryEra.isNotEmpty)
              'Era/setting: ${state.backstoryEra}',
            if (state.backstoryNotesController.text.trim().isNotEmpty)
              'Backstory: ${state.backstoryNotesController.text.trim()}',
            if (state.nsfwEnabled && nsfwParts.isNotEmpty) nsfwParts.join(', '),
          ].join('\n'),
          userPersonaContext: persona,
          nsfwEnabled: state.nsfwEnabled,
          reasoningEnabled: state.reasoningEnabled,
          imageGenPromptParadigm:
              storage.imageGenSettings.imageGenPromptParadigm,
          onProgress: _core.onProgress,
          onStatus: _core.onStatus,
          onError: _core.onError,
        );
        // The automated flow injects the (possibly magic-wand authored)
        // description verbatim rather than trusting the model's rewrite.
        if (card != null) card.description = enriched;
        return card;
      },
    );
  }
}
