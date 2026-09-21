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
  final List<String> diffusionModels;
  final List<String> textEncoders;
  final List<String> vaes;
  final List<String> loras;

  const ComfyFileCatalog({
    this.checkpoints = const [],
    this.diffusionModels = const [],
    this.textEncoders = const [],
    this.vaes = const [],
    this.loras = const [],
  });

  /// Create / pack picker union — ZIT and friends appear here.
  List<String> get createDiscovery =>
      mergeComfyCreateModels(checkpoints, diffusionModels);
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
