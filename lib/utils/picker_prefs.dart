// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';

// Re-export the file_picker types call sites need. FilePickerResult is gone
// in file_picker 12; we keep a local shim below.
export 'package:file_picker/file_picker.dart' show FileType, PlatformFile;

/// Compatibility shim for file_picker 12, which dropped [FilePickerResult]
/// and now returns `List<PlatformFile>` (empty list = cancel).
class FilePickerResult {
  const FilePickerResult(this.files);

  final List<PlatformFile> files;

  /// Bytes of the first picked file, or null when empty / unreadable.
  ///
  /// Uses [PlatformFile.readAsBytes] (file_picker 12 dropped `.bytes`).
  /// Call only for small picks (images, json, txt, lore). Never use this
  /// for GGUF; path-based model/voice imports stay on [PlatformFile.path].
  Future<Uint8List?> firstBytes() async {
    if (files.isEmpty) return null;
    final bytes = await files.first.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }
}

/// In-memory [PlatformFile] for tests and the web chargen facade.
/// file_picker 12 made [PlatformFile] an abstract base with no constructor.
base class MemoryPlatformFile extends PlatformFile {
  MemoryPlatformFile({required this.name, required Uint8List bytes})
      : _bytes = bytes;

  @override
  final String name;

  final Uint8List _bytes;

  @override
  Uri get uri => Uri(scheme: 'memory', path: '/$name');

  @override
  XFile get xFile => XFile.fromData(_bytes, name: name);

  @override
  Future<int> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream<Uint8List>.value(_bytes);
}

/// Thin wrapper around `FilePicker` that remembers the last folder
/// used per [category] and reopens the native dialog there (#84).
///
/// file_picker ≥12.1.1 is required: 12.0.0's facade does not forward
/// allowMultiple/withData/withReadStream, and skipEntitlementsChecks is a
/// no-op until 12.1.1. 12.1.0 restored [PlatformFile.extension] but still
/// is not the pin. Single-file picks go through [FilePicker.pickFile]
/// because 12 defaults [FilePicker.pickFiles] `allowMultiple` to true.
/// Android SAF persistable URI grants are never enabled (we never pass
/// FilePickerAndroidOptions).
///
/// Every open/save/directory dialog previously started at the OS default (root
/// of the drive on macOS), which made repetitive imports from the same folder
/// slow. This records the parent directory of whatever the user picks and feeds
/// it back as `initialDirectory` next time — bucketed by [category] so image
/// imports, general file imports, exports and folder pickers each resume where
/// that particular workflow last left off.
///
/// Self-contained on [SharedPreferences] (the same store [StorageService] uses)
/// so call sites don't need a BuildContext/service handle. Keys follow the same
/// `beta_`-prefix convention as the rest of the app's preferences.
class PickerPrefs {
  PickerPrefs._();

  /// Image / avatar / background picks.
  static const String catImage = 'image';

  /// General file imports (cards, lorebooks, JSON, GGUF, .kcpps, data bank…).
  static const String catImport = 'import';

  /// Save/export dialogs (chats, personas, worlds, character transfer…).
  static const String catExport = 'export';

  /// Folder pickers (data root, models folder, export destination…).
  static const String catDirectory = 'directory';

  static String _key(String category) =>
      '${isPreRelease ? 'beta_' : ''}last_picker_dir_$category';

  static String? _read(SharedPreferences prefs, String category) =>
      prefs.getString(_key(category));

  static Future<void> _remember(
    SharedPreferences prefs,
    String category,
    String? dir,
  ) async {
    if (dir != null && dir.isNotEmpty) {
      await prefs.setString(_key(category), dir);
    }
  }

  /// Convert file_picker 12's [Uri?] save result back to the [String?] path
  /// callers still expect. File URIs become filesystem paths; other schemes
  /// keep `toString()`.
  @visibleForTesting
  static String? uriToSavePath(Uri? uri) {
    if (uri == null) return null;
    if (uri.scheme == 'file' || uri.scheme.isEmpty) {
      try {
        return uri.toFilePath();
      } catch (_) {
        return uri.path;
      }
    }
    return uri.toString();
  }

