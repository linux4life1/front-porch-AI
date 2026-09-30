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

import 'image_gen_types.dart';

/// What one image surface can do. Built once from the backend capability.
/// Screens read [imageSurfaceControls] and do not switch on the backend to
/// decide edit, img2img, LoRA, or which model slot to show.
class ImageSurfaceCapabilities {
  final bool edit;
  final bool img2img;
  final bool lora;
  final bool negativePrompt;
  final bool checkpointSlot;
  final bool workflowSlots;
  final bool scheduler;
  final bool editAllowlist;

  /// The surface offers an edit-model picker even before the current model
  /// can edit, so the user can choose one.
  final bool editPicker;

  const ImageSurfaceCapabilities({
    required this.edit,
    required this.img2img,
    required this.lora,
    required this.negativePrompt,
    required this.checkpointSlot,
    required this.workflowSlots,
    required this.scheduler,
    required this.editAllowlist,
    required this.editPicker,
  });
}

/// Controls derived only from [ImageSurfaceCapabilities].
class ImageSurfaceControls {
  final bool showEdit;
  final bool showImg2img;
  final bool showLora;
  final bool showNegative;
  final bool showCheckpointSlot;
  final bool showWorkflowSlots;
  final bool showScheduler;
  final bool editAllowlist;
  final bool showEditPicker;

  const ImageSurfaceControls({
    required this.showEdit,
    required this.showImg2img,
    required this.showLora,
    required this.showNegative,
    required this.showCheckpointSlot,
    required this.showWorkflowSlots,
    required this.showScheduler,
    required this.editAllowlist,
    required this.showEditPicker,
  });

  Map<String, bool> toJson() => {
    'edit': showEdit,
    'img2img': showImg2img,
    'lora': showLora,
    'negative': showNegative,
    'checkpointSlot': showCheckpointSlot,
    'workflowSlots': showWorkflowSlots,
    'scheduler': showScheduler,
    'editAllowlist': editAllowlist,
    'editPicker': showEditPicker,
  };
}

/// Pass-through. Does not inspect which backend produced [caps].
ImageSurfaceControls imageSurfaceControls(ImageSurfaceCapabilities caps) {
  return ImageSurfaceControls(
    showEdit: caps.edit,
    showImg2img: caps.img2img,
    showLora: caps.lora,
    showNegative: caps.negativePrompt,
    showCheckpointSlot: caps.checkpointSlot,
    showWorkflowSlots: caps.workflowSlots,
    showScheduler: caps.scheduler,
    editAllowlist: caps.editAllowlist,
    showEditPicker: caps.editPicker,
  );
}

/// The one mapping from a backend's reference capability to surface flags.
ImageSurfaceCapabilities capabilitiesFor({
  required ImageGenBackend backend,
  required ImageReferenceCapability reference,
}) {
  switch (backend) {
    case ImageGenBackend.a1111:
      return ImageSurfaceCapabilities(
        edit: reference.supportsEdit,
        img2img: reference.supportsImg2img,
        lora: true,
        negativePrompt: true,
        checkpointSlot: true,
        workflowSlots: false,
        scheduler: true,
        editAllowlist: false,
        editPicker: false,
      );
    case ImageGenBackend.drawThings:
      return ImageSurfaceCapabilities(
        edit: reference.supportsEdit,
        img2img: reference.supportsImg2img,
        lora: true,
        negativePrompt: true,
        checkpointSlot: true,
        workflowSlots: false,
        scheduler: false,
        editAllowlist: false,
        editPicker: true,
      );
    case ImageGenBackend.comfyUi:
      return ImageSurfaceCapabilities(
        edit: reference.supportsEdit,
        img2img: reference.supportsImg2img,
        lora: true,
        negativePrompt: true,
        checkpointSlot: false,
        workflowSlots: true,
        scheduler: true,
        editAllowlist: false,
        editPicker: false,
      );
    case ImageGenBackend.remote:
      return ImageSurfaceCapabilities(
        edit: reference.supportsEdit,
        img2img: reference.supportsImg2img,
        lora: false,
        negativePrompt: false,
        checkpointSlot: true,
        workflowSlots: false,
        scheduler: false,
        editAllowlist: true,
        editPicker: true,
      );
  }
}

ImageSurfaceControls imageSurfaceFor({
  required ImageGenBackend backend,
  required String modelName,
}) {
  return imageSurfaceControls(
    capabilitiesFor(
      backend: backend,
      reference: ImageReferenceResolver.resolveForBackend(
        backend: backend,
        modelName: modelName,
      ),
    ),
  );
}
