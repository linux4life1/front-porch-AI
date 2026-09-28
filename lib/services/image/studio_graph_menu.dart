// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/comfy_create_presets.dart';
import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';
import 'package:front_porch_ai/services/image/comfy_template_index.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/image/studio_readiness.dart';
import 'package:front_porch_ai/utils/png_metadata_utils.dart';

/// One row in Change graph. [title] is what a person reads. [id] is what
/// the desk stores. [detail] says where the row came from.
class DeskGraphChoice {
  final String id;
  final String title;
  final String detail;
  final String group;

  const DeskGraphChoice({
    required this.id,
    required this.title,
    required this.detail,
    required this.group,
  });
}

/// A stored id or a bare stem is not a title. Spaces stay as written.
String readableGraphTitle(String id, String title) {
  final clean = title.trim();
  final stem = id.split(':').last.split('/').last.replaceAll('.json', '');
  final raw = clean.isEmpty || clean == id || clean.startsWith('comfy:')
      ? stem
      : clean;
  if (raw.contains(' ')) return raw;
  return raw.replaceAll('_', ' ');
}

/// True when a saved workflow is an edit: it loads a picture and then
/// encodes that picture (an edit encoder, a reference latent, Kontext,
/// or a VAE encode). A graph that only makes a new picture is Create.
bool savedGraphIsEdit(Map<String, dynamic> graph) {
  final types = <String>{};
  void take(Object? node) {
    if (node is! Map) return;
    final type = node['class_type'] ?? node['type'];
    if (type is String && type.isNotEmpty) types.add(type);
  }

  for (final node in graph.values) {
    take(node);
  }
  final nodes = graph['nodes'];
  if (nodes is List) {
    for (final node in nodes) {
      take(node);
    }
  }
  final loads = types.contains('LoadImage') || types.contains('LoadImageMask');
  if (!loads) return false;
  for (final type in types) {
    if (type.contains('ImageEdit') ||
        type.contains('Kontext') ||
        type == 'ReferenceLatent') {
      return true;
    }
  }
  return false;
}

/// Built-in graphs, then this mode's Comfy templates, then saved
/// workflows already classified for this mode. [unread] files could
/// not be opened, so they are not offered as either mode.
List<DeskGraphChoice> deskGraphMenu({
  required bool edit,
  required List<DeskGraphRow> templates,
  required List<DeskGraphRow> saved,
  List<DeskGraphRow> unread = const [],
}) {
  final built = edit ? 'Edit graphs' : 'Text to image graphs';
  final bundled = <DeskGraphChoice>[
    if (edit)
      for (final preset in kComfyEditPresets)
        DeskGraphChoice(
          id: preset.id,
          title: preset.label,
          detail: 'Built into Front Porch',
          group: built,
        )
    else
      for (final preset in kComfyCreatePresets)
        DeskGraphChoice(
          id: preset.id,
          title: preset.label,
          detail: 'Built into Front Porch',
          group: built,
        ),
  ];
  final seen = {for (final row in bundled) row.id};
  final fromComfy = <DeskGraphChoice>[];
  for (final row in templates) {
    if (row.id.isEmpty || !seen.add(row.id)) continue;
    fromComfy.add(
      DeskGraphChoice(
        id: row.id,
        title: readableGraphTitle(row.id, row.title),
        detail: 'Comfy template',
        group: 'From this Comfy',
      ),
    );
  }
  final onDisk = <DeskGraphChoice>[];
  for (final row in saved) {
    if (row.id.isEmpty || !seen.add(row.id)) continue;
    onDisk.add(
      DeskGraphChoice(
        id: row.id,
        title: readableGraphTitle(row.id, row.title),
        detail: 'Saved on this Comfy',
        group: 'Saved on this Comfy',
      ),
    );
  }
  final closed = <DeskGraphChoice>[];
  for (final row in unread) {
    if (row.id.isEmpty || !seen.add(row.id)) continue;
    closed.add(
      DeskGraphChoice(
        id: row.id,
        title: readableGraphTitle(row.id, row.title),
        detail:
            'Could not read this file, so it is not a Create or Edit graph.',
        group: 'Could not read',
      ),
    );
  }
  return [...bundled, ...fromComfy, ...onDisk, ...closed];
}

/// Templates plus saved workflows for one mode. A saved edit graph is
/// left off the Create list, and the reverse.
Future<List<DeskGraphChoice>> loadDeskGraphMenu({
  required ComfyUiService comfy,
  required bool edit,
  required List<ComfyTemplateEntry> templates,
  required List<ComfyTemplateEntry> saved,
}) async {
  final savedRows = <DeskGraphRow>[];
  final unread = <DeskGraphRow>[];
  for (final file in saved) {
    final json = await comfy.fetchTemplateJson(file.name, preferUserdata: true);
    if (json == null) {
      unread.add(DeskGraphRow(file.pickerId, file.title));
      continue;
    }
    if (savedGraphIsEdit(json) != edit) continue;
    savedRows.add(DeskGraphRow(file.pickerId, file.title));
  }
  return deskGraphMenu(
    edit: edit,
    templates: [
      for (final row in templates) DeskGraphRow(row.pickerId, row.title),
    ],
    saved: savedRows,
    unread: unread,
  );
}

/// JSON workflow text from a `.json` file or from a PNG Comfy saved.
/// Null when the bytes are neither.
String? workflowJsonFromBytes(List<int> bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71) {
    final prompt = PngMetadataUtils.extractTextChunk(bytes, 'prompt');
    final workflow = PngMetadataUtils.extractTextChunk(bytes, 'workflow');
    return pngWorkflowText({'prompt': ?prompt, 'workflow': ?workflow});
  }
  final text = utf8.decode(bytes, allowMalformed: true).trim();
  return pngWorkflowText({'prompt': text});
}

/// `edit` when the shipped rule files it as an edit, `create` when it
/// is a picture-making graph, `unstated` when it names neither.
String deskGraphStance(String json) {
  Map<String, dynamic>? graph;
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      graph = decoded.map((key, value) => MapEntry('$key', value));
    }
  } catch (_) {
    return 'unstated';
  }
  if (graph == null) return 'unstated';
  if (savedGraphIsEdit(graph)) return 'edit';
  final types = <String>{};
  void take(Object? node) {
    if (node is! Map) return;
    final type = node['class_type'] ?? node['type'];
    if (type is String && type.isNotEmpty) types.add(type);
  }

  for (final node in graph.values) {
    take(node);
  }
  final nodes = graph['nodes'];
  if (nodes is List) {
    for (final node in nodes) {
      take(node);
    }
  }
  const marks = {
    'KSampler',
    'EmptyLatentImage',
    'EmptySD3LatentImage',
    'UNETLoader',
    'UnetLoaderGGUF',
    'CheckpointLoaderSimple',
    'VAEDecode',
  };
  if (types.any(marks.contains)) return 'create';
  return 'unstated';
}

/// How many nodes the stored workflow JSON describes. Zero when it is
/// not a graph.
int workflowNodeCount(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map) return 0;
  final nodes = decoded['nodes'];
  if (nodes is List) return nodes.length;
  var count = 0;
  for (final value in decoded.values) {
    if (value is Map && value.containsKey('class_type')) count++;
  }
  return count;
}
