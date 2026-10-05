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

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/model_file_check.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'kcpps_codec.dart';
import 'kobold_preset_read.dart';

/// What a launch will load.
class KoboldLaunch {
  const KoboldLaunch({
    required this.modelPath,
    this.kcppsPath,
    this.mmprojPath,
    this.note,
  });

  /// The GGUF that will be in memory. Empty when there is nothing to start.
  final String modelPath;

  /// The user's preset, or null when the app's own settings are used.
  final String? kcppsPath;

  /// The vision file kept for [modelPath], if any.
  final String? mmprojPath;

  /// Something the user should be told about how this was decided.
  final String? note;

  bool get canLaunch => modelPath.isNotEmpty;
}

/// Which model and preset a launch loads. Every launch site asks here, so
/// the engine, the status card, the vision lookup, the thinking settings and
/// the web "loaded" marker cannot disagree.
///
/// The rule: the active preset's own model when it names one that is on this
/// disk; otherwise [pickedModel] (what the user just chose), otherwise the
/// last-used model. A preset whose model is not here (made on another
/// computer, or the file was moved) keeps its settings and runs that
/// fallback model. A preset whose file is gone is dropped.
///
/// A preset may name its model by a relative path. KoboldCpp runs in the
/// engine folder, so that is what the path is relative to: [engineDir], the
/// folder of the executable. Left out, it is the app's engine folder, which
/// is where the app keeps the executable and what Settings uses. The model
/// comes back as a full path either way.
///
/// Never throws, whatever is in the preset file.
KoboldLaunch resolveKoboldLaunch(
  StorageService storage, {
  String? pickedModel,
  String? engineDir,
}) {
  final b = storage.backendSettings;
  final active = b.activeKcppsPath?.trim() ?? '';
  String? preset = active.isEmpty ? null : active;
  String? note;
  String? owned;

  if (preset != null) {
    final file = File(preset);
    if (!file.existsSync()) {
      note =
          'The preset "${p.basename(preset)}" is no longer on this '
          'computer, so the app\'s own settings were used.';
      preset = null;
    } else {
      final read = _read(file);
      final named = read is KcppsOk ? read.config.modelPath : '';
      if (read is KcppsOk && named.isNotEmpty) {
        final full = kcppsModelOf(
          read.raw,
          engineDir: engineDir ?? storage.binDir.path,
        );
        if (File(full).existsSync()) {
          owned = full;
        } else {
          note =
              'The preset "${p.basename(preset)}" names a model that is not '
              'on this computer (${p.basename(named)}), so the model chosen '
              'here was loaded with the preset\'s settings.';
        }
      }
    }
  }

  final picked = pickedModel?.trim() ?? '';
  final model =
      owned ?? (picked.isNotEmpty ? picked : b.lastUsedModelPath?.trim() ?? '');
  return KoboldLaunch(
    modelPath: model,
    kcppsPath: preset,
    mmprojPath: model.isEmpty
        ? null
        : storage.presetSettings.modelMmprojMap[model],
    note: note,
  );
}

/// Why a launch asked for now cannot go ahead, in plain words, or null:
/// no model chosen, a model file that cannot be read, or a preset that
/// cannot be read. The screens that start the engine ask first, so the
/// reason reaches the user at once and nothing running is stopped for a
/// launch that would fail.
Future<String?> koboldLaunchProblem(
  StorageService storage, {
  String? pickedModel,
}) async {
  final launch = resolveKoboldLaunch(storage, pickedModel: pickedModel);
  if (!launch.canLaunch) return 'Please select a model.';
  return await ModelFileCheck.validate(launch.modelPath) ??
      await koboldPresetProblem(launch.kcppsPath);
}

/// Said when nothing is chosen to load.
const String kKoboldNoModelWords =
    'No model is chosen yet. Pick one in Settings, on the Backend tab.';

/// What a launch did.
class KoboldLaunchResult {
  /// The engine was started. [message] says how the model was chosen when
  /// that is worth telling (a preset from another computer, a preset whose
  /// file is gone).
  const KoboldLaunchResult.started([this.message]) : started = true;

  /// Nothing was started; [message] says why.
  const KoboldLaunchResult.refused(String this.message) : started = false;

  final bool started;
  final String? message;
}

KcppsRead _read(File file) {
  try {
    return readKcpps(file.readAsStringSync());
  } on Object catch (e) {
    // Whatever went wrong, it is "this preset names no model", never an
    // error thrown at the screen that asked.
    return KcppsBroken('$e');
  }
}

/// The user picked [modelPath] (desktop picker, phone model switch): it
/// becomes the last-used model, and the active preset becomes that model's
/// own preset, or none. Leaving the previous model's preset active would
/// launch the new model with the old one's context and layers.
Future<void> selectKoboldModel(StorageService storage, String modelPath) async {
  await storage.backendSettings.setLastUsedModelPath(modelPath);
  final saved = storage.presetSettings.modelPresetMap[modelPath];
  final usable = saved != null && saved.isNotEmpty && File(saved).existsSync();
  await storage.backendSettings.setActiveKcppsPath(usable ? saved : null);
}

/// The model KoboldCpp was given becomes the app's one record of "which
/// model": the status card, the vision lookup, the thinking settings, an
/// automatic restart and the phone's "loaded" marker all read it. A launch
/// records it, and so does a live reload of chat. So does choosing a preset
/// that names its own model, which a launch would load: from then on every
/// screen names that model.
///
/// [launch] is what a launch resolved; left out, what one would load now.
Future<void> recordKoboldModelInUse(
  StorageService storage, {
  KoboldLaunch? launch,
}) async {
  final model = (launch ?? resolveKoboldLaunch(storage)).modelPath;
  final b = storage.backendSettings;
  if (model.isNotEmpty && b.lastUsedModelPath != model) {
    await b.setLastUsedModelPath(model);
  }
}
