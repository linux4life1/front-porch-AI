// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as p;

/// The person's home folder: `USERPROFILE` on Windows (where `HOME` is only
/// set by a Unix-style shell), `HOME` elsewhere. Empty when neither is set.
String civitaiHomeFolder({Map<String, String>? env, String? os}) {
  env ??= Platform.environment;
  os ??= Platform.operatingSystem;
  final keys = os == 'windows'
      ? const ['USERPROFILE', 'HOME']
      : const ['HOME', 'USERPROFILE'];
  for (final key in keys) {
    final value = env[key] ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// Folders of the home folder that hold what a login runs or a program keeps
/// for the system, though they are not named with a dot: `~/Library` on macOS
/// (LaunchAgents are in it) and, on Windows, the roaming and local app data
/// folders (the Startup folder is in the first). Empty on Linux, where those
/// are dot folders.
///
/// With a [home] given, the Windows folders are the ones under it: the
/// environment's own app data folders count only when they are inside it, so a
/// home folder that is not this machine's (a test's, a copy's) is judged by
/// its own `AppData`.
List<String> civitaiSensitiveHomeFolders({
  String? home,
  Map<String, String>? env,
  String? os,
}) {
  env ??= Platform.environment;
  os ??= Platform.operatingSystem;
  if (os == 'macos') {
    final h = home ?? civitaiHomeFolder(env: env, os: os);
    return [if (h.isNotEmpty) p.join(h, 'Library')];
  }
  if (os != 'windows') return const [];
  final w = p.windows;
  final h = home ?? civitaiHomeFolder(env: env, os: os);
  final found = <String>[];
  void add(String path) {
    if (path.isNotEmpty && !found.any((f) => w.equals(f, path))) {
      found.add(path);
    }
  }

  for (final key in ['APPDATA', 'LOCALAPPDATA']) {
    final value = env[key] ?? '';
    if (home == null || (value.isNotEmpty && w.isWithin(home, value))) {
      add(value);
    }
  }
  if (h.isNotEmpty) {
    add(w.join(h, 'AppData', 'Roaming'));
    add(w.join(h, 'AppData', 'Local'));
  }
  return found;
}
