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
      if (storage.useCublas == null) {
        storage.setUseCublas(true);
        storage.setUseVulkan(false);
        _useCublas = true;
        _useVulkan = false;
        changed = true;
      } else {
        _useCublas = storage.useCublas!;
        if (storage.useVulkan != null) {
          _useVulkan = storage.useVulkan!;
        } else if (_useCublas) {
          _useVulkan = false;
        }
      }
    }
    // MacOS Logic: Default to Metal if not set
    else if (Platform.isMacOS) {
      if (storage.useMetal == null) {
        storage.setUseMetal(true);
        storage.setUseVulkan(false);
        storage.setUseCublas(false);
        _useMetal = true;
        _useVulkan = false;
        _useCublas = false;
        changed = true;
      } else {
        _useMetal = storage.useMetal!;
        if (storage.useVulkan != null) _useVulkan = storage.useVulkan!;
        if (storage.useCublas != null) _useCublas = storage.useCublas!;
        if (storage.useRocm != null) _useRocm = storage.useRocm!;
      }
    }
    // Non-NVIDIA/Non-Mac Logic: Default to ROCm if available, else Vulkan
    else {
      if (storage.useVulkan == null && storage.useRocm == null) {
        // First run: auto-detect best GPU backend
        if (hw.vendor == 'AMD' && Platform.isLinux && hw.hasRocm) {
          storage.setUseRocm(true);
          storage.setUseVulkan(false);
          storage.setUseCublas(false);
          storage.setUseMetal(false);
          _useRocm = true;
          _useVulkan = false;
          _useCublas = false;
          _useMetal = false;
        } else {
          storage.setUseVulkan(true);
          storage.setUseCublas(false);
          storage.setUseMetal(false);
          storage.setUseRocm(false);
          _useVulkan = true;
          _useCublas = false;
          _useMetal = false;
          _useRocm = false;
        }
        changed = true;
      } else {
        _useVulkan = storage.useVulkan ?? false;
        if (storage.useCublas != null) _useCublas = storage.useCublas!;
        if (storage.useMetal != null) _useMetal = storage.useMetal!;
        if (storage.useRocm != null) _useRocm = storage.useRocm!;
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

    // Trigger silent autoconfig on load if model is present
    // BUT only if user hasn't manually customized GPU layers.
    // A non-zero persisted gpuLayers means the user or a previous
    // explicit auto-config set it — don't silently overwrite.
    if (_selectedModelPath != null && storage.gpuLayers == 0) {
      // Warm before the silent auto-config so the solver gets good data on first run
      final modelManager = Provider.of<ModelManager>(context, listen: false);
      modelManager.getModelArchitectureInfo(_selectedModelPath!);
      _applyAutoConfiguration(silent: true);
    } else if (_selectedModelPath != null) {
      // Respect previously saved settings — just load them into the UI
      _gpuLayersController.text = storage.gpuLayers.toString();
      _contextSizeController.text = storage.backendSettings.contextSize
          .toString();
    }
  }

  Future<void> _pickStoragePath() async {
    String? selectedDirectory = await PickerPrefs.getDirectoryPath(
      category: PickerPrefs.catDirectory,
    );
    if (selectedDirectory != null) {
      if (mounted) {
        // Close the current database so the file can be moved
        await AppDatabase.closeAndReset();
        await Provider.of<StorageService>(
          context,
          listen: false,
        ).setRootPath(selectedDirectory);
        // Reopen the database from the new location
        final newDb = await AppDatabase.instance();
        // Update ALL downstream services that hold a DB reference
        if (mounted) {
          Provider.of<CharacterRepository>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<FolderService>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<UserPersonaService>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<GroupChatRepository>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<WorldRepository>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<ChatService>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          // Rebind the web server + Porch Stories too — they held the closed
          // pre-move DB, so after a storage move remote users were dropped and
          // couldn't log back in, and story queries threw, until an app restart.
          Provider.of<StoryRepository>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<WebServerHost>(context, listen: false).setDatabase(newDb);
          // Reload data from the new DB location
          await Provider.of<CharacterRepository>(
            context,
            listen: false,
          ).loadCharacters();
          await Provider.of<FolderService>(context, listen: false).reload();
          // Refresh backend/models after path change
          Provider.of<BackendManager>(
            context,
            listen: false,
          ).checkBackendAvailability();
          Provider.of<ModelManager>(context, listen: false).refreshModels();
        }
      }
    }
  }

  void _applyAutoConfiguration({bool silent = false}) {
    final hardware = Provider.of<HardwareService>(
      context,
      listen: false,
    ).hardwareInfo;
    if (hardware == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hardware not detected yet.')),
        );
      }
      return;
    }

    if (silent) {
      _runOptimization(hardware.vramMb, hardware, silent: true);
    } else {
      final vramController = TextEditingController(
        text: hardware.vramMb.toString(),
      );
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.cardOf(context),
          title: Text(
            'Auto-Configuration',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirm your System VRAM (MB):',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: vramController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: AppColors.textPrimary(context)),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Note: Some systems report incorrect VRAM (e.g. 4095MB for >4GB cards). Adjust if necessary.',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final adjustedVram =
                    int.tryParse(vramController.text) ?? hardware.vramMb;
                Navigator.pop(context);
                _runOptimization(adjustedVram, hardware, silent: false);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      );
    }
  }

  void _runOptimization(
    int vramMb,
    HardwareInfo hardware, {
    required bool silent,
  }) {
    // Create temp hardware info with adjusted VRAM
    final adjustedHw = HardwareInfo(
      gpuName: hardware.gpuName,
      vramMb: vramMb,
      ramMb: hardware.ramMb,
      vendor: hardware.vendor,
    );

    // Attempt to estimate model size from selected model
    int modelSize = 5000;
    if (_selectedModelPath != null) {
      try {
        final file = File(_selectedModelPath!);
        if (file.existsSync()) {
          modelSize = (file.lengthSync() / (1024 * 1024)).round();
        }
      } catch (e) {
        debugPrint('Error getting file size: $e');
      }
    }

    // Respect user's context size — pass it to the optimizer so only GPU layers adjust
    final userContext = int.tryParse(_contextSizeController.text);

    int? kvBytesPerToken;
    if (_selectedModelPath != null && mounted) {
      final modelManager = Provider.of<ModelManager>(context, listen: false);
      kvBytesPerToken = modelManager.getCachedKvBytesPerToken(
        _selectedModelPath!,
      );
    }

    final suggestion = OptimizationService.calculateSettings(
      adjustedHw,
      modelSizeMb: modelSize,
      requestedContextSize: userContext,
      kvBytesPerToken: kvBytesPerToken,
      kvQuantizationLevel: Provider.of<StorageService>(
        context,
        listen: false,
      ).kvQuantizationLevel,
    );

    // Persist settings to storage so they survive app restart
    final storage = Provider.of<StorageService>(context, listen: false);
    storage.setGpuLayers(suggestion.gpuLayers);
    storage.setContextSize(suggestion.contextSize);

    rebuildState(() {
      _gpuLayersController.text = suggestion.gpuLayers.toString();
      _contextSizeController.text = suggestion.contextSize.toString();
      // If user has Mac, suggest Metal
      if (Platform.isMacOS) {
        _useMetal = true;
        _useVulkan = false;
        _useCublas = false;
        storage.setUseMetal(true);
        storage.setUseVulkan(false);
        storage.setUseCublas(false);
      }
      // If user has Nvidia, suggest Cublas instead of Vulkan usually
      else if (hardware.vendor == 'Nvidia') {
        _useCublas = true;
        _useVulkan = false;
        _useMetal = false;
        storage.setUseCublas(true);
        storage.setUseVulkan(false);
      } else {
        _useCublas = false;
        _useMetal = false;
      }
    });

    if (!silent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(suggestion.reasoning)));
    }
  }

  void _autoConfigure() {
    _applyAutoConfiguration(silent: false);
  }

  Future<void> _toggleManagedBackend(BuildContext context) async {
    final koboldService = Provider.of<KoboldService>(context, listen: false);
    final backendManager = Provider.of<BackendManager>(context, listen: false);

    if (koboldService.isRunning || koboldService.isStarting) {
      await koboldService.stopKobold();
      return;
    }

    if (backendManager.backendPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backend not found. Please download it first.'),
        ),
      );
      return;
    }
    final storage = Provider.of<StorageService>(context, listen: false);

    final presetOwnsModel = storage.kcppsHasModel;

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

    final gpuLayers = int.tryParse(_gpuLayersController.text) ?? 0;
    final contextSize = int.tryParse(_contextSizeController.text) ?? 16384;

    storage.setGpuLayers(gpuLayers);
    storage.setContextSize(contextSize);
    storage.setUseCublas(_useCublas);
    storage.setUseVulkan(_useVulkan);
    storage.setUseMetal(_useMetal);
    storage.setUseRocm(_useRocm);

    final effectiveModel = presetOwnsModel ? '' : _selectedModelPath!;
    await koboldService.startKobold(
      backendManager.backendPath!,
      effectiveModel,
      kcppsPath: storage.activeKcppsPath,
      mmprojPath: _selectedModelPath != null
          ? storage.mmprojForModel(_selectedModelPath!)
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
