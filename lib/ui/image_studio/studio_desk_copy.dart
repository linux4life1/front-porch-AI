// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:front_porch_ai/services/image/comfy_create_presets.dart';
import 'package:front_porch_ai/services/image/comfy_create_workflow.dart';
import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

const String kStudioCreateWell =
    'Start from a picture — optional. A reference here varies the Create '
    'model. It does not switch you to Edit.';

const String kStudioEditWell =
    'Portrait in this chat. Edit sends an instruction with this picture.';

const String kStudioCreatePack =
    'Pack uses this Create model to vary the portrait.';

const String kStudioEditPack = 'Pack uses this edit model.';

const String kStudioDropCopy =
    'Drop a ComfyUI graph, or an image that has one saved inside it.';

const String kStudioDropKind = 'JSON, or a PNG from Comfy’s Save.';

const String kStudioPngReject =
    'That image has no ComfyUI workflow saved inside it.';

const String kStudioFileReject = 'That file isn’t a ComfyUI graph.';

const String kStudioLoraFamilyNote =
    'These files do not set the LoRA family. The text encoder can be Qwen '
    'while the model is Z-Image.';

const String kStudioCheckpointSupport =
    'This checkpoint graph has no text encoder or VAE slot.';

const List<(int, int, String)> kStudioSizeChips = [
  (512, 512, '512×512'),
  (768, 768, '768×768'),
  (1024, 1024, '1024×1024'),
  (1536, 1024, '1536×1024'),
  (1024, 1536, '1024×1536'),
];

String studioBackendName(String backend) {
  switch (backend) {
    case 'comfyui':
      return 'ComfyUI';
    case 'a1111':
      return 'Automatic1111';
    case 'drawthings':
      return 'Draw Things';
    default:
      return 'Remote';
  }
}

String studioSizeNote(int width, int height) =>
    'Sends $width×$height. Each side snaps to a multiple of 64, from 256 to 2048.';

String studioAdvancedSummary({
  required int steps,
  required double cfg,
  required String sampler,
  required String scheduler,
}) => '$steps steps · cfg $cfg · $sampler · $scheduler';

String studioWorkflowWhy({
  required String workflowId,
  required String primaryFile,
  required bool uploaded,
  String uploadedTitle = '',
  int uploadedNodes = 0,
}) {
  if (uploaded) {
    final title = uploadedTitle.trim().isEmpty
        ? 'workflow'
        : uploadedTitle.trim();
    return 'Workflow · your file · $title · $uploadedNodes nodes';
  }
  if (primaryFile.toLowerCase().endsWith('.gguf')) {
    return 'Workflow · GGUF · chosen for this file · $workflowId';
  }
  final task = workflowId == 'qwen_image_edit' || workflowId == 'flux_kontext'
      ? 'Edit'
      : 'Text to image';
  return 'Workflow · $task · $workflowId';
}

String studioReadyLine({required bool ready, String? blockedLora}) {
  if (blockedLora != null && blockedLora.isNotEmpty && !ready) {
    return 'Not ready — LoRA architecture does not match $blockedLora.';
  }
  if (ready) return 'Ready to generate.';
  return 'Not ready.';
}

String studioLoraBadge(LoraCompat compat) {
  switch (compat) {
    case LoraCompat.match:
      return 'match';
    case LoraCompat.certain:
      return 'other base';
    case LoraCompat.likely:
    case LoraCompat.unknown:
      return 'likely';
  }
}

const String kStudioLoraFactsKey = 'image_studio_lora_facts';

Map<String, DeskLoraCheck> storedLoraFacts(ImageGenSettings settings) {
  final raw = settings.prefs?.getString(settings.k(kStudioLoraFactsKey));
  if (raw == null || raw.isEmpty) return const {};
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return const {};
  final out = <String, DeskLoraCheck>{};
  for (final entry in decoded.entries) {
    final value = entry.value;
    if (value is! Map) continue;
    final familyName = value['family']?.toString() ?? '';
    final family = ModelFamily.values.asNameMap()[familyName];
    if (family == null) continue;
    out[entry.key.toString()] = DeskLoraCheck(
      entry.key.toString(),
      family,
      metadataBacked: value['meta'] == true,
    );
  }
  return out;
}

Future<void> saveLoraFacts(
  ImageGenSettings settings,
  List<DeskLoraCheck> checks,
) async {
  final body = {
    for (final row in checks)
      row.file: {'family': row.family.name, 'meta': row.metadataBacked},
  };
  await settings.prefs?.setString(
    settings.k(kStudioLoraFactsKey),
    jsonEncode(body),
  );
  settings.notify();
}

/// A text encoder or VAE the graph loads besides the diffusion file.
class StudioSupportRow {
  final String role;
  final String token;
  final String file;

  const StudioSupportRow(this.role, this.token, this.file);
}

/// Support files for a known preset. An empty list with [checkpointOnly]
/// is a checkpoint graph: it has no text-encoder or VAE slot.
({bool checkpointOnly, List<StudioSupportRow> rows}) studioSupport({
  required bool edit,
  required String workflowId,
  required Map<String, String> choices,
}) {
  final slots = edit
      ? comfyEditPresetById(workflowId)?.modelSlots
      : comfyCreatePresetById(workflowId)?.modelSlots;
  if (slots == null) {
    return (checkpointOnly: false, rows: const <StudioSupportRow>[]);
  }
  final rows = <StudioSupportRow>[
    for (final slot in slots)
      if (slot.token != '%MODEL_DIFFUSION%' &&
          slot.token != kComfyCheckpointToken)
        StudioSupportRow(
          slot.label,
          slot.token,
          (choices['$workflowId/${slot.token}'] ?? '').trim(),
        ),
  ];
  return (checkpointOnly: rows.isEmpty, rows: rows);
}

/// Short quant mark for a model row. Empty when the name has none.
String studioQuantBadge(String file) {
  final lower = file.toLowerCase();
  if (lower.endsWith('.gguf')) {
    final mark = RegExp(
      r'q\d[a-z0-9_]*',
      caseSensitive: false,
    ).firstMatch(file);
    return mark?.group(0) ?? 'gguf';
  }
  for (final tag in ['bf16', 'fp16', 'fp8', 'int8', 'int4', 'nf4']) {
    if (lower.contains(tag)) return tag;
  }
  return '';
}
