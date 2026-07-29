// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';

// Re-export the file_picker types call sites need, so a migrated file can
// import just this one helper instead of both.
export 'package:file_picker/file_picker.dart'
    show FileType, FilePickerResult, PlatformFile;

/// Thin wrapper around `FilePicker` that remembers the last folder
/// used per [category] and reopens the native dialog there (#84).
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

  /// Drop-in for `FilePicker.pickFiles` that resumes at (and records)
  /// the last folder used for [category].
  static Future<FilePickerResult?> pickFiles({
    required String category,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool withData = false,
    bool lockParentWindow = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final result = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: _read(prefs, category),
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      withData: withData,
      lockParentWindow: lockParentWindow,
    );
    final path = (result != null && result.files.isNotEmpty)
        ? result.files.first.path
        : null;
    if (path != null) await _remember(prefs, category, p.dirname(path));
    return result;
  }

  /// Drop-in for `FilePicker.saveFile`.
  static Future<String?> saveFile({
    required String category,
    String? dialogTitle,
    String? fileName,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final path = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory: _read(prefs, category),
      type: type,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
      lockParentWindow: lockParentWindow,
    );
    if (path != null) await _remember(prefs, category, p.dirname(path));
    return path;
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
