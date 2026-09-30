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

import 'package:front_porch_ai/services/capability/image_reference_resolver.dart';
import 'package:front_porch_ai/services/capability/image_reference_role.dart';

import 'edit_profile.dart';
import 'image_gen_types.dart';
import 'image_studio_remote.dart';

/// Shown when a second generate starts while one is already running.
const String kAlreadyGeneratingMessage = 'Already generating.';

/// Which checkpoint a generation will name, before any backend is called.
///
/// Create reads the create slot. Edit reads the edit slot. An explicit model
/// wins. Remote refuses a local filename instead of POSTing it.
class ResolvedImageModel {
  final String model;

  /// When set, generation stops. No backend is contacted.
  final String? stopMessage;
  final bool clearCreateSlot;
  final bool clearEditSlot;

  const ResolvedImageModel({
    this.model = '',
    this.stopMessage,
    this.clearCreateSlot = false,
    this.clearEditSlot = false,
  });

  bool get stopped => stopMessage != null;
}

ResolvedImageModel resolveGenerationModel({
  required ImageGenBackend backend,
  required StudioIntent intent,
  required String? explicitModel,
  required String createSlot,
  required String editSlot,
  required String hostModel,
}) {
  final slot = intent == StudioIntent.edit ? editSlot : createSlot;
  final named = explicitModel ?? slot;
  if (backend != ImageGenBackend.remote) {
    return ResolvedImageModel(model: named);
  }
  final picked = pickRemoteImageModelId(
    explicit: explicitModel,
    slotModel: slot,
    hostModel: hostModel,
  );
  if (picked != null) return ResolvedImageModel(model: picked);
  final leftover =
      looksLikeLocalImageModel(named) ||
      looksLikeLocalImageModel(explicitModel ?? '');
  return ResolvedImageModel(
    stopMessage: leftover
        ? kRemoteLocalCheckpointMessage
        : 'No image model selected.',
    clearCreateSlot: leftover && intent != StudioIntent.edit,
    clearEditSlot: leftover && intent == StudioIntent.edit,
  );
}

/// Draw Things steps / CFG / sampler for this role.
///
/// Edit reads the edit-scoped store (seeded from the Qwen recipe). Create
/// keeps the txt2img knobs. Mixing them is how an edit returns a blank image
/// or a create inherits UniPC.
class DrawThingsKnobs {
  final int steps;
  final double cfg;
  final int sampler;
  final double shift;
  final int seedMode;
  final double strength;

  const DrawThingsKnobs({
    required this.steps,
    required this.cfg,
    required this.sampler,
    required this.shift,
    required this.seedMode,
    required this.strength,
  });
}

DrawThingsKnobs drawThingsGenerationKnobs({
  required ImageReferenceRole role,
  required int createSteps,
  required double createCfg,
  required int createSampler,
  required double createShift,
  required int createSeedMode,
  required double createStrength,
  required int editSteps,
  required double editCfg,
  required int editSampler,
  required double editShift,
  required int editSeedMode,
  required double? editStrength,
}) {
  if (role != ImageReferenceRole.editConditioning) {
    return DrawThingsKnobs(
      steps: createSteps,
      cfg: createCfg,
      sampler: createSampler,
      shift: createShift,
      seedMode: createSeedMode,
      strength: createStrength,
    );
  }
  return DrawThingsKnobs(
    steps: editSteps,
    cfg: editCfg,
    sampler: editSampler,
    shift: editShift,
    seedMode: editSeedMode,
    strength: editStrength ?? kEditRecommendedStrength,
  );
}

/// Model, reference role, and the stop message for one generation.
class ImageJobPlan {
  final ImageGenBackend backend;
  final ResolvedImageModel model;
  final ImageReferenceRole role;
  final ImageReferenceCapability capability;

  const ImageJobPlan({
    required this.backend,
    required this.model,
    required this.role,
    required this.capability,
  });

  /// User-facing reason to stop, or null when a backend call should proceed.
  String? get stopMessage {
    if (model.stopped) return model.stopMessage;
    if (role == ImageReferenceRole.unsupported) {
      return capability.degradeReason ??
          'This backend can’t edit from a photo. Try Create instead.';
    }
    return null;
  }
}

ImageJobPlan planImageJob({
  required ImageGenBackend backend,
  required StudioIntent intent,
  required String? explicitModel,
  required String createSlot,
  required String editSlot,
  required String hostModel,
  required int attachedRefCount,
}) {
  final model = resolveGenerationModel(
    backend: backend,
    intent: intent,
    explicitModel: explicitModel,
    createSlot: createSlot,
    editSlot: editSlot,
    hostModel: hostModel,
  );
  final capability = ImageReferenceResolver.resolveForBackend(
    backend: backend,
    modelName: model.model,
  );
  final role = model.stopped
      ? ImageReferenceRole.none
      : routeReference(
          intent: intent,
          attachedRefCount: attachedRefCount,
          cap: capability,
        );
  return ImageJobPlan(
    backend: backend,
    model: model,
    role: role,
    capability: capability,
  );
}
