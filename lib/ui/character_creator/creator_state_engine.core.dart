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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import 'package:front_porch_ai/services/lore_extraction_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.profile.dart';

/// Shared generation core + callbacks: the single [run] funnel the three
/// mode assemblers (creator_state_engine.modes.dart) all go through, plus
/// LLM-service resolution, persona context, world-lore extraction, and the
/// streaming progress/status/error callbacks. Works on [state].
class CreatorGenerationCore {
  final CreatorState state;

  CreatorGenerationCore(this.state);

  // ── Shared core + helpers ────────────────────────────────────────────

  /// Runs Phase A (#530): resolves the LLM, gathers persona and world lore,
  /// builds the run's inputs with [inputs], writes the profile and its
  /// facts, and stops on the Profile step. Nothing downstream (dialogue,
  /// lorebook, greetings) is written until Next ([continueGeneration]).
  Future<void> run({
    required LLMProvider llmProvider,
    required StorageService storage,
    required UserPersonaService personaService,
    required GenRunInputs Function(String? worldLore, String personaContext)
    inputs,
  }) async {
    state.setStep(3);
    state.isGenerating = true;
    state.generationStatus = 'Crafting character with AI...';
    state.generationPreview = '';
    state.progress = 0.0;
    // A new profile: whatever the last run left is gone.
    state.profile.reset();
    state.review.reset();
    state.notify();

    final llmService = llmProvider.serviceForModel(state.selectedModelId);
    if (llmService == null) {
      state.generationStatus = llmProvider.hasManagedProcess
          ? 'Error: The backend is not running. Start it first.'
          : 'Error: No LLM service available. Configure a model first.';
      state.isGenerating = false;
      state.notify();
      return;
    }

    final persona = _personaContext(personaService);
    final worldLore = await _extractWorldLore(llmProvider, storage);
    final genService = state.newGenService(llmService);
    state.activeGenService = genService;

    final paused = await genService.generateProfile(
      inputs: inputs(worldLore, persona),
      onProgress: onProgress,
      onStatus: onStatus,
      onError: onError,
    );

    // _abortGeneration already restored state when the user cancels.
    if (genService.isAborted) return;
    state.isGenerating = false;
    state.activeGenService = null;
    if (paused == null) {
      _failed();
      return;
    }
    final card = paused.card;
    state.generatedCard = card;
    state.profile
      ..paused = paused
      ..facts = paused.facts
      ..completed = false;
    state.adoptProfileBoxes(card.description, card.personality, card.scenario);
    _clearDownstream();
    applyGeneratedRealism(card);
    state.progress = 1.0;
    state.setStep(4); // → Profile step
    state.notify();
  }

  /// Phase B (Next on the Profile step): the boxes' text and the facts card
  /// as they are now go into the paused card, then the rest is written on
  /// a fresh service and the wizard lands on Greetings. A Stop or a failure
  /// returns to the Profile step with the pause kept.
  Future<void> continueGeneration(LLMProvider llmProvider) async {
    final p = state.profile;
    final paused = p.paused;
    if (paused == null || state.isGenerating || p.busy) return;
    final llmService = llmProvider.serviceForModel(state.selectedModelId);
    if (llmService == null) {
      p.error = llmProvider.hasManagedProcess
          ? 'The backend is not running. Start it, then press Next again.'
          : 'No model is ready. Pick or connect one in Setup, then press '
                'Next again.';
      state.notify();
      return;
    }
    final run = paused.copyWith(card: profileCardNow(state));
    p
      ..paused = run
      ..continuing = true
      ..error = null;
    state.isGenerating = true;
    state.generationStatus = 'Writing the greetings and the rest...';
    state.generationPreview = '';
    state.progress = 0.0;
    state.setStep(3);
    state.notify();

    final gen = state.newGenService(llmService);
    state.activeGenService = gen;
    final card = await gen.completeCharacter(
      paused: run,
      onProgress: onProgress,
      onStatus: onStatus,
      onError: onError,
    );
    if (gen.isAborted) return; // abortGeneration put the wizard back
    p.continuing = false;
    state.isGenerating = false;
    state.activeGenService = null;
    if (card == null) {
      if (!state.generationStatus.startsWith('Error')) {
        state.generationStatus =
            'The rest of the character could not be written. Check your '
            'backend connection, then press Next again.';
      }
      p.error = state.generationStatus;
      state.setStep(4);
      state.notify();
      return;
    }
    state.imagePrompt = gen.generatedImagePrompt ?? state.imagePrompt;
    _loadCompletedCard(card, gen.greetingRecipe ?? const GreetingRecipe());
    applyGeneratedRealism(card);
    p.completed = true;
    state.progress = 1.0;
    state.setStep(5); // → Greetings step
    state.notify();
  }

  void _failed() {
    state.generatedCard = null;
    if (!state.generationStatus.startsWith('Error')) {
      state.generationStatus =
          'Generation failed. Check your backend connection.';
    }
    state.setStep(4); // → Profile step (shows the error/Try-Again state)
    state.notify();
  }

