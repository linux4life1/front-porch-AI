// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'civitai_home_folders.dart';
import 'civitai_version.dart';
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
///
/// [typeFolders] holds the folders the backend's own config sends a kind of
/// weight to (`checkpoints` on another drive, say). A kind listed there is
/// saved in that folder, not under [root].
String? civitaiDownloadPath({
  required String root,
  required String folder,
  required String name,
  Map<String, String> typeFolders = const {},
}) {
  if (!p.isAbsolute(root)) return null;
  if (folder.isNotEmpty && !kCivitaiFolders.contains(folder)) return null;
  final base = safeDownloadBasename(name);
  if (base == null) return null;
  if (!kCivitaiSafeExtensions.contains(p.extension(base).toLowerCase())) {
    return null;
  }
  final own = folder.isEmpty ? null : typeFolders[folder]?.trim();
  if (own != null && own.isNotEmpty) {
    if (!p.isAbsolute(own)) return null;
    final candidate = p.join(own, base);
    return pathStaysUnderRoot(own, candidate) ? candidate : null;
  }
  final candidate = folder.isEmpty
      ? p.join(root, base)
      : p.join(root, folder, base);
  if (!pathStaysUnderRoot(root, candidate)) return null;
  return candidate;
}

/// The folder a kind of weight is read from: its own folder from the
/// backend's config, else `root/folder`.
String civitaiKindFolder(
  String root,
  String folder, [
  Map<String, String> typeFolders = const {},
]) {
  final own = typeFolders[folder]?.trim();
  if (own != null && own.isNotEmpty) return own;
  return folder.isEmpty ? root : p.join(root, folder);
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
  Map<String, String> typeFolders = const {},
}) {
  if (backend != 'comfyui' || folder != 'diffusion_models') return null;
  if (modelType.trim().toLowerCase() != 'checkpoint') return null;
  if (p.extension(name).toLowerCase() != '.safetensors') return null;
  return civitaiDownloadPath(
    root: root,
    folder: 'checkpoints',
    name: name,
    typeFolders: typeFolders,
  );
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

bool _hiddenBelow(String relative) => p
    .split(relative)
    .any((part) => part.startsWith('.') && part != '.' && part != '..');

/// True when [real], a folder with every link followed, is one of the
/// resolved [roots] or inside one. This is the check a link cannot get past:
/// a link inside a models folder that leads to `~/.ssh` resolves to `~/.ssh`.
bool civitaiRealInRoots(String real, List<String> roots) {
  for (final root in roots) {
    if (root.trim().isEmpty) continue;
    if (real == root || p.isWithin(root, real)) return true;
  }
  return false;
}

/// [folder] with every link followed. A folder that does not exist yet is
/// judged by its nearest existing parent. Null when it cannot be resolved.
Future<String?> civitaiRealFolder(String folder) async {
  var probe = p.normalize(folder);
  while (!await Directory(probe).exists()) {
    final parent = p.dirname(probe);
    if (parent == probe) return null;
    probe = parent;
  }
  return _resolved(probe);
}

/// True when [folder] is one of [roots] or inside one, by its own spelling.
/// Links are not followed: a models folder that is a link to another drive
/// stays inside its root. Only for a folder the person's own models folder
/// names; anything a link could redirect is judged by [civitaiRealInRoots].
bool civitaiFolderInRoots(String folder, List<String> roots) {
  final path = p.normalize(folder);
  for (final root in roots) {
    if (root.trim().isEmpty) continue;
    final base = p.normalize(root);
    if (path == base || p.isWithin(base, path)) return true;
  }
  return false;
}

/// True when a download may be written into [folder].
///
/// The models folder is whatever the backend uses, so a folder that is a link
/// to another drive is fine. What is refused is a folder that, once every link
/// is followed, is the drive root, the home folder itself, a system folder, or
/// inside a hidden folder of the home folder (`~/.ssh`, `~/.config`...) or one
/// that the system reads at login ([sensitiveFolders]: `~/Library`, the app
/// data folders) unless
/// what it resolves to is inside one of [roots]: the models folders the person
/// chose, each already resolved (as it was when they chose it), so a link put
/// inside one of them later does not count as being inside it. A folder that
/// does not exist yet is judged by its nearest existing parent. [home] and
/// [systemFolders] default to this machine's.
Future<bool> civitaiFolderIsSafe(
  String folder, {
  String? home,
  List<String>? systemFolders,
  List<String>? sensitiveFolders,
  List<String> roots = const [],
}) async {
  final real = await civitaiRealFolder(folder);
  if (real == null) return false;
  if (real == p.rootPrefix(real) || p.dirname(real) == real) return false;
  final homePath = home ?? civitaiHomeFolder();
  if (homePath.isNotEmpty) {
    final realHome = await _resolved(homePath) ?? homePath;
    if (real == realHome) return false;
    if (p.isWithin(realHome, real) &&
        _hiddenBelow(p.relative(real, from: realHome)) &&
        !civitaiRealInRoots(real, roots)) {
      return false;
    }
  }
  for (final sensitive
      in sensitiveFolders ?? civitaiSensitiveHomeFolders(home: home)) {
    final realSensitive = await _resolved(sensitive) ?? sensitive;
    if ((real == realSensitive || p.isWithin(realSensitive, real)) &&
        !civitaiRealInRoots(real, roots)) {
      return false;
    }
  }
  for (final system in systemFolders ?? civitaiSystemFolders()) {
    final realSystem = await _resolved(system) ?? system;
    if (real == realSystem || p.isWithin(realSystem, real)) return false;
  }
  return true;
}

/// Draw Things' `custom_lora.json` version id for CivitAI's [baseModel].
/// Empty when CivitAI names none, or names one this cannot place: a LoRA with
/// no version shows for every checkpoint, so a guess that is wrong (a file
/// name says Klein, the base is Klein 4B) is worse than none.
String drawThingsVersionForBase(String baseModel) {
  final base = baseModel.trim().toLowerCase();
  if (base.startsWith('flux.2 klein 4b')) return 'flux2_4b';
  if (base.startsWith('flux.2 klein 9b')) return 'flux2_9b';
  if (base == 'flux.2 d') return 'flux2';
  if (base == 'flux.1 d' || base == 'flux.1 s') return 'flux1';
  if (base == 'zimageturbo' || base == 'zimagebase') return 'z_image';
  if (base == 'qwen') return 'qwen_image';
  if (base == 'qwen 2.1') return 'qwen_image_2.1';
  if (base.startsWith('sd 3')) return 'sd3';
  if (base.startsWith('sdxl') ||
      base == 'pony' ||
      base == 'illustrious' ||
      base == 'noobai') {
    return 'sdxl_base_v0.9';
  }
  if (base.startsWith('sd 1.4') || base.startsWith('sd 1.5')) return 'v1';
  return '';
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

/// Adds [filename] to Draw Things' LoRA catalog when it is not already there,
/// tagged with the version for CivitAI's [baseModel] (none when it says none).
/// A catalog that is not a list is left alone. The write is atomic, and two
/// callers for the same catalog take turns, so neither loses the other's row.
Future<void> rememberDrawThingsLora(
  Directory modelsDir,
  String filename, {
  String baseModel = '',
  Future<void> Function(File temp, String contents)? writeTemp,
}) async {
  final key = p.join(modelsDir.path, 'custom_lora.json');
  final turn = (_loraCatalogWrites[key] ?? Future<void>.value())
      .catchError((Object _) {})
      .then((_) => _addLoraRow(key, filename, baseModel, writeTemp));
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
  String baseModel,
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
  final version = drawThingsVersionForBase(baseModel);
  rows.add({
    'file': base,
    'name': p.basenameWithoutExtension(base),
    if (version.isNotEmpty) 'version': version,
  });
  await writeFileAtomically(catalog, jsonEncode(rows), writeTemp: writeTemp);
}
