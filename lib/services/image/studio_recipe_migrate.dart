// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'image_gen_lora_slots.dart';
import 'studio_recipe.dart';

const _kPrimaryTokens = ['%MODEL_DIFFUSION%', '%MODEL_CHECKPOINT%'];

const _kKnobKeys = [
  'image_gen_steps',
  'image_gen_cfg_scale',
  'image_gen_sampler',
  'image_gen_scheduler',
  'image_gen_denoise',
  'draw_things_sampler',
  'draw_things_shift',
  'draw_things_seed_mode',
  'image_gen_edit_steps',
  'image_gen_edit_cfg_scale',
  'draw_things_edit_sampler',
  'draw_things_edit_shift',
  'draw_things_edit_seed_mode',
];

/// Reads the legacy image-gen prefs. Does not write, clear, or mutate [prefs].
///
/// An upload is active only when the workflow id is `__uploaded__`. A leftover
/// upload string from an earlier preset does not become the graph.
/// On Comfy the primary file is that workflow's diffusion or checkpoint
/// choice. `image_gen_model` is used only for an `sd` Comfy workflow, or for
/// Draw Things and Automatic1111. There is no stored edit-LoRA list.
StudioRecipe migrateImageStudioRecipe(Map<String, Object?> prefs) {
  String text(String key) => prefs[key]?.toString() ?? '';

  Map<String, String> decodeMap(String key) {
    final raw = text(key);
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Map<String, String> supportFor(String rawKey, String workflowId) {
    final prefix = '$workflowId/';
    final out = <String, String>{};
    decodeMap(rawKey).forEach((key, value) {
      if (!key.startsWith(prefix)) return;
      final token = key.substring(prefix.length);
      if (token.isEmpty) return;
      out[token] = value;
    });
    return out;
  }

  String choice(Map<String, String> support) {
    for (final token in _kPrimaryTokens) {
      final file = support[token];
      if (file != null && file.isNotEmpty) return file;
    }
    return '';
  }

  ({String json, String external}) uploadBody(String id, String raw) {
    if (id != '__uploaded__' || raw.trim().isEmpty) {
      return (json: '', external: '');
    }
    if (utf8.encode(raw).length > kStudioUploadInlineLimit) {
      return (json: '', external: raw);
    }
    return (json: raw, external: '');
  }

  final backend = text('image_gen_backend').isEmpty
      ? 'remote'
      : text('image_gen_backend');
  final comfy = backend == 'comfyui';
  final createId = text('comfy_create_workflow_id').isEmpty
      ? 'sd'
      : text('comfy_create_workflow_id');
  final editId = text('comfy_edit_workflow_id').isEmpty
      ? 'qwen_image_edit'
      : text('comfy_edit_workflow_id');
  final createSupport = supportFor('comfy_create_model_choices', createId);
  final editSupport = supportFor('comfy_edit_model_choices', editId);
  final createUpload = uploadBody(
    createId,
    text('comfy_create_uploaded_workflow'),
  );
  final editUpload = uploadBody(editId, text('comfy_edit_uploaded_workflow'));

  String createPrimary() {
    if (!comfy) return text('image_gen_model');
    final picked = choice(createSupport);
    if (picked.isNotEmpty) return picked;
    if (createId == 'sd') return text('image_gen_model');
    return '';
  }

  String editPrimary() {
    if (!comfy) return text('image_gen_edit_model');
    return choice(editSupport);
  }

  final legacyWeight = prefs['image_gen_lora_weight'];
  final slots = ImageGenLoraSlot.decode(
    text('image_gen_loras').isEmpty ? null : text('image_gen_loras'),
    legacyFile: text('image_gen_lora'),
    legacyWeight: legacyWeight is num
        ? legacyWeight.toDouble()
        : double.tryParse(legacyWeight?.toString() ?? '') ?? 0.8,
  );
  final loras = [
    for (final slot in slots)
      if (!slot.isEmpty) {'file': slot.file, 'weight': slot.weight},
  ];

  final knobs = <String, String>{};
  for (final key in _kKnobKeys) {
    final value = prefs[key];
    if (value == null) continue;
    final asText = value.toString();
    if (asText.isEmpty) continue;
    final mode = key.contains('_edit_') ? 'edit' : 'create';
    final knobBackend = key.startsWith('draw_things_') ? 'drawthings' : backend;
    knobs['$mode/$knobBackend/$key'] = asText;
  }

  return StudioRecipe(
    create: StudioSection(
      workflowId: createId,
      primaryFile: createPrimary(),
      customWorkflow: createId == '__uploaded__',
      support: createSupport,
      uploadedJson: createUpload.json,
      externalUpload: createUpload.external,
      uploadExternal: createUpload.external.isNotEmpty,
    ),
    edit: StudioSection(
      workflowId: editId,
      primaryFile: editPrimary(),
      customWorkflow: editId == '__uploaded__',
      support: editSupport,
      uploadedJson: editUpload.json,
      externalUpload: editUpload.external,
      uploadExternal: editUpload.external.isNotEmpty,
    ),
    backend: backend,
    size: text('image_gen_size').isEmpty ? '1024x1024' : text('image_gen_size'),
    loras: loras,
    knobs: knobs,
    modelRoots: <String, String>{},
  );
}
