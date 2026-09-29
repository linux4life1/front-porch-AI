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

// Which `widgets_values` entry belongs to which input, per node class.

/// Socket types: an input of one of these is a link, not a widget.
const kComfyLinkTypes = {
  'MODEL',
  'CLIP',
  'VAE',
  'LATENT',
  'CONDITIONING',
  'IMAGE',
  'AUDIO',
  'VIDEO',
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
  'DualCLIPLoaderGGUF': ['clip_name1', 'clip_name2', 'type'],
  'TripleCLIPLoaderGGUF': ['clip_name1', 'clip_name2', 'clip_name3'],
  'QuadrupleCLIPLoaderGGUF': [
    'clip_name1',
    'clip_name2',
    'clip_name3',
    'clip_name4',
  ],
  'DualCLIPLoader': ['clip_name1', 'clip_name2', 'type', 'device'],
  'VAELoader': ['vae_name'],
  'CheckpointLoaderSimple': ['ckpt_name'],
  'CLIPTextEncode': ['text'],
  'KSampler': ['seed', 'steps', 'cfg', 'sampler_name', 'scheduler', 'denoise'],
  'EmptyLatentImage': ['width', 'height', 'batch_size'],
  'EmptySD3LatentImage': ['width', 'height', 'batch_size'],
  'ModelSamplingAuraFlow': ['shift'],
  'ModelSamplingSD3': ['shift'],
  'ModelSamplingFlux': ['max_shift', 'base_shift', 'width', 'height'],
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
    'sampling_mode.seed',
    'sampling_mode.presence_penalty',
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

List<String> comfyWidgetInputNames(
  Map<String, dynamic>? objectInfo,
  String type,
) {
  return [for (final slot in comfyWidgetSlots(objectInfo, type)) slot.name];
}

/// One widget in `widgets_values` order. A dynamic combo (`TextGenerate`'s
/// sampling mode) lists what each of its options adds right after it, so a
/// stored value picks which widgets follow.
class ComfyWidgetSlot {
  const ComfyWidgetSlot(this.name, [this.options = const {}]);

  final String name;
  final Map<String, List<ComfyWidgetSlot>> options;
}

List<ComfyWidgetSlot> comfyWidgetSlots(
  Map<String, dynamic>? objectInfo,
  String type,
) {
  final fromInfo = _widgetSlotsFromObjectInfo(objectInfo, type);
  if (fromInfo.isNotEmpty) return fromInfo;
  return [
    for (final name in kComfyFallbackWidgets[type] ?? const <String>[])
      ComfyWidgetSlot(name),
  ];
}

const _kDynamicCombo = 'COMFY_DYNAMICCOMBO_V3';

List<ComfyWidgetSlot> _widgetSlotsFromObjectInfo(
  Map<String, dynamic>? info,
  String type,
) {
  if (info == null) return const [];
  final node = info[type];
  if (node is! Map) return const [];
  return _widgetSlotsOf(node['input'], '');
}

List<ComfyWidgetSlot> _widgetSlotsOf(Object? input, String prefix) {
  if (input is! Map) return const [];
  final slots = <ComfyWidgetSlot>[];
  for (final section in ['required', 'optional']) {
    final sec = input[section];
    if (sec is! Map) continue;
    for (final e in sec.entries) {
      if (!_isWidgetSpec(e.value)) continue;
      final name = '$prefix${e.key}';
      slots.add(ComfyWidgetSlot(name, _dynamicOptions(e.value, '$name.')));
    }
  }
  return slots;
}

Map<String, List<ComfyWidgetSlot>> _dynamicOptions(
  Object? spec,
  String prefix,
) {
  if (spec is! List || spec.length < 2 || spec.first != _kDynamicCombo) {
    return const {};
  }
  final extra = spec[1];
  final options = extra is Map ? extra['options'] : null;
  if (options is! List) return const {};
  return {
    for (final option in options)
      if (option is Map && option['key'] != null)
        option['key'].toString(): _widgetSlotsOf(option['inputs'], prefix),
  };
}

bool _isWidgetSpec(Object? spec) {
  if (spec is! List || spec.isEmpty) return false;
  final first = spec.first;
  if (first is List) return true;
  if (first is String) return !kComfyLinkTypes.contains(first);
  return false;
}
