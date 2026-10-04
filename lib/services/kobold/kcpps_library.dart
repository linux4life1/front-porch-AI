// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'kcpps_codec.dart';
import 'kobold_config_stage.dart';

/// The user's presets in KoboldCpp's folder ([dir]), sorted by name, the
/// app's own files left out. The one listing every preset picker uses.
List<File> kcppsPresetFiles(String dir) {
  final folder = Directory(dir);
  try {
    if (!folder.existsSync()) return [];
    return folder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.kcpps'))
        .where((f) => !isAppOwnedKcpps(f.path))
        .toList()
      ..sort(
        (a, b) => kcppsPresetName(
          a.path,
        ).toLowerCase().compareTo(kcppsPresetName(b.path).toLowerCase()),
      );
  } on FileSystemException catch (e) {
    debugPrint('[Presets] cannot list $dir: $e');
    return [];
  }
}

/// A preset's name: its file name, without `.kcpps`.
String kcppsPresetName(String path) => p.basenameWithoutExtension(path);

/// One preset as read from its file.
class KcppsPreset {
  const KcppsPreset({required this.path, required this.read});

  final String path;
  final KcppsRead read;

  String get name => kcppsPresetName(path);
}

/// Why a name cannot be a preset's, in plain words; null when it can.
String? kcppsNameProblem(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'Give the preset a name.';
  if (RegExp(r'[\\/:*?"<>|\x00-\x1F]').hasMatch(n)) {
    return r'A name cannot have any of \ / : * ? " < > | in it.';
  }
  if (n.toLowerCase().startsWith(kStagedConfigPrefix) ||
      n.toLowerCase() == 'fpai_batch_override') {
    return 'Names starting with "$kStagedConfigPrefix" are kept for the '
        "app's own files.";
  }
  if (n.endsWith('.') || n.endsWith(' ')) {
    return 'A name cannot end with a dot or a space.';
  }
  return null;
}

/// Reads, writes, renames, copies and deletes presets in one folder.
///
/// Callers that rename or delete also move or clear what points at the
/// file (see `repointKcppsPreset`).
class KcppsLibrary {
  const KcppsLibrary(this.dir);

  final String dir;

  Future<List<KcppsPreset>> list() async => [
    for (final f in kcppsPresetFiles(dir)) await open(f.path),
  ];

  /// Any `.kcpps`, this folder's or not. Never throws: a file that cannot
  /// be read comes back as [KcppsBroken].
  static Future<KcppsPreset> open(String path) async {
    try {
      final text = await File(path).readAsString();
      return KcppsPreset(path: path, read: readKcpps(text));
    } on FileSystemException catch (e) {
      return KcppsPreset(
        path: path,
        read: KcppsBroken('This preset file could not be read (${e.message}).'),
      );
    }
  }

  /// Where a preset called [name] is kept.
  String pathFor(String name) => p.join(dir, '${name.trim()}.kcpps');

  /// The preset called [name], when there is one.
  Future<bool> exists(String name) => File(pathFor(name)).exists();

  /// Writes [map] as the preset called [name], over any preset of that
  /// name. Returns its path.
  Future<String> write(String name, Map<String, dynamic> map) async {
    await Directory(dir).create(recursive: true);
    final file = await stageKoboldConfig(
      dir,
      '${name.trim()}.kcpps',
      encodeKcpps(map),
    );
    return file.path;
  }

  /// Renames the preset at [path] to [name]. Returns the new path.
  Future<String> rename(String path, String name) async {
    final target = pathFor(name);
    if (p.equals(path, target)) return path;
    return (await File(path).rename(target)).path;
  }

  /// A copy of the preset at [path] under the first free "(copy)" name.
  Future<String> duplicate(String path) async {
    final base = '${kcppsPresetName(path)} (copy)';
    var name = base;
    for (var n = 2; await exists(name); n++) {
      name = '$base $n';
    }
    final target = pathFor(name);
    await File(path).copy(target);
    return target;
  }

  Future<void> delete(String path) => File(path).delete();
}
