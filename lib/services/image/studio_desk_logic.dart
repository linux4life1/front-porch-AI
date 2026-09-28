// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

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

/// The bundled graph for this file. A GGUF name never stays on the
/// checkpoint graph, which cannot load it.
String workflowForModel({required bool edit, required String file}) {
  final family = ImageModelFamily.detectFromName(file);
  final gguf = isGgufFile(file);
  if (edit) {
    if (family == ModelFamily.flux || family == ModelFamily.kontext) {
      return 'flux_kontext';
    }
    return 'qwen_image_edit';
  }
  switch (family) {
    case ModelFamily.zImage:
      return 'z_image_turbo';
    case ModelFamily.flux:
    case ModelFamily.kontext:
      return 'flux';
    case ModelFamily.qwen:
      return 'qwen_image';
    case ModelFamily.sd15:
    case ModelFamily.sdxl:
    case ModelFamily.pony:
    case ModelFamily.sd3:
    case ModelFamily.unknown:
      return gguf ? 'z_image_turbo' : 'sd';
  }
}

/// Which choice token a picked Comfy file belongs in.
String deskComfyToken({required String workflowId, required String file}) {
  final gguf = file.toLowerCase().endsWith('.gguf');
  if (!gguf && workflowId == 'sd') return '%MODEL_CHECKPOINT%';
  return '%MODEL_DIFFUSION%';
}

String? deskLoraBlocker(String primaryFile, List<DeskLoraCheck> loras) {
  final checkpoint = ImageModelFamily.detectFromName(primaryFile);
  for (final lora in loras) {
    if (lora.file.trim().isEmpty) continue;
    final compat = ImageModelFamily.compatibility(
      lora.family,
      checkpoint,
      metadataBacked: lora.metadataBacked,
    );
    if (compat == LoraCompat.certain) return lora.file;
  }
  return null;
}

bool deskLoraBlocks(String primaryFile, List<DeskLoraCheck> loras) =>
    deskLoraBlocker(primaryFile, loras) != null;

/// Metadata when Comfy can read it. A name-only guess never blocks.
Future<List<DeskLoraCheck>> deskLoraChecks({
  required ImageGenSettings settings,
  ComfyUiService? comfy,
}) async {
  final out = <DeskLoraCheck>[];
  for (final slot in settings.imageGenLoraSlots) {
    final file = slot.file.trim();
    if (file.isEmpty) continue;
    if (comfy == null) {
      out.add(DeskLoraCheck(file, ImageModelFamily.detectFromName(file)));
      continue;
    }
    final meta = await comfy.fetchLoraMetadata(file);
    final option = ImageModelFamily.classifyLora(
      file,
      metadata: meta.isEmpty ? null : meta,
    );
    out.add(
      DeskLoraCheck(
        file,
        option.family,
        metadataBacked: option.familyFromMetadata,
      ),
    );
  }
  return out;
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
  bool allowLoraMismatch = false,
}) {
  if (backend != 'comfyui') {
    if (primaryFile.trim().isEmpty) {
      return const StudioReadiness(StudioReady.missingFile);
    }
    if (!allowLoraMismatch && deskLoraBlocks(primaryFile, loras)) {
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
  if (!allowLoraMismatch && deskLoraBlocks(primaryFile, loras)) {
    return const StudioReadiness(StudioReady.loraMismatch);
  }
  return const StudioReadiness(StudioReady.ready);
}
