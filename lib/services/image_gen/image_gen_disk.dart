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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/services/storage_service.dart';

import 'image_gen_clients.dart';
import 'image_gen_status.dart';

/// Disk persistence for generated pictures: the images folder and avatars.
class ImageGenDisk {
  ImageGenDisk(this._storage, this._clients, this._status);

  final StorageService _storage;
  final ImageGenClients _clients;
  final ImageGenStatus _status;

  /// Save the last generated image to disk.
  ///
  /// Returns the saved file path, or null on failure.
  ///
  /// [preferredFileName] — optional basename (e.g. package import). Sanitized
  /// and uniquified if a file already exists so back-to-back writes never
  /// collide on the same millisecond (review 03d46d9a finding 1).
  /// When omitted, uses `img_<ms>.png` with the same collision guard.
  Future<String?> saveImageToDisk([
    Uint8List? imageBytes,
    String? preferredFileName,
  ]) async {
    final bytes = imageBytes ?? _status.lastGeneratedImage;
    if (bytes == null) return null;

    try {
      final dir = _clients.imagesDir;
      await dir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      var base =
          (preferredFileName != null && preferredFileName.trim().isNotEmpty)
          ? path.basename(preferredFileName.trim())
          : 'img_$timestamp.png';
      // Strip path traversal; force a png-ish name if empty after sanitize.
      base = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      if (base.isEmpty || base == '.' || base == '..') {
        base = 'img_$timestamp.png';
      }
      var file = File(path.join(dir.path, base));
      if (await file.exists()) {
        final stem = path.basenameWithoutExtension(base);
        final ext = path.extension(base).isEmpty
            ? '.png'
            : path.extension(base);
        var n = 1;
        do {
          file = File(path.join(dir.path, '${stem}_$n$ext'));
          n++;
        } while (await file.exists());
      }
      await file.writeAsBytes(bytes);

      // Import/package paths pass preferredFileName — do not clobber Image
      // Studio "last saved" or fire a notify storm (one per imported image).
      if (preferredFileName == null || preferredFileName.trim().isEmpty) {
        _status.lastSavedPath = file.path;
        _status.notify();
      }
      return file.path;
    } catch (e) {
      debugPrint('Failed to save image: $e');
      return null;
    }
  }

  /// Save a generated image as a character avatar to the characters directory.
  ///
  /// Unlike [saveImageToDisk], this saves to the characters directory
  /// (`KoboldManager/Characters/`) so cloud sync picks it up.
  /// Returns the saved file path, or null on failure.
  Future<String?> saveAvatarToDisk(
    Uint8List? imageBytes, {
    String? characterName,
  }) async {
    final bytes = imageBytes ?? _status.lastGeneratedImage;
    if (bytes == null) return null;

    try {
      final dir = _storage.charactersDir;
      await dir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = (characterName ?? 'avatar')
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final filename = '${safeName}_$timestamp.png';
      final file = File(path.join(dir.path, filename));
      await file.writeAsBytes(bytes);

      _status.lastSavedPath = file.path;
      _status.notify();
      return file.path;
    } catch (e) {
      debugPrint('Failed to save avatar: $e');
      return null;
    }
  }
}
