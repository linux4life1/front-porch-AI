// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'comfy_edit_workflow.dart';
import 'comfy_create_workflow.dart';
import 'comfy_edit_presets.dart';
import 'comfy_gguf_loaders.dart';
import 'studio_desk_logic.dart';

/// A saved, template or legacy `comfy:*` pick, or an uploaded graph. The desk
/// never swaps one of these for a bundled family graph: the person chose it.
bool deskKeepsWorkflow(String workflowId) =>
    workflowId.startsWith('comfy:') || workflowId == kComfyUploadedWorkflowId;

/// The token that holds the diffusion or checkpoint file of the graph whose
/// [slots] are known. A GGUF file goes to a diffusion slot, another file to
/// the checkpoint slot when the graph has one. Without slots it falls back to
/// [deskComfyToken].
String deskPrimaryToken({
  required String workflowId,
  required String file,
  List<ComfyModelSlot> slots = const [],
}) {
  var diffusion = false;
  var checkpoint = false;
  for (final slot in slots) {
    if (slot.token == '%MODEL_DIFFUSION%') diffusion = true;
    if (slot.token == kComfyCheckpointToken) checkpoint = true;
  }
  if (diffusion && checkpoint) {
    return isGgufFile(file) ? '%MODEL_DIFFUSION%' : kComfyCheckpointToken;
  }
  if (checkpoint) return kComfyCheckpointToken;
  if (diffusion) return '%MODEL_DIFFUSION%';
  return deskComfyToken(workflowId: workflowId, file: file);
}
