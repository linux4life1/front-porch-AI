// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

/// Graphs larger than this stay out of the prefs blob.
const int kStudioUploadInlineLimit = 512 * 1024;

/// One Create or Edit section of the studio recipe.
class StudioSection {
  final String workflowId;
  final String primaryFile;

  /// True only when [workflowId] is `__uploaded__`.
  final bool customWorkflow;
  final Map<String, String> support;

  /// In-blob graph. Empty when [uploadExternal] is true.
  final String uploadedJson;

  /// Body that must be written beside the library. Not part of [encode].
  final String externalUpload;

  /// The graph lives in `image_studio/custom_*.json`, not in the blob.
  final bool uploadExternal;

  /// Stem chosen on the previous resolve. Empty on a first migration.
  final String previousWorkflowId;

  const StudioSection({
    required this.workflowId,
    required this.primaryFile,
    required this.customWorkflow,
    required this.support,
    this.uploadedJson = '',
    this.externalUpload = '',
    this.uploadExternal = false,
    this.previousWorkflowId = '',
  });

  Map<String, dynamic> toJson() => {
    'workflowId': workflowId,
    'primaryFile': primaryFile,
    'customWorkflow': customWorkflow,
    'support': support,
    'uploadedJson': uploadedJson,
    'uploadExternal': uploadExternal,
    'previousWorkflowId': previousWorkflowId,
  };

  factory StudioSection.fromJson(Map<String, dynamic> json) {
    final id = json['workflowId']?.toString() ?? '';
    final support = <String, String>{};
    final raw = json['support'];
    if (raw is Map) {
      raw.forEach((k, v) => support[k.toString()] = v.toString());
    }
    return StudioSection(
      workflowId: id,
      primaryFile: json['primaryFile']?.toString() ?? '',
      customWorkflow: id == '__uploaded__',
      support: support,
      uploadedJson: json['uploadedJson']?.toString() ?? '',
      uploadExternal: json['uploadExternal'] == true,
      previousWorkflowId: json['previousWorkflowId']?.toString() ?? '',
    );
  }
}

/// Saved studio settings. Legacy prefs stay where they are.
class StudioRecipe {
  final StudioSection create;
  final StudioSection edit;
  final String backend;
  final String size;
  final List<Map<String, dynamic>> loras;
  final Map<String, String> knobs;
  final Map<String, String> modelRoots;

  StudioRecipe({
    required this.create,
    required this.edit,
    required this.backend,
    required this.size,
    required this.loras,
    required this.knobs,
    required this.modelRoots,
  });

  Map<String, dynamic> toJson() => {
    'create': create.toJson(),
    'edit': edit.toJson(),
    'backend': backend,
    'size': size,
    'loras': loras,
    'knobs': knobs,
    'modelRoots': modelRoots,
  };

  factory StudioRecipe.fromJson(Map<String, dynamic> json) {
    Map<String, String> strings(Object? raw) {
      final out = <String, String>{};
      if (raw is Map) {
        raw.forEach((k, v) => out[k.toString()] = v.toString());
      }
      return out;
    }

    final loras = <Map<String, dynamic>>[];
    final rawLoras = json['loras'];
    if (rawLoras is List) {
      for (final row in rawLoras) {
        if (row is Map) {
          loras.add(row.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
    }
    return StudioRecipe(
      create: StudioSection.fromJson(
        (json['create'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      edit: StudioSection.fromJson(
        (json['edit'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      backend: json['backend']?.toString() ?? 'remote',
      size: json['size']?.toString() ?? '1024x1024',
      loras: loras,
      knobs: strings(json['knobs']),
      modelRoots: strings(json['modelRoots']),
    );
  }

  String encode() => jsonEncode(toJson());

  factory StudioRecipe.decode(String raw) =>
      StudioRecipe.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
}

/// Nearest multiple of 64, each side clamped to 256–2048.
({int width, int height}) snapStudioSize(int width, int height) {
  int snap(int n) {
    final x = (n / 64).round() * 64;
    if (x < 256) return 256;
    if (x > 2048) return 2048;
    return x;
  }

  return (width: snap(width), height: snap(height));
}
