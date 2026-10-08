// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/grpc/dt_native/dt_local_loras.dart';
import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/local_model_roots.dart';

/// Prefs name for the models folders the desk remembers. Not a legacy key.
const String kStudioModelRootsKey = 'image_studio_model_roots';

/// Each saved folder as it resolved (every link followed) when it was saved,
/// by the same keys. Downloads are judged against these, so a link put inside
/// a saved folder later does not count as being inside it.
const String kStudioModelRootsResolvedKey = 'image_studio_model_roots_resolved';

/// Folders a backend's config named that the person chose to use, as
/// `[{"path": ..., "resolved": ...}]`.
const String kStudioExtraModelRootsKey = 'image_studio_extra_model_roots';

Map<String, String> decodeModelRoots(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        entry.key.toString(): entry.value.toString(),
    };
  } on FormatException {
    return const {};
  }
}

String encodeModelRoots(Map<String, String> roots) => jsonEncode(roots);

/// ComfyUI, Automatic1111, and Draw Things can have a folder.
String? modelRootFor(Map<String, String> roots, String backend) {
  if (backend != 'comfyui' && backend != 'a1111' && backend != 'drawthings') {
    return null;
  }
  final value = roots[backend]?.trim() ?? '';
  if (value.isEmpty) return null;
  return value;
}

/// Said when the folder the person saved no longer exists. It carries no
/// path, so the phone can be told too.
const String kStudioSavedFolderGone =
    'The models folder you saved is gone. Pick it again on this computer.';

/// Why a phone download cannot start, or null when the folder is usable.
/// [savedGone] says the folder the person saved no longer exists.
String? civitaiBlockedDownload({
  required String backend,
  required String? savedRoot,
  bool savedGone = false,
}) {
  if (backend != 'comfyui' && backend != 'a1111' && backend != 'drawthings') {
    return 'CivitAI downloads are for ComfyUI, Automatic1111, and Draw Things';
  }
  if (savedRoot == null || savedRoot.trim().isEmpty) {
    if (savedGone) return kStudioSavedFolderGone;
    if (backend == 'drawthings') {
      return 'Draw Things models folder was not found on this Mac';
    }
    return 'Pick your models folder on this computer first';
  }
  return null;
}

/// Saved Comfy URL, or Comfy's default port on this computer.
Future<String> studioComfyUrl() async {
  final prefs = await SharedPreferences.getInstance();
  final key = isPreRelease ? 'beta_comfy_ui_url' : 'comfy_ui_url';
  final saved = prefs.getString(key)?.trim() ?? '';
  if (saved.isEmpty) return 'http://127.0.0.1:8188';
  return saved;
}

/// Every models folder the person saved or chose to use, as it resolved when
/// they did. A folder saved before this was recorded is resolved now.
Future<List<String>> studioSavedModelRoots() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = decodeModelRoots(prefs.getString(kStudioModelRootsKey));
  final resolved = decodeModelRoots(
    prefs.getString(kStudioModelRootsResolvedKey),
  );
  final out = <String>[];
  for (final entry in saved.entries) {
    final spelled = entry.value.trim();
    if (spelled.isEmpty) continue;
    final stored = resolved[entry.key]?.trim() ?? '';
    out.add(
      stored.isNotEmpty ? stored : await civitaiRealFolder(spelled) ?? spelled,
    );
  }
  for (final row in _extraRoots(prefs)) {
    final resolvedPath = row['resolved']?.toString().trim() ?? '';
    if (resolvedPath.isNotEmpty) out.add(resolvedPath);
  }
  return out;
}

List<Map<String, dynamic>> _extraRoots(SharedPreferences prefs) {
  final raw = prefs.getString(kStudioExtraModelRootsKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return [
        for (final row in decoded)
          if (row is Map) row.cast<String, dynamic>(),
      ];
    }
  } on FormatException {
    // Nothing chosen is better than a guess.
  }
  return const [];
}

