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

/// The single seam every image path routes on: what does a reference image MEAN
/// to the active backend + model? Deciding this ONCE — instead of re-asking
/// "is there a reference?" in four backends — is what keeps a new edit-model
/// family from forcing yet another rewrite of "image-to-image".
///
/// Pure and deterministic: no I/O, and deliberately NO dependency on
/// `ImageGenBackend` (which lives in the god file `image_gen_service.dart`).
/// The backend → pure-bits mapping lives in `image_reference_resolver.dart`, so
/// this file stays trivially unit-testable. Mirrors the metadata-first /
/// name-second philosophy of `image/model_family.dart`.
library;

/// What generation should DO with an attached reference image.
enum ImageReferenceRole {
  /// No reference — plain txt2img.
  none,

  /// Classic Stable-Diffusion img2img: the reference is a blended starting
  /// canvas at a denoise strength (Create → "start from a photo").
  img2imgDenoise,

  /// Instruction edit: the reference is conditioning read the WHOLE run, so
  /// identity is pinned (Qwen-Image-Edit / Flux Kontext). Never silently
  /// downgraded to [img2imgDenoise].
  editConditioning,

  /// A reference was attached and the user asked to edit, but this
  /// backend + model genuinely cannot — refuse honestly, do not fake it.
  unsupported,
}

/// The edit-model variant of the active checkpoint, if any. This is a VARIANT
/// axis (edit vs not), distinct from the base-family axis in
/// `image/model_family.dart` (SDXL / Flux / …). [generic] = an allowlisted
/// remote edit model we don't name-classify further.
enum EditModelKind { none, qwenEdit, kontext, generic }

/// Which Studio tab the user is in — the intent that seeds the default role.
enum StudioIntent { create, edit }

/// Per-model reference-image ceilings (each min'd with the backend's own).
/// Qwen-Image-Edit-2509 "Plus" accepts 1–3 reference images; Flux.1 Kontext
/// [dev] is single-reference. (Verified against the model docs, 2026-07.)
const int kQwenEditMaxImages = 3;
const int kKontextEditMaxImages = 1;

/// Draw Things' edit ceiling until its multi-image gRPC plumbing lands
/// (Phase 6). DT the app supports multi-ref Qwen-Edit; our bridge sends one.
const int kDrawThingsEditMaxImages = 1;

/// What a backend + model can do with a reference image. Derived ONCE in
/// [resolveCapability]; consumed by the Studio UI (render 1..N slots, enable /
/// disable Edit) and by generation routing ([routeReference]).
class ImageReferenceCapability {
  /// Instruction-edit is achievable here. When false, [editMaxImages] is 0 and
  /// [degradeReason] explains why (for honest Edit-tab copy).
  final bool supportsEdit;

  /// Max reference photos the Edit flow accepts (0 when !supportsEdit).
  final int editMaxImages;

  /// Classic img2img (denoise blend) is available — Create's "start from a
  /// photo". Independent of edit support.
  final bool supportsImg2img;

  /// The detected edit-model variant (informs the prompt dialect downstream).
  final EditModelKind editKind;

  /// Why edit is unavailable, for the Edit tab's honest-degrade copy. Null iff
  /// [supportsEdit] is true.
  final String? degradeReason;

  const ImageReferenceCapability({
    required this.supportsEdit,
    required this.editMaxImages,
    required this.supportsImg2img,
    required this.editKind,
    this.degradeReason,
  });

  @override
  bool operator ==(Object other) =>
      other is ImageReferenceCapability &&
      other.supportsEdit == supportsEdit &&
      other.editMaxImages == editMaxImages &&
      other.supportsImg2img == supportsImg2img &&
      other.editKind == editKind &&
      other.degradeReason == degradeReason;

  @override
  int get hashCode => Object.hash(
    supportsEdit,
    editMaxImages,
    supportsImg2img,
    editKind,
    degradeReason,
  );

  @override
  String toString() =>
      'ImageReferenceCapability(edit: $supportsEdit x$editMaxImages, '
      'img2img: $supportsImg2img, kind: $editKind'
      '${degradeReason == null ? '' : ', why: $degradeReason'})';
}

