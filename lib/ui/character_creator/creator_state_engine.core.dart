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

/// Shared generation core + callbacks: the single `_runGeneration` funnel the
/// three mode assemblers (creator_state_engine.modes.dart) all go through, plus
/// LLM-service resolution, persona context, world-lore extraction, and the
/// streaming progress/status/error callbacks.
extension _CreatorCore on CreatorState {
  // ── Shared core + helpers ────────────────────────────────────────────

  Future<void> _runGeneration({
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
    setStep(3);
    isGenerating = true;
    generationStatus = 'Crafting character with AI...';
    generationPreview = '';
    progress = 0.0;
    notify();

    final llmService = llmProvider.serviceForModel(selectedModelId);
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
      _applyGeneratedPorchLife(card);
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
      for (final c in altGreetingControllers) {
        c.dispose();
      }
      altGreetingControllers = [
        for (final g in card.alternateGreetings) TextEditingController(text: g),
      ];
      greetingSeeds = alignGreetingSeeds(
        card.frontPorchExtensions?.greetingSeeds ?? const [],
        altGreetingControllers.length,
      );

      progress = 1.0;
      isGenerating = false;
      activeGenService = null;
      setStep(4); // → Realism Engine step
      notify();
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

  /// Copy the extract pass onto the wizard's Porch Life chips so Review
  /// and Save see what the model wrote. Empty lists stay empty.
  void _applyGeneratedPorchLife(CharacterCard card) {
    final ext = card.frontPorchExtensions;
    if (ext == null) return;
    realismAmbitions = List<String>.from(ext.ambitions);
    realismPlanLines = List<String>.from(ext.planLines);
    realismOccupation = ext.occupation;
    realismOccupationBrief = ext.occupationBrief;
    realismBirthday = ext.birthday;
    realismHours = ext.hours;
    realismWorkDays = ext.workDays;
    realismLikes = List<String>.from(ext.likes);
    realismDislikes = List<String>.from(ext.dislikes);
    realismIntimateInto = List<String>.from(ext.intimateInto);
    realismIntimateNotInto = List<String>.from(ext.intimateNotInto);
    final pockets = Pockets.fromJson(ext.inventory);
    realismWorn = pockets.wornDisplay;
    realismCarrying = pockets.carryingDisplay;
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
      if (freeContextLimit <= 0) {
        // A context window at or under that 3K reservation (the app's own
        // low-VRAM recommendation is 2048) made the limit negative, and the
        // clamp below then truncated EVERY character of lore away — the model
        // got the bare "[TRUNCATED…]" marker and nothing else, silently. Give
        // the lore half a small window instead of none of it.
        freeContextLimit = storage.contextSize ~/ 2;
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
}
