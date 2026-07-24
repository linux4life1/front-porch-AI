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

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';
import 'package:front_porch_ai/services/image_gen_service.dart'
    show ImageGenBackend;
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

/// Adapter that maps the active [ImageGenBackend] to the pure backend bits
/// [resolveCapability] needs — the ONE place the service enum meets the pure
/// seam, so `image_reference_role.dart` stays dependency-free and unit-testable.
///
/// Stateless and cheap (pure sync, no network/file I/O), so there is no cache —
/// the intent of `VisionSupportResolver` without its cost.
class ImageReferenceResolver {
  const ImageReferenceResolver._();

  /// The reference capability for the active backend + model.
  ///
  /// Edit GENERATION is wired per backend as phases land; a backend whose edit
  /// path isn't built yet passes `backendEditMaxImages: 0`, so its Edit tab
  /// honestly degrades instead of appearing-and-failing. Today only Draw Things
  /// edit is wired (Phase 2); ComfyUI + remote turn on in Phase 5, and Draw
  /// Things reaches [kQwenEditMaxImages] once its multi-image plumbing lands
  /// (Phase 6).
  static ImageReferenceCapability resolveForBackend({
    required ImageGenBackend backend,
    required String modelName,
  }) {
    switch (backend) {
      case ImageGenBackend.a1111:
        // Stock A1111 / Forge is classic denoise only — never edit-conditioning.
        return resolveCapability(
          modelName: modelName,
          backendSupportsImg2img: true,
          backendEditMaxImages: 0,
        );
      case ImageGenBackend.drawThings:
        return resolveCapability(
          modelName: modelName,
          backendSupportsImg2img: true,
          backendEditMaxImages: kDrawThingsEditMaxImages,
        );
      case ImageGenBackend.comfyUi:
        // ComfyUI edits via a SELECTED workflow (a bundled preset or an uploaded
        // graph), NOT a detected model name — so edit is offered whenever ComfyUI
        // is the backend, and the fine readiness (required nodes present, model
        // slots picked) is enforced in the Edit tab (the ✓/⚠ line) and by the
        // server on submit. editKind is generic: the chosen workflow IS the
        // recipe. Single reference image (multi-image was dropped).
        return const ImageReferenceCapability(
          supportsEdit: true,
          editMaxImages: 1,
          supportsImg2img: true,
          editKind: EditModelKind.generic,
        );
      case ImageGenBackend.remote:
        // Remote edit is detected from the model ID allowlist (canonical
        // provider ids, e.g. qwen-image-max-edit / nano-banana-edit), capped at
        // one reference image. The transport is verified against Nano-GPT's
        // OpenAI-compatible /images/edits; OpenRouter's chat-completions image
        // path is wired too (community-verified). A non-edit remote model still
        // degrades honestly.
        return resolveCapability(
          modelName: modelName,
          backendSupportsImg2img: false,
          backendEditMaxImages: 1,
          useRemoteAllowlist: true,
        );
    }
  }

  /// The expression-pack "edit-first" decision, shared VERBATIM by the
  /// Studio's pack dialog and the creator's Portrait & Avatars panel so the
  /// two hosts can never diverge: drive each emotion through the EDIT path
  /// (identity pinned by the base portrait) when the active backend + the
  /// EDIT-slot model can instruction-edit; otherwise fall back to img2img.
  ///
  /// ComfyUI advertises edit unconditionally (it's workflow-gated, not
  /// model-gated), so `supportsEdit` alone would route every slot to the edit
  /// path and fail on unfilled model slots when no edit workflow is set up —
  /// and the img2img fallback would be unreachable. Gate on the SAME
  /// readiness the Edit tab enforces; when it isn't ready, img2img (which the
  /// plain checkpoint can always do) takes over.
  static bool packEditMode(ImageGenSettings settings) {
    final backend = ImageGenBackend.fromKey(settings.imageGenBackend);
    var editMode = resolveForBackend(
      backend: backend,
      modelName: settings.imageGenEditModel,
    ).supportsEdit;
    if (editMode && backend == ImageGenBackend.comfyUi) {
      editMode = comfyEditReady(
        workflowId: settings.comfyEditWorkflowId,
        uploadedWorkflowJson: settings.comfyEditUploadedWorkflow,
        modelChoices: settings.comfyEditModelChoices,
      );
    }
    return editMode;
  }
}
