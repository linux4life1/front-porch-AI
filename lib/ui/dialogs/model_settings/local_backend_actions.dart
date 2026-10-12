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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';

/// The layer count box saves as it is typed, so the launch can read it from
/// storage. Text that is not a number saves nothing: an emptied box is not 0,
/// which keeps the model off the card.
void saveGpuLayersText(StorageService storage, String text) {
  final layers = int.tryParse(text);
  if (layers == null) return;
  storage.backendSettings.setGpuLayers(layers);
}

/// The context box saves as it is typed, like the layer count box.
void saveContextSizeText(StorageService storage, String text) {
  final tokens = int.tryParse(text);
  if (tokens == null || tokens <= 0) return;
  storage.backendSettings.setContextSize(tokens);
}

/// The backend restart/start action for the local (KoboldCpp) backend.
/// [context] is the Model Settings dialog's; it is popped once the launch
/// returns. [pickedModel] is read where the launch needs it, as the choice can
/// change while the engine is looked up.
Future<void> restartKoboldBackend(
  BuildContext context, {
  required String? Function() pickedModel,
}) async {
  final koboldService = Provider.of<KoboldService>(context, listen: false);
  final backendManager = Provider.of<BackendManager>(context, listen: false);

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
    pickedModel: pickedModel(),
  );
  if (problem != null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(problem)));
    return;
  }

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
  // choice never made stays "let the app pick from the hardware". Nothing
  // else is written here either: every box saves as it is typed, and this
  // dialog's copy of the context can be older than storage (a chosen preset
  // sets its own, the phone sets it too). The launch reads storage. A preset
  // whose file is gone is cleared by the launch, which then goes ahead
  // and says so.
  final result = await koboldService.launch(engine, pickedModel: pickedModel());
  if (context.mounted) navigator.pop();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.message ?? 'Restarting backend with new settings...',
      ),
    ),
  );
}
