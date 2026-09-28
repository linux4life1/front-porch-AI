// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

/// ComfyUI and Automatic1111 can have a folder. Other backends cannot.
String? modelRootFor(Map<String, String> roots, String backend) {
  if (backend != 'comfyui' && backend != 'a1111') return null;
  final value = roots[backend]?.trim() ?? '';
  if (value.isEmpty) return null;
  return value;
}

/// Why a phone download cannot start, or null when the folder is usable.
String? civitaiBlockedDownload({
  required String backend,
  required String? savedRoot,
}) {
  if (backend != 'comfyui' && backend != 'a1111') {
    return 'CivitAI downloads are for ComfyUI and Automatic1111';
  }
  if (savedRoot == null || savedRoot.trim().isEmpty) {
    return 'Pick your models folder on this computer first';
  }
  return null;
}

Future<String?> savedStudioModelRoot(String backend) async {
  final prefs = await SharedPreferences.getInstance();
  return modelRootFor(
    decodeModelRoots(prefs.getString(kStudioModelRootsKey)),
    backend,
  );
}

Future<void> rememberStudioModelRoot(String backend, String root) async {
  if (backend != 'comfyui' && backend != 'a1111') return;
  final prefs = await SharedPreferences.getInstance();
  final roots = decodeModelRoots(prefs.getString(kStudioModelRootsKey));
  roots[backend] = root.trim();
  await prefs.setString(kStudioModelRootsKey, encodeModelRoots(roots));
}
