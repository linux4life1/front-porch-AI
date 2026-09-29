// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as p;

import 'civitai_bases.dart';
import 'studio_model_roots.dart';

const _kWeightExts = {'.safetensors', '.gguf', '.ckpt', '.pt', '.pth', '.bin'};

/// Folders under the models root that hold this sheet's files.
/// Model scans skip text encoders, VAEs, and LoRA drawers.
List<String> civitaiScanFolders({required String backend, required bool lora}) {
  switch (backend) {
    case 'drawthings':
      return [lora ? 'lora' : ''];
    case 'a1111':
      return [lora ? 'models/Lora' : 'models/Stable-diffusion'];
    case 'comfyui':
      return lora
          ? const ['loras']
          : const ['diffusion_models', 'checkpoints', 'unet'];
    default:
      return const [];
  }
}

/// Weight basenames in the slot folders. Partial downloads are skipped.
Future<List<String>> civitaiSlotNames({
  required String root,
  required String backend,
  required bool lora,
}) async {
  if (root.trim().isEmpty || !p.isAbsolute(root)) return const [];
  final found = <String>{};
  for (final folder in civitaiScanFolders(backend: backend, lora: lora)) {
    final dir = Directory(folder.isEmpty ? root : p.join(root, folder));
    if (!await dir.exists()) continue;
    await for (final entity in dir.list(followLinks: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.') || name.startsWith('put_')) continue;
      if (name == '.gitkeep' || name.endsWith('.part')) continue;
      if (!_kWeightExts.contains(p.extension(name).toLowerCase())) continue;
      found.add(name);
    }
  }
  final names = found.toList()..sort();
  return names;
}

/// True when [filename] is already one of [names], ignoring case.
bool civitaiFileInstalled(String? filename, Iterable<String> names) {
  final want = filename?.trim().toLowerCase() ?? '';
  if (want.isEmpty) return false;
  for (final name in names) {
    if (name.toLowerCase() == want) return true;
  }
  return false;
}

/// Catalog lists plus a file that is already on disk.
///
/// Comfy's model list can lag behind the folder. A finished download still
/// has to be selectable.
class CivitaiDiskLists {
  final List<String> checkpoints;
  final List<String> diffusion;
  final List<String> gguf;
  final List<String> loras;

  const CivitaiDiskLists({
    this.checkpoints = const [],
    this.diffusion = const [],
    this.gguf = const [],
    this.loras = const [],
  });
}

Future<CivitaiDiskLists> mergeCivitaiDisk({
  String? root,
  required String backend,
  required String file,
  required bool lora,
  required String workflowId,
  required List<String> checkpoints,
  required List<String> diffusion,
  required List<String> gguf,
  required List<String> loras,
}) async {
  final same = CivitaiDiskLists(
    checkpoints: checkpoints,
    diffusion: diffusion,
    gguf: gguf,
    loras: loras,
  );
  final wanted = file.trim();
  if (wanted.isEmpty) return same;
  final folder = root ?? await savedStudioModelRoot(backend);
  if (folder == null || folder.trim().isEmpty) return same;
  final names = await civitaiSlotNames(
    root: folder,
    backend: backend,
    lora: lora,
  );
  if (!civitaiFileInstalled(wanted, names)) return same;
  List<String> plus(List<String> list) {
    for (final name in list) {
      if (name.toLowerCase() == wanted.toLowerCase()) return list;
    }
    return [...list, wanted];
  }

  if (lora) {
    return CivitaiDiskLists(
      checkpoints: checkpoints,
      diffusion: diffusion,
      gguf: gguf,
      loras: plus(loras),
    );
  }
  if (wanted.toLowerCase().endsWith('.gguf')) {
    return CivitaiDiskLists(
      checkpoints: checkpoints,
      diffusion: diffusion,
      gguf: plus(gguf),
      loras: loras,
    );
  }
  if (workflowId == 'sd') {
    return CivitaiDiskLists(
      checkpoints: plus(checkpoints),
      diffusion: diffusion,
      gguf: gguf,
      loras: loras,
    );
  }
  return CivitaiDiskLists(
    checkpoints: checkpoints,
    diffusion: plus(diffusion),
    gguf: gguf,
    loras: loras,
  );
}

/// Installed model files, expressed as CivitAI base API values.
Future<List<String>> civitaiInstalledBases({
  required String root,
  required String backend,
}) async {
  final models = await civitaiSlotNames(
    root: root,
    backend: backend,
    lora: false,
  );
  final bases = civitaiBasesForFiles(models).toList()..sort();
  return bases;
}
