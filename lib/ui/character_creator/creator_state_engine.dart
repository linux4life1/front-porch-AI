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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/lore_extraction_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';

/// The real generation + save engine for the AI character creator, restored
/// faithfully from the pre-refactor implementation. Lives as an extension so
/// `creator_state.dart` stays focused on state and under the file-size cap.
///
/// All `BuildContext`/`Provider`/`setState` usage from the original is replaced
/// by explicit service parameters and `notify()` — the engine holds no context.
/// SnackBars, the accept/reject dialog, and `Navigator.pop` are the caller's
/// responsibility (the steps own the context); the engine returns the data they
/// need (e.g. `saveCharacter` returns success, `expandNarrative` returns text).
///
/// The three mode entry points funnel through a single `_runGeneration` core so
/// the LLM-service resolution, persona context, world-lore extraction, and
/// post-generation wiring exist once instead of being triplicated.
extension CreatorEngine on CreatorState {
  // ── Public entry points ──────────────────────────────────────────────

  /// Dispatch generation for the currently selected mode.
  Future<void> generateFromMode({
    required LLMProvider llmProvider,
    required StorageService storage,
    required UserPersonaService personaService,
    required ImageGenService imageService,
  }) {
    switch (creatorMode) {
      case CreatorMode.quick:
        return _generateQuick(
          llmProvider,
          storage,
          personaService,
          imageService,
        );
      case CreatorMode.guided:
        return _generateGuided(
          llmProvider,
          storage,
          personaService,
          imageService,
        );
      case CreatorMode.automated:
        return _generateAutomated(
          llmProvider,
          storage,
          personaService,
          imageService,
        );
    }
  }

  /// Persist the generated (and possibly edited) card. Returns true on success;
  /// the caller shows the SnackBar and pops on true, or surfaces [engineError]
  /// on false.
  Future<bool> saveCharacter({
    required CharacterRepository repo,
    required StorageService storage,
  }) async {
    final card = generatedCard;
    if (card == null) return false;
    try {
      card.description = descController.text;
      card.personality = personalityController.text;
      card.scenario = scenarioController.text;
      card.firstMessage = firstMessageController.text;
      card.mesExample = exampleDialogueController.text;
      card.systemPrompt = systemPromptController.text;

      // Always build the V2.5 extensions — even when realism is disabled — so
      // configured realism/needs values AND the stable tracking id survive the
      // PNG round-trip. realismEnabled only controls whether the engine *uses*
      // them at runtime, matching create_character_page's behaviour.
      final fpExt = FrontPorchExtensions(
        realismEnabled: realismStepEnabled,
        shortTermBond: realismShortTermBond,
        longTermBond: realismLongTermBond,
        trustLevel: realismTrustLevel,
        dayCount: realismDayCount,
        timeOfDay: realismTimeOfDay,
        characterEmotion: realismEmotion,
        emotionIntensity: realismEmotionIntensity,
        nsfwCooldownEnabled: realismNsfwCooldown,
        chaosModeEnabled: realismChaosMode,
        needsSimEnabled: realismNeedsSim,
        enjoysLowHygiene: realismEnjoysLowHygiene,
        currentTask: realismCurrentTask,
        realismVerificationEnabled: realismVerificationEnabled,
        realismVerificationMaxReprocesses: realismVerificationMaxReprocesses,
        realismVerificationStrictness: realismVerificationStrictness,
        realismNeedsDirectorAuthority: realismNeedsDirectorAuthority,
        needsBaselineHunger: needsBaselineHunger,
        needsBaselineBladder: needsBaselineBladder,
        needsBaselineEnergy: needsBaselineEnergy,
        needsBaselineSocial: needsBaselineSocial,
        needsBaselineFun: needsBaselineFun,
        needsBaselineHygiene: needsBaselineHygiene,
        needsBaselineComfort: needsBaselineComfort,
        needsDecayHunger: needsDecayHunger,
        needsDecayBladder: needsDecayBladder,
        needsDecayEnergy: needsDecayEnergy,
        needsDecaySocial: needsDecaySocial,
        needsDecayFun: needsDecayFun,
        needsDecayHygiene: needsDecayHygiene,
        needsDecayComfort: needsDecayComfort,
      );
      // Stable tracking UUID: ensures later realism/needs edits update this
      // character in place instead of decoupling it from its DB row.
      fpExt.ensureStableId();
      card.frontPorchExtensions = fpExt;

      // Drop lorebook entries the user unchecked in the Review step.
      final lore = card.lorebook;
      if (lore != null && lorebookEntryEnabled.isNotEmpty) {
        final filtered = <LorebookEntry>[];
        for (int i = 0; i < lore.entries.length; i++) {
          if (lorebookEntryEnabled[i] ?? true) filtered.add(lore.entries[i]);
        }
        card.lorebook = Lorebook(entries: filtered);
      }

      // Write the avatar image; the repo handles V2 PNG embedding.
      if (generatedAvatar != null) {
        final charDir = storage.charactersDir;
        if (!charDir.existsSync()) charDir.createSync(recursive: true);
        final epoch = DateTime.now().millisecondsSinceEpoch;
        final safeName = card.name
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .replaceAll(' ', '_');
        final imagePath = p.join(charDir.path, '${safeName}_$epoch.png');
        await File(imagePath).writeAsBytes(generatedAvatar!);
        card.imagePath = imagePath;
      }

      await repo.addCharacter(card);
      await clearSavedFormPrefsAfterSave();
      return true;
    } catch (e, st) {
      debugPrint('CharacterCreator: save failed: $e\n$st');
      engineError = 'Failed to save character: $e';
      notify();
      return false;
    }
  }

