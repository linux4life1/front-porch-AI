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

part of 'creator_state_engine.dart';

/// Mode assemblers: each of the three creator modes (Quick/Guided/Automated)
/// builds its own concept/context/backstory strings from the relevant form
/// fields, then funnels through `_runGeneration` (creator_state_engine.core.dart).
extension _CreatorModes on CreatorState {
  // ── Mode assemblers ──────────────────────────────────────────────────

  Future<void> _generateQuick(
    LLMProvider llmProvider,
    StorageService storage,
    UserPersonaService personaService,
  ) {
    // Quick mode owns a separate NSFW toggle; sync it into the main flag so the
    // review step and prompts reflect it.
    nsfwEnabled = quickNsfwEnabled;
    final concept = conceptController.text.trim().isNotEmpty
        ? conceptController.text.trim()
        : 'Create an interesting, unique character for roleplay.';
    final quickConcept = quickNsfwEnabled
        ? '$concept. Adult content enabled: include explicit personality traits and sensual details.'
        : concept;

    return _runGeneration(
      llmProvider: llmProvider,
      storage: storage,
      personaService: personaService,
      build: (gen, worldLore, persona) => gen.generateCharacter(
        name: nameController.text.trim(),
        concept: quickConcept,
        personalityKeywords: '',
        artStyle: artStyle,
        greetingLength: 'Medium (2-4 paragraphs)',
        altGreetingCount: quickGreetingCount,
        greetingTones: quickSelectedTones,
        generateLorebook: true,
        loreCategories: const [],
        loreDepth: 'Standard',
        includeDynamicMacros: includeDynamicMacros,
        narrativePerspective: narrativePerspective,
        narrativeTense: narrativeTense,
        descriptionDetail: '2-3 paragraphs',
        age: '',
        sex: sexController.text.trim(),
        relationship: '',
        scenario: quickScenarioController.text.trim(),
        backstory: '',
        characterContext: '',
        userPersonaContext: persona,
        worldLore: worldLore,
        generateDescription: true,
        nsfwEnabled: nsfwEnabled,
        reasoningEnabled: reasoningEnabled,
        imageGenPromptParadigm: storage.imageGenPromptParadigm,
        onProgress: _onGenProgress,
        onStatus: _onGenStatus,
        onError: _onGenError,
      ),
    );
  }

