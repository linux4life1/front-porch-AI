// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'draw_things_lora_filter.dart';
import 'model_family.dart';

const _kFolders = {
  'checkpoints',
  'diffusion_models',
  'loras',
  'text_encoders',
  'vae',
  'models/Stable-diffusion',
  'models/Lora',
  'models/VAE',
  'lora',
};

const _kReserved = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

/// Basename only. Null when the name could escape the models folder.
String? safeDownloadBasename(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed != name) return null;
  if (trimmed.contains('/') || trimmed.contains(r'\')) return null;
  if (trimmed.contains('..') || trimmed.contains(':')) return null;
  if (p.isAbsolute(trimmed)) return null;
  for (final unit in trimmed.codeUnits) {
    if (unit < 32) return null;
  }
  final base = p.basename(trimmed);
  if (base.isEmpty || base == '.' || base == '..') return null;
  if (base.endsWith('.') || base.endsWith(' ')) return null;
  final stem = base.split('.').first.toUpperCase();
  if (_kReserved.contains(stem)) return null;
  return base;
}

/// Subfolder for a CivitAI model type. `Model` is a file type, not a
/// checkpoint, so it is refused. GGUF is not offered on Automatic1111.
String? civitaiSlotFolder({
  required bool fromLoraSheet,
  required String civitaiType,
  required String filename,
  String backend = 'comfyui',
}) {
  final type = civitaiType.trim().toLowerCase();
  final gguf = filename.toLowerCase().endsWith('.gguf');
  final lora = type == 'lora' || type == 'locon' || type == 'dora';
  if (backend == 'drawthings') {
    if (gguf) return null;
    if (lora) return fromLoraSheet ? 'lora' : null;
    if (type == 'checkpoint') return fromLoraSheet ? null : '';
    return null;
  }
  if (backend != 'comfyui' && backend != 'a1111') return null;
  final a1111 = backend == 'a1111';
  if (a1111 && gguf) return null;
  if (lora) {
    if (!fromLoraSheet) return null;
    return a1111 ? 'models/Lora' : 'loras';
  }
  if (type == 'checkpoint') {
    if (fromLoraSheet) return null;
    if (a1111) return 'models/Stable-diffusion';
    return _comfyCheckpointFolder(filename, gguf: gguf);
  }
  if (type == 'vae') {
    if (fromLoraSheet) return null;
    return a1111 ? 'models/VAE' : 'vae';
  }
  if (type == 'text encoder' || type == 'textencoder') {
    if (fromLoraSheet || a1111) return null;
    return 'text_encoders';
  }
  return null;
}

/// True when [candidate] is [root] or a file inside it.
bool pathStaysUnderRoot(String root, String candidate) {
  if (!p.isAbsolute(root)) return false;
  final r = p.normalize(root);
  final c = p.normalize(candidate);
  return c == r || p.isWithin(r, c);
}

/// Comfy's UNET loader reads `diffusion_models`. Checkpoint files for SD 1.5,
/// SDXL, and Pony stay in `checkpoints`.
String _comfyCheckpointFolder(String filename, {required bool gguf}) {
  if (gguf) return 'diffusion_models';
  switch (ImageModelFamily.detectFromName(filename)) {
    case ModelFamily.flux:
    case ModelFamily.kontext:
    case ModelFamily.qwen:
    case ModelFamily.zImage:
    case ModelFamily.sd3:
      return 'diffusion_models';
    case ModelFamily.sd15:
    case ModelFamily.sdxl:
    case ModelFamily.pony:
    case ModelFamily.unknown:
      return 'checkpoints';
  }
}

/// Join [root]/[folder]/basename, or null when the name or root is unsafe.
String? civitaiDownloadPath({
  required String root,
  required String folder,
  required String name,
}) {
  if (!p.isAbsolute(root)) return null;
  if (folder.isNotEmpty && !_kFolders.contains(folder)) return null;
  final base = safeDownloadBasename(name);
  if (base == null) return null;
  final candidate = folder.isEmpty
      ? p.join(root, base)
      : p.join(root, folder, base);
  if (!pathStaysUnderRoot(root, candidate)) return null;
  return candidate;
}

/// `custom_lora.json` version id for a file name, when the name says.
/// A specific Draw Things id (Klein 9B, LTX) wins. Names that only say
/// SDXL via "XL" still use the coarser family.
String drawThingsCatalogVersion(String filename) {
  final specific = drawThingsVersionFromName(filename);
  if (specific.isNotEmpty) return specific;
  switch (ImageModelFamily.detectFromName(filename)) {
    case ModelFamily.zImage:
      return 'z_image';
    case ModelFamily.qwen:
      return 'qwen_image';
    case ModelFamily.flux:
    case ModelFamily.kontext:
      return 'flux1';
    case ModelFamily.pony:
    case ModelFamily.sdxl:
      return 'sdxl_base_v0.9';
    case ModelFamily.sd3:
      return 'sd3';
    case ModelFamily.sd15:
      return 'v1';
    case ModelFamily.unknown:
      return '';
  }
}

/// Adds [filename] to Draw Things' LoRA catalog when it is not already there.
/// A catalog that is not a list is left alone.
Future<void> rememberDrawThingsLora(
  Directory modelsDir,
  String filename,
) async {
  final base = p.basename(filename);
  if (base.isEmpty) return;
  final catalog = File(p.join(modelsDir.path, 'custom_lora.json'));
  final rows = <dynamic>[];
  if (await catalog.exists()) {
    try {
      final decoded = jsonDecode(await catalog.readAsString());
      if (decoded is! List) return;
      rows.addAll(decoded);
    } catch (_) {
      return;
    }
  }
  for (final row in rows) {
    if (row is Map && p.basename(row['file']?.toString() ?? '') == base) {
      return;
    }
  }
  final version = drawThingsCatalogVersion(base);
  rows.add({
    'file': base,
    'name': p.basenameWithoutExtension(base),
    if (version.isNotEmpty) 'version': version,
  });
  await catalog.writeAsString(jsonEncode(rows));
}
