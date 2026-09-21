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

/// Field-tool generators: single-shot LLM helpers called directly from wizard
/// step widgets (guided vision expansion, name randomization, automated
/// concept randomization). Public extension — these are called from OTHER
/// libraries, so it cannot be library-private.
extension CreatorEngineTools on CreatorState {
  /// (Guided) Expand all filled fields into a cohesive description. Returns the
  /// generated text; the step shows an accept/reject dialog and, if accepted,
  /// writes it into [guidedVisionController].
  Future<String?> expandNarrative({
    required LLMProvider llmProvider,
    required StorageService storage,
  }) async {
    if (isExpandingNarrative) return null;
    isExpandingNarrative = true;
    notify();
    try {
      final llmService = llmProvider.serviceForModel(selectedModelId);
      if (llmService == null) {
        engineError = 'No LLM available — configure a model first';
        return null;
      }

      final details = <String>[];
      void add(String label, TextEditingController c) {
        if (c.text.trim().isNotEmpty) details.add('$label: ${c.text.trim()}');
      }

      add('Name', nameController);
      add('Age', ageController);
      add('Sex', sexController);
      add('Build/Body', guidedAppearanceController);
      add('Hair', guidedHairController);
      add('Features', guidedFeaturesController);
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
        add('Intimate body', guidedNsfwBodyController);
        add('Experience', guidedNsfwExpController);
        add('Dominance', guidedNsfwDomController);
        add('Kinks', guidedNsfwKinksController);
        add('Clothing', guidedNsfwClothingController);
        add('Sexual personality', guidedNsfwPersonalityController);
      }

      final userVision = guidedVisionController.text.trim();
      if (details.length <= 1 && userVision.isEmpty) return null;

      final visionBlock = userVision.isNotEmpty
          ? '\n\nUser\'s additional notes/vision:\n"$userVision"'
          : '';

      String accumulated = '';
      await for (final token in llmService.generateStream(
        GenerationParams(
          prompt:
              'A user is creating a roleplay character using a guided form. They filled in '
              'various fields with details about the character. Generate a vivid, cohesive character '
              'description that weaves ALL of these details together into 2-3 flowing paragraphs. '
              'PRESERVE the user\'s creative intent — do not override their ideas with generic tropes. '
              'If they provided NSFW details, include them tastefully in the description.\n\n'
              'Character details from form:\n${details.join('\n')}$visionBlock\n\n'
              'Output ONLY a JSON object with exactly one key: "expanded". The value should be '
              'the complete character description in third person. No markdown, no explanation, just the JSON:',
          maxLength: 1024,
          minLength: 64,
          temperature: 1.0,
          repeatPenalty: 1.1,
          minP: 0.05,
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
          mandatoryReasoningHeadroom: true,
          stopSequences: ['<END>'],
        ),
      )) {
        accumulated += token;
      }
      return extractChargenValue(accumulated, 'expanded');
    } catch (e) {
      if (e is SilentMandatoryReasoningStarveException) {
        debugPrint('CharacterCreator: $e — failing expand (no more retries)');
        return null;
      }
      debugPrint('CharacterCreator: expand narrative failed: $e');
      return null;
    } finally {
      isExpandingNarrative = false;
      notify();
    }
  }

  /// Generate a single creative character name into [nameController].
  Future<void> randomizeName({
    required LLMProvider llmProvider,
    required StorageService storage,
  }) async {
    if (isRandomizing) return;
    isRandomizing = true;
    notify();
    try {
      final llmService = llmProvider.serviceForModel(selectedModelId);
      if (llmService == null) {
        engineError = 'No LLM available — configure a model first';
        return;
      }
      final archetypeHint = selectedArchetype.isNotEmpty
          ? ' The name should suit a "$selectedArchetype" character.'
          : '';
      String accumulated = '';
      await for (final token in llmService.generateStream(
        GenerationParams(
          prompt:
              'Generate ONE unique, creative character name for a roleplay character.$archetypeHint Output ONLY a JSON object with exactly one key: "name". No markdown, no explanation, just the JSON:',
          maxLength: 128,
          minLength: 16,
          temperature: 1.2,
          repeatPenalty: 1.1,
          minP: 0.05,
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
          mandatoryReasoningHeadroom: true,
          stopSequences: ['<END>'],
        ),
      )) {
        accumulated += token;
      }
      final name = extractChargenValue(accumulated, 'name');
      if (name != null) nameController.text = name;
    } catch (e) {
      if (e is SilentMandatoryReasoningStarveException) {
        debugPrint(
          'CharacterCreator: $e — failing name roll (no more retries)',
        );
        return;
      }
      debugPrint('CharacterCreator: randomize name failed: $e');
    } finally {
      isRandomizing = false;
      notify();
    }
  }

  /// (Automated) Generate a description into [conceptController] from all the
  /// selected toggles, streaming progress into [conceptGenProgress].
  Future<void> randomizeConcept({
    required LLMProvider llmProvider,
    required StorageService storage,
  }) async {
    if (isRandomizing) return;
    isRandomizing = true;
    conceptGenProgress = 0.0;
    notify();
    try {
      final llmService = llmProvider.serviceForModel(selectedModelId);
      if (llmService == null) {
        engineError = 'No LLM available — configure a model first';
        return;
      }

      final ctx = <String>[];
      if (selectedArchetype.isNotEmpty) {
        ctx.add('Archetype: $selectedArchetype');
      }
      if (nameController.text.trim().isNotEmpty) {
        ctx.add('Name: ${nameController.text.trim()}');
      }
      if (keywordsController.text.trim().isNotEmpty) {
        ctx.add('Personality: ${keywordsController.text.trim()}');
      }
      if (ageController.text.trim().isNotEmpty) {
        ctx.add('Age: ${ageController.text.trim()}');
      }
      if (sexController.text.trim().isNotEmpty) {
        ctx.add('Sex: ${sexController.text.trim()}');
      }
      final effectiveRace = customRaceController.text.trim().isNotEmpty
          ? customRaceController.text.trim()
          : race;
      if (effectiveRace.isNotEmpty) ctx.add('Race/species: $effectiveRace');
      if (bodyType.isNotEmpty) ctx.add('Body type: $bodyType');
      if (hairLength.isNotEmpty || hairStyle.isNotEmpty) {
        ctx.add(
          'Hair: ${[if (hairLength.isNotEmpty) hairLength, if (hairStyle.isNotEmpty) hairStyle].join(", ")}',
        );
      }
      if (skinTone.isNotEmpty) ctx.add('Skin tone: $skinTone');
      if (notableFeatures.isNotEmpty) {
        ctx.add('Notable features: ${notableFeatures.join(", ")}');
      }
      if (selectedRelationships.isNotEmpty) {
        ctx.add('Relationship to user: ${selectedRelationships.join(", ")}');
      }
      if (backstoryOrigin.isNotEmpty) {
        ctx.add('Backstory origin: $backstoryOrigin');
      }
      if (backstoryTone.isNotEmpty) ctx.add('Backstory tone: $backstoryTone');
      if (backstoryEra.isNotEmpty) ctx.add('Era/setting: $backstoryEra');
      if (backstoryNotesController.text.trim().isNotEmpty) {
        ctx.add('Backstory notes: ${backstoryNotesController.text.trim()}');
      }
      if (nsfwEnabled) {
        if (experience.isNotEmpty) ctx.add('Experience: $experience');
        if (dominance.isNotEmpty) ctx.add('Dominance: $dominance');
        if (selectedKinks.isNotEmpty) {
          ctx.add('Kinks: ${selectedKinks.join(", ")}');
        }
        if (outfitVibe.isNotEmpty) ctx.add('Outfit vibe: $outfitVibe');
      }

      final contextStr = ctx.isNotEmpty
          ? ' Use these character details as inspiration: ${ctx.join("; ")}.'
          : '';
      final descLength =
          CreatorState.generationDetailOptions[generationDetail] ??
          '2-3 paragraphs';
      final maxTokens =
          const {
            'Brief': 256,
            'Standard': 512,
            'Detailed': 1024,
            'Comprehensive': 2048,
          }[generationDetail] ??
          512;

      String accumulated = '';
      int tokenCount = 0;
      await for (final token in llmService.generateStream(
        GenerationParams(
          prompt:
              'Generate a creative character description ($descLength) for a roleplay character.$contextStr Write in third person. Include physical appearance, personality hints, and backstory elements. Output ONLY a JSON object with exactly one key: "concept". Be vivid and detailed. No markdown, no explanation, just the JSON:',
          maxLength: maxTokens,
          minLength: 32,
          temperature: 1.2,
          repeatPenalty: 1.1,
          minP: 0.05,
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
          mandatoryReasoningHeadroom: true,
          stopSequences: ['<END>'],
        ),
      )) {
        accumulated += token;
        tokenCount++;
        conceptGenProgress = (tokenCount / maxTokens).clamp(0.0, 0.95);
        notify();
      }

      final concept = extractChargenValue(accumulated, 'concept');
      if (concept != null) {
        conceptController.text = concept;
        conceptGenerated = true;
      }
    } catch (e) {
      if (e is SilentMandatoryReasoningStarveException) {
        debugPrint(
          'CharacterCreator: $e — failing concept roll (no more retries)',
        );
      } else {
        debugPrint('CharacterCreator: randomize concept failed: $e');
      }
    } finally {
      isRandomizing = false;
      notify();
    }
  }
}
