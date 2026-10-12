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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';

/// Abort, catalog, and local-model reload for the creator setup step. Reads
/// and writes [state]'s model fields and notifies through it.
class CreatorBackendModels {
  final CreatorState state;

  CreatorBackendModels(this.state);

  void abortGeneration() {
    state.activeGenService?.abort();
    state.isGenerating = false;
    state.generationStatus = 'Generation aborted.';
    state.generationPreview = '';
    state.progress = 0.0;
    state.setStep(2); // Return to config step
    state.activeGenService = null;
    state.notify();
  }

  // Model loading / scanning (signatures adapted to accept services; callers pass from UI context)
  Future<void> loadAvailableModels(LLMProvider llmProvider) async {
    if (llmProvider.hasManagedProcess) {
      state.availableModels = [];
      state.isLoadingModels = false;
      state.selectedModelId = '';
      state.notify();
      return;
    }
    final openRouter = llmProvider.openRouterService;
    try {
      final models = await openRouter.fetchAvailableModels();
      state.availableModels = models;
      state.isLoadingModels = false;
      if (state.selectedModelId.isEmpty) {
        state.selectedModelId = openRouter.modelName;
      }
      state.notify();
    } catch (e) {
      debugPrint('CreatorState: Failed to load models: $e');
      state.isLoadingModels = false;
      state.selectedModelId = llmProvider.openRouterService.modelName;
      state.notify();
    }
  }

  void scanLocalModels(StorageService storage) {
    final modelsDir = storage.modelsDir;
    final noDir = !modelsDir.existsSync(); // io-ok: catalog scan
    if (noDir) {
      state.localModels = [];
      state.notify();
      return;
    }
    try {
      final files =
          modelsDir
              .listSync(recursive: true) // io-ok: catalog scan
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.gguf'))
              .toList()
            ..sort(
              (a, b) => p
                  .basename(a.path)
                  .toLowerCase()
                  .compareTo(p.basename(b.path).toLowerCase()),
            );
      state.localModels = files;
      if (state.selectedLocalModelPath.isEmpty) {
        state.selectedLocalModelPath =
            storage.backendSettings.lastUsedModelPath ?? '';
      }
      state.notify();
    } catch (e) {
      debugPrint('CreatorState: Failed to scan models: $e');
      state.localModels = [];
      state.notify();
    }
  }

  void scanLocalPresets(StorageService storage) {
    state.localPresets = kcppsPresetFiles(storage.binDir.path);
    state.notify();
  }

  void initLocalSettingsControllers(StorageService storage) {
    state.gpuLayersController.text = storage.backendSettings.gpuLayers
        .toString();
    state.contextSizeController.text = storage.backendSettings.contextSize
        .toString();
  }

  // Note: reloadKoboldWithModel lifted with service params (callers in steps
  // pass providers/storage from their context). It already launches a .kcpps
  // preset when one is active, so preset launching needs no separate path.
  Future<void> reloadKoboldWithModel(
    String modelPath,
    LLMProvider llmProvider,
    StorageService storage,
    BackendManager backendManager,
  ) async {
    if (state.isReloadingKobold) return;
    final kobold = llmProvider.koboldService;

    state.isReloadingKobold = true;
    state.notify();

    try {
      // Checked before anything is stopped, as the desktop's buttons do: a
      // missing engine, or a model or preset that cannot be used, leaves the
      // running one alone. The engine is looked for again: the build on
      // disk must be the one the acceleration choice needs.
      final execPath = await backendManager.engineForStart();
      final problem = execPath == null
          ? 'Error: Backend executable not found'
          : await koboldLaunchProblem(storage, pickedModel: modelPath);
      if (execPath == null || problem != null) {
        state.isReloadingKobold = false;
        state.koboldStatus = problem!;
        state.notify();
        return;
      }

      state.koboldStatus = 'Stopping KoboldCpp...';
      state.notify();
      if (kobold.isRunning) {
        await kobold.stopKobold();
        await Future.delayed(const Duration(seconds: 1));
      }

      state.koboldStatus = 'Starting KoboldCpp with new model...';
      state.notify();

      // Same rule as every other start: the active preset's own model when
      // it has one on this disk, otherwise the model picked here. The
      // launch records whichever loads as the last-used model, and refuses
      // (saying why) a model or preset that cannot be read.
      final result = await kobold.launch(execPath, pickedModel: modelPath);
      if (!result.started) {
        state.isReloadingKobold = false;
        state.koboldStatus =
            result.message ?? 'KoboldCpp could not be started.';
        state.notify();
        return;
      }
      // The model that loaded, which the launch records: the active
      // preset's own model when it has one here, not always the one picked.
      final loaded = storage.backendSettings.lastUsedModelPath ?? modelPath;
      state.selectedLocalModelPath = loaded;

      // Poll for model readiness
      state.koboldStatus = 'Loading model...';
      state.notify();
      for (int i = 0; i < 120; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (kobold.modelReady) {
          state.isReloadingKobold = false;
          state.koboldStatus = 'Model loaded successfully!';
          state.selectedLocalModelPath = loaded;
          state.notify();
          return;
        }
        if (kobold.modelLoadingStatus.isNotEmpty) {
          state.koboldStatus = kobold.modelLoadingStatus;
          state.notify();
        }
      }

      state.isReloadingKobold = false;
      state.koboldStatus = 'Timeout waiting for model to load';
      state.notify();
    } catch (e) {
      state.isReloadingKobold = false;
      state.koboldStatus = 'Error: $e';
      state.notify();
    }
  }
}
