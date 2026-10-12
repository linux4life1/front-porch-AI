// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The engine files in the bin closet: finding the one a start runs, its
// version record, making it runnable, and removing them all.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

/// The engine file a start runs: [wanted] (the build this machine
/// downloads), or on Linux a build already on disk that carries [backend]
/// (a ROCm choice never runs on a build without ROCm). Null: none is there.
Future<File?> findEngineFile({
  required String binDir,
  required String wanted,
  required bool onLinux,
  required GpuBackend backend,
  required bool avx2,
}) async {
  if (!onLinux) {
    final file = File(path.join(binDir, wanted));
    return await file.exists() ? file : null;
  }
  final onDisk = <String>[
    for (final name in {wanted, ...kLinuxEngineBuilds.keys})
      if (await File(path.join(binDir, name)).exists()) name,
  ];
  final pick = linuxEngineFor(
    wanted: wanted,
    backend: backend,
    onDisk: onDisk,
    avx2: avx2,
  );
  return pick == null ? null : File(path.join(binDir, pick));
}

/// The version and size of the build at [exe], from its own entry in the
/// record: another build's entry would show its version for this one.
Future<({String? version, int? size})> readEngineVersion(String? exe) async {
  final version = exe == null
      ? null
      : await KoboldBinaryVersion.versionFor(exe);
  int? size;
  try {
    size = exe != null && await File(exe).exists()
        ? await File(exe).length()
        : null;
  } on FileSystemException catch (e) {
    debugPrint('[Kobold] the engine file could not be read: $e');
    size = null;
  }
  return (version: version, size: size);
}

/// Deletes every engine file beside [exe] (each `koboldcpp*` variant, a
/// half-downloaded `.part`) and the version record. Throws
/// [FileSystemException] when one cannot go.
Future<void> deleteEngineFiles(String exe) async {
  final dir = Directory(path.dirname(exe));
  await for (final entry in dir.list()) {
    if (entry is! File) continue;
    final name = path.basename(entry.path);
    if (name.startsWith('koboldcpp') || name == KoboldBinaryVersion.fileName) {
      await entry.delete();
    }
  }
}

/// Records [remoteVersion] for the engine just downloaded into [binDir].
/// Null (the lookup failed, or was for another build): no record beats the
/// old engine's, which would refuse this one as too old.
Future<void> recordEngineVersion(
  String binDir,
  String? remoteVersion,
  int size,
) async {
  if (remoteVersion != null) {
    await KoboldBinaryVersion.write(binDir, version: remoteVersion, size: size);
  } else {
    final stale = File(path.join(binDir, KoboldBinaryVersion.fileName));
    if (await stale.exists()) await stale.delete();
  }
}

/// Makes [exe] runnable: executable permission on Linux/Mac, and on macOS
/// the quarantine attribute the sandbox sets on downloads cleared.
Future<void> prepareEngineExecutable(String exe) async {
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', exe]);
  }
  if (Platform.isMacOS) {
    await Process.run('xattr', ['-cr', exe]);
    print('AG_DEBUG: Cleared quarantine on $exe');
  }
}

/// Whether nvidia-smi answers, i.e. the CUDA build can use this machine.
Future<bool> probeCuda() async {
  try {
    final cudaRes = await Process.run('nvidia-smi', []);
    final hasCuda = cudaRes.exitCode == 0;
    print('AG_DEBUG: CUDA detected: $hasCuda');
    return hasCuda;
  } catch (_) {
    print('AG_DEBUG: CUDA not found (nvidia-smi not available)');
    return false;
  }
}
