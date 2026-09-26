// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// UI (litegraph) → /prompt API format. Official Comfy templates are UI
// JSON, often wrapped in a subgraph. Porch does not own those graphs —
// it flattens and converts them, then the token adapter fills Studio knobs.

const _kSkipTypes = {'MarkdownNote', 'Note'};
const _kControlAfter = {'randomize', 'fixed', 'increment', 'decrement'};
const _kLinkTypes = {
  'MODEL',
  'CLIP',
  'VAE',
  'LATENT',
  'CONDITIONING',
  'IMAGE',
  'MASK',
  'CONTROL_NET',
  'GUIDER',
  'NOISE',
  'SAMPLER',
  'SIGMAS',
};

/// Fallback widget order when /object_info is missing (bundled starters, CI).
const kComfyFallbackWidgets = <String, List<String>>{
  'UNETLoader': ['unet_name', 'weight_dtype'],
  'UnetLoaderGGUF': ['unet_name'],
  'UnetLoaderGGUFAdvanced': [
    'unet_name',
    'dequant_dtype',
    'patch_dtype',
    'patch_on_device',
  ],
  'CLIPLoader': ['clip_name', 'type', 'device'],
  'CLIPLoaderGGUF': ['clip_name', 'type'],
  'DualCLIPLoader': ['clip_name1', 'clip_name2', 'type', 'device'],
  'VAELoader': ['vae_name'],
  'CheckpointLoaderSimple': ['ckpt_name'],
  'CLIPTextEncode': ['text'],
  'KSampler': ['seed', 'steps', 'cfg', 'sampler_name', 'scheduler', 'denoise'],
  'EmptyLatentImage': ['width', 'height', 'batch_size'],
  'EmptySD3LatentImage': ['width', 'height', 'batch_size'],
  'ModelSamplingAuraFlow': ['shift'],
  'FluxGuidance': ['guidance'],
  'CFGNorm': ['strength'],
  'LoraLoader': ['lora_name', 'strength_model', 'strength_clip'],
  'SaveImage': ['filename_prefix'],
  'LoadImage': ['image'],
  'TextEncodeQwenImageEditPlus': ['prompt'],
  'TextEncodeQwenImage21': ['prompt', 'negative_prompt', 'resolution'],
  'TextGenerate': [
    'prompt',
    'max_length',
    'sampling_mode',
    'sampling_mode.temperature',
    'sampling_mode.top_k',
    'sampling_mode.top_p',
    'sampling_mode.min_p',
    'sampling_mode.repetition_penalty',
    'sampling_mode.presence_penalty',
    'sampling_mode.seed',
    'thinking',
    'use_default_template',
    'mtp',
  ],
  'ComfySwitchNode': ['switch'],
  'PrimitiveStringMultiline': ['value'],
  'QwenImage21Cache': ['device', 'dtype'],
  'ResolutionSelector': ['aspect_ratio', 'megapixels', 'multiple'],
  'SaveImageAdvanced': [
    'filename_prefix',
    'format',
    'format.bit_depth',
    'format.input_color_space',
  ],
};

bool isComfyApiWorkflow(Map<String, dynamic> raw) {
  if (raw.containsKey('nodes') && raw.containsKey('links')) return false;
  for (final v in raw.values) {
    if (v is Map && v['class_type'] != null) return true;
  }
  return false;
}

bool isComfyUiWorkflow(Map<String, dynamic> raw) =>
    raw['nodes'] is List && raw.containsKey('links');

/// API-format graph, or null if [raw] is neither UI nor API.
Map<String, dynamic>? ensureComfyApiGraph(
  Map<String, dynamic> raw, {
  Map<String, dynamic>? objectInfo,
}) {
  if (isComfyApiWorkflow(raw)) {
    return raw.map(
      (k, v) => MapEntry(k, v is Map ? Map<String, dynamic>.from(v) : v),
    );
  }
  if (isComfyUiWorkflow(raw)) {
    return convertComfyUiToApi(raw, objectInfo: objectInfo);
  }
  return null;
}

/// Flatten subgraphs, drop notes, map widgets_values + links → API nodes.
Map<String, dynamic> convertComfyUiToApi(
  Map<String, dynamic> ui, {
  Map<String, dynamic>? objectInfo,
}) {
  final flat = _flattenComfyUiGraph(ui);
  final nodes = flat.nodes;
  final linksById = {for (final l in flat.links) l.id: l};
  final nodesById = {for (final n in nodes) n.id: n};

  final out = <String, dynamic>{};
  for (final n in nodes) {
    if (n.type == 'Reroute') continue;
    final inputs = <String, dynamic>{};
    for (final inp in n.inputs) {
      final linkId = inp.link;
      if (linkId == null) continue;
      final link = linksById[linkId];
      if (link == null) continue;
      final origin = _followReroute(
        link.originId,
        link.originSlot,
        nodesById,
        linksById,
      );
      if (origin == null) continue;
      inputs[inp.name] = [origin.$1, origin.$2];
    }
    final names = comfyWidgetInputNames(objectInfo, n.type);
    var nameI = 0;
    for (final value in n.widgets) {
      if (value is String && _kControlAfter.contains(value)) continue;
      if (nameI >= names.length) break;
      final name = names[nameI++];
      inputs.putIfAbsent(name, () => value);
    }
    inputs.addAll(flat.values[n.id] ?? const {});
    out[n.id] = {'class_type': n.type, 'inputs': inputs};
  }
  return out;
}