  Future<void> _generateGuided(
    LLMProvider llmProvider,
    StorageService storage,
    UserPersonaService personaService,
  ) {
    final vision = guidedVisionController.text.trim();
    final parts = <String>[vision];
    void add(String label, TextEditingController c) {
      if (c.text.trim().isNotEmpty) parts.add('$label: ${c.text.trim()}');
    }

    add('Physical build', guidedAppearanceController);
    add('Hair', guidedHairController);
    add('Distinguishing features', guidedFeaturesController);
    add('Race/Species', guidedRaceController);
    add('Personality', guidedPersonalityController);
    add('Speech style', guidedSpeechController);
    add('Hidden depth', guidedSecretController);
    add('Background', guidedOriginController);
    add('Setting', guidedSettingController);
    add('Tone', guidedToneController);
    add('Relationship to {{user}}', guidedRelDynamicController);
    add('Opening scenario', guidedRelScenarioController);
    if (nsfwEnabled) {
      add('Intimate body details', guidedNsfwBodyController);
      add('Sexual experience', guidedNsfwExpController);
      add('Dominance', guidedNsfwDomController);
      add('Turn-ons/kinks', guidedNsfwKinksController);
      add('Clothing aesthetic', guidedNsfwClothingController);
      add('Sexual personality', guidedNsfwPersonalityController);
    }

    final contextParts = <String>[];
    void addCtx(String label, TextEditingController c) {
      if (c.text.trim().isNotEmpty) {
        contextParts.add('$label: ${c.text.trim()}');
      }
    }

    addCtx('Age', ageController);
    addCtx('Sex', sexController);
    addCtx('Appearance', guidedAppearanceController);
    addCtx('Hair', guidedHairController);
    addCtx('Features', guidedFeaturesController);
    addCtx('Race/Species', guidedRaceController);
    addCtx('Relationship to {{user}}', guidedRelDynamicController);
    addCtx('Backstory', guidedOriginController);
    addCtx('Setting', guidedSettingController);
    addCtx('Tone', guidedToneController);
    if (nsfwEnabled) {
      final nsfw = <String>[];
      if (guidedNsfwExpController.text.trim().isNotEmpty) {
        nsfw.add('Experience: ${guidedNsfwExpController.text.trim()}');
      }
      if (guidedNsfwDomController.text.trim().isNotEmpty) {
        nsfw.add('Dominance: ${guidedNsfwDomController.text.trim()}');
      }
      if (guidedNsfwKinksController.text.trim().isNotEmpty) {
        nsfw.add('Kinks: ${guidedNsfwKinksController.text.trim()}');
      }
      if (nsfw.isNotEmpty) contextParts.add(nsfw.join(', '));
    }

    return _runGeneration(
      llmProvider: llmProvider,
      storage: storage,
      personaService: personaService,
      build: (gen, worldLore, persona) => gen.generateCharacter(
        name: nameController.text.trim(),
        concept: parts.join('. '),
        personalityKeywords: guidedPersonalityController.text.trim(),
        artStyle: artStyle,
        greetingLength: greetingLength,
        altGreetingCount: altGreetingCount,
        greetingTones: selectedTones.toList(),
        generateLorebook: generateLorebook,
        loreCategories: selectedLoreCategories.toList(),
        loreDepth: loreDepth,
        includeDynamicMacros: includeDynamicMacros,
        narrativePerspective: narrativePerspective,
        narrativeTense: narrativeTense,
        descriptionDetail:
            CreatorState.generationDetailOptions[generationDetail] ??
            '2-3 paragraphs',
        age: ageController.text.trim(),
        sex: sexController.text.trim(),
        relationship: guidedRelDynamicController.text.trim(),
        backstory: [
          if (guidedOriginController.text.trim().isNotEmpty)
            guidedOriginController.text.trim(),
          if (guidedToneController.text.trim().isNotEmpty)
            '${guidedToneController.text.trim()} tone',
          if (guidedSettingController.text.trim().isNotEmpty)
            '${guidedSettingController.text.trim()} setting',
        ].join(', '),
        characterContext: contextParts.join('\n'),
        userPersonaContext: persona,
        worldLore: worldLore,
        generateDescription: true,
        nsfwEnabled: nsfwEnabled,
        reasoningEnabled: reasoningEnabled,
        imageGenPromptParadigm: storage.imageGenPromptParadigm,
        onProgress: _onGenProgress,
        onStatus: _onGenStatus,
        onError: _onGenError,
      ),
    );
  }

