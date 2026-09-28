// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

bool isGgufFile(String name) => name.toLowerCase().endsWith('.gguf');

class FileRetarget {
  final Map<String, dynamic> graph;
  final String? missingClass;
  final bool unreachable;

  /// The graph is a checkpoint starter. GGUF needs the family's unet starter.
  final bool useUnetStarter;

  const FileRetarget({
    required this.graph,
    this.missingClass,
    this.unreachable = false,
    this.useUnetStarter = false,
  });
}

bool _hasInput(Map<String, dynamic> info, String className, String input) {
  final node = info[className];
  if (node is! Map) return false;
  final spec = node['input'];
  if (spec is! Map) return false;
  for (final group in spec.values) {
    if (group is Map && group.containsKey(input)) return true;
  }
  return false;
}

bool _isGgufUnet(Map<String, dynamic>? info, String className) {
  if (!className.contains('GGUF')) return false;
  if (info != null && _hasInput(info, className, 'unet_name')) return true;
  return className.toLowerCase().contains('unet');
}

/// Installed GGUF unet loader, or null when this ComfyUI has none.
String? ggufUnetClass(Map<String, dynamic>? objectInfo) {
  if (objectInfo == null) return null;
  const preferred = ['UnetLoaderGGUF', 'UnetLoaderGGUFAdvanced'];
  for (final name in preferred) {
    if (objectInfo.containsKey(name)) return name;
  }
  for (final name in objectInfo.keys) {
    if (_isGgufUnet(objectInfo, name)) return name;
  }
  return null;
}

Map<String, dynamic> _deep(Map<String, dynamic> graph) {
  final decoded = jsonDecode(jsonEncode(graph));
  return (decoded as Map).cast<String, dynamic>();
}

const _clipSwap = {
  'CLIPLoader': 'CLIPLoaderGGUF',
  'DualCLIPLoader': 'DualCLIPLoaderGGUF',
  'TripleCLIPLoader': 'TripleCLIPLoaderGGUF',
  'QuadrupleCLIPLoader': 'QuadrupleCLIPLoaderGGUF',
};

bool _isTextClipClass(String type) =>
    _clipSwap.containsKey(type) || _clipSwap.containsValue(type);

String? _clipGgufClass(String current, Map<String, dynamic> info) {
  final next = _clipSwap[current];
  if (next != null && info.containsKey(next)) return next;
  return null;
}

bool _clipNames(Map inputs, bool Function(String) test) {
  var saw = false;
  for (final entry in inputs.entries) {
    final key = entry.key.toString();
    if (!key.startsWith('clip_name')) continue;
    final value = entry.value;
    if (value is! String) continue;
    saw = true;
    if (!test(value)) return false;
  }
  return saw;
}

bool _anyClip(Map inputs) => _clipNames(inputs, (_) => true);

bool _anyGgufClip(Map inputs) {
  var any = false;
  for (final entry in inputs.entries) {
    if (!entry.key.toString().startsWith('clip_name')) continue;
    final value = entry.value;
    if (value is String && isGgufFile(value)) any = true;
  }
  return any;
}

bool _isGgufClipClass(String type) => _clipSwap.containsValue(type);

String? _expectedClipGguf(String type) => _clipSwap[type];

String? _clipPlainClass(String current) {
  for (final entry in _clipSwap.entries) {
    if (entry.value == current) return entry.key;
  }
  return null;
}

Map<String, dynamic> _asInputMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

/// Null when this class has no input schema. An empty schema is not a
/// reason to drop the node's existing inputs.
({Map<String, dynamic> required, Map<String, dynamic> optional})? _loaderInputs(
  Map<String, dynamic> info,
  String className,
) {
  final node = info[className];
  if (node is! Map) return null;
  final input = node['input'];
  if (input is! Map) return null;
  return (
    required: _asInputMap(input['required']),
    optional: _asInputMap(input['optional']),
  );
}

/// A combo's first option, or the metadata default. Null when neither exists.
Object? _requiredDefault(Object? spec) {
  if (spec is! List || spec.isEmpty) return null;
  Map? meta;
  if (spec.length > 1 && spec[1] is Map) meta = spec[1] as Map;
  if (meta != null && meta.containsKey('default')) return meta['default'];
  final options = meta?['options'];
  if (options is List && options.isNotEmpty) return options.first;
  final head = spec.first;
  if (head is List && head.isNotEmpty) return head.first;
  return null;
}

