// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'comfy_model_paths.dart';

/// Comfy's YAML folder names that hold weights, and the slot folder each one
/// is. `unet` and `clip` are Comfy's older names for the same folders.
const Map<String, String> _kTypeKeys = {
  'checkpoints': 'checkpoints',
  'diffusion_models': 'diffusion_models',
  'unet': 'diffusion_models',
  'loras': 'loras',
  'vae': 'vae',
  'text_encoders': 'text_encoders',
  'clip': 'text_encoders',
  'embeddings': 'embeddings',
};

/// Where each kind of weight lives for one YAML block, as absolute folders
/// keyed by slot folder name (`checkpoints`, `loras`...). A block can send
/// each kind to a different drive; those folders must not be collapsed into
/// one models folder. The first path listed for a kind is Comfy's first
/// choice. A newer name (`diffusion_models`) wins over its older alias.
Map<String, String> comfyTypeFolders({
  required ComfyModelConfig config,
  required String yamlDir,
  required String home,
}) {
  final base = resolveComfyYamlPath(config.basePath, '', yamlDir, home);
  final out = <String, String>{};
  final fromAlias = <String>{};
  for (final entry in config.folders.entries) {
    final slot = _kTypeKeys[entry.key.trim().toLowerCase()];
    if (slot == null || entry.value.isEmpty) continue;
    final abs = resolveComfyYamlPath(entry.value.first, base, yamlDir, home);
    if (abs.isEmpty) continue;
    final alias = entry.key.trim().toLowerCase() != slot;
    if (out.containsKey(slot) && (alias || !fromAlias.contains(slot))) {
      continue;
    }
    out[slot] = abs;
    if (alias) {
      fromAlias.add(slot);
    } else {
      fromAlias.remove(slot);
    }
  }
  return out;
}
