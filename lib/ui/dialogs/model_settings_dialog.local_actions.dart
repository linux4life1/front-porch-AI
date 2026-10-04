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

part of 'model_settings_dialog.dart';

/// The backend restart/start action for the local (KoboldCpp) backend. Split out of `model_settings_dialog.dart` — verbatim
/// except `setState` -> `rebuildState` (extensions can't call a State's
/// protected members).
extension _ModelSettingsLocalActions on _ModelSettingsDialogState {
  Future<void> _restartBackend() async {
    final koboldService = Provider.of<KoboldService>(context, listen: false);
    final backendManager = Provider.of<BackendManager>(context, listen: false);

    if (backendManager.backendPath == null) {
      // Not an error state anymore: kick the background acquisition (no-op
      // when already downloading) and point at the corner chip's progress.
      backendManager.ensureEngineInstalled();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            backendManager.isDownloading
                ? 'The AI engine is still downloading — progress is in the corner chip.'
                : 'The AI engine isn\'t installed yet — downloading it now in the background (see the corner chip).',
          ),
        ),
      );
      return;
    }

    final storage = Provider.of<StorageService>(context, listen: false);

    // Case A — preset owns a valid model file: skip model-path checks.
    // Case B — no preset / preset has no model / model file missing: user must pick one.
    final presetOwnsModel =
        storage.backendSettings.kcppsHasModel &&
        _kcppsModelExists.of(storage.backendSettings.kcppsModelPath);

    if (!presetOwnsModel) {
      if (_selectedModelPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Valid model not selected.')),
        );
        return;
      }
      // Same pre-flight KoboldService runs before spawning the process,
      // surfaced here so the specific reason reaches a snackbar immediately
      // instead of only the backend log. A bare existsSync() guarded this
      // spot before, and that is exactly the check a OneDrive placeholder
      // passes on its way to an unexplained exit 2 (issue #137).
      final problem = await ModelFileCheck.validate(_selectedModelPath!);
      if (problem != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(problem)));
        return;
      }
    }

    // Validate preset file exists if one is active
    if (storage.backendSettings.activeKcppsPath != null &&
        storage.backendSettings.activeKcppsPath!.isNotEmpty) {
      if (!_presetFileExists.of(storage.backendSettings.activeKcppsPath)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selected preset not found. It may have been deleted or moved.\n'
              'Clearing the preset and falling back to app settings.',
            ),
            backgroundColor: Colors.redAccent, // theme-keep: error snackbar
          ),
        );
        storage.backendSettings.setActiveKcppsPath(null);
        if (_selectedModelPath != null) {
          storage.presetSettings.setModelPreset(_selectedModelPath!, '');
        }
        return;
      }
    }

    // A preset that cannot be read stops the launch. Said here, because
    // the launch itself only writes it to the engine log.
    final presetProblem = await koboldPresetProblem(
      storage.backendSettings.activeKcppsPath,
    );
    if (presetProblem != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(presetProblem)));
      return;
    }

    // When the preset owns the model, pass empty string — KoboldCPP reads
    // it from the .kcpps config. Otherwise pass the Flutter-selected path.
    final effectiveModel = presetOwnsModel ? '' : _selectedModelPath!;

    storage.backendSettings.setLastUsedModelPath(_selectedModelPath);
    storage.backendSettings.setGpuLayers(
      int.tryParse(_gpuLayersController.text) ?? 0,
    );
    storage.backendSettings.setContextSize(
      int.tryParse(_contextSizeController.text) ?? 16384,
    );

    // Await the full stop so the process tree is terminated and the port is
    // released before we start a new instance. Without this, Windows can
    // leave the old koboldcpp.exe alive → zombie processes accumulate.
    if (koboldService.isRunning) {
      await koboldService.stopKobold();
    }

    // Give the OS a moment to fully release the port after process termination.
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    koboldService.startKobold(
      backendManager.backendPath!,
      effectiveModel,
      kcppsPath: storage.backendSettings.activeKcppsPath,
      // Vision projector is keyed by the concrete GGUF the user picked; when a
      // preset owns the model there is no Flutter-side path to key on.
      mmprojPath: _selectedModelPath != null
          ? storage.presetSettings.modelMmprojMap[_selectedModelPath!]
          : null,
      gpuLayers: int.tryParse(_gpuLayersController.text) ?? 0,
      contextSize: int.tryParse(_contextSizeController.text) ?? 16384,
      // This dialog has no graphics-backend control, so it passes on what
      // is stored and records nothing. A choice never made stays "let the
      // app pick from the hardware"; writing it here as four offs used to
      // turn that into a deliberate CPU-only.
      useVulkan: storage.backendSettings.useVulkan == true,
      useCublas: storage.backendSettings.useCublas == true,
      useMetal: storage.backendSettings.useMetal == true,
      useRocm: storage.backendSettings.useRocm == true,
    );
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restarting backend with new settings...')),
    );
  }
}
