// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/utils/utils.dart';

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

/// Every node class a workflow uses, including the nodes inside subgraphs.
/// A UI-format workflow keeps subgraph contents under
/// `definitions.subgraphs`; the top level then only shows the subgraph as one
/// node, so an edit graph wrapped in one would otherwise read as Create.
Set<String> workflowNodeTypes(Map<String, dynamic> graph) {
  final types = <String>{};
  void take(Object? node) {
    if (node is! Map) return;
    final type = node['class_type'] ?? node['type'];
    if (type is String && type.isNotEmpty) types.add(type);
  }

  void takeAll(Object? nodes) {
    if (nodes is! List) return;
    for (final node in nodes) {
      take(node);
    }
  }

  for (final node in graph.values) {
    take(node);
  }
  takeAll(graph['nodes']);
  final definitions = graph['definitions'];
  final subgraphs = definitions is Map ? definitions['subgraphs'] : null;
  if (subgraphs is List) {
    for (final sub in subgraphs) {
      if (sub is Map) takeAll(sub['nodes']);
    }
  }
  return types;
}

/// True when a saved workflow is an edit: it loads a picture and then
/// uses it for image-aware conditioning (an edit encoder, a reference
/// latent, or Kontext). Ordinary img2img stays in Create.
bool savedGraphIsEdit(Map<String, dynamic> graph) {
  final types = workflowNodeTypes(graph);
  final loads = types.contains('LoadImage') || types.contains('LoadImageMask');
  if (!loads) return false;
  if (types.contains('TextEncodeQwenImage21') &&
      _qwenEncoderTakesImages(graph)) {
    return true;
  }
  for (final type in types) {
    if (type.contains('ImageEdit') ||
        type.contains('Kontext') ||
        type == 'ReferenceLatent') {
      return true;
    }
  }
  return false;
}

bool _qwenEncoderTakesImages(Map<String, dynamic> graph) {
  final Map<String, dynamic>? api;
  try {
    api = ensureComfyApiGraph(graph);
  } catch (error) {
    debugPrint('ComfyUI: could not inspect Qwen image links: $error');
    return false;
  }
  if (api == null) return false;
  for (final node in api.values.whereType<Map>()) {
    if (node['class_type'] != 'TextEncodeQwenImage21') continue;
    final inputs = node['inputs'];
    if (inputs is! Map) continue;
    for (final entry in inputs.entries) {
      final name = '${entry.key}';
      if (name != 'images' && !name.startsWith('images.')) continue;
      final value = entry.value;
      if (value is List &&
          value.length == 2 &&
          value[0] is String &&
          api[value[0]] is Map &&
          value[1] is int &&
          value[1] >= 0) {
        return true;
      }
    }
  }
  return false;
}

/// Secondary line under a graph title: the task, then the stored id.
String graphRowDetail({required bool edit, required String id}) {
  final task = edit ? 'Edit' : 'Text to image';
  return '$task · $id';
}

/// True when [id] is one of the graphs shipped with Front Porch.
bool _bundledGraphId(String id) {
  for (final preset in kComfyCreatePresets) {
    if (preset.id == id) return true;
  }
  for (final preset in kComfyEditPresets) {
    if (preset.id == id) return true;
  }
  return false;
}

/// A stock template whose name is another architecture cannot load
/// [modelFile]. A name with no architecture stays. Saved workflows and
/// files that could not be read stay either way.
bool _graphFitsModel({
  required bool edit,
  required String modelFile,
  required String id,
  required String title,
  required String group,
}) {
  if (group == 'Saved on this Comfy' || group == 'Could not read') {
    return true;
  }
  if (id == kComfyUploadedWorkflowId) return true;
  final allowed = workflowForModel(edit: edit, file: modelFile);
  if (id == allowed) return true;
  if (_bundledGraphId(id)) return false;
  final stem = '${title.trim()} ${id.split(':').last}'.trim();
  final named =
      isGgufFile(stem) ||
      ImageModelFamily.detectFromName(stem) != ModelFamily.unknown;
  if (!named) return true;
  return workflowForModel(edit: edit, file: stem) == allowed;
}

/// Built-in graphs, then this mode's Comfy templates, then saved
/// workflows already classified for this mode. [unread] files could
/// not be opened, so they are not offered as either mode.
/// When [modelFile] is set, premade graphs that cannot load it are
/// left off. An empty name still lists every premade for the mode.
List<DeskGraphChoice> deskGraphMenu({
  required bool edit,
  required List<DeskGraphRow> templates,
  required List<DeskGraphRow> saved,
  List<DeskGraphRow> unread = const [],
  String modelFile = '',
}) {
  final built = edit ? 'Edit graphs' : 'Text to image graphs';
  final bundled = <DeskGraphChoice>[];
  void addBuiltIn(String id, String label) {
    bundled.add(
      DeskGraphChoice(
        id: id,
        title: label,
        detail: graphRowDetail(edit: edit, id: id),
        group: built,
      ),
    );
  }

  if (edit) {
    for (final preset in kComfyEditPresets) {
      addBuiltIn(preset.id, preset.label);
    }
  } else {
    for (final preset in kComfyCreatePresets) {
      addBuiltIn(preset.id, preset.label);
    }
  }
  final seen = {for (final row in bundled) row.id};
  final fromComfy = <DeskGraphChoice>[];
  for (final row in templates) {
    if (row.id.isEmpty || !seen.add(row.id)) continue;
    fromComfy.add(
      DeskGraphChoice(
        id: row.id,
        title: readableGraphTitle(row.id, row.title),
        detail: graphRowDetail(edit: edit, id: row.id),
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
        detail: graphRowDetail(edit: edit, id: row.id),
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
        detail: graphRowDetail(edit: edit, id: row.id),
        group: 'Could not read',
      ),
    );
  }
  final rows = [...bundled, ...fromComfy, ...onDisk, ...closed];
  final file = modelFile.trim();
  if (file.isEmpty) return rows;
  return [
    for (final row in rows)
      if (_graphFitsModel(
        edit: edit,
        modelFile: file,
        id: row.id,
        title: row.title,
        group: row.group,
      ))
        row,
  ];
}