bool _isModelToken(String value) {
  final trimmed = value.trim();
  return trimmed.length >= 2 &&
      trimmed.startsWith('%') &&
      trimmed.endsWith('%');
}

/// A concrete `unet_name` decides. An empty value or a `%MODEL_…%` token
/// follows [primaryFile].
bool _nodeWantsGguf(Map node, String primaryFile) {
  final inputs = node['inputs'];
  if (inputs is Map) {
    final name = inputs['unet_name'];
    if (name is String) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty && !_isModelToken(trimmed)) {
        return isGgufFile(trimmed);
      }
    }
  }
  return isGgufFile(primaryFile);
}

String? _installPlainUnet(
  Map node,
  Map<String, dynamic> info,
  String primaryFile,
) {
  final schema = _loaderInputs(info, 'UNETLoader');
  if (!_installLoader(node, 'UNETLoader', info, primaryFile)) {
    return 'UNETLoader';
  }
  final bare =
      schema == null || (schema.required.isEmpty && schema.optional.isEmpty);
  final takesDtype =
      bare ||
      schema.required.containsKey('weight_dtype') ||
      schema.optional.containsKey('weight_dtype');
  if (takesDtype) {
    final slot = node['inputs'];
    if (slot is Map) slot.putIfAbsent('weight_dtype', () => 'default');
  }
  return null;
}

/// Null when the node is already on a loader its file can use.
String? _retargetDiffusion(
  Map node,
  Map<String, dynamic> info,
  String primaryFile,
) {
  final type = node['class_type']?.toString() ?? '';
  if (type == 'CheckpointLoaderSimple') return null;
  final inputs = node['inputs'];
  final named =
      inputs is Map && inputs.containsKey('unet_name') && type.contains('GGUF');
  final diffusion = type == 'UNETLoader' || _isGgufUnet(info, type) || named;
  if (!diffusion) return null;
  if (_nodeWantsGguf(node, primaryFile)) {
    final missing =
        !info.containsKey(type) && (_isGgufUnet(info, type) || named);
    if (type != 'UNETLoader' && !missing) return null;
    final loader = ggufUnetClass(info);
    if (loader == null) return 'UnetLoaderGGUF';
    if (!_installLoader(node, loader, info, primaryFile)) return loader;
    return null;
  }
  if (type == 'UNETLoader') return null;
  if (!_isGgufUnet(info, type) && !named) return null;
  return _installPlainUnet(node, info, primaryFile);
}

/// Points [node] at [loader] and fills required inputs it does not have.
/// Leaves the node unchanged when a required input has no usable value.
bool _installLoader(
  Map node,
  String loader,
  Map<String, dynamic> info,
  String primaryFile,
) {
  final schema = _loaderInputs(info, loader);
  if (schema == null || (schema.required.isEmpty && schema.optional.isEmpty)) {
    node['class_type'] = loader;
    return true;
  }
  final raw = node['inputs'];
  final slot = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};
  final allowed = {...schema.required.keys, ...schema.optional.keys};
  final next = <String, dynamic>{
    for (final entry in slot.entries)
      if (allowed.contains(entry.key)) entry.key: entry.value,
  };
  for (final entry in schema.required.entries) {
    if (next.containsKey(entry.key)) continue;
    if (entry.key == 'unet_name') {
      next[entry.key] = primaryFile;
      continue;
    }
    final value = _requiredDefault(entry.value);
    if (value == null) return false;
    next[entry.key] = value;
  }
  node['inputs'] = next;
  node['class_type'] = loader;
  return true;
}

