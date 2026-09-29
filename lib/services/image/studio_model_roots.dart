// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/grpc/dt_native/dt_local_loras.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/local_model_roots.dart';

/// Prefs name for the models folders the desk remembers. Not a legacy key.
const String kStudioModelRootsKey = 'image_studio_model_roots';

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

/// Every models folder the person saved, whichever backend it is for.
Future<List<String>> studioSavedModelRoots() async {
  final prefs = await SharedPreferences.getInstance();
  return [
    for (final folder in decodeModelRoots(
      prefs.getString(kStudioModelRootsKey),
    ).values)
      if (folder.trim().isNotEmpty) folder.trim(),
  ];
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
  final roots = decodeModelRoots(prefs.getString(kStudioModelRootsKey));
  roots[backend] = root.trim();
  await prefs.setString(kStudioModelRootsKey, encodeModelRoots(roots));
}
