// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'comfy_template_index.dart';
import 'model_family.dart';

enum StudioReady { ready, missingFile, missingNodeClass, unreachable }

/// [objectInfo] null means the server could not be read.
class StudioReadiness {
  final StudioReady kind;
  final String? missingClass;

  const StudioReadiness(this.kind, [this.missingClass]);
}

StudioReadiness studioReady({
  required Map<String, dynamic>? objectInfo,
  required List<String> requiredClasses,
  required Map<String, String> files,
  String? missingClass,
}) {
  if (objectInfo == null) return const StudioReadiness(StudioReady.unreachable);
  if (missingClass != null && missingClass.isNotEmpty) {
    return StudioReadiness(StudioReady.missingNodeClass, missingClass);
  }
  for (final name in requiredClasses) {
    if (!objectInfo.containsKey(name)) {
      return StudioReadiness(StudioReady.missingNodeClass, name);
    }
  }
  for (final file in files.values) {
    if (file.trim().isEmpty) {
      return const StudioReadiness(StudioReady.missingFile);
    }
  }
  return const StudioReadiness(StudioReady.ready);
}

bool generateEnabled(StudioReadiness ready) => ready.kind == StudioReady.ready;

/// The LoRA family is the diffusion or checkpoint file, never the text encoder.
ModelFamily familyForRun({
  required String primaryFile,
  required String textEncoder,
}) {
  return ImageModelFamily.detectFromName(primaryFile);
}

/// A title that is both text-to-image and image-edit is not a Create row.
bool _hasTag(String title, Set<String> tags) {
  final text = title.toLowerCase();
  for (final tag in tags) {
    if (text.contains(tag)) return true;
  }
  return false;
}

bool isCreateTemplateTitle(String title) {
  final create = _hasTag(title, kComfyCreateTags);
  final edit = _hasTag(title, kComfyEditTags);
  return create && !edit;
}

/// PNG text chunks. Null when neither chunk is JSON.
String? pngWorkflowText(Map<String, String> texts) {
  for (final key in ['prompt', 'workflow']) {
    final raw = texts[key];
    if (raw == null || raw.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return raw;
    } catch (_) {}
  }
  return null;
}
