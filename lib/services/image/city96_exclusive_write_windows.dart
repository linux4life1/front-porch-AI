// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Replaces ComfyUI-GGUF's loader.py on Windows with the same guarantees as the
// POSIX writer: every new file is created exclusively and written through the
// handle that creation returned, never by name again; the folder is held open
// (nobody can rename or delete it) for the whole operation; and the new file
// is renamed over loader.py by handle.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'city96_write_common.dart';
import 'comfy_process_probe_windows.dart';
import 'windows_api.dart';

const _kNotWritten =
    'Front Porch could not update its ComfyUI-GGUF loader safely on this '
    'computer, so it was left alone.';

City96WriteRefused _failed(String what, int err) =>
    City96WriteRefused('$_kNotWritten ($what: Windows error $err)');

/// Writes [patched] over [loader] (`.../ComfyUI-GGUF/loader.py`), keeping the
/// original as `loader.py.bak` unless one is already there. [afterCreate]
/// (after a new file exists, before it is written) and [beforeRename] are for
/// tests, as is [api].
Future<void> writeCity96LoaderWindows(
  File loader,
  String patched, {
  Win32Api api = kWin32,
  void Function(String path)? afterCreate,
  Future<void> Function(String temp)? beforeRename,
}) async {
  final folderPath = p.windows.dirname(loader.path);
  final bakPath = '${loader.path}.bak';
  final tempPath = '${loader.path}.fpai-tmp-${city96Token()}';
  var folder = kInvalidHandle;
  var temp = kInvalidHandle;
  var madeBackup = false;
  var done = false;
  try {
    // Hold the folder without FILE_SHARE_DELETE: it cannot be renamed, moved
    // or replaced while this runs.
    final (fh, fErr) = api.createFile(
      folderPath,
      kReadControl | kFileReadAttributes,
      kShareRead | kShareWrite,
      kOpenExisting,
      kFlagBackupSemantics | kFlagOpenReparsePoint,
    );
    if (fh == kInvalidHandle) throw _failed('open the folder', fErr);
    folder = fh;
    _requirePlain(api, folder, folderPath, 'folder');

    final original = _readChecked(api, loader.path);

    // The backup: created new, or the one already there stays.
    final (bh, bErr) = api.createFile(
      bakPath,
      kGenericWrite | kDelete | kReadControl,
      0,
      kCreateNew,
      kFlagOpenReparsePoint | kFlagWriteThrough,
    );
    if (bh == kInvalidHandle) {
      if (bErr != kErrorFileExists) throw _failed('create the backup', bErr);
    } else {
      madeBackup = true;
      try {
        afterCreate?.call(bakPath);
        final werr = api.writeAll(bh, original);
        if (werr != 0) throw _failed('write the backup', werr);
        final ferr = api.flush(bh);
        if (ferr != 0) throw _failed('flush the backup', ferr);
        _requireNotReparse(api, bh, 'backup');
      } finally {
        api.closeHandle(bh);
      }
    }

    final (th, tErr) = api.createFile(
      tempPath,
      kGenericWrite | kDelete | kReadControl,
      0,
      kCreateNew,
      kFlagOpenReparsePoint | kFlagWriteThrough,
    );
    if (th == kInvalidHandle) throw _failed('create the new file', tErr);
    temp = th;
    afterCreate?.call(tempPath);
    final werr = api.writeAll(temp, Uint8List.fromList(utf8.encode(patched)));
    if (werr != 0) throw _failed('write the new file', werr);
    final ferr = api.flush(temp);
    if (ferr != 0) throw _failed('flush the new file', ferr);
    _requireNotReparse(api, temp, 'new file');
    await beforeRename?.call(tempPath);

    // Rename by handle, replacing loader.py. Where that form is not
    // supported, the older form; only then a path move, with the folder still
    // held and the new file closed.
    var err = api.renameByHandle(temp, loader.path, ex: true);
    if (err != 0) err = api.renameByHandle(temp, loader.path, ex: false);
    if (err != 0) {
      api.closeHandle(temp);
      temp = kInvalidHandle;
      err = api.moveReplacing(tempPath, loader.path);
    }
    if (err != 0) throw _failed('replace loader.py', err);
    done = true;
  } finally {
    api.closeHandle(temp);
    if (!done) {
      api.deletePath(tempPath);
      if (madeBackup) api.deletePath(bakPath);
    }
    api.closeHandle(folder);
  }
}

void _requirePlain(Win32Api api, int handle, String path, String what) {
  _requireNotReparse(api, handle, what);
  final final_ = api.finalPath(handle);
  if (final_ == null || !windowsSpelledAs(api, final_, path)) {
    throw City96WriteRefused(
      'Its ComfyUI-GGUF $what is not where it is spelled (a link, a '
      'substituted drive or a short name), so it was left alone.',
    );
  }
}

void _requireNotReparse(Win32Api api, int handle, String what) {
  final attributes = api.handleAttributes(handle);
  if (attributes == null) throw _failed('read the $what', 0);
  if (attributes & kAttributeReparsePoint != 0) {
    throw City96WriteRefused(
      'Its ComfyUI-GGUF $what is a link, so it was left alone.',
    );
  }
}

Uint8List _readChecked(Win32Api api, String path) {
  final (h, err) = api.createFile(
    path,
    kGenericRead,
    kShareRead,
    kOpenExisting,
    kFlagOpenReparsePoint,
  );
  if (h == kInvalidHandle) throw _failed('open loader.py', err);
  try {
    _requireNotReparse(api, h, 'loader.py');
    final (data, rerr) = api.readAll(h);
    if (data == null) throw _failed('read loader.py', rerr);
    return data;
  } finally {
    api.closeHandle(h);
  }
}

/// Creates [path] (which must not exist) and writes [bytes] through the handle
/// creation returned: the Windows form of writeNewFileExclusive. Throws
/// [PathExistsException] when the name is taken.
void writeNewFileExclusiveWindows(
  String path,
  List<int> bytes, {
  void Function(String path)? afterCreate,
  Win32Api api = kWin32,
}) {
  final (h, err) = api.createFile(
    path,
    kGenericWrite | kDelete | kReadControl,
    0,
    kCreateNew,
    kFlagOpenReparsePoint | kFlagWriteThrough,
  );
  if (h == kInvalidHandle) {
    if (err == kErrorFileExists) {
      throw PathExistsException(path, OSError('File exists', err));
    }
    throw _failed('create a file', err);
  }
  try {
    afterCreate?.call(path);
    final werr = api.writeAll(h, Uint8List.fromList(bytes));
    if (werr != 0) throw _failed('write a file', werr);
    final ferr = api.flush(h);
    if (ferr != 0) throw _failed('flush a file', ferr);
    _requireNotReparse(api, h, 'file');
  } finally {
    api.closeHandle(h);
  }
}