List<String> comfyWidgetInputNames(
  Map<String, dynamic>? objectInfo,
  String type,
) {
  final fromInfo = _widgetNamesFromObjectInfo(objectInfo, type);
  if (fromInfo.isNotEmpty) return fromInfo;
  return kComfyFallbackWidgets[type] ?? const [];
}

List<String> _widgetNamesFromObjectInfo(
  Map<String, dynamic>? info,
  String type,
) {
  if (info == null) return const [];
  final node = info[type];
  if (node is! Map) return const [];
  final input = node['input'];
  if (input is! Map) return const [];
  final names = <String>[];
  for (final section in ['required', 'optional']) {
    final sec = input[section];
    if (sec is! Map) continue;
    for (final e in sec.entries) {
      if (_isWidgetSpec(e.value)) names.add(e.key.toString());
    }
  }
  return names;
}

bool _isWidgetSpec(Object? spec) {
  if (spec is! List || spec.isEmpty) return false;
  final first = spec.first;
  if (first is List) return true;
  if (first is String) return !_kLinkTypes.contains(first);
  return false;
}

(String, int)? _followReroute(
  String originId,
  int originSlot,
  Map<String, _UiNode> nodes,
  Map<int, _UiLink> links,
) {
  var id = originId;
  var slot = originSlot;
  for (var i = 0; i < 8; i++) {
    final n = nodes[id];
    if (n == null) return null;
    if (n.type != 'Reroute') return (id, slot);
    if (n.inputs.isEmpty || n.inputs.first.link == null) return null;
    final link = links[n.inputs.first.link];
    if (link == null) return null;
    id = link.originId;
    slot = link.originSlot;
  }
  return null;
}

class _UiNode {
  final String id;
  final String type;
  final List<Object?> widgets;
  final List<_UiIn> inputs;
  const _UiNode({
    required this.id,
    required this.type,
    required this.widgets,
    required this.inputs,
  });
}

class _UiIn {
  final String name;
  final int? link;
  const _UiIn(this.name, this.link);
}

class _UiLink {
  final int id;
  final String originId;
  final int originSlot;
  final String targetId;
  final int targetSlot;
  const _UiLink({
    required this.id,
    required this.originId,
    required this.originSlot,
    required this.targetId,
    required this.targetSlot,
  });
}

class _FlatUi {
  final List<_UiNode> nodes;
  final List<_UiLink> links;
  final Map<String, Map<String, Object?>> values;
  const _FlatUi(this.nodes, this.links, this.values);
}

_FlatUi _flattenComfyUiGraph(Map<String, dynamic> ui) {
  final subgraphs = <String, Map<String, dynamic>>{};
  final defs = ui['definitions'];
  if (defs is Map && defs['subgraphs'] is List) {
    for (final raw in defs['subgraphs'] as List) {
      if (raw is Map && raw['id'] != null) {
        subgraphs[raw['id'].toString()] = raw.cast<String, dynamic>();
      }
    }
  }
  final nodes = <_UiNode>[];
  final links = <_UiLink>[];
  final outputRewire = <String, (String, int)>{};
  final values = <String, Map<String, Object?>>{};

  void walk(List rawNodes, List rawLinks, String prefix) {
    final local = <_UiNode>[];
    for (final raw in rawNodes) {
      if (raw is! Map) continue;
      final type = raw['type']?.toString() ?? '';
      if (_kSkipTypes.contains(type)) continue;
      final id = '$prefix${raw['id']}';
      if (subgraphs.containsKey(type)) {
        final sg = subgraphs[type]!;
        walk(_asList(sg['nodes']), _asList(sg['links']), '${id}_');
        final ports = _asList(sg['inputs']);
        final widgets = _asList(raw['widgets_values']);
        for (final internal in _asList(sg['links'])) {
          final origin = _linkOrigin(internal);
          final target = _linkTarget(internal);
          final linkId = _linkId(internal);
          if (origin?.$1 != '-10' || target == null || linkId == null) {
            continue;
          }
          final portIndex = origin!.$2;
          if (portIndex >= ports.length || ports[portIndex] is! Map) continue;
          final portName = (ports[portIndex] as Map)['name']?.toString();
          final childId = '${id}_${target.$1}';
          final child = nodes.where((n) => n.id == childId).firstOrNull;
          if (child == null || target.$2 >= child.inputs.length) continue;
          final inputName = child.inputs[target.$2].name;
          final parentInput = _asList(
            raw['inputs'],
          ).whereType<Map>().where((i) => i['name'] == portName).firstOrNull;
          final parentLinkId = parentInput?['link'];
          if (parentLinkId is num) {
            final parentLink = _asList(
              rawLinks,
            ).where((l) => _linkId(l) == parentLinkId.toInt()).firstOrNull;
            final parentOrigin = _linkOrigin(parentLink);
            if (parentOrigin != null) {
              links.add(
                _UiLink(
                  id: linkId,
                  originId: '$prefix${parentOrigin.$1}',
                  originSlot: parentOrigin.$2,
                  targetId: childId,
                  targetSlot: target.$2,
                ),
              );
              continue;
            }
          }
          if (portIndex < widgets.length) {
            values.putIfAbsent(childId, () => {})[inputName] =
                widgets[portIndex];
          }
        }
        _recordSubgraphOutputs(
          sg,
          prefix: '${id}_',
          parentId: id,
          into: outputRewire,
        );
        continue;
      }
      final node = _readNode(raw, id);
      local.add(node);
      nodes.add(node);
    }
    for (final raw in rawLinks) {
      final parsed = _readLink(raw, prefix);
      if (parsed == null) continue;
      links.add(parsed);
    }
  }

  walk(_asList(ui['nodes']), _asList(ui['links']), '');

  final remapped = <_UiLink>[];
  for (final l in links) {
    final hit = outputRewire['${l.originId}:${l.originSlot}'];
    if (hit != null) {
      remapped.add(
        _UiLink(
          id: l.id,
          originId: hit.$1,
          originSlot: hit.$2,
          targetId: l.targetId,
          targetSlot: l.targetSlot,
        ),
      );
    } else {
      remapped.add(l);
    }
  }
  return _FlatUi(nodes, remapped, values);
}