  /// Phase A wrote no greetings, dialogue or lorebook; boxes a previous run
  /// left must not show as if they belonged to this profile.
  void _clearDownstream() {
    state.greetings.reset();
    final oldFirst = state.firstMessageController;
    state.firstMessageController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => oldFirst.dispose());
    for (final c in state.altGreetingControllers) {
      c.dispose();
    }
    state.altGreetingControllers = [];
    state.greetingSeeds = [];
    state.exampleDialogueController.clear();
    state.systemPromptController.text = state.generatedCard?.systemPrompt ?? '';
    state.lorebookEntryEnabled = {};
  }

  /// Phase B's card into the wizard's boxes.
  void _loadCompletedCard(CharacterCard card, GreetingRecipe recipe) {
    state.generatedCard = card;
    // A new card: its greetings were written this way, and its outfit
    // already follows its first message.
    state.greetings.reset(next: recipe, outfitFrom: card.firstMessage);
    state.lorebookEntryEnabled = {
      for (var i = 0; i < (card.lorebook?.entries.length ?? 0); i++) i: true,
    };
    state.descController.text = card.description;
    state.personalityController.text = card.personality;
    state.scenarioController.text = card.scenario;
    final oldFirst = state.firstMessageController;
    state.firstMessageController = state.newGreetingBox(card.firstMessage);
    // A step still fading out may hold the old box this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => oldFirst.dispose());
    state.exampleDialogueController.text = card.mesExample;
    state.systemPromptController.text = card.systemPrompt;
    for (final c in state.altGreetingControllers) {
      c.dispose();
    }
    state.altGreetingControllers = [
      for (final g in card.alternateGreetings) state.newGreetingBox(g),
    ];
    state.greetingSeeds = alignGreetingSeeds(
      card.frontPorchExtensions?.greetingSeeds ?? const [],
      state.altGreetingControllers.length,
    );
  }

  /// Copy what the model wrote onto the wizard's Porch Life and Realism
  /// values so the facts card, the Realism step and Save see it: the
  /// identity facts after Phase A, the mood, time and outfit after Phase B.
  void applyGeneratedRealism(CharacterCard card) {
    final ext = card.frontPorchExtensions;
    if (ext == null) return;
    applyIdentityRealism(card);
    state.realismEmotion = ext.characterEmotion;
    state.realismEmotionIntensity = ext.emotionIntensity;
    state.realismTimeOfDay = ext.timeOfDay;
    state.realismStoryStartTime = ext.storyStartTime;
    final pockets = Pockets.fromJson(ext.inventory);
    state.realismWorn = pockets.wornDisplay;
    state.realismCarrying = pockets.carryingDisplay;
  }

  /// The identity facts alone (the facts card): a profile rewrite or a
  /// re-read must not reset the mood, time or outfit Phase B wrote.
  void applyIdentityRealism(CharacterCard card) {
    final ext = card.frontPorchExtensions;
    if (ext == null) return;
    state.realismShortTermBond = ext.shortTermBond;
    state.realismTrustLevel = ext.trustLevel;
    state.realismCurrentTask = ext.currentTask;
    state.realismAmbitions = List<String>.from(ext.ambitions);
    state.realismPlanLines = List<String>.from(ext.planLines);
    state.realismOccupation = ext.occupation;
    state.realismOccupationBrief = ext.occupationBrief;
    state.realismBirthday = ext.birthday;
    state.realismHours = ext.hours;
    state.realismWorkDays = ext.workDays;
    state.realismLikes = List<String>.from(ext.likes);
    state.realismDislikes = List<String>.from(ext.dislikes);
    state.realismIntimateInto = List<String>.from(ext.intimateInto);
    state.realismIntimateNotInto = List<String>.from(ext.intimateNotInto);
  }

  String _personaContext(UserPersonaService personaService) {
    if (state.selectedPersonaId.isEmpty) return '';
    final persona = personaService.personas
        .where((pp) => pp.id == state.selectedPersonaId)
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
    final urls = state.loreUrlsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (urls.isEmpty && state.loreFiles.isEmpty) return null;

    state.generationStatus = 'Gathering world lore...';
    state.notify();
    String? worldLore = await LoreExtractionService.extractAll(
      urls: urls,
      files: state.loreFiles,
      onProgress: (msg) {
        state.generationStatus = msg;
        state.notify();
      },
    );

    if (worldLore.trim().isEmpty) return null;

    final estimatedTokens = worldLore.length ~/ 4;
    int freeContextLimit;
    if (provider.activeBackend == BackendType.kobold &&
        provider.koboldService.isReady) {
      freeContextLimit =
          storage.backendSettings.promptContext(
            storage.backendSettings.contextSize,
          ) -
          3000; // leave 3K for generation
      if (freeContextLimit <= 0) {
        // A context window at or under that 3K reservation (the app's own
        // low-VRAM recommendation is 2048) made the limit negative, and the
        // clamp below then truncated EVERY character of lore away — the model
        // got the bare "[TRUNCATED…]" marker and nothing else, silently. Give
        // the lore half a small window instead of none of it.
        freeContextLimit =
            storage.backendSettings.promptContext(
              storage.backendSettings.contextSize,
            ) ~/
            2;
      }
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

  void onProgress(String accumulated) {
    state.generationPreview = accumulated;
    state.progress = (accumulated.length / 3000.0).clamp(0.0, 0.95);
    state.notify();
  }

  void onStatus(String status) {
    state.generationStatus = status;
    state.notify();
  }

  void onError(String error) {
    state.generationStatus = 'Error: $error';
    state.notify();
  }
}