/// Local edit-model detection from a checkpoint/file NAME (the floor — metadata
/// isn't reliably exposed the same way across DT / Comfy / A1111; see
/// `image/model_family.dart`). `kontext` → Flux Kontext; a name carrying BOTH
/// `qwen` and `edit` → Qwen-Image-Edit. Plain `qwen_image` / `flux` are NOT
/// edit models.
EditModelKind detectEditModel(String modelName) {
  final s = modelName.toLowerCase();
  if (s.contains('kontext')) return EditModelKind.kontext;
  // Require "image"+"edit" adjacency so a plain Qwen checkpoint that was merely
  // renamed/"edited" (e.g. "qwen_image_edited_v2") doesn't false-positive.
  if (s.contains('qwen') && _qwenImageEditRe.hasMatch(s)) {
    return EditModelKind.qwenEdit;
  }
  return EditModelKind.none;
}

/// Loose "smells like an edit model" check for the CREATE slot's non-blocking
/// warning and the one-time edit-slot migration seed (phase #12 model-slot
/// split): true when either strict detector hits, or when the name carries an
/// inpaint/instruct token. Warnings only — never gates generation, because a
/// name heuristic can be wrong in both directions.
bool looksLikeEditModel(String modelName) {
  if (modelName.trim().isEmpty) return false;
  if (detectEditModel(modelName) != EditModelKind.none) return true;
  if (remoteEditSpec(modelName) != null) return true;
  final s = modelName.toLowerCase();
  return s.contains('inpaint') || s.contains('instruct');
}

/// "image edit" as an adjacent token ("image-edit", "image_edit", "imageedit",
/// "image edit"), with "edit" not bleeding into "edited".
final RegExp _qwenImageEditRe = RegExp(r'image[-_ ]?edit(?![a-z])');

/// Remote edit models are an explicit ID ALLOWLIST (not name heuristics):
/// provider IDs are canonical and arbitrary. Additive — a new edit model is one
/// row, or is caught by the `*-edit` suffix fallback. Verified/extended when the
/// remote transport lands (Phase 5).
const Map<String, ({EditModelKind kind, int maxImages})> _remoteEditModels = {
  'qwen-image-max-edit': (
    kind: EditModelKind.qwenEdit,
    maxImages: kQwenEditMaxImages,
  ),
  'gpt-image-2': (kind: EditModelKind.generic, maxImages: 16),
  'glm-image-edit': (kind: EditModelKind.generic, maxImages: 1),
  'bria-fibo-edit': (kind: EditModelKind.generic, maxImages: 1),
};

/// Matches an "edit" SEGMENT in a provider model id — `-edit`, `/edit`,
/// `edit-image`, `edit-2`, etc. — but not "edit" buried in another word
/// ("credit"). Verified against Nano-GPT's live list: `qwen-image-max-edit`,
/// `glm-image-edit`, `nano-banana-edit`, `nano-banana-pro-edit`,
/// `step-image-edit-2`, `bytedance/seedream-v5.0-pro/edit`,
/// `microsoft/mai-image-2.5/edit`, `fal-ai/bernini-r/edit-image`, …
final RegExp _editSegmentRe = RegExp(r'(?:^|[-_/])edit(?:[-_/]|$)');

/// The edit spec for a remote model ID, or null if it isn't an edit model.
({EditModelKind kind, int maxImages})? remoteEditSpec(String modelId) {
  final id = modelId.trim().toLowerCase();
  final hit = _remoteEditModels[id];
  if (hit != null) return hit;
  // Any provider model with an "edit" segment edits at least one image.
  if (_editSegmentRe.hasMatch(id)) {
    return (kind: EditModelKind.generic, maxImages: 1);
  }
  return null;
}

/// The model's own reference ceiling for a LOCAL [kind] (remote uses
/// [remoteEditSpec]'s maxImages instead).
int _modelCapForKind(EditModelKind kind) {
  switch (kind) {
    case EditModelKind.qwenEdit:
      return kQwenEditMaxImages;
    case EditModelKind.kontext:
      return kKontextEditMaxImages;
    case EditModelKind.generic:
      return 1;
    case EditModelKind.none:
      return 0;
  }
}