void _recordSubgraphOutputs(
  Map<String, dynamic> sg, {
  required String prefix,
  required String parentId,
  required Map<String, (String, int)> into,
}) {
  for (final raw in _asList(sg['links'])) {
    final origin = _linkOrigin(raw);
    final target = _linkTarget(raw);
    if (origin == null || target == null) continue;
    if (target.$1 == '-20' || target.$1.endsWith('-20')) {
      into['$parentId:${target.$2}'] = ('$prefix${origin.$1}', origin.$2);
    }
  }
}

_UiNode _readNode(Map raw, String id) {
  final widgets = <Object?>[];
  final wv = raw['widgets_values'];
  if (wv is List) widgets.addAll(wv);
  final inputs = <_UiIn>[];
  final rawIns = raw['inputs'];
  if (rawIns is List) {
    for (final inp in rawIns) {
      if (inp is! Map) continue;
      final name = inp['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final link = inp['link'];
      inputs.add(_UiIn(name, link is num ? link.toInt() : null));
    }
  }
  return _UiNode(
    id: id,
    type: raw['type']?.toString() ?? '',
    widgets: widgets,
    inputs: inputs,
  );
}

_UiLink? _readLink(Object? raw, String prefix) {
  final origin = _linkOrigin(raw);
  final target = _linkTarget(raw);
  final id = _linkId(raw);
  if (origin == null || target == null || id == null) return null;
  if (_isIoId(origin.$1) || _isIoId(target.$1)) return null;
  return _UiLink(
    id: id,
    originId: '$prefix${origin.$1}',
    originSlot: origin.$2,
    targetId: '$prefix${target.$1}',
    targetSlot: target.$2,
  );
}

bool _isIoId(String id) =>
    id == '-10' || id == '-20' || id.endsWith('-10') || id.endsWith('-20');

int? _linkId(Object? raw) {
  if (raw is List && raw.isNotEmpty && raw[0] is num) {
    return (raw[0] as num).toInt();
  }
  if (raw is Map && raw['id'] is num) return (raw['id'] as num).toInt();
  return null;
}

(String, int)? _linkOrigin(Object? raw) {
  if (raw is List && raw.length >= 3) {
    return (raw[1].toString(), raw[2] is num ? (raw[2] as num).toInt() : 0);
  }
  if (raw is Map) {
    final id = raw['origin_id'] ?? raw['from'];
    final slot = raw['origin_slot'] ?? raw['from_slot'] ?? 0;
    if (id == null) return null;
    return (id.toString(), slot is num ? slot.toInt() : 0);
  }
  return null;
}

(String, int)? _linkTarget(Object? raw) {
  if (raw is List && raw.length >= 5) {
    return (raw[3].toString(), raw[4] is num ? (raw[4] as num).toInt() : 0);
  }
  if (raw is Map) {
    final id = raw['target_id'] ?? raw['to'];
    final slot = raw['target_slot'] ?? raw['to_slot'] ?? 0;
    if (id == null) return null;
    return (id.toString(), slot is num ? slot.toInt() : 0);
  }
  return null;
}

List<dynamic> _asList(Object? v) => v is List ? v : const [];
