// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'comfy_edit_workflow.dart';

/// The ComfyUI folder each loader input reads from, for the words that say
/// where a missing file belongs.
const _kLoaderFolders = <String, String>{
  'ckpt_name': 'checkpoints',
  'unet_name': 'diffusion_models',
  'vae_name': 'vae',
  'lora_name': 'loras',
  'clip_name': 'text_encoders',
  'clip_name1': 'text_encoders',
  'clip_name2': 'text_encoders',
  'clip_name3': 'text_encoders',
  'clip_name4': 'text_encoders',
};

/// The files ComfyUI offers for one loader input, in either `/object_info`
/// shape (`[[options], {meta}]` or `['COMBO', {'options': [...]}]`). Null
/// when the input is not described, so an unknown shape never blocks.
List<String>? _offered(
  Map<String, dynamic> objectInfo,
  String nodeType,
  String inputName,
) {
  final node = objectInfo[nodeType];
  if (node is! Map) return null;
  final input = node['input'];
  if (input is! Map) return null;
  for (final section in ['required', 'optional']) {
    final sec = input[section];
    if (sec is! Map) continue;
    final spec = sec[inputName];
    if (spec is! List || spec.isEmpty) continue;
    final head = spec.first;
    if (head is List) return [for (final o in head) o.toString()];
    if (head == 'COMBO' && spec.length > 1 && spec[1] is Map) {
      final options = (spec[1] as Map)['options'];
      if (options is List) return [for (final o in options) o.toString()];
    }
  }
  return null;
}

String _sameSlashes(String name) => name.trim().replaceAll(r'\', '/');

bool _listed(List<String> offered, String file) {
  final want = _sameSlashes(file);
  return offered.any((o) => _sameSlashes(o) == want);
}

/// Loaders that read the same folder in another format: an empty
/// `UNETLoader` list is not an empty folder while the GGUF loader lists one.
const _kSiblingLoaders = <String, List<String>>{
  'UNETLoader': ['UnetLoaderGGUF', 'UnetLoaderGGUFAdvanced'],
  'CLIPLoader': ['CLIPLoaderGGUF'],
};

String _emptyFolderWords(String folder) =>
    'ComfyUI lists no files in its models/$folder folder. Put a model there '
    '(or add its folder to extra_model_paths.yaml), restart ComfyUI, then '
    'press Check.';

String _words(String file, String folder, List<String> offered) {
  if (offered.isEmpty) {
    return 'ComfyUI lists no files in its models/$folder folder, so it can’t '
        'load $file. Put the file there (or add its folder to '
        'extra_model_paths.yaml), restart ComfyUI, then press Check.';
  }
  return 'ComfyUI doesn’t have $file in models/$folder. Choose a file it '
      'lists, or put that file there and restart ComfyUI.';
}

/// Why this graph would be refused for a file ComfyUI does not list, or null.
///
/// ComfyUI rejects a loader value that is not one of its options (`ckpt_name:
/// 'x' not in []`). A model or LoRA picked for another backend, or one that
/// was moved away, is caught here instead of at the post. [loras] are the
/// filled LoRA slots, which are spliced in at generate time.
String? comfyUnlistedFileWords({
  required Map<String, dynamic> graph,
  required Map<String, dynamic> objectInfo,
  Iterable<String> loras = const [],
}) {
  for (final node in graph.values) {
    if (node is! Map) continue;
    final type = node['class_type']?.toString() ?? '';
    final inputs = node['inputs'];
    if (type.isEmpty || inputs is! Map) continue;
    for (final entry in _kLoaderFolders.entries) {
      final value = inputs[entry.key];
      if (value is! String) continue;
      final file = value.trim();
      if (file.isEmpty || file.startsWith('%')) continue;
      final offered = _offered(objectInfo, type, entry.key);
      if (offered == null || _listed(offered, file)) continue;
      return _words(file, entry.value, offered);
    }
  }
  final offeredLoras = _offered(objectInfo, 'LoraLoader', 'lora_name');
  if (offeredLoras == null) return null;
  for (final lora in loras) {
    final file = lora.trim();
    if (file.isEmpty || _listed(offeredLoras, file)) continue;
    return _words(file, 'loras', offeredLoras);
  }
  return null;
}

/// Why an empty slot can't be filled, or null: ComfyUI lists nothing at all
/// in the folder that slot reads, so "choose a file" has nothing to choose.
String? comfyEmptySlotWords({
  required List<ComfyModelSlot> slots,
  required Set<String> unfilled,
  required Map<String, dynamic> objectInfo,
}) {
  for (final slot in slots) {
    if (!unfilled.contains(slot.token)) continue;
    final offered = _offered(objectInfo, slot.loaderClass, slot.inputName);
    if (offered == null || offered.isNotEmpty) continue;
    final siblings = _kSiblingLoaders[slot.loaderClass] ?? const <String>[];
    final elsewhere = siblings.any(
      (loader) =>
          (_offered(objectInfo, loader, slot.inputName) ?? const []).isNotEmpty,
    );
    if (elsewhere) continue;
    final folder = slot.folderHint.isEmpty ? 'models' : slot.folderHint;
    return _emptyFolderWords(folder);
  }
  return null;
}
