// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'city96_exclusive_write.dart';
import 'comfy_process_probe.dart';

/// The update was not written, and why. The message is shown as it is.
class City96WriteRefused implements Exception {
  const City96WriteRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Why [loader] must not be written, or null when it may be.
///
/// Every check that cannot be answered refuses: a missing `id`, `stat` or
/// Windows (which has no user ids here) is "not checked", and unchecked is
/// not allowed. The ComfyUI-GGUF folder has to be this user's and closed to
/// group and world writes, because a name in it is what a write goes through.
/// `loader.py` and `loader.py.bak` may not be links or another user's.
Future<String?> city96TargetProblem(
  File loader, {
  ComfyProcessProbe probe = const ComfyProcessProbe(),
}) async {
  final me = await probe.currentUid();
  if (me == null) {
    return 'Front Porch cannot tell which user it runs as here, so it cannot '
        'check whose ComfyUI-GGUF loader this is and left it alone. Update '
        'ComfyUI-GGUF by hand.';
  }
  final folder = loader.parent.path;
  final folderOwner = await probe.fileOwner(folder);
  final folderMode = await probe.filePermissions(folder);
  if (folderOwner == null || folderMode == null) {
    return 'Front Porch could not check who owns the ComfyUI-GGUF folder, so '
        'it left the loader alone.';
  }
  if (folderOwner != me) {
    return 'The ComfyUI-GGUF folder belongs to another user, so its loader '
        'was left alone.';
  }
  if (folderMode & 0x12 != 0) {
    return 'The ComfyUI-GGUF folder can be written by other users, so its '
        'loader was left alone.';
  }
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
    if (owner == null) {
      return 'Front Porch could not check who owns its ComfyUI-GGUF loader, '
          'so it was left alone.';
    }
    if (owner != me) {
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
/// name is never written through. Both new files are created exclusively and
/// written through the descriptor that creation returned, never by name
/// again, and end with `loader.py`'s mode. When anything fails the temp file,
/// and a backup made by this call, are removed.
///
/// [afterCreate] (after a new file is created, before it is written) and
/// [beforeRename] are for tests.
Future<void> writeCity96Loader(
  File loader,
  String patched, {
  ComfyProcessProbe probe = const ComfyProcessProbe(),
  @visibleForTesting void Function(String path)? afterCreate,
  @visibleForTesting FutureOr<void> Function(File temp)? beforeRename,
}) async {
  final problem = await city96TargetProblem(loader, probe: probe);
  if (problem != null) throw City96WriteRefused(problem);
  final bak = File('${loader.path}.bak');
  var madeBackup = false;
  final temp = File('${loader.path}.fpai-tmp-${_token()}');
  try {
    final mode = (await loader.stat()).mode & 0xFFF;
    try {
      writeNewFileExclusive(
        bak.path,
        await loader.readAsBytes(),
        mode: mode,
        afterCreate: afterCreate,
      );
      madeBackup = true;
    } on PathExistsException {
      // An earlier backup stays as it is.
    }
    writeNewFileExclusive(
      temp.path,
      utf8.encode(patched),
      mode: mode,
      afterCreate: afterCreate,
    );
    // A name that became a link since it was created is not ours any more.
    for (final made in [temp, if (madeBackup) bak]) {
      if (await FileSystemEntity.isLink(made.path)) {
        throw const City96WriteRefused(
          'A file beside its ComfyUI-GGUF loader was replaced by a link while '
          'it was being written, so nothing was changed.',
        );
      }
    }
    await beforeRename?.call(temp);
    await temp.rename(loader.path);
  } on UnsupportedError {
    throw const City96WriteRefused(
      'Front Porch cannot write this file safely on this system, so its '
      'ComfyUI-GGUF loader was left alone. Update ComfyUI-GGUF by hand.',
    );
  } catch (_) {
    if (await temp.exists()) await temp.delete();
    if (madeBackup && await bak.exists()) await bak.delete();
    rethrow;
  }
}
