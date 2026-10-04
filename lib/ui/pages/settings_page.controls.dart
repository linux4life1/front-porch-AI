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

part of 'settings_page.dart';

/// Backend-launch + hardware orchestration for [_SettingsPageState], split out
/// of the shell to keep every file under the 500-LOC cap (mirrors the
/// chat_service.dart `part of` pattern). These methods keep direct access to
/// the page's private launch state, so behavior is identical to when they
/// lived inline. AppColors exclusive.
extension _SettingsLaunchControls on _SettingsPageState {
  /// Apply GPU defaults based on detected hardware info.
  void _applyHardwareDefaults(HardwareInfo hw) {
    final storage = Provider.of<StorageService>(context, listen: false);
    bool changed = false;

    // NVIDIA Logic: Default to CuBLAS if not set
    if (hw.vendor == 'Nvidia') {
      if (storage.backendSettings.useCublas == null) {
        storage.backendSettings.setUseCublas(true);
        storage.backendSettings.setUseVulkan(false);
        _useCublas = true;
        _useVulkan = false;
        changed = true;
      } else {
        _useCublas = storage.backendSettings.useCublas!;
        if (storage.backendSettings.useVulkan != null) {
          _useVulkan = storage.backendSettings.useVulkan!;
        } else if (_useCublas) {
          _useVulkan = false;
        }
      }
    }
    // MacOS Logic: Default to Metal if not set
    else if (Platform.isMacOS) {
      if (storage.backendSettings.useMetal == null) {
        storage.backendSettings.setUseMetal(true);
        storage.backendSettings.setUseVulkan(false);
        storage.backendSettings.setUseCublas(false);
        _useMetal = true;
        _useVulkan = false;
        _useCublas = false;
        changed = true;
      } else {
        _useMetal = storage.backendSettings.useMetal!;
        if (storage.backendSettings.useVulkan != null) {
          _useVulkan = storage.backendSettings.useVulkan!;
        }
        if (storage.backendSettings.useCublas != null) {
          _useCublas = storage.backendSettings.useCublas!;
        }
        if (storage.backendSettings.useRocm != null) {
          _useRocm = storage.backendSettings.useRocm!;
        }
      }
    }
    // Non-NVIDIA/Non-Mac Logic: Default to ROCm if available, else Vulkan
    else {
      if (storage.backendSettings.useVulkan == null &&
          storage.backendSettings.useRocm == null) {
        // First run: auto-detect best GPU backend
        if (hw.vendor == 'AMD' && Platform.isLinux && hw.hasRocm) {
          storage.backendSettings.setUseRocm(true);
          storage.backendSettings.setUseVulkan(false);
          storage.backendSettings.setUseCublas(false);
          storage.backendSettings.setUseMetal(false);
          _useRocm = true;
          _useVulkan = false;
          _useCublas = false;
          _useMetal = false;
        } else {
          storage.backendSettings.setUseVulkan(true);
          storage.backendSettings.setUseCublas(false);
          storage.backendSettings.setUseMetal(false);
          storage.backendSettings.setUseRocm(false);
          _useVulkan = true;
          _useCublas = false;
          _useMetal = false;
          _useRocm = false;
        }
        changed = true;
      } else {
        _useVulkan = storage.backendSettings.useVulkan ?? false;
        if (storage.backendSettings.useCublas != null) {
          _useCublas = storage.backendSettings.useCublas!;
        }
        if (storage.backendSettings.useMetal != null) {
          _useMetal = storage.backendSettings.useMetal!;
        }
        if (storage.backendSettings.useRocm != null) {
          _useRocm = storage.backendSettings.useRocm!;
        }
      }
    }

    if (changed) {
      rebuildState(() {});
      final String msg;
      if (hw.vendor == 'Nvidia') {
        msg = 'NVIDIA GPU detected: CuBLAS enabled.';
      } else if (Platform.isMacOS) {
        msg = 'Apple Silicon detected: Metal enabled.';
      } else if (hw.vendor == 'AMD' && Platform.isLinux && hw.hasRocm) {
        msg = 'AMD GPU detected: ROCm enabled for native GPU acceleration.';
      } else if (hw.vendor == 'AMD' &&
          Platform.isLinux &&
          hw.hasRocm == false) {
        msg =
            'AMD GPU detected: Vulkan enabled. Install ROCm for better performance.';
        showRocmGuidanceDialog(context, hw.linuxDistro);
      } else {
        msg = 'Non-NVIDIA GPU detected: Vulkan enabled.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else {
      // Just update UI to match loaded persistence
      rebuildState(() {});
    }

    // Mirror the persisted settings into the UI controllers FIRST. The silent
    // auto-config below reads the context field as the user's wish, and it
    // used to run against the controllers' construction defaults ('16384') —
    // and because it PERSISTS its result, every Settings visit silently
    // overwrote a custom context limit ("my context size doesn't survive a
    // restart", field-reported).
    _gpuLayersController.text = storage.backendSettings.gpuLayers.toString();
    _contextSizeController.text = storage.backendSettings.contextSize
        .toString();
  }

  Future<void> _pickStoragePath() async {
    String? selectedDirectory = await PickerPrefs.getDirectoryPath(
      category: PickerPrefs.catDirectory,
    );
    if (selectedDirectory != null) {
      if (mounted) {
        // Close the current database so the file can be moved.
        await AppDatabase.closeAndReset();
        if (!mounted) return;
        final refusal = await Provider.of<StorageService>(
          context,
          listen: false,
        ).setRootPath(selectedDirectory);
        if (!mounted) return;
        // Reopen from the new location and re-point every service that holds a
        // DB reference. Shared with the stable-DB import and backup restore —
        // this used to be a hand-maintained second copy that silently missed
        // whatever the other one gained. No image cleanup: the move carries the
        // same characters, so nothing here is orphaned. On a REFUSAL the root
        // is unchanged, but the rebind must still run — the database was
        // closed above and needs reopening from the old location.
        await reopenAndRebindDatabase(context);
        if (!mounted) return;
        if (refusal != null) {
          // The move was refused (destination already has data, or a copy
          // failed). Nothing moved; say so plainly instead of looking done.
          await showWarmDialog<void>(
            context,
            title: 'Storage folder not changed',
            icon: Icons.folder_off_outlined,
            content: Text(refusal),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
          return;
        }
        // Backend/model discovery is path-dependent, so it is specific to a
        // storage move rather than part of the shared rebind.
        Provider.of<BackendManager>(
          context,
          listen: false,
        ).checkBackendAvailability();
        Provider.of<ModelManager>(context, listen: false).refreshModels();
      }
    }
  }

  Future<void> _toggleManagedBackend(BuildContext context) async {
    final koboldService = Provider.of<KoboldService>(context, listen: false);
    final backendManager = Provider.of<BackendManager>(context, listen: false);

    if (koboldService.isRunning || koboldService.isStarting) {
      await koboldService.stopKobold();
      return;
    }

    if (backendManager.backendPath == null) {
      // Not an error state anymore: kick the background acquisition (no-op
      // when already downloading) and point at the corner chip's progress.
      backendManager.ensureEngineInstalled();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            backendManager.isDownloading
                ? 'The AI engine is still downloading — progress is in the corner chip. Launch again once it finishes.'
                : 'The AI engine isn\'t installed yet — downloading it now in the background (see the corner chip).',
          ),
        ),
      );
      return;
    }
    final storage = Provider.of<StorageService>(context, listen: false);

