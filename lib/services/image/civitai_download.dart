// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:path/path.dart' as p;

const _kFolders = {
  'checkpoints',
  'diffusion_models',
  'loras',
  'text_encoders',
  'vae',
  'models/Stable-diffusion',
  'models/Lora',
  'models/VAE',
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
  if (backend != 'comfyui' && backend != 'a1111') return null;
  final a1111 = backend == 'a1111';
  if (a1111 && gguf) return null;
  final lora = type == 'lora' || type == 'locon' || type == 'dora';
  if (lora) {
    if (!fromLoraSheet) return null;
    return a1111 ? 'models/Lora' : 'loras';
  }
  if (type == 'checkpoint') {
    if (fromLoraSheet) return null;
    if (a1111) return 'models/Stable-diffusion';
    return gguf ? 'diffusion_models' : 'checkpoints';
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

/// Join [root]/[folder]/basename, or null when the name or root is unsafe.
String? civitaiDownloadPath({
  required String root,
  required String folder,
  required String name,
}) {
  if (!p.isAbsolute(root) || !_kFolders.contains(folder)) return null;
  final base = safeDownloadBasename(name);
  if (base == null) return null;
  final candidate = p.join(root, folder, base);
  if (!pathStaysUnderRoot(root, candidate)) return null;
  return candidate;
}