/// One saved workflow file, read once and sorted into a mode.
class _SavedGraph {
  const _SavedGraph(this.row, this.edit);

  final DeskGraphRow row;

  /// Null when the file could not be read.
  final bool? edit;
}

/// Reads every saved workflow at the same time, once each.
Future<List<_SavedGraph>> _readSavedGraphs(
  ComfyUiService comfy,
  List<ComfyTemplateEntry> saved,
) {
  return Future.wait([
    for (final file in saved)
      () async {
        final json = await comfy.fetchTemplateJson(
          file.name,
          preferUserdata: true,
        );
        return _SavedGraph(
          DeskGraphRow(file.pickerId, file.title),
          json == null ? null : savedGraphIsEdit(json),
        );
      }(),
  ]);
}

List<DeskGraphChoice> _menuFor({
  required bool edit,
  required List<ComfyTemplateEntry> templates,
  required List<_SavedGraph> saved,
  required String modelFile,
}) {
  return deskGraphMenu(
    edit: edit,
    templates: [
      for (final row in templates) DeskGraphRow(row.pickerId, row.title),
    ],
    saved: [
      for (final graph in saved)
        if (graph.edit == edit) graph.row,
    ],
    unread: [
      for (final graph in saved)
        if (graph.edit == null) graph.row,
    ],
    modelFile: modelFile,
  );
}

/// Templates plus saved workflows for one mode. A saved edit graph is
/// left off the Create list, and the reverse.
Future<List<DeskGraphChoice>> loadDeskGraphMenu({
  required ComfyUiService comfy,
  required bool edit,
  required List<ComfyTemplateEntry> templates,
  required List<ComfyTemplateEntry> saved,
  String modelFile = '',
}) async {
  return _menuFor(
    edit: edit,
    templates: templates,
    saved: await _readSavedGraphs(comfy, saved),
    modelFile: modelFile,
  );
}

/// What one round of reads found on a Comfy: its Create and Edit template
/// listings, its saved workflows, and which mode each saved one is for.
class DeskGraphReads {
  const DeskGraphReads._(
    this.createTemplates,
    this.editTemplates,
    this.savedWorkflows,
    this._saved,
  );

  final List<ComfyTemplateEntry> createTemplates;
  final List<ComfyTemplateEntry> editTemplates;
  final List<ComfyTemplateEntry> savedWorkflows;
  final List<_SavedGraph> _saved;

  /// Both Change graph lists, for the file the desk has picked.
  ({List<DeskGraphChoice> create, List<DeskGraphChoice> edit}) menus({
    String modelFile = '',
  }) => (
    create: _menuFor(
      edit: false,
      templates: createTemplates,
      saved: _saved,
      modelFile: modelFile,
    ),
    edit: _menuFor(
      edit: true,
      templates: editTemplates,
      saved: _saved,
      modelFile: modelFile,
    ),
  );
}

/// The three listings together, then every saved workflow together and only
/// once. The desktop desk and the phone both read this way.
Future<DeskGraphReads> readDeskGraphs(ComfyUiService comfy) async {
  final lists = await Future.wait([
    comfy.fetchCreateTemplates(),
    comfy.fetchEditTemplates(),
    comfy.fetchUserWorkflows(),
  ]);
  return DeskGraphReads._(
    lists[0],
    lists[1],
    lists[2],
    await _readSavedGraphs(comfy, lists[2]),
  );
}

/// Both Change graph lists from one round of reads.
Future<({List<DeskGraphChoice> create, List<DeskGraphChoice> edit})>
loadDeskGraphMenus({
  required ComfyUiService comfy,
  String modelFile = '',
}) async => (await readDeskGraphs(comfy)).menus(modelFile: modelFile);

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
  final types = workflowNodeTypes(graph);
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
  if (json.trim().isEmpty) return 0;
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    // A saved workflow that is not JSON has no nodes. This is read while the
    // desk draws, so it must not throw.
    return 0;
  }
  if (decoded is! Map) return 0;
  final nodes = decoded['nodes'];
  if (nodes is List) return nodes.length;
  var count = 0;
  for (final value in decoded.values) {
    if (value is Map && value.containsKey('class_type')) count++;
  }
  return count;
}
