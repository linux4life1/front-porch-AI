// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'comfy_edit_workflow.dart';
import 'comfy_template_index.dart';
import 'model_family.dart';

enum StudioReady {
  ready,
  missingFile,
  missingNodeClass,
  unreachable,
  loraMismatch,
  needsUnetGraph,

  /// The graph needs a ComfyUI-GGUF loader update that has not been done
  /// (see `City96Gate`). Only that model is held back; [StudioReadiness.message]
  /// says why.
  needsLoaderUpdate,

  /// The loader was updated, but the ComfyUI that is running started before
  /// that and has not loaded it. [StudioReadiness.message] says to restart.
  needsComfyRestart,
}

/// [objectInfo] null means the server could not be read.
class StudioReadiness {
  final StudioReady kind;
  final String? missingClass;

  /// The words for [StudioReady.needsLoaderUpdate].
  final String? message;

  /// The graph this verdict judged, as it would be posted. Set on Comfy when
  /// the graph resolved.
  final Map<String, dynamic>? graph;

  /// The model files this graph loads, in the order it lists them. Set on
  /// Comfy once the graph resolved, even when the verdict is not Ready, so a
  /// slot that is still empty can be filled. Empty for an uploaded graph,
  /// whose files are named inside it.
  final List<ComfyModelSlot> slots;

  /// For [StudioReady.needsLoaderUpdate]: the person can allow the update from
  /// the desk ("Update loader…"). False when it cannot be changed at all
  /// (another computer, an unrecognised or unsafe loader).
  final bool canUpdateLoader;

  /// The `%TOKEN%` inputs the graph takes (`%SHIFT%`, `%SEED%`, ...). Empty
  /// for an uploaded graph, which is posted as it is. A control whose token
  /// is missing here would change nothing.
  final Set<String> tokens;

  const StudioReadiness(
    this.kind, [
    this.missingClass,
    this.message,
    this.graph,
    this.slots = const [],
    this.canUpdateLoader = false,
    this.tokens = const {},
  ]);
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

/// An edit row is edit-only. A title that is both tasks is neither list.
bool isEditTemplateTitle(String title) {
  final create = _hasTag(title, kComfyCreateTags);
  final edit = _hasTag(title, kComfyEditTags);
  return edit && !create;
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
