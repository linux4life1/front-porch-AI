// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'civitai_version.dart';
import 'draw_things_lora_filter.dart';
import 'model_family.dart';

const kCivitaiFolders = {
  'checkpoints',
  'embeddings',
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
  if (type == 'textualinversion' || type == 'embedding') {
    return fromLoraSheet ? 'embeddings' : null;
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
  if (folder.isNotEmpty && !kCivitaiFolders.contains(folder)) return null;
  final base = safeDownloadBasename(name);
  if (base == null) return null;
  if (!kCivitaiSafeExtensions.contains(p.extension(base).toLowerCase())) {
    return null;
  }
  final candidate = folder.isEmpty
      ? p.join(root, base)
      : p.join(root, folder, base);
  if (!pathStaysUnderRoot(root, candidate)) return null;
  return candidate;
}

/// Suffix of the file a download streams into before it is moved into place.
/// It is ours alone, so a sweep never deletes another program's partial.
const String kCivitaiPartSuffix = '.fpai-part';

String civitaiPartPath(String path) => '$path$kCivitaiPartSuffix';

/// Where a Comfy checkpoint with its own encoders and VAE belongs, or null
/// when the download cannot be one. Only a diffusion-folder `.safetensors`
/// Checkpoint chosen by name can turn out to be all-in-one.
String? civitaiAllInOnePath({
  required String root,
  required String backend,
  required String folder,
  required String modelType,
  required String name,
}) {
  if (backend != 'comfyui' || folder != 'diffusion_models') return null;
  if (modelType.trim().toLowerCase() != 'checkpoint') return null;
  if (p.extension(name).toLowerCase() != '.safetensors') return null;
  return civitaiDownloadPath(root: root, folder: 'checkpoints', name: name);
}

/// Folders no download may be written into, once links are resolved: a
/// system location, the drive root, or the home folder itself.
List<String> civitaiSystemFolders() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    return [
      for (final key in ['SystemRoot', 'ProgramFiles', 'ProgramFiles(x86)'])
        if ((env[key] ?? '').isNotEmpty) env[key]!,
    ];
  }
  return const [
    '/etc',
    '/usr',
    '/bin',
    '/sbin',
    '/lib',
    '/lib32',
    '/lib64',
    '/boot',
    '/dev',
    '/proc',
    '/sys',
    '/System',
    '/Library',
    '/private/etc',
  ];
}

Future<String?> _resolved(String path) async {
  try {
    return await Directory(path).resolveSymbolicLinks();
  } on FileSystemException {
    return null;
  }
}

/// True when a download may be written into [folder].
///
/// The models folder is whatever the backend uses, so a folder that is a link
/// to another drive is fine. What is refused is a folder that, once every link
/// is followed, is the drive root, the home folder itself, or a system
/// folder. A folder that does not exist yet is judged by its nearest existing
/// parent. [home] and [systemFolders] default to this machine's.
Future<bool> civitaiFolderIsSafe(
  String folder, {
  String? home,
  List<String>? systemFolders,
}) async {
  var probe = p.normalize(folder);
  while (!await Directory(probe).exists()) {
    final parent = p.dirname(probe);
    if (parent == probe) return false;
    probe = parent;
  }
  final real = await _resolved(probe);
  if (real == null) return false;
  if (real == p.rootPrefix(real) || p.dirname(real) == real) return false;
  final homePath =
      home ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  if (homePath.isNotEmpty && real == (await _resolved(homePath) ?? homePath)) {
    return false;
  }
  for (final system in systemFolders ?? civitaiSystemFolders()) {
    final realSystem = await _resolved(system) ?? system;
    if (real == realSystem || p.isWithin(realSystem, real)) return false;
  }
  return true;
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

/// Writes [contents] to [target] so a crash cannot leave half a file: a temp
/// file beside it is written and flushed, then renamed over [target]. A reader
/// sees the old file or the whole new one. [writeTemp] is for tests.
Future<void> writeFileAtomically(
  File target,
  String contents, {
  Future<void> Function(File temp, String contents)? writeTemp,
}) async {
  final temp = File(
    '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    if (writeTemp != null) {
      await writeTemp(temp, contents);
    } else {
      final out = await temp.open(mode: FileMode.write);
      try {
        await out.writeString(contents);
        await out.flush();
      } finally {
        await out.close();
      }
    }
    await temp.rename(target.path);
  } catch (_) {
    try {
      if (await temp.exists()) await temp.delete();
    } on FileSystemException {
      // Nothing more to do; the original file is untouched.
    }
    rethrow;
  }
}

final Map<String, Future<void>> _loraCatalogWrites = {};

/// Adds [filename] to Draw Things' LoRA catalog when it is not already there.
/// A catalog that is not a list is left alone. The write is atomic, and two
/// callers for the same catalog take turns, so neither loses the other's row.
Future<void> rememberDrawThingsLora(
  Directory modelsDir,
  String filename, {
  Future<void> Function(File temp, String contents)? writeTemp,
}) async {
  final key = p.join(modelsDir.path, 'custom_lora.json');
  final turn = (_loraCatalogWrites[key] ?? Future<void>.value())
      .catchError((Object _) {})
      .then((_) => _addLoraRow(key, filename, writeTemp));
  _loraCatalogWrites[key] = turn;
  try {
    await turn;
  } finally {
    if (identical(_loraCatalogWrites[key], turn)) {
      _loraCatalogWrites.remove(key);
    }
  }
}

Future<void> _addLoraRow(
  String path,
  String filename,
  Future<void> Function(File temp, String contents)? writeTemp,
) async {
  final base = p.basename(filename);
  if (base.isEmpty) return;
  final catalog = File(path);
  final rows = <dynamic>[];
  if (await catalog.exists()) {
    try {
      final decoded = jsonDecode(await catalog.readAsString());
      if (decoded is! List) return;
      rows.addAll(decoded);
    } catch (e) {
      debugPrint(
        'custom_lora.json left alone, it did not read: ${e.runtimeType}',
      );
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
  await writeFileAtomically(catalog, jsonEncode(rows), writeTemp: writeTemp);
}
