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
    localPresets = scanKcppsPresets(storage.binDir);
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
    koboldStatus = 'Stopping KoboldCpp...';
    notify();

    try {
      // Stop if running
      if (kobold.isRunning) {
        await kobold.stopKobold();
        await Future.delayed(const Duration(seconds: 1));
      }

      // Use BackendManager to find the executable (same pattern as model_settings_dialog & settings_page)
      if (backendManager.backendPath == null) {
        isReloadingKobold = false;
        koboldStatus = 'Error: Backend executable not found';
        notify();
        return;
      }
      final execPath = backendManager.backendPath!;

      koboldStatus = 'Starting KoboldCpp with new model...';
      notify();

      // If the .kcpps preset owns the model, let it handle model loading
      final hasValidKcppsModel =
          storage.backendSettings.kcppsHasModel &&
          storage.backendSettings.kcppsModelFileExists;
      final effectiveModel = hasValidKcppsModel ? '' : modelPath;

      await kobold.startKobold(
        execPath,
        effectiveModel,
        kcppsPath: storage.backendSettings.activeKcppsPath,
        mmprojPath: modelPath.isNotEmpty
            ? storage.presetSettings.modelMmprojMap[modelPath]
            : null,
        port: 5001,
        gpuLayers: storage.backendSettings.gpuLayers,
        contextSize: storage.backendSettings.contextSize,
        useVulkan: storage.backendSettings.useVulkan ?? false,
        useCublas: storage.backendSettings.useCublas ?? false,
        useMetal: storage.backendSettings.useMetal ?? false,
        useRocm: storage.backendSettings.useRocm ?? false,
      );

      // Save as last used model
      await storage.backendSettings.setLastUsedModelPath(modelPath);

      // Poll for model readiness
      koboldStatus = 'Loading model...';
      notify();
      for (int i = 0; i < 120; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (kobold.modelReady) {
          isReloadingKobold = false;
          koboldStatus = 'Model loaded successfully!';
          selectedLocalModelPath = modelPath;
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

// Helper for kcpps scan (lifted if not in utils; assume or duplicate minimal)
List<File> scanKcppsPresets(Directory binDir) {
  if (!binDir.existsSync()) return []; // io-ok: preset scan
  try {
    return binDir
        .listSync() // io-ok: preset scan
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.kcpps'))
        .toList();
  } catch (_) {
    return [];
  }
}
