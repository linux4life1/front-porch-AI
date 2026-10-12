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

/// Shared generation core + callbacks: the single [run] funnel the three
/// mode assemblers (creator_state_engine.modes.dart) all go through, plus
/// LLM-service resolution, persona context, world-lore extraction, and the
/// streaming progress/status/error callbacks. Works on [state].
class CreatorGenerationCore {
  final CreatorState state;

  CreatorGenerationCore(this.state);

  // ── Shared core + helpers ────────────────────────────────────────────

  /// Runs one generation: resolves the LLM, gathers persona and world lore,
  /// calls [build], then loads the card into the wizard.
  Future<void> run({
    required LLMProvider llmProvider,
    required StorageService storage,
    required UserPersonaService personaService,
    required Future<CharacterCard?> Function(
      CharacterGenService gen,
      String? worldLore,
      String personaContext,
    )
    build,
  }) async {
    state.setStep(3);
    state.isGenerating = true;
    state.generationStatus = 'Crafting character with AI...';
    state.generationPreview = '';
    state.progress = 0.0;
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
    final genService = CharacterGenService(llmService);
    state.activeGenService = genService;

    final card = await build(genService, worldLore, persona);

    state.imagePrompt = genService.generatedImagePrompt ?? state.imagePrompt;

    // _abortGeneration already restored state when the user cancels.
    if (genService.isAborted) return;

    if (card != null) {
      state.generatedCard = card;
      // A new card: its greetings were written this way, and its outfit
      // already follows its first message.
      state.greetings.reset(
        next: genService.greetingRecipe ?? const GreetingRecipe(),
        outfitFrom: card.firstMessage,
      );
      _applyGeneratedPorchLife(card);
      state.lorebookEntryEnabled = {};
      final lore = card.lorebook;
      if (lore != null) {
        for (int i = 0; i < lore.entries.length; i++) {
          state.lorebookEntryEnabled[i] = true;
        }
      }
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

      state.progress = 1.0;
      state.isGenerating = false;
      state.activeGenService = null;
      state.setStep(4); // → Greetings step
      state.notify();
    } else {
      state.generatedCard = null;
      state.isGenerating = false;
      state.activeGenService = null;
      if (!state.generationStatus.startsWith('Error')) {
        state.generationStatus =
            'Generation failed. Check your backend connection.';
      }
      state.setStep(4); // → Greetings step (shows the error/Try-Again state)
      state.notify();
    }
  }

  /// Copy the extract pass onto the wizard's Porch Life chips so Review
  /// and Save see what the model wrote. Empty lists stay empty.
  void _applyGeneratedPorchLife(CharacterCard card) {
    final ext = card.frontPorchExtensions;
    if (ext == null) return;
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
    final pockets = Pockets.fromJson(ext.inventory);
    state.realismWorn = pockets.wornDisplay;
    state.realismCarrying = pockets.carryingDisplay;
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
