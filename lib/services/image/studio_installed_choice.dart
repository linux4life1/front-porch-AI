// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

import 'studio_desk_logic.dart';

/// A finished CivitAI file is selected only when this workflow can load it.
bool deskAcceptsInstalledFile({
  required String backend,
  required String workflowId,
  required String file,
  required bool lora,
  required List<String> checkpoints,
  required List<String> diffusionModels,
  required List<String> ggufUnets,
  required List<String> loras,
}) {
  if (lora) return loras.contains(file);
  if (backend != 'comfyui') return file.trim().isNotEmpty;
  final name = file.trim();
  if (name.isEmpty) return false;
  final gguf = name.toLowerCase().endsWith('.gguf');
  if (gguf) {
    if (workflowId == 'sd') return false;
    return ggufUnets.contains(name) || diffusionModels.contains(name);
  }
  final checkpoint = checkpoints.contains(name);
  final diffusion = diffusionModels.contains(name);
  if (checkpoint && !diffusion && workflowId != 'sd') return false;
  return checkpoint || diffusion;
}

/// What the desk should do with a file that just finished downloading.
///
/// This is the desktop install rule: Comfy selects only a file the live
/// loader list can run on this workflow. Automatic1111 selects a model
/// by name. A LoRA is selected only when that list contains it.
class InstalledDeskChoice {
  final bool accept;
  final String kind;
  final String token;
  final int slot;

  const InstalledDeskChoice({
    required this.accept,
    this.kind = '',
    this.token = '',
    this.slot = -1,
  });

  Map<String, Object?> toJson(String workflowId) => {
    'accept': accept,
    'kind': kind,
    if (token.isNotEmpty) 'token': token,
    if (slot >= 0) 'slot': slot,
    if (accept && kind == 'comfy') 'workflowId': workflowId,
  };
}

int _firstEmptyLoraSlot(List<String> files) {
  for (var i = 0; i < files.length; i++) {
    if (files[i].trim().isEmpty) return i;
  }
  return -1;
}

InstalledDeskChoice installedDeskChoice({
  required String backend,
  required String workflowId,
  required String file,
  required bool lora,
  required List<String> checkpoints,
  required List<String> diffusionModels,
  required List<String> ggufUnets,
  required List<String> loras,
  required List<String> loraSlotFiles,
}) {
  final accepted = deskAcceptsInstalledFile(
    backend: backend,
    workflowId: workflowId,
    file: file,
    lora: lora,
    checkpoints: checkpoints,
    diffusionModels: diffusionModels,
    ggufUnets: ggufUnets,
    loras: loras,
  );
  if (!accepted) return const InstalledDeskChoice(accept: false);
  if (lora) {
    final slot = _firstEmptyLoraSlot(loraSlotFiles);
    if (slot < 0) {
      return const InstalledDeskChoice(accept: false, kind: 'lora-full');
    }
    return InstalledDeskChoice(accept: true, kind: 'lora', slot: slot);
  }
  if (backend == 'comfyui') {
    return InstalledDeskChoice(
      accept: true,
      kind: 'comfy',
      token: deskComfyToken(workflowId: workflowId, file: file),
    );
  }
  return const InstalledDeskChoice(accept: true, kind: 'slot');
}

/// Writes an accepted download onto the desk. A LoRA fills an empty slot.
/// It does not replace the model.
Future<void> applyInstalledDeskChoice({
  required ImageGenSettings settings,
  required InstalledDeskChoice choice,
  required String workflowId,
  required String file,
  required bool edit,
}) async {
  if (!choice.accept) return;
  if (choice.kind == 'lora') {
    await settings.setImageGenLoraSlot(choice.slot, file: file);
    return;
  }
  if (choice.kind == 'comfy') {
    if (edit) {
      await settings.setComfyEditModelChoice(workflowId, choice.token, file);
    } else {
      await settings.setComfyCreateModelChoice(workflowId, choice.token, file);
    }
    return;
  }
  if (choice.kind == 'slot') {
    if (edit) {
      await settings.setImageGenEditModel(file);
    } else {
      await settings.setImageGenModel(file);
    }
  }
}
