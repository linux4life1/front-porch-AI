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

part of 'image_gen_service.dart';

/// Cluster B (disk persistence) + Cluster F (backend generator
/// implementations). Neither saveImageToDisk/saveAvatarToDisk nor any
/// `_generateVia*`/helper below is overridden by a test fake, so all of it
/// moves here as ordinary extension members under their original names.
/// This extension's name is PUBLIC (not `_`-prefixed): saveImageToDisk and
/// saveAvatarToDisk are called from other libraries (chat_service parts, the
/// image studio, chat_page, the web image facade) — a private extension name
/// would make those calls resolve to `undefined_method`, because extension
/// applicability for a caller outside the declaring library requires the
/// extension itself to be public, independent of whether the individual
/// member name is public. (The private `_generateVia*`/helper members below
/// stay uncallable externally either way, by ordinary identifier privacy.)
/// The one edit versus the original file: `_generateViaA1111`'s internal
/// `buildA1111Payload(...)` call gains the `ImageGenService.` qualifier,
/// because that member is a true class static (kept on the shell for its
/// test-pinned qualified name) and statics are not in an extension's lexical
/// scope. Also: `notifyListeners()` calls become `_notify()` (the shell's
/// forwarder) — a direct call from here trips
/// `invalid_use_of_protected_member`.
extension ImageGenBackends on ImageGenService {
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
    final bytes = imageBytes ?? _lastGeneratedImage;
    if (bytes == null) return null;

    try {
      final dir = _imagesDir;
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
        _lastSavedPath = file.path;
        _notify();
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
    final bytes = imageBytes ?? _lastGeneratedImage;
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

      _lastSavedPath = file.path;
      _notify();
      return file.path;
    } catch (e) {
      debugPrint('Failed to save avatar: $e');
      return null;
    }
  }
}