  /// Generate the avatar image from the dedicated image prompt (or a fallback
  /// built from known details). Uses the configured Image Studio image backend
  /// (Draw Things / A1111 / remote API) — independent of the LLM backend, so it
  /// works whether the active LLM is local KoboldCpp or a remote provider.
  Future<void> generateAvatar({required ImageGenService imageService}) async {
    if (isGeneratingAvatar) return;

    String prompt = imagePromptController.text.trim();
    if (prompt.isEmpty) {
      final llmPrompt = imagePrompt;
      if (llmPrompt != null && llmPrompt.isNotEmpty) {
        // Strip the character name out of the LLM-authored prompt.
        String clean = llmPrompt;
        final charName = nameController.text.trim();
        if (charName.isNotEmpty) {
          clean = clean
              .replaceAll(
                RegExp(RegExp.escape(charName), caseSensitive: false),
                '',
              )
              .trim();
          for (final part in charName.split(RegExp(r'\s+'))) {
            if (part.length > 2) {
              clean = clean
                  .replaceAll(
                    RegExp(
                      '\\b${RegExp.escape(part)}\\b',
                      caseSensitive: false,
                    ),
                    '',
                  )
                  .trim();
            }
          }
          clean = clean
              .replaceAll(RegExp(r',\s*,'), ',')
              .replaceAll(RegExp(r'\s{2,}'), ' ')
              .trim();
          if (clean.startsWith(',')) clean = clean.substring(1).trim();
        }
        prompt = '$clean, $artStyle style';
      } else {
        // Fallback: assemble visual tags from whatever the user provided.
        final tags = <String>['character portrait', '$artStyle style'];
        final sex = sexController.text.trim();
        final age = ageController.text.trim();
        if (sex.isNotEmpty) tags.add(sex.toLowerCase());
        if (age.isNotEmpty) tags.add('$age years old');
        if (guidedAppearanceController.text.trim().isNotEmpty) {
          tags.add(guidedAppearanceController.text.trim());
        }
        if (guidedHairController.text.trim().isNotEmpty) {
          tags.add(guidedHairController.text.trim());
        }
        if (guidedFeaturesController.text.trim().isNotEmpty) {
          tags.add(guidedFeaturesController.text.trim());
        }
        if (guidedRaceController.text.trim().isNotEmpty) {
          tags.add(guidedRaceController.text.trim());
        }
        if (tags.length <= 4 && descController.text.trim().isNotEmpty) {
          final snippet = descController.text.trim();
          tags.add(snippet.length > 150 ? snippet.substring(0, 150) : snippet);
        }
        prompt = tags.join(', ');
      }
      imagePromptController.text = prompt;
    }

    isGeneratingAvatar = true;
    notify();
    try {
      // No hardcoded size: use the configured size, oriented portrait, and the
      // configured default negative (via generateImage's defaults). The old
      // fixed 512x512 both capped quality on local backends and made remote
      // models that reject small sizes (e.g. DALL·E 3) fail outright.
      final bytes = await imageService.generateImage(
        prompt: prompt,
        isPortrait: true,
      );
      if (bytes != null) generatedAvatar = bytes;
    } catch (e) {
      debugPrint('CharacterCreator: avatar gen failed: $e');
    }
    isGeneratingAvatar = false;
    notify();
  }

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
      final llmService = _resolveLlmService(llmProvider, storage);
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
          stopSequences: ['<END>'],
        ),
      )) {
        accumulated += token;
      }
      return _extractChargenValue(accumulated, 'expanded');
    } catch (e) {
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
      final llmService = _resolveLlmService(llmProvider, storage);
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
          stopSequences: ['<END>'],
        ),
      )) {
        accumulated += token;
      }
      final name = _extractChargenValue(accumulated, 'name');
      if (name != null) nameController.text = name;
    } catch (e) {
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
      final llmService = _resolveLlmService(llmProvider, storage);
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
          stopSequences: ['<END>'],
        ),
      )) {
        accumulated += token;
        tokenCount++;
        conceptGenProgress = (tokenCount / maxTokens).clamp(0.0, 0.95);
        notify();
      }

      final concept = _extractChargenValue(accumulated, 'concept');
      if (concept != null) {
        conceptController.text = concept;
        conceptGenerated = true;
      }
    } catch (e) {
      debugPrint('CharacterCreator: randomize concept failed: $e');
    } finally {
      isRandomizing = false;
      notify();
    }
  }

  // ── Mode assemblers ──────────────────────────────────────────────────

  Future<void> _generateQuick(
    LLMProvider llmProvider,
    StorageService storage,
    UserPersonaService personaService,
    ImageGenService imageService,
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
      imageService: imageService,
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
        descriptionDetail: '2-3 paragraphs',
        age: '',
        sex: '',
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
    ImageGenService imageService,
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
      imageService: imageService,
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
    ImageGenService imageService,
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

    String enriched = concept;
    if (appearance.isNotEmpty) {
      enriched += '. Physical appearance: ${appearance.join(", ")}';
    }
    if (nsfwParts.isNotEmpty) enriched += '. ${nsfwParts.join(". ")}';

    final relationship = [
      ...selectedRelationships,
      if (relationshipController.text.trim().isNotEmpty)
        relationshipController.text.trim(),
    ].join(', ');

    return _runGeneration(
      llmProvider: llmProvider,
      storage: storage,
      personaService: personaService,
      imageService: imageService,
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

  // ── Shared core + helpers ────────────────────────────────────────────

  Future<void> _runGeneration({
    required LLMProvider llmProvider,
    required StorageService storage,
    required UserPersonaService personaService,
    required ImageGenService imageService,
    required Future<CharacterCard?> Function(
      CharacterGenService gen,
      String? worldLore,
      String personaContext,
    )
    build,
  }) async {
    setStep(3);
    isGenerating = true;
    generationStatus = 'Crafting character with AI...';
    generationPreview = '';
    progress = 0.0;
    notify();

    final llmService = _resolveLlmService(llmProvider, storage);
    if (llmService == null) {
      generationStatus = llmProvider.hasManagedProcess
          ? 'Error: The backend is not running. Start it first.'
          : 'Error: No LLM service available. Configure a model first.';
      isGenerating = false;
      notify();
      return;
    }

    final persona = _personaContext(personaService);
    final worldLore = await _extractWorldLore(llmProvider, storage);
    final genService = CharacterGenService(llmService);
    activeGenService = genService;

    final card = await build(genService, worldLore, persona);

    imagePrompt = genService.generatedImagePrompt ?? imagePrompt;

    // _abortGeneration already restored state when the user cancels.
    if (genService.isAborted) return;

    if (card != null) {
      generatedCard = card;
      lorebookEntryEnabled = {};
      final lore = card.lorebook;
      if (lore != null) {
        for (int i = 0; i < lore.entries.length; i++) {
          lorebookEntryEnabled[i] = true;
        }
      }
      descController.text = card.description;
      personalityController.text = card.personality;
      scenarioController.text = card.scenario;
      firstMessageController.text = card.firstMessage;
      exampleDialogueController.text = card.mesExample;
      systemPromptController.text = card.systemPrompt;

      progress = 1.0;
      isGenerating = false;
      activeGenService = null;
      setStep(4); // → Realism Engine step
      notify();

      // Auto-start avatar generation when an image backend is configured.
      // Avatar generation uses the Image Studio image backend (Draw Things /
      // A1111 / a remote API), which is independent of the LLM backend — so
      // this no longer depends on whether the active LLM is KoboldCpp.
      if (imageService.isConfigured) {
        generateAvatar(imageService: imageService);
      }
    } else {
      generatedCard = null;
      isGenerating = false;
      activeGenService = null;
      if (!generationStatus.startsWith('Error')) {
        generationStatus = 'Generation failed. Check your backend connection.';
      }
      setStep(4); // → Realism step (shows the error/Try-Again state)
      notify();
    }
  }

  /// Resolve the LLM service for the active backend, or null if none is ready.
  LLMService? _resolveLlmService(
    LLMProvider llmProvider,
    StorageService storage,
  ) {
    if (llmProvider.hasManagedProcess) {
      final svc = llmProvider.activeService;
      return svc.isReady ? svc : null;
    }
    if (selectedModelId.isNotEmpty &&
        selectedModelId != llmProvider.openRouterService.modelName) {
      return OpenRouterService(
        apiUrl: storage.remoteApiUrl,
        apiKey: storage.remoteApiKey,
        modelName: selectedModelId,
      );
    }
    final active = llmProvider.activeService;
    return active.isReady ? active : null;
  }

  String _personaContext(UserPersonaService personaService) {
    if (selectedPersonaId.isEmpty) return '';
    final persona = personaService.personas
        .where((pp) => pp.id == selectedPersonaId)
        .firstOrNull;
    if (persona == null) return '';
    final parts = <String>[];
    if (persona.name.isNotEmpty) parts.add('Name: ${persona.name}');
    if (persona.persona.isNotEmpty) parts.add('Persona: ${persona.persona}');
    return parts.join('\n');
  }

  Future<String?> _extractWorldLore(
    LLMProvider provider,
    StorageService storage,
  ) async {
    final urls = loreUrlsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (urls.isEmpty && loreFiles.isEmpty) return null;

    generationStatus = 'Gathering world lore...';
    notify();
    String? worldLore = await LoreExtractionService.extractAll(
      urls: urls,
      files: loreFiles,
      onProgress: (msg) {
        generationStatus = msg;
        notify();
      },
    );

    if (worldLore.trim().isEmpty) return null;

    final estimatedTokens = worldLore.length ~/ 4;
    int freeContextLimit;
    if (provider.activeBackend == BackendType.kobold &&
        provider.koboldService.isReady) {
      freeContextLimit = storage.contextSize - 3000; // leave 3K for generation
    } else {
      freeContextLimit = 120000;
    }
    if (estimatedTokens > freeContextLimit) {
      final charLimit = (freeContextLimit * 4).clamp(0, worldLore.length);
      worldLore =
          '${worldLore.substring(0, charLimit)}\n[TRUNCATED DUE TO CONTEXT LIMITS]';
    }
    return worldLore;
  }

  void _onGenProgress(String accumulated) {
    generationPreview = accumulated;
    progress = (accumulated.length / 3000.0).clamp(0.0, 0.95);
    notify();
  }

  void _onGenStatus(String status) {
    generationStatus = status;
    notify();
  }

  void _onGenError(String error) {
    generationStatus = 'Error: $error';
    notify();
  }

  /// Robust extractor for chargen JSON values from LLM output. Handles markdown
  /// fences, literal newlines, unescaped quotes, and falls back to regex.
  String? _extractChargenValue(String raw, String key) {
    String cleaned = raw
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
        .trim();
    cleaned = cleaned
        .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*$', multiLine: true), '')
        .trim();

    final jsonStart = cleaned.indexOf('{');
    final jsonEnd = cleaned.lastIndexOf('}');
    if (jsonStart < 0 || jsonEnd <= jsonStart) return null;
    final jsonStr = cleaned.substring(jsonStart, jsonEnd + 1);

    // 1) Direct parse.
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final value = data[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}

    // 2) Escape literal newlines inside strings, drop trailing commas, retry.
    try {
      String fixed = jsonStr.replaceAll('\r\n', '\\n').replaceAll('\r', '\\n');
      final sb = StringBuffer();
      bool inString = false;
      bool escaped = false;
      for (int i = 0; i < fixed.length; i++) {
        final ch = fixed[i];
        if (escaped) {
          sb.write(ch);
          escaped = false;
          continue;
        }
        if (ch == '\\') {
          sb.write(ch);
          escaped = true;
          continue;
        }
        if (ch == '"') {
          inString = !inString;
          sb.write(ch);
          continue;
        }
        if (ch == '\n' && inString) {
          sb.write('\\n');
          continue;
        }
        sb.write(ch);
      }
      fixed = sb
          .toString()
          .replaceAll(RegExp(r',\s*}'), '}')
          .replaceAll(RegExp(r',\s*]'), ']');
      final data = json.decode(fixed) as Map<String, dynamic>;
      final value = data[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    } catch (_) {}

    // 3) Regex fallback — value after "key": "
    try {
      final match = RegExp(
        '"$key"\\s*:\\s*"',
        caseSensitive: false,
      ).firstMatch(jsonStr);
      if (match != null) {
        final valueStart = match.end;
        bool esc = false;
        for (int i = valueStart; i < jsonStr.length; i++) {
          final ch = jsonStr[i];
          if (esc) {
            esc = false;
            continue;
          }
          if (ch == '\\') {
            esc = true;
            continue;
          }
          if (ch == '"') {
            final value = jsonStr
                .substring(valueStart, i)
                .replaceAll('\\n', '\n')
                .replaceAll('\\t', '\t')
                .replaceAll('\\"', '"');
            return value.isNotEmpty ? value : null;
          }
        }
        final rawValue = jsonStr
            .substring(valueStart)
            .replaceAll(RegExp(r'"\s*}?\s*$'), '');
        if (rawValue.isNotEmpty) {
          return rawValue
              .replaceAll('\\n', '\n')
              .replaceAll('\\t', '\t')
              .replaceAll('\\"', '"');
        }
      }
    } catch (_) {}

    return null;
  }
}
