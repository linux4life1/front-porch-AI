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
  /// A new chat model or preset goes into a running KoboldCpp at once: a
  /// reload by name, a restart only when that is not acted on. When it was
  /// not loaded, the reason is said the way a Start says its own, and the
  /// model dropdown follows the stored choice again.
  void _reloadChatIfRunning() {
    final llm = context.read<LLMProvider>();
    if (!llm.koboldService.isProcessRunning) return;
    // Taken before the wait: the page may be gone when it ends.
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      llm
          .reloadChatKobold()
          .then((result) {
            final words = result?.message;
            if (words != null) {
              messenger.showSnackBar(SnackBar(content: Text(words)));
            }
            // A model that was not loaded was not kept either: the stored
            // choice is back on what runs, and the dropdown names it again.
            if (result?.refusal != null && mounted) {
              rebuildState(() => _selectedModelPath = null);
            }
          })
          .catchError(
            (Object e) => debugPrint('[Settings] chat reload failed: $e'),
          ),
    );
  }

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
    // Mac Logic: Default to Metal if not set. Detection reports Metal on
    // every Mac and nowhere else.
    else if (hw.hasMetal) {
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
    // Everything else (AMD, Intel, no card): nothing is written. A choice
    // nobody made stays automatic (all four unset), which runs Vulkan on an
    // AMD or Intel card at each launch; ROCm is only ever picked by hand.
    else {
      final bs = storage.backendSettings;
      _useVulkan = bs.useVulkan == true;
      _useCublas = bs.useCublas == true;
      _useMetal = bs.useMetal == true;
      _useRocm = bs.useRocm == true;
    }

    if (changed) {
      rebuildState(() {});
      final msg = hw.vendor == 'Nvidia'
          ? 'NVIDIA GPU detected: CuBLAS enabled.'
          : 'Apple Silicon detected: Metal enabled.';
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
    String? selectedDirectory = await GuardedPicker.getDirectoryPath(
      context,
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

    // Looked for again: the build on disk must be the one the choice needs.
    final engine = await backendManager.engineForStart();
    if (!context.mounted) return;
    if (engine == null) {
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

    // The same check the launch runs (model chosen, model readable, preset
    // readable), done here so the reason lands in a snackbar the moment the
    // button is pressed. It reads the model file rather than asking whether
    // it exists: a OneDrive placeholder "exists" and KoboldCpp still cannot
    // open it (issue #137).
    final problem = await koboldLaunchProblem(
      storage,
      pickedModel: _selectedModelPath,
    );
    if (problem != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    // Nothing is written here: every control saves as it changes, and the
    // launch reads storage. This page's copy of the context, layers and
    // switches can be older than storage (the Local model card, the phone and
    // "Reset to Automatic" write it directly), so writing it back undoes them.
    final result = await koboldService.launch(
      engine,
      pickedModel: _selectedModelPath,
    );
    // Why nothing started, or how the model was chosen when that needs
    // saying (a preset from another computer, a preset whose file is gone).
    if (result.message != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message!)));
    }
  }
}
