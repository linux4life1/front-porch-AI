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

part of 'creator_state.dart';

/// Abort, catalog, and local-model reload for the creator setup step.
extension CreatorStateModels on CreatorState {
  void abortGeneration() {
    activeGenService?.abort();
    isGenerating = false;
    generationStatus = 'Generation aborted.';
    generationPreview = '';
    progress = 0.0;
    _currentStep = 2; // Return to config step
    activeGenService = null;
    notify();
  }

  // Model loading / scanning (signatures adapted to accept services; callers pass from UI context)
  Future<void> loadAvailableModels(LLMProvider llmProvider) async {
    if (llmProvider.hasManagedProcess) {
      availableModels = [];
      isLoadingModels = false;
      selectedModelId = '';
      notify();
      return;
    }
    final openRouter = llmProvider.openRouterService;
    try {
      final models = await openRouter.fetchAvailableModels();
      availableModels = models;
      isLoadingModels = false;
      if (selectedModelId.isEmpty) {
        selectedModelId = openRouter.modelName;
      }
      notify();
    } catch (e) {
      debugPrint('CreatorState: Failed to load models: $e');
      isLoadingModels = false;
      selectedModelId = llmProvider.openRouterService.modelName;
      notify();
    }
  }

  void scanLocalModels(StorageService storage) {
    final modelsDir = storage.modelsDir;
    final noDir = !modelsDir.existsSync(); // io-ok: catalog scan
    if (noDir) {
      localModels = [];
      notify();
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
      localModels = files;
      if (selectedLocalModelPath.isEmpty) {
        selectedLocalModelPath =
            storage.backendSettings.lastUsedModelPath ?? '';
      }
      notify();
    } catch (e) {
      debugPrint('CreatorState: Failed to scan models: $e');
      localModels = [];
      notify();
    }
  }

  void scanLocalPresets(StorageService storage) {
    localPresets = kcppsPresetFiles(storage.binDir.path);
    notify();
  }

  void initLocalSettingsControllers(StorageService storage) {
    gpuLayersController.text = storage.backendSettings.gpuLayers.toString();
    contextSizeController.text = storage.backendSettings.contextSize.toString();
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
    if (isReloadingKobold) return;
    final kobold = llmProvider.koboldService;

    isReloadingKobold = true;
    notify();

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
        isReloadingKobold = false;
        koboldStatus = problem!;
        notify();
        return;
      }

      koboldStatus = 'Stopping KoboldCpp...';
      notify();
      if (kobold.isRunning) {
        await kobold.stopKobold();
        await Future.delayed(const Duration(seconds: 1));
      }

      koboldStatus = 'Starting KoboldCpp with new model...';
      notify();

      // Same rule as every other start: the active preset's own model when
      // it has one on this disk, otherwise the model picked here. The
      // launch records whichever loads as the last-used model, and refuses
      // (saying why) a model or preset that cannot be read.
      final result = await kobold.launch(execPath, pickedModel: modelPath);
      if (!result.started) {
        isReloadingKobold = false;
        koboldStatus = result.message ?? 'KoboldCpp could not be started.';
        notify();
        return;
      }
      // The model that loaded, which the launch records: the active
      // preset's own model when it has one here, not always the one picked.
      final loaded = storage.backendSettings.lastUsedModelPath ?? modelPath;
      selectedLocalModelPath = loaded;

      // Poll for model readiness
      koboldStatus = 'Loading model...';
      notify();
      for (int i = 0; i < 120; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (kobold.modelReady) {
          isReloadingKobold = false;
          koboldStatus = 'Model loaded successfully!';
          selectedLocalModelPath = loaded;
          notify();
          return;
        }
        if (kobold.modelLoadingStatus.isNotEmpty) {
          koboldStatus = kobold.modelLoadingStatus;
          notify();
        }
      }

      isReloadingKobold = false;
      koboldStatus = 'Timeout waiting for model to load';
      notify();
    } catch (e) {
      isReloadingKobold = false;
      koboldStatus = 'Error: $e';
      notify();
    }
  }
}
