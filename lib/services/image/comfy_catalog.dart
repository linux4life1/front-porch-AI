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

import 'comfy_edit_workflow.dart';

/// Files ComfyUI exposes for Image Studio Create / pack discovery.
///
/// Checkpoints live in `models/checkpoints` (A1111-shaped SD piles).
/// Flux / Qwen-Image / Z-Image Turbo live in `models/diffusion_models`
/// and are listed by `UNETLoader.unet_name`, not `CheckpointLoaderSimple`.
class ComfyFileCatalog {
  final List<String> checkpoints;

  /// `UNETLoader` names only. GGUF loaders stay in [ggufUnets] so the older
  /// forms do not list the same file twice.
  final List<String> diffusionModels;
  final List<String> ggufUnets;
  final List<String> textEncoders;
  final List<String> vaes;
  final List<String> loras;

  const ComfyFileCatalog({
    this.checkpoints = const [],
    this.diffusionModels = const [],
    this.ggufUnets = const [],
    this.textEncoders = const [],
    this.vaes = const [],
    this.loras = const [],
  });

  /// Create / pack picker union the older forms already used.
  List<String> get createDiscovery =>
      mergeComfyCreateModels(checkpoints, diffusionModels);

  /// Checkpoints, UNETLoader names, and GGUF unet names, each once.
  List<String> get deskDiscovery =>
      mergeComfyCreateModels(createDiscovery, ggufUnets);
}

/// Builds the catalog the desk and the older forms share.
///
/// [unetNames] is `UNETLoader` only. The two GGUF loaders often list the
/// same folder; they are merged into [ComfyFileCatalog.ggufUnets].
ComfyFileCatalog assembleComfyCatalog({
  required List<String> checkpoints,
  required List<String> unetNames,
  required List<String> ggufNames,
  required List<String> ggufAdvancedNames,
  required List<String> textEncoders,
  required List<String> vaes,
  required List<String> loras,
}) {
  return ComfyFileCatalog(
    checkpoints: checkpoints,
    diffusionModels: unetNames,
    ggufUnets: mergeComfyCreateModels(ggufNames, ggufAdvancedNames),
    textEncoders: textEncoders,
    vaes: vaes,
    loras: loras,
  );
}

/// Deduped checkpoints-then-diffusion_models list. Pure.
List<String> mergeComfyCreateModels(
  List<String> checkpoints,
  List<String> diffusionModels,
) {
  final seen = <String>{};
  final out = <String>[];
  for (final n in [...checkpoints, ...diffusionModels]) {
    if (n.isEmpty || !seen.add(n)) continue;
    out.add(n);
  }
  return out;
}

/// Empty-slot copy that names the Comfy drawer so "this family is empty"
/// is distinct from "you picked the wrong family".
String comfySlotEmptyMessage(ComfyModelSlot slot) {
  if (slot.folderHint.isEmpty) {
    return 'No files found for this slot.';
  }
  return 'No files in Comfy’s ${slot.folderHint} folder. '
      'If your model lives in a different drawer, pick that family above.';
}
