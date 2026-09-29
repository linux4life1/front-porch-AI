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

/// Why a phone download cannot start, or null when the folder is usable.
String? civitaiBlockedDownload({
  required String backend,
  required String? savedRoot,
}) {
  if (backend != 'comfyui' && backend != 'a1111' && backend != 'drawthings') {
    return 'CivitAI downloads are for ComfyUI, Automatic1111, and Draw Things';
  }
  if (savedRoot == null || savedRoot.trim().isEmpty) {
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

/// True when the saved Comfy URL is not this computer.
Future<bool> comfyStudioIsRemote() async {
  return !await comfyHostIsLocal(await studioComfyUrl());
}

Future<String?> savedStudioModelRoot(String backend) async {
  String? discovered;
  if (backend == 'comfyui') {
    final url = await studioComfyUrl();
    if (!await comfyHostIsLocal(url)) return null;
    discovered = await discoverComfyModelsRoot(preferPort: comfyUrlPort(url));
  } else if (backend == 'a1111') {
    discovered = await discoverAutomatic1111Root();
  } else if (backend == 'drawthings') {
    final dir = drawThingsDefaultModelsDirectory();
    if (dir != null && await dir.exists()) discovered = dir.path;
  } else {
    return null;
  }
  if (discovered != null) return discovered;
  final prefs = await SharedPreferences.getInstance();
  final saved = modelRootFor(
    decodeModelRoots(prefs.getString(kStudioModelRootsKey)),
    backend,
  );
  if (saved == null || !await Directory(saved).exists()) return null;
  return saved;
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