/// Saves [folder], a folder a backend's config named, as a models folder to
/// download into. Only a folder that is safe by itself (not the home folder, a
/// system folder or a hidden folder of home) can be added, whoever asks.
/// Returns false when it was refused.
Future<bool> addTrustedModelFolder(String folder) async {
  final path = folder.trim();
  if (path.isEmpty || !await civitaiFolderIsSafe(path)) return false;
  final real = await civitaiRealFolder(path);
  if (real == null) return false;
  final prefs = await SharedPreferences.getInstance();
  final rows = [..._extraRoots(prefs)];
  if (rows.any((row) => row['resolved'] == real)) return true;
  rows.add({'path': path, 'resolved': real});
  await prefs.setString(kStudioExtraModelRootsKey, jsonEncode(rows));
  return true;
}

/// True when the saved Comfy URL is not this computer.
Future<bool> comfyStudioIsRemote() async {
  return !await comfyHostIsLocal(await studioComfyUrl());
}

/// The folder the person saved for [backend], or null when none is saved.
Future<String?> _savedFolder(String backend) async {
  final prefs = await SharedPreferences.getInstance();
  return modelRootFor(
    decodeModelRoots(prefs.getString(kStudioModelRootsKey)),
    backend,
  );
}

/// True when the person saved a models folder for [backend] and it no longer
/// exists. Then [savedStudioModelRoot] gives none, rather than a guess.
Future<bool> studioSavedRootMissing(String backend) async {
  if (backend != 'comfyui' && backend != 'a1111' && backend != 'drawthings') {
    return false;
  }
  if (backend == 'comfyui' && !await comfyHostIsLocal(await studioComfyUrl())) {
    return false;
  }
  final saved = await _savedFolder(backend);
  return saved != null && !await Directory(saved).exists();
}

/// Where [backend]'s models live on this computer. The folder the person
/// saved wins. If it is gone the answer is none, not a discovered folder:
/// downloads should not land somewhere they did not choose, and they are told
/// ([studioSavedRootMissing]). [discover] (default: scan the machine) only
/// runs when nothing was saved.
Future<String?> savedStudioModelRoot(
  String backend, {
  Future<String?> Function(String backend)? discover,
}) async {
  if (backend != 'comfyui' && backend != 'a1111' && backend != 'drawthings') {
    return null;
  }
  if (backend == 'comfyui' && !await comfyHostIsLocal(await studioComfyUrl())) {
    return null;
  }
  final saved = await _savedFolder(backend);
  if (saved != null) return await Directory(saved).exists() ? saved : null;
  return (discover ?? _discoverModelRoot)(backend);
}

Future<String?> _discoverModelRoot(String backend) async {
  switch (backend) {
    case 'comfyui':
      return discoverComfyModelsRoot(
        preferPort: comfyUrlPort(await studioComfyUrl()),
      );
    case 'a1111':
      return discoverAutomatic1111Root();
    case 'drawthings':
      final dir = drawThingsDefaultModelsDirectory();
      if (dir != null && await dir.exists()) return dir.path;
  }
  return null;
}

/// Where each kind of weight goes for [backend] when [root] is its models
/// folder, for the kinds its ComfyUI config sends elsewhere. Empty for the
/// other backends and when every kind lives under [root].
/// [discover] defaults to reading this computer's ComfyUI configs.
Future<Map<String, String>> studioModelTypeFolders(
  String backend,
  String? root, {
  Future<Map<String, String>> Function(String root, int port)? discover,
}) async {
  if (backend != 'comfyui' || root == null || root.trim().isEmpty) {
    return const {};
  }
  final url = await studioComfyUrl();
  if (!await comfyHostIsLocal(url)) return const {};
  final port = comfyUrlPort(url);
  if (discover != null) return discover(root, port);
  return discoverComfyTypeFolders(root, preferPort: port);
}

Future<void> rememberStudioModelRoot(String backend, String root) async {
  if (backend != 'comfyui' && backend != 'a1111' && backend != 'drawthings') {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final roots = Map.of(decodeModelRoots(prefs.getString(kStudioModelRootsKey)));
  roots[backend] = root.trim();
  await prefs.setString(kStudioModelRootsKey, encodeModelRoots(roots));
  final resolved = Map.of(
    decodeModelRoots(prefs.getString(kStudioModelRootsResolvedKey)),
  );
  resolved[backend] = await civitaiRealFolder(root.trim()) ?? root.trim();
  await prefs.setString(
    kStudioModelRootsResolvedKey,
    encodeModelRoots(resolved),
  );
}
