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

    // The same check the launch runs (model chosen, model readable, preset
    // readable), surfaced here so the specific reason reaches a snackbar at
    // once instead of only the engine log. It reads the model file rather
    // than asking whether it exists: a OneDrive placeholder "exists" and
    // still ends in an unexplained exit 2 (issue #137).
    final problem = await koboldLaunchProblem(
      storage,
      pickedModel: _selectedModelPath,
    );
    if (problem != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    storage.backendSettings.setGpuLayers(
      int.tryParse(_gpuLayersController.text) ?? 0,
    );
    storage.backendSettings.setContextSize(
      int.tryParse(_contextSizeController.text) ?? 16384,
    );

    // Taken now: the dialog can be closed while the engine stops and starts,
    // and the launch below must still happen.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Await the full stop so the process tree is terminated and the port is
    // released before we start a new instance. Without this, Windows can
    // leave the old koboldcpp.exe alive → zombie processes accumulate.
    if (koboldService.isRunning) {
      await koboldService.stopKobold();
    }

    // Give the OS a moment to fully release the port after process termination.
    await Future.delayed(const Duration(seconds: 1));

    // This dialog has no graphics-backend control, so it records none: a
    // choice never made stays "let the app pick from the hardware". The
    // launch reads everything else from the settings saved above. A preset
    // whose file is gone is cleared by the launch, which then goes ahead
    // and says so.
    final result = await koboldService.launch(
      backendManager.backendPath!,
      pickedModel: _selectedModelPath,
    );
    if (mounted) navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.message ?? 'Restarting backend with new settings...',
        ),
      ),
    );
  }
}
