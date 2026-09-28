// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'comfy_create_presets.dart';
import 'comfy_create_workflow.dart';
import 'comfy_edit_presets.dart';
import 'comfy_edit_workflow.dart';
import 'comfy_gguf_loaders.dart';
import 'comfy_workflow_adapt.dart';
import 'comfy_workflow_convert.dart';
import 'model_family.dart';
import 'studio_readiness.dart';

/// The file this run actually loads. On ComfyUI that is the workflow slot,
/// not a leftover `image_gen_model` from another family.
String deskPrimaryFile({
  required String backend,
  required bool edit,
  required String workflowId,
  required Map<String, String> choices,
  required String legacyModel,
}) {
  if (backend != 'comfyui') return legacyModel.trim();
  final diffusion = (choices['$workflowId/%MODEL_DIFFUSION%'] ?? '').trim();
  if (diffusion.isNotEmpty) return diffusion;
  final checkpoint = (choices['$workflowId/%MODEL_CHECKPOINT%'] ?? '').trim();
  if (checkpoint.isNotEmpty) return checkpoint;
  if (!edit && workflowId == 'sd') return legacyModel.trim();
  return '';
}

/// One filled LoRA slot checked against the file that will actually load.
class DeskLoraCheck {
  final String file;
  final ModelFamily family;
  final bool metadataBacked;

  const DeskLoraCheck(this.file, this.family, {this.metadataBacked = false});
}

/// A graph row the desk may offer. A title that is both tasks is omitted.
class DeskGraphRow {
  final String id;
  final String title;

  const DeskGraphRow(this.id, this.title);
}

/// True when [title] belongs on the Create or Edit graph list.
bool deskOffersGraphTitle(String title, {required bool edit}) {
  if (edit) return isEditTemplateTitle(title);
  return isCreateTemplateTitle(title);
}

/// Bundled graphs for this mode, plus live rows whose title matches it.
List<String> deskGraphChoices({
  required bool edit,
  required List<DeskGraphRow> live,
}) {
  final bundled = edit
      ? [for (final preset in kComfyEditPresets) preset.id]
      : const ['sd', 'z_image_turbo', 'flux', 'qwen_image'];
  final seen = bundled.toSet();
  final out = <String>[...bundled];
  for (final row in live) {
    if (!deskOffersGraphTitle(row.title, edit: edit)) continue;
    if (row.id.isEmpty || !seen.add(row.id)) continue;
    out.add(row.id);
  }
  return out;
}

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

/// Which choice token a picked Comfy file belongs in.
String deskComfyToken({required String workflowId, required String file}) {
  final gguf = file.toLowerCase().endsWith('.gguf');
  if (!gguf && workflowId == 'sd') return '%MODEL_CHECKPOINT%';
  return '%MODEL_DIFFUSION%';
}

bool deskLoraBlocks(String primaryFile, List<DeskLoraCheck> loras) {
  final checkpoint = ImageModelFamily.detectFromName(primaryFile);
  for (final lora in loras) {
    if (lora.file.trim().isEmpty) continue;
    final compat = ImageModelFamily.compatibility(
      lora.family,
      checkpoint,
      metadataBacked: lora.metadataBacked,
    );
    if (compat == LoraCompat.certain) return true;
  }
  return false;
}

Map<String, dynamic>? _deskGraph({
  required bool edit,
  required String workflowId,
  required String uploadedWorkflowJson,
  Map<String, dynamic>? liveTemplate,
}) {
  if (edit && workflowId != kComfyUploadedWorkflowId) {
    if (liveTemplate != null && liveTemplate.isNotEmpty) return liveTemplate;
    return comfyEditPresetById(workflowId)?.template;
  }
  return loadComfyCreateSource(
    workflowId: workflowId,
    uploadedWorkflowJson: uploadedWorkflowJson,
    liveTemplate: liveTemplate,
  );
}