  Future<void> _generateAutomated(
    LLMProvider llmProvider,
    StorageService storage,
    UserPersonaService personaService,
  ) {
    final concept = conceptController.text.trim();
    final keywords = keywordsController.text.trim();
    final effectiveRace = customRaceController.text.trim().isNotEmpty
        ? customRaceController.text.trim()
        : race;

    final appearance = <String>[];
    if (effectiveRace.isNotEmpty) appearance.add('$effectiveRace race/species');
    if (bodyType.isNotEmpty) appearance.add('$bodyType build');
    if (hairLength.isNotEmpty) appearance.add('$hairLength hair');
    if (hairStyle.isNotEmpty) appearance.add('$hairStyle hair style');
    if (skinTone.isNotEmpty) appearance.add('$skinTone skin');
    if (notableFeatures.isNotEmpty) appearance.addAll(notableFeatures);
    if (absCore.isNotEmpty) appearance.add('$absCore abs');
    if (thighs.isNotEmpty) appearance.add('$thighs thighs');
    if (hips.isNotEmpty) appearance.add('$hips hips');
    if (shoulders.isNotEmpty) appearance.add('$shoulders shoulders');
    if (waist.isNotEmpty) appearance.add('$waist waist');
    if (nsfwEnabled) {
      if (chestSize.isNotEmpty) appearance.add('$chestSize chest');
      if (buttSize.isNotEmpty) appearance.add('$buttSize butt');
    }

    final nsfwParts = <String>[];
    if (nsfwEnabled) {
      if (experience.isNotEmpty) {
        nsfwParts.add('Sexual experience: $experience');
      }
      if (dominance.isNotEmpty) nsfwParts.add('Dominance: $dominance');
      if (selectedKinks.isNotEmpty) {
        nsfwParts.add('Kinks: ${selectedKinks.join(", ")}');
      }
      if (customKinksController.text.trim().isNotEmpty) {
        nsfwParts.add('Also into: ${customKinksController.text.trim()}');
      }
      if (outfitVibe.isNotEmpty) {
        nsfwParts.add('Typical outfit vibe: $outfitVibe');
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
      ...selectedRelationships,
      if (relationshipController.text.trim().isNotEmpty)
        relationshipController.text.trim(),
    ].join(', ');

    return _runGeneration(
      llmProvider: llmProvider,
      storage: storage,
      personaService: personaService,
      build: (gen, worldLore, persona) async {
        final card = await gen.generateCharacter(
          name: nameController.text.trim(),
          concept: enriched,
          personalityKeywords: keywords,
          artStyle: artStyle,
          greetingLength: greetingLength,
          altGreetingCount: altGreetingCount,
          greetingTones: selectedTones.toList(),
          generateLorebook: generateLorebook,
          loreCategories: selectedLoreCategories.toList(),
          loreDepth: loreDepth,
          includeDynamicMacros: includeDynamicMacros,
          narrativePerspective: narrativePerspective,
          narrativeTense: narrativeTense,
          descriptionDetail:
              CreatorState.generationDetailOptions[generationDetail] ??
              '2-3 paragraphs',
          age: ageController.text.trim(),
          sex: sexController.text.trim(),
          worldLore: worldLore,
          relationship: relationship,
          backstory: [
            if (backstoryOrigin.isNotEmpty) backstoryOrigin,
            if (backstoryTone.isNotEmpty) '$backstoryTone tone',
            if (backstoryEra.isNotEmpty) '$backstoryEra era',
            if (backstoryNotesController.text.trim().isNotEmpty)
              backstoryNotesController.text.trim(),
          ].join(', '),
          characterContext: [
            if (effectiveRace.isNotEmpty) 'Race/Species: $effectiveRace',
            if (ageController.text.trim().isNotEmpty)
              'Age: ${ageController.text.trim()}',
            if (sexController.text.trim().isNotEmpty)
              'Sex: ${sexController.text.trim()}',
            if (appearance.isNotEmpty) 'Appearance: ${appearance.join(", ")}',
            if (relationship.isNotEmpty)
              'Relationship to {{user}}: $relationship',
            if (backstoryOrigin.isNotEmpty)
              'Backstory origin: $backstoryOrigin',
            if (backstoryTone.isNotEmpty) 'Story tone: $backstoryTone',
            if (backstoryEra.isNotEmpty) 'Era/setting: $backstoryEra',
            if (backstoryNotesController.text.trim().isNotEmpty)
              'Backstory: ${backstoryNotesController.text.trim()}',
            if (nsfwEnabled && nsfwParts.isNotEmpty) nsfwParts.join(', '),
          ].join('\n'),
          userPersonaContext: persona,
          nsfwEnabled: nsfwEnabled,
          reasoningEnabled: reasoningEnabled,
          imageGenPromptParadigm: storage.imageGenPromptParadigm,
          onProgress: _onGenProgress,
          onStatus: _onGenStatus,
          onError: _onGenError,
        );
        // The automated flow injects the (possibly magic-wand authored)
        // description verbatim rather than trusting the model's rewrite.
        if (card != null) card.description = enriched;
        return card;
      },
    );
  }
}
