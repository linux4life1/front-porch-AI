// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/capability/image_reference_resolver.dart';
import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// How a pack's pictures are made.
enum PackMode {
  /// The Edit path: the base portrait is read as conditioning.
  edit,

  /// img2img from the base portrait, on a backend that has no Edit path.
  img2img,
}

/// What a pack will do, or why it cannot start.
class PackPlan {
  const PackPlan.edit() : mode = PackMode.edit, refusal = null;
  const PackPlan.img2img() : mode = PackMode.img2img, refusal = null;
  const PackPlan.refused(String this.refusal) : mode = null;

  final PackMode? mode;

  /// The sentence to show when the pack cannot start; null when it can.
  final String? refusal;

  bool get canStart => refusal == null;
  bool get edit => mode == PackMode.edit;
}

/// The one decision for Studio's pack dialog, the creator's Portrait &
/// Avatars panel and the phone.
///
/// ComfyUI packs run the Edit graph and nothing else: the same readiness rule
/// as the desk ([checkStudioReady]), and a graph that is not ready is a
/// refusal with the reason, never a quiet switch to the Create graph. A remote
/// API needs an edit-capable model id. Backends that have no Edit path at all
/// (A1111, or a Draw Things model that cannot edit) make the pack by img2img.
Future<PackPlan> planExpressionPack(
  StorageService storage, {
  ComfyUiService? comfy,
  City96Gate? gate,
}) async {
  final settings = storage.imageGenSettings;
  final backend = ImageGenBackend.fromKey(settings.imageGenBackend);
  if (backend == ImageGenBackend.comfyUi) {
    final report = await checkStudioReady(
      settings: settings,
      edit: true,
      comfy: comfy,
      gate: gate,
    );
    return report.ready
        ? const PackPlan.edit()
        : PackPlan.refused(
            packNotReadyMessage(report.readiness, settings.comfyUiUrl),
          );
  }
  if (backend == ImageGenBackend.remote) {
    final account = resolveImageStudioRemoteAccount(
      imageRemoteApiUrl: settings.imageRemoteApiUrl,
      chatRemoteApiUrl: storage.backendSettings.remoteApiUrl,
      keyFor: storage.backendSettings.remoteApiKeyFor,
    );
    await sanitizeRemoteImageSlot(
      image: settings,
      hostUrl: account.url,
      editScoped: true,
    );
    return ImageReferenceResolver.packEditMode(settings)
        ? const PackPlan.edit()
        : const PackPlan.refused(kRemotePackNeedsEditModel);
  }
  return ImageReferenceResolver.packEditMode(settings)
      ? const PackPlan.edit()
      : const PackPlan.img2img();
}

const String kRemotePackNeedsEditModel =
    'On a remote API the pack generates through the provider\'s image-edit '
    'endpoint, so it needs an edit model (for example qwen-image-max-edit or '
    'qwen-image-2.1/edit), not a Comfy or A1111 checkpoint left in the Edit '
    'slot. Pick one in Image Studio → Edit, or switch to a local backend.';

/// Why a ComfyUI pack will not start: what the Edit graph is missing.
String packNotReadyMessage(StudioReadiness readiness, String comfyUrl) {
  final why = switch (readiness.kind) {
    StudioReady.unreachable => 'ComfyUI can’t be reached at $comfyUrl',
    StudioReady.missingNodeClass =>
      'ComfyUI is missing the ${readiness.missingClass} node',
    StudioReady.needsUnetGraph => 'a GGUF file needs a diffusion graph',
    StudioReady.needsLoaderUpdate ||
    StudioReady.needsComfyRestart => readiness.message ?? kCity96NeedsUpdate,
    StudioReady.missingFile =>
      'a model file it needs is not chosen or not installed',
    StudioReady.loraMismatch => 'a LoRA does not match its model',
    StudioReady.ready => '',
  };
  return 'An expression pack on ComfyUI runs your Edit graph, and it is not '
      'ready: $why. Set it up in Image Studio → Edit. A pack is never made '
      'with the Create graph instead.';
}