/// Resolve the reference capability from PURE backend bits (no
/// `ImageGenBackend` dependency — the adapter supplies these).
///
/// [backendEditMaxImages] is the backend's own edit ceiling: 0 means the
/// backend cannot edit-condition at all (A1111, or a backend whose edit path
/// isn't wired yet). The effective slot count is `min(modelCap,
/// backendEditMaxImages)`. [useRemoteAllowlist] switches edit detection from
/// local name-heuristics to the remote ID allowlist. When [requireComfyEditNodes]
/// is set (ComfyUI), edit additionally needs [comfyEditNodesAvailable].
///
/// [backendEditUnavailableReason] overrides the honest-degrade copy for the
/// "this is an edit model but the backend can't run edit right now" case — used
/// by the adapter to say "coming in an update" for a backend whose edit path
/// isn't wired yet, instead of the generic "switch backends" line.
ImageReferenceCapability resolveCapability({
  required String modelName,
  required bool backendSupportsImg2img,
  required int backendEditMaxImages,
  bool useRemoteAllowlist = false,
  bool requireComfyEditNodes = false,
  bool comfyEditNodesAvailable = false,
  String? backendEditUnavailableReason,
}) {
  final EditModelKind kind;
  final int modelCap;
  if (useRemoteAllowlist) {
    final spec = remoteEditSpec(modelName);
    kind = spec?.kind ?? EditModelKind.none;
    modelCap = spec?.maxImages ?? 0;
  } else {
    kind = detectEditModel(modelName);
    modelCap = _modelCapForKind(kind);
  }

  final editMax = modelCap < backendEditMaxImages
      ? modelCap
      : backendEditMaxImages;
  final nodesOk = !requireComfyEditNodes || comfyEditNodesAvailable;
  final supportsEdit = kind != EditModelKind.none && editMax > 0 && nodesOk;

  String? reason;
  if (!supportsEdit) {
    if (kind == EditModelKind.none) {
      reason =
          'This model can’t do precise edits. Switch to a Qwen-Image-Edit or '
          'Flux Kontext model, or use Create.';
    } else if (requireComfyEditNodes && !comfyEditNodesAvailable) {
      reason =
          'ComfyUI is missing the edit nodes for this model. Install them, or '
          'use Create.';
    } else {
      reason =
          backendEditUnavailableReason ??
          'This backend can’t run edit models. Try Draw Things, ComfyUI, or a '
          'remote edit model — or use Create.';
    }
  }

  return ImageReferenceCapability(
    supportsEdit: supportsEdit,
    editMaxImages: supportsEdit ? editMax : 0,
    supportsImg2img: backendSupportsImg2img,
    editKind: kind,
    degradeReason: reason,
  );
}

/// Pure routing: given the tab [intent], how many references are attached
/// (already UI-clamped to [ImageReferenceCapability.editMaxImages]), and the
/// resolved [cap], decide the [ImageReferenceRole] generation will use.
///
/// Fail-closed contract: an edit intent NEVER silently becomes img2img. When
/// the backend/model can't edit, the role is [ImageReferenceRole.unsupported]
/// (honest refusal), not denoise mush. An edit intent with no reference is an
/// inert no-op ([ImageReferenceRole.none]) — the Edit UI guards against
/// generating without a source.
ImageReferenceRole routeReference({
  required StudioIntent intent,
  required int attachedRefCount,
  required ImageReferenceCapability cap,
}) {
  if (intent == StudioIntent.edit) {
    if (!cap.supportsEdit) return ImageReferenceRole.unsupported;
    return attachedRefCount >= 1
        ? ImageReferenceRole.editConditioning
        : ImageReferenceRole.none;
  }
  // Create.
  if (attachedRefCount >= 1 && cap.supportsImg2img) {
    return ImageReferenceRole.img2imgDenoise;
  }
  return ImageReferenceRole.none;
}
