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
import 'package:front_porch_ai/ui/character_creator/chargen_json.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';

/// Field-tool generators: single-shot LLM helpers called from wizard step
/// widgets (guided vision expansion, name randomization, automated concept
/// randomization). They read and write [state].
class CreatorFieldTools {
  final CreatorState state;

  CreatorFieldTools(this.state);

  /// (Guided) Expand all filled fields into a cohesive description. Returns the
  /// generated text; the step shows an accept/reject dialog and, if accepted,
  /// writes it into [guidedVisionController].
  Future<String?> expandNarrative({
    required LLMProvider llmProvider,
    required StorageService storage,
  }) async {
    if (state.isExpandingNarrative) return null;
    state.isExpandingNarrative = true;
    state.notify();
    try {
      final llmService = llmProvider.serviceForModel(state.selectedModelId);
      if (llmService == null) {
        state.engineError = 'No LLM available — configure a model first';
        return null;
      }

      final details = <String>[];
      void add(String label, TextEditingController c) {
        if (c.text.trim().isNotEmpty) details.add('$label: ${c.text.trim()}');
      }

      add('Name', state.nameController);
      add('Age', state.ageController);
      add('Sex', state.sexController);
      add('Build/Body', state.guidedAppearanceController);
      add('Hair', state.guidedHairController);
      add('Features', state.guidedFeaturesController);
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
        add('Intimate body', state.guidedNsfwBodyController);
        add('Experience', state.guidedNsfwExpController);
        add('Dominance', state.guidedNsfwDomController);
        add('Kinks', state.guidedNsfwKinksController);
        add('Clothing', state.guidedNsfwClothingController);
        add('Sexual personality', state.guidedNsfwPersonalityController);
      }

      final userVision = state.guidedVisionController.text.trim();
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
      state.isExpandingNarrative = false;
      state.notify();
    }
  }

  /// Generate a single creative character name into [nameController].
  Future<void> randomizeName({
    required LLMProvider llmProvider,
    required StorageService storage,
  }) async {
    if (state.isRandomizing) return;
    state.isRandomizing = true;
    state.notify();
    try {
      final llmService = llmProvider.serviceForModel(state.selectedModelId);
      if (llmService == null) {
        state.engineError = 'No LLM available — configure a model first';
        return;
      }
      final archetypeHint = state.selectedArchetype.isNotEmpty
          ? ' The name should suit a "${state.selectedArchetype}" character.'
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
      if (name != null) state.nameController.text = name;
    } catch (e) {
      if (e is SilentMandatoryReasoningStarveException) {
        debugPrint(
          'CharacterCreator: $e — failing name roll (no more retries)',
        );
        return;
      }
      debugPrint('CharacterCreator: randomize name failed: $e');
    } finally {
      state.isRandomizing = false;
      state.notify();
    }
  }

  /// (Automated) Generate a description into [conceptController] from all the
  /// selected toggles, streaming progress into [conceptGenProgress].
  Future<void> randomizeConcept({
    required LLMProvider llmProvider,
    required StorageService storage,
  }) async {
    if (state.isRandomizing) return;
    state.isRandomizing = true;
    state.conceptGenProgress = 0.0;
    state.notify();
    try {
      final llmService = llmProvider.serviceForModel(state.selectedModelId);
      if (llmService == null) {
        state.engineError = 'No LLM available — configure a model first';
        return;
      }

      final ctx = <String>[];
      if (state.selectedArchetype.isNotEmpty) {
        ctx.add('Archetype: ${state.selectedArchetype}');
      }
      if (state.nameController.text.trim().isNotEmpty) {
        ctx.add('Name: ${state.nameController.text.trim()}');
      }
      if (state.keywordsController.text.trim().isNotEmpty) {
        ctx.add('Personality: ${state.keywordsController.text.trim()}');
      }
      if (state.ageController.text.trim().isNotEmpty) {
        ctx.add('Age: ${state.ageController.text.trim()}');
      }
      if (state.sexController.text.trim().isNotEmpty) {
        ctx.add('Sex: ${state.sexController.text.trim()}');
      }
      final effectiveRace = state.customRaceController.text.trim().isNotEmpty
          ? state.customRaceController.text.trim()
          : state.race;
      if (effectiveRace.isNotEmpty) ctx.add('Race/species: $effectiveRace');
      if (state.bodyType.isNotEmpty) ctx.add('Body type: ${state.bodyType}');
      if (state.hairLength.isNotEmpty || state.hairStyle.isNotEmpty) {
        ctx.add(
          'Hair: ${[if (state.hairLength.isNotEmpty) state.hairLength, if (state.hairStyle.isNotEmpty) state.hairStyle].join(", ")}',
        );
      }
      if (state.skinTone.isNotEmpty) ctx.add('Skin tone: ${state.skinTone}');
      if (state.notableFeatures.isNotEmpty) {
        ctx.add('Notable features: ${state.notableFeatures.join(", ")}');
      }
      if (state.selectedRelationships.isNotEmpty) {
        ctx.add(
          'Relationship to user: ${state.selectedRelationships.join(", ")}',
        );
      }
      if (state.backstoryOrigin.isNotEmpty) {
        ctx.add('Backstory origin: ${state.backstoryOrigin}');
      }
      if (state.backstoryTone.isNotEmpty) {
        ctx.add('Backstory tone: ${state.backstoryTone}');
      }
      if (state.backstoryEra.isNotEmpty) {
        ctx.add('Era/setting: ${state.backstoryEra}');
      }
      if (state.backstoryNotesController.text.trim().isNotEmpty) {
        ctx.add(
          'Backstory notes: ${state.backstoryNotesController.text.trim()}',
        );
      }
      if (state.nsfwEnabled) {
        if (state.experience.isNotEmpty) {
          ctx.add('Experience: ${state.experience}');
        }
        if (state.dominance.isNotEmpty) {
          ctx.add('Dominance: ${state.dominance}');
        }
        if (state.selectedKinks.isNotEmpty) {
          ctx.add('Kinks: ${state.selectedKinks.join(", ")}');
        }
        if (state.outfitVibe.isNotEmpty) {
          ctx.add('Outfit vibe: ${state.outfitVibe}');
        }
      }

      final contextStr = ctx.isNotEmpty
          ? ' Use these character details as inspiration: ${ctx.join("; ")}.'
          : '';
      final descLength =
          CreatorState.generationDetailOptions[state.generationDetail] ??
          '2-3 paragraphs';
      final maxTokens =
          const {
            'Brief': 256,
            'Standard': 512,
            'Detailed': 1024,
            'Comprehensive': 2048,
          }[state.generationDetail] ??
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
        state.conceptGenProgress = (tokenCount / maxTokens).clamp(0.0, 0.95);
        state.notify();
      }

      final concept = extractChargenValue(accumulated, 'concept');
      if (concept != null) {
        state.conceptController.text = concept;
        state.conceptGenerated = true;
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
      state.isRandomizing = false;
      state.notify();
    }
  }
}
