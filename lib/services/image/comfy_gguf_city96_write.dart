// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'comfy_process_probe.dart';

/// The update was not written, and why. The message is shown as it is.
class City96WriteRefused implements Exception {
  const City96WriteRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Why [loader] must not be written, or null when it may be. Refuses a link
/// or a file owned by someone else at `loader.py` and `loader.py.bak`: a
/// link would send the write somewhere else, and a foreign-owned file is not
/// this person's to change.
Future<String?> city96TargetProblem(
  File loader, {
  ComfyProcessProbe probe = const ComfyProcessProbe(),
}) async {
  final me = await probe.currentUid();
  for (final path in [loader.path, '${loader.path}.bak']) {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      continue;
    }
    if (await FileSystemEntity.isLink(path)) {
      return 'Its ComfyUI-GGUF loader (or its backup) is a link, so it was '
          'left alone.';
    }
    final owner = await probe.fileOwner(path);
    if (me != null && owner != null && owner != me) {
      return 'Its ComfyUI-GGUF loader (or its backup) belongs to another '
          'user, so it was left alone.';
    }
  }
  return null;
}

String _token() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Keeps the original as `loader.py.bak` (never replacing one that is
/// already there), then replaces `loader.py` through a new, unpredictably
/// named file beside it, so a crash never leaves half a loader and a planted
/// name is never written through. The file keeps its mode. When anything
/// fails the temp file, and a backup made by this call, are removed.
Future<void> writeCity96Loader(
  File loader,
  String patched, {
  ComfyProcessProbe probe = const ComfyProcessProbe(),
  @visibleForTesting FutureOr<void> Function(File temp)? beforeRename,
}) async {
  final problem = await city96TargetProblem(loader, probe: probe);
  if (problem != null) throw City96WriteRefused(problem);
  final bak = File('${loader.path}.bak');
  var madeBackup = false;
  final temp = File('${loader.path}.fpai-tmp-${_token()}');
  try {
    try {
      await bak.create(exclusive: true);
      madeBackup = true;
      await bak.writeAsBytes(await loader.readAsBytes());
    } on PathExistsException {
      // An earlier backup stays as it is.
    }
    await temp.create(exclusive: true);
    final out = await temp.open(mode: FileMode.write);
    try {
      await out.writeString(patched);
      await out.flush();
    } finally {
      await out.close();
    }
    await _keepMode(loader, temp);
    await beforeRename?.call(temp);
    await temp.rename(loader.path);
  } catch (_) {
    if (await temp.exists()) await temp.delete();
    if (madeBackup && await bak.exists()) await bak.delete();
    rethrow;
  }
}

Future<void> _keepMode(File from, File to) async {
  if (Platform.isWindows) return;
  final mode = (await from.stat()).mode & 0xFFF;
  final result = await Process.run('chmod', [mode.toRadixString(8), to.path]);
  if (result.exitCode != 0) {
    throw FileSystemException('chmod failed', to.path);
  }
}