Map<String, dynamic> _graphWithChoices({
  required Map<String, dynamic> api,
  required String workflowId,
  required Map<String, String> modelChoices,
  required String primaryFile,
  required bool edit,
}) {
  final adapted = adaptComfyApiWorkflow(api);
  final values = <String, Object?>{};
  for (final slot in adapted.slots) {
    final file = (modelChoices['$workflowId/${slot.token}'] ?? '').trim();
    if (file.isNotEmpty) values[slot.token] = file;
  }
  if (!edit && workflowId == 'sd') {
    final checkpoint = primaryFile.trim();
    if (checkpoint.isNotEmpty) {
      values.putIfAbsent(kComfyCheckpointToken, () => checkpoint);
    }
  }
  return substituteComfyWorkflow(adapted.template, values);
}

String? _firstMissingClass(
  Map<String, dynamic> graph,
  Map<String, dynamic> objectInfo,
) {
  for (final node in graph.values) {
    if (node is! Map) continue;
    final type = node['class_type']?.toString() ?? '';
    if (type.isEmpty) continue;
    if (!objectInfo.containsKey(type)) return type;
  }
  return null;
}

/// Readiness for the graph that will actually be submitted.
///
/// An uploaded graph is not retargeted. A missing `/object_info` is
/// unreachable. An empty required slot stays off.
StudioReadiness deskReadiness({
  required String backend,
  required String primaryFile,
  required Map<String, dynamic>? objectInfo,
  bool edit = false,
  String workflowId = '',
  String uploadedWorkflowJson = '',
  Map<String, String> modelChoices = const {},
  Map<String, dynamic>? liveTemplate,
  List<DeskLoraCheck> loras = const [],
}) {
  if (backend != 'comfyui') {
    if (primaryFile.trim().isEmpty) {
      return const StudioReadiness(StudioReady.missingFile);
    }
    if (deskLoraBlocks(primaryFile, loras)) {
      return const StudioReadiness(StudioReady.loraMismatch);
    }
    return const StudioReadiness(StudioReady.ready);
  }
  if (objectInfo == null) {
    return const StudioReadiness(StudioReady.unreachable);
  }
  final source = _deskGraph(
    edit: edit,
    workflowId: workflowId,
    uploadedWorkflowJson: uploadedWorkflowJson,
    liveTemplate: liveTemplate,
  );
  if (source == null || source.isEmpty) {
    return const StudioReadiness(StudioReady.missingFile);
  }
  final api = ensureComfyApiGraph(source, objectInfo: objectInfo);
  if (api == null) {
    return const StudioReadiness(StudioReady.missingFile);
  }
  final uploaded = workflowId == kComfyUploadedWorkflowId;
  final graph = uploaded
      ? api
      : _graphWithChoices(
          api: api,
          workflowId: workflowId,
          modelChoices: modelChoices,
          primaryFile: primaryFile,
          edit: edit,
        );
  final retarget = retargetForFile(
    graph: graph,
    primaryFile: primaryFile,
    uploaded: uploaded,
    objectInfo: objectInfo,
  );
  if (retarget.unreachable) {
    return const StudioReadiness(StudioReady.unreachable);
  }
  if (!uploaded && retarget.useUnetStarter) {
    return const StudioReadiness(StudioReady.needsUnetGraph);
  }
  final missingLoader = retarget.missingClass;
  if (missingLoader != null && missingLoader.isNotEmpty) {
    return StudioReadiness(StudioReady.missingNodeClass, missingLoader);
  }
  final missing = _firstMissingClass(retarget.graph, objectInfo);
  if (missing != null) {
    return StudioReadiness(StudioReady.missingNodeClass, missing);
  }
  final filled = edit
      ? comfyEditReady(
          workflowId: workflowId,
          uploadedWorkflowJson: uploadedWorkflowJson,
          modelChoices: modelChoices,
          liveTemplate: liveTemplate,
        )
      : comfyCreateReady(
          workflowId: workflowId,
          uploadedWorkflowJson: uploadedWorkflowJson,
          modelChoices: modelChoices,
          checkpointFallback: workflowId == 'sd' ? primaryFile : '',
          liveTemplate: liveTemplate,
        );
  if (!filled) return const StudioReadiness(StudioReady.missingFile);
  if (deskLoraBlocks(primaryFile, loras)) {
    return const StudioReadiness(StudioReady.loraMismatch);
  }
  return const StudioReadiness(StudioReady.ready);
}
