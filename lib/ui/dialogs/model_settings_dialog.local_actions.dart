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

/// Auto-configuration and backend restart/start actions for the local
/// (KoboldCpp) backend. Split out of `model_settings_dialog.dart` — verbatim
/// except `setState` -> `rebuildState` (extensions can't call a State's
/// protected members).
extension _ModelSettingsLocalActions on _ModelSettingsDialogState {
  void _applyAutoConfiguration() {
    final hardware = Provider.of<HardwareService>(
      context,
      listen: false,
    ).hardwareInfo;
    if (hardware == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hardware not detected yet.')),
      );
      return;
    }

    int modelSize = 5000;
    if (_selectedModelPath != null) {
      try {
        final file = File(_selectedModelPath!);
        if (file.existsSync()) {
          modelSize = (file.lengthSync() / (1024 * 1024)).round();
        }
      } catch (e) {
        // ignore
      }
    }

    final storage = Provider.of<StorageService>(context, listen: false);

    // Respect whatever the user currently has in the context field (critical for
    // the new accurate KoboldLayerSolver). Also try to get real kvBytesPerToken
    // for the selected model so the solver can be precise.
    final userContext = int.tryParse(_contextSizeController.text);
    int? kvBytesPerToken;
    if (_selectedModelPath != null) {
      final modelManager = Provider.of<ModelManager>(context, listen: false);
      kvBytesPerToken =
          modelManager
              .getCachedModelArchitectureInfo(_selectedModelPath!)
              ?.kvBytesPerToken ??
          modelManager.getCachedKvBytesPerToken(_selectedModelPath!);
    }

    final suggestion = OptimizationService.calculateSettings(
      hardware,
      modelSizeMb: modelSize,
      requestedContextSize: userContext,
      kvBytesPerToken: kvBytesPerToken,
      kvQuantizationLevel: storage.backendSettings.kvQuantizationLevel,
    );

    rebuildState(() {
      _gpuLayersController.text = suggestion.gpuLayers.toString();
      _contextSizeController.text = suggestion.contextSize.toString();

      if (Platform.isMacOS) {
        _useMetal = true;
        _useVulkan = false;
        _useCublas = false;
        _useRocm = false;
      } else if (hardware.vendor == 'Nvidia') {
        _useCublas = true;
        _useVulkan = false;
        _useMetal = false;
        _useRocm = false;
      } else if (hardware.vendor == 'AMD' &&
          Platform.isLinux &&
          hardware.hasRocm) {
        _useRocm = true;
        _useVulkan = false;
        _useCublas = false;
        _useMetal = false;
      } else {
        _useVulkan = suggestion.useVulkan;
        _useCublas = false;
        _useMetal = false;
        _useRocm = false;
      }
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(suggestion.reasoning)));
  }

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
    storage.backendSettings.setUseCublas(_useCublas);
    storage.backendSettings.setUseVulkan(_useVulkan);
    storage.backendSettings.setUseMetal(_useMetal);
    storage.backendSettings.setUseRocm(_useRocm);

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
      useVulkan: _useVulkan,
      useCublas: _useCublas,
      useMetal: _useMetal,
      useRocm: _useRocm,
    );
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restarting backend with new settings...')),
    );
  }
}
