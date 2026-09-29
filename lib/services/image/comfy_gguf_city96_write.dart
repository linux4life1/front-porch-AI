// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'city96_exclusive_write.dart';
import 'city96_exclusive_write_windows.dart';
import 'city96_write_common.dart';
import 'comfy_process_probe.dart';

export 'city96_write_common.dart' show City96WriteRefused;

/// What may be said about writing [loader]: a reason to refuse, or whether
/// other users could change what is being written to (a warning, not a
/// refusal: the person is told when they are asked).
class City96Judgement {
  const City96Judgement({this.refusal, this.othersCanWrite = false});

  final String? refusal;
  final bool othersCanWrite;
}

const String kCity96OthersCanWrite =
    'Other users on this computer can change this folder.';

/// Judges [loader], the ComfyUI-GGUF folder and `custom_nodes` above it, and
/// `loader.py.bak` if there is one, the same way on every OS.
///
/// Refused: a check that cannot be answered, a link, junction or reparse
/// point anywhere on the way, an owner that is not this user (an
/// administrator or root owner is told to update by hand), and an access list
/// that lets anyone at all in. Allowed with [City96Judgement.othersCanWrite]:
/// other users may change the folder or the files.
Future<City96Judgement> city96Judge(
  File loader, {
  ComfyProcessProbe probe = const ComfyProcessProbe(),
}) async {
  City96Judgement refuse(String why) => City96Judgement(refusal: why);
  final me = await probe.currentPrincipal();
  if (me == null) {
    return refuse(
      'Front Porch cannot tell which user it runs as here, so it cannot '
      'check whose ComfyUI-GGUF loader this is and left it alone. Update '
      'ComfyUI-GGUF by hand.',
    );
  }
  final folder = loader.parent;
  final checks = <(String path, bool folder, String what)>[
    (folder.parent.parent.path, true, 'ComfyUI folder'),
    (folder.parent.path, true, 'custom_nodes folder'),
    (folder.path, true, 'ComfyUI-GGUF folder'),
    (loader.path, false, 'loader'),
    if (await FileSystemEntity.type('${loader.path}.bak', followLinks: false) !=
        FileSystemEntityType.notFound)
      ('${loader.path}.bak', false, 'loader backup'),
  ];
  var others = false;
  for (final (path, isFolder, what) in checks) {
    final facts = await probe.pathFacts(path, folder: isFolder);
    if (facts == null) {
      return refuse(
        'Front Porch could not check who owns its $what, so it left the '
        'loader alone.',
      );
    }
    if (facts.problem != null) return refuse(facts.problem!);
    if (facts.isLink) {
      return refuse(
        'Its $what is, or is reached through, a link or a junction, so the '
        'loader was left alone.',
      );
    }
    if (what == 'ComfyUI folder') continue; // Only its being a link matters.
    final owner = facts.owner;
    if (owner == null) {
      return refuse(
        'Front Porch could not check who owns its $what, so it left the '
        'loader alone.',
      );
    }
    if (owner != me) {
      return refuse(
        facts.ownerIsAdmin
            ? 'Its $what is owned by an administrator (root, Administrators '
                  'or SYSTEM), so Front Porch left it alone. Update '
                  'ComfyUI-GGUF by hand.'
            : 'Its $what belongs to another user, so the loader was left '
                  'alone.',
      );
    }
    final canWrite = facts.othersCanWrite;
    if (canWrite == null) {
      return refuse(
        'Front Porch could not check who else can write to its $what, so it '
        'left the loader alone.',
      );
    }
    others = others || canWrite;
  }
  return City96Judgement(othersCanWrite: others);
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
  final judged = await city96Judge(loader, probe: probe);
  if (judged.refusal != null) throw City96WriteRefused(judged.refusal!);
  if (Platform.isWindows) {
    return writeCity96LoaderWindows(
      loader,
      patched,
      afterCreate: afterCreate,
      beforeRename: (temp) async => beforeRename?.call(File(temp)),
    );
  }
  final bak = File('${loader.path}.bak');
  var madeBackup = false;
  final temp = File('${loader.path}.fpai-tmp-${city96Token()}');
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