    final presetOwnsModel = storage.backendSettings.kcppsHasModel;

    if (!presetOwnsModel) {
      if (_selectedModelPath == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please select a model.')));
        return;
      }
      // Same validation KoboldService runs before spawning the process — used
      // here purely so the reason lands in a snackbar the moment the user hits
      // the button, instead of only in the backend log. A bare existsSync()
      // used to guard this spot, which is exactly the check that says "yes"
      // for a OneDrive placeholder KoboldCpp then cannot open (issue #137).
      final problem = await ModelFileCheck.validate(_selectedModelPath!);
      if (problem != null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(problem)));
        return;
      }
    }

    // A preset that cannot be read stops the launch. Said here, because
    // the launch itself only writes it to the engine log.
    final presetProblem = await koboldPresetProblem(
      storage.backendSettings.activeKcppsPath,
    );
    if (presetProblem != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(presetProblem)));
      return;
    }

    final gpuLayers = int.tryParse(_gpuLayersController.text) ?? 0;
    final contextSize = int.tryParse(_contextSizeController.text) ?? 16384;

    storage.backendSettings.setGpuLayers(gpuLayers);
    storage.backendSettings.setContextSize(contextSize);
    storage.backendSettings.setUseCublas(_useCublas);
    storage.backendSettings.setUseVulkan(_useVulkan);
    storage.backendSettings.setUseMetal(_useMetal);
    storage.backendSettings.setUseRocm(_useRocm);

    final effectiveModel = presetOwnsModel ? '' : _selectedModelPath!;
    // Record the GGUF we are actually launching. This scalar is the app's only
    // memory of the running model — the system-role probe's cache key, the
    // auto-restart path, "Restart Backend" and the web UI's "loaded" marker all
    // read it. The Backend tab auto-picks the first model when nothing was
    // chosen, so without this the user launches model A while every consumer
    // still points at model B. (A preset that owns its model supplies the path
    // itself, so that branch leaves the scalar alone — same as the twin in
    // model_settings_dialog.local_actions.dart.)
    if (!presetOwnsModel) {
      await storage.backendSettings.setLastUsedModelPath(_selectedModelPath);
    }
    await koboldService.startKobold(
      backendManager.backendPath!,
      effectiveModel,
      kcppsPath: storage.backendSettings.activeKcppsPath,
      mmprojPath: _selectedModelPath != null
          ? storage.presetSettings.modelMmprojMap[_selectedModelPath!]
          : null,
      gpuLayers: gpuLayers,
      contextSize: contextSize,
      useVulkan: _useVulkan,
      useCublas: _useCublas,
      useMetal: _useMetal,
      useRocm: _useRocm,
    );
  }
}