/// Rewrites loader classes to match the files already written into the graph.
///
/// Call this after model tokens are filled. A placeholder such as
/// `%MODEL_CLIP%` is not a GGUF name, so a GGUF encoder would be switched
/// back to a plain loader. Each diffusion node's own `unet_name` picks its
/// loader; a `%MODEL_…%` token or an empty name follows [primaryFile].
/// An uploaded graph is copied and not rewritten.
/// A null [objectInfo] is unreachable, not a missing class. A checkpoint
/// node is never turned into a GGUF unet loader.
FileRetarget retargetForFile({
  required Map<String, dynamic> graph,
  required String primaryFile,
  required bool uploaded,
  required Map<String, dynamic>? objectInfo,
}) {
  final copy = _deep(graph);
  if (uploaded || primaryFile.trim().isEmpty) {
    return FileRetarget(graph: copy);
  }
  if (objectInfo == null) {
    return FileRetarget(graph: copy, unreachable: true);
  }
  final gguf = isGgufFile(primaryFile);
  var sawCheckpoint = false;
  var sawUnet = false;
  String? missingClip;
  for (final node in copy.values.whereType<Map>()) {
    final type = node['class_type']?.toString() ?? '';
    if (type == 'CheckpointLoaderSimple') sawCheckpoint = true;
    final inputs = node['inputs'];
    final namedGguf =
        inputs is Map &&
        inputs.containsKey('unet_name') &&
        type.contains('GGUF');
    if (type == 'UNETLoader' || _isGgufUnet(objectInfo, type) || namedGguf) {
      sawUnet = true;
    }
    if (inputs is Map && _isTextClipClass(type)) {
      final map = Map<String, dynamic>.from(inputs);
      if (_anyGgufClip(map)) {
        if (_isGgufClipClass(type)) {
          if (!objectInfo.containsKey(type)) {
            missingClip ??= type;
          } else if (!_installLoader(node, type, objectInfo, primaryFile)) {
            missingClip ??= type;
          }
        } else {
          final next = _clipGgufClass(type, objectInfo);
          if (next == null ||
              !_installLoader(node, next, objectInfo, primaryFile)) {
            missingClip ??= _expectedClipGguf(type);
          }
        }
      } else if (_anyClip(map)) {
        final back = _clipPlainClass(type);
        if (back != null &&
            !_installLoader(node, back, objectInfo, primaryFile)) {
          missingClip ??= back;
        }
      }
    }
  }
  if (missingClip != null) {
    return FileRetarget(graph: copy, missingClass: missingClip);
  }
  if (gguf && sawCheckpoint && !sawUnet) {
    return FileRetarget(graph: copy, useUnetStarter: true);
  }
  String? blocked;
  for (final node in copy.values.whereType<Map>()) {
    final problem = _retargetDiffusion(node, objectInfo, primaryFile);
    if (problem != null) blocked ??= problem;
  }
  if (blocked != null) {
    return FileRetarget(graph: copy, missingClass: blocked);
  }
  return FileRetarget(graph: copy);
}

/// A filled diffusion or checkpoint name already written into [graph].
String primaryFileInGraph(Map<String, dynamic> graph) {
  String? checkpoint;
  for (final node in graph.values.whereType<Map>()) {
    final inputs = node['inputs'];
    if (inputs is! Map) continue;
    final unet = inputs['unet_name'];
    if (unet is String) {
      final name = unet.trim();
      if (name.isNotEmpty && !_isModelToken(name)) return name;
    }
    final ckpt = inputs['ckpt_name'];
    if (ckpt is String) {
      final name = ckpt.trim();
      if (name.isNotEmpty && !_isModelToken(name)) checkpoint ??= name;
    }
  }
  return checkpoint ?? '';
}

/// The graph [ComfyUiService] posts. Loaders match the file after tokens
/// are filled. An uploaded graph is not rewritten.
Map<String, dynamic> graphToPost({
  required Map<String, dynamic> graph,
  required String primaryFile,
  required bool uploaded,
  required Map<String, dynamic>? objectInfo,
}) {
  final named = primaryFile.trim().isNotEmpty
      ? primaryFile.trim()
      : primaryFileInGraph(graph);
  final ready = retargetForFile(
    graph: graph,
    primaryFile: named,
    uploaded: uploaded,
    objectInfo: objectInfo,
  );
  if (uploaded || named.isEmpty) return ready.graph;
  if (ready.unreachable) {
    throw Exception('ComfyUI node list could not be read.');
  }
  if (ready.useUnetStarter) {
    throw Exception(
      'This GGUF file needs an unet workflow. Pick one in Image Studio.',
    );
  }
  final missing = ready.missingClass;
  if (missing != null && missing.isNotEmpty) {
    throw Exception('ComfyUI is missing the $missing node.');
  }
  return ready.graph;
}

bool graphUsesLoader(Map<String, dynamic> graph, String classType) {
  for (final node in graph.values.whereType<Map>()) {
    if (node['class_type'] == classType) return true;
  }
  return false;
}
