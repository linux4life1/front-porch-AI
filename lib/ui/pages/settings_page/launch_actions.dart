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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Moves the library to a folder the user picks, then reopens the database
/// there and re-points every service that holds it.
Future<void> pickStoragePath(BuildContext context) async {
  String? selectedDirectory = await GuardedPicker.getDirectoryPath(
    context,
    category: PickerPrefs.catDirectory,
  );
  if (selectedDirectory != null) {
    if (context.mounted) {
      // Close the current database so the file can be moved.
      await AppDatabase.closeAndReset();
      if (!context.mounted) return;
      final refusal = await Provider.of<StorageService>(
        context,
        listen: false,
      ).setRootPath(selectedDirectory);
      if (!context.mounted) return;
      // Reopen from the new location and re-point every service that holds a
      // DB reference. Shared with the stable-DB import and backup restore —
      // this used to be a hand-maintained second copy that silently missed
      // whatever the other one gained. No image cleanup: the move carries the
      // same characters, so nothing here is orphaned. On a REFUSAL the root
      // is unchanged, but the rebind must still run — the database was
      // closed above and needs reopening from the old location.
      await reopenAndRebindDatabase(context);
      if (!context.mounted) return;
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

/// The Backend tab's Start/Stop: stops a running engine, otherwise starts
/// it on [pickedModel] (read when used: the model the dropdown names then).
Future<void> toggleManagedBackend(
  BuildContext context, {
  required String? Function() pickedModel,
}) async {
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
    pickedModel: pickedModel(),
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
  final result = await koboldService.launch(engine, pickedModel: pickedModel());
  // Why nothing started, or how the model was chosen when that needs
  // saying (a preset from another computer, a preset whose file is gone).
  if (result.message != null && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message!)));
  }
}

/// The Start/Restart button under Advanced Launch Options: applies the
/// launch settings above by starting the engine again.
Future<void> restartFromLaunchOptions(BuildContext ctx) async {
  final koboldService = Provider.of<KoboldService>(ctx, listen: false);
  final backendManager = Provider.of<BackendManager>(ctx, listen: false);
  final storage = Provider.of<StorageService>(ctx, listen: false);
  final messenger = ScaffoldMessenger.of(ctx);

  // Checked before anything is stopped, so a model or preset that cannot
  // be used, or an engine build the choice cannot run on (looked for
  // again; it downloads), leaves the running engine alone.
  final problem = await koboldLaunchProblem(storage);
  final engine = await backendManager.engineForStart();
  if (problem != null || engine == null) {
    if (engine == null) backendManager.ensureEngineInstalled();
    final why = problem ?? 'The AI engine is downloading (see the corner).';
    messenger.showSnackBar(SnackBar(content: Text(why)));
    return;
  }

  final wasRunning = koboldService.isRunning;
  if (wasRunning) {
    await koboldService.stopKobold();
    await Future.delayed(const Duration(seconds: 1));
  }
  final result = await koboldService.launch(engine);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.message ??
            (wasRunning
                ? 'Restarting backend with new settings…'
                : 'Starting backend…'),
      ),
    ),
  );
}