  /// Test seam: when set, [pickFiles] returns this instead of opening the OS
  /// dialog, and the last-folder bookkeeping is skipped.
  ///
  /// The native picker is the hard stop for every import journey — the file
  /// dialog belongs to the OS, so a suite can reach the button and no further.
  /// That left the Import Lorebook wizard's later steps untestable even though
  /// everything AFTER the pick is ordinary Flutter. One seam here unblocks all
  /// of them, and it is deliberately a function (not a fixed result) so a test
  /// can assert WHICH category/extensions a flow asked for.
  ///
  /// Set it in a test, and always null it again in the teardown.
  @visibleForTesting
  static Future<FilePickerResult?> Function({
    required String category,
    List<String>? allowedExtensions,
  })?
  testPickFilesOverride;

  /// Drop-in for `FilePicker.pickFiles` that resumes at (and records)
  /// the last folder used for [category].
  ///
  /// [allowMultiple] defaults to false and routes through [FilePicker.pickFile]
  /// so a 12.x default of true cannot leak in. Bytes are read later via
  /// [PlatformFile.readAsBytes] — `withData` is not passed. pickFiles itself
  /// does not eager-read GGUF/ZIP/PDF.
  static Future<FilePickerResult?> pickFiles({
    required String category,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool lockParentWindow = false,
  }) async {
    final override = testPickFilesOverride;
    if (override != null) {
      return override(category: category, allowedExtensions: allowedExtensions);
    }
    final prefs = await SharedPreferences.getInstance();
    final initialDirectory = _read(prefs, category);

    if (allowMultiple) {
      final files = await FilePicker.pickFiles(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: true,
        lockParentWindow: lockParentWindow,
      );
      if (files.isEmpty) return null;
      final path = files.first.path;
      if (path != null) await _remember(prefs, category, p.dirname(path));
      return FilePickerResult(files);
    }

    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      lockParentWindow: lockParentWindow,
    );
    if (file == null) return null;
    final path = file.path;
    if (path != null) await _remember(prefs, category, p.dirname(path));
    return FilePickerResult([file]);
  }

  /// Save [bytes] through the native dialog. file_picker 12 writes those
  /// bytes itself (Windows/Linux/macOS `writeAsBytes` after the dialog).
  /// [bytes] is required and must be non-empty — a dummy `Uint8List(0)`
  /// truncates/wipes the chosen file.
  static Future<String?> saveFile({
    required String category,
    required Uint8List bytes,
    String? dialogTitle,
    String? fileName,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError.value(
        bytes,
        'bytes',
        'file_picker 12 writes these bytes; empty would wipe the chosen file',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName ?? 'untitled',
      bytes: bytes,
      initialDirectory: _read(prefs, category),
      type: type,
      allowedExtensions: allowedExtensions,
      lockParentWindow: lockParentWindow,
    );
    final path = uriToSavePath(uri);
    if (path != null) await _remember(prefs, category, p.dirname(path));
    return path;
  }

  /// Path-then-write exporters: write to a temp file, then pass the real
  /// bytes to [saveFile] so the plugin writes the chosen path. Never a dummy.
  static Future<String?> saveFromBuilder({
    required String category,
    required Future<void> Function(String tempPath) writeTemp,
    String? dialogTitle,
    required String fileName,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) async {
    final dir = await Directory.systemTemp.createTemp('fpai_export_');
    final tempPath = p.join(dir.path, p.basename(fileName));
    try {
      await writeTemp(tempPath);
      final bytes = await File(tempPath).readAsBytes();
      return await saveFile(
        category: category,
        bytes: bytes,
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: type,
        allowedExtensions: allowedExtensions,
        lockParentWindow: lockParentWindow,
      );
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Filesystem path if this pick is file://. Otherwise write bytes to a
  /// temp file so path-based card/lore/backup imports do not silently skip
  /// when path is null (web blob: / Android content://). Do not use for GGUF.
  static Future<String?> localPathOrTemp(PlatformFile file) async {
    final path = file.path;
    if (path != null) return path;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final dir = await Directory.systemTemp.createTemp('fpai_pick_');
    final out = File(p.join(dir.path, p.basename(file.name)));
    await out.writeAsBytes(bytes);
    return out.path;
  }

  /// Drop-in for `FilePicker.getDirectoryPath`. Remembers the chosen
  /// directory itself so the next pick starts there.
  static Future<String?> getDirectoryPath({
    required String category,
    String? dialogTitle,
    bool lockParentWindow = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: _read(prefs, category),
      lockParentWindow: lockParentWindow,
    );
    if (path != null) await _remember(prefs, category, path);
    return path;
  }
}
