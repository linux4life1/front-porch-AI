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
import 'package:path/path.dart' as path;

/// Directory computation and resolution helpers extracted from StorageService
/// (Stage 7 mechanical decomposition).
///
/// StorageService owns the root/customModels state (for setRootPath relocation
/// logic and init) and exposes an AppDirectories instance. All pure dir
/// getters, resolveCharacterImage, and characterAvatarDir live here so the
/// thin storage_service.dart focuses on directory management (~300 LOC target).
class AppDirectories {
  final String? rootPath;
  final String? customModelsPath;

  AppDirectories({required this.rootPath, required this.customModelsPath});

  Directory get binDir =>
      Directory(rootPath != null ? path.join(rootPath!, 'koboldcpp_bin') : '');

  Directory get modelsDir =>
      customModelsPath != null && customModelsPath!.isNotEmpty
      ? Directory(customModelsPath!)
      : Directory(path.join(rootPath ?? '', 'models'));

  Directory get chatsDir => Directory(path.join(rootPath ?? '', 'chats'));

  Directory get worldsDir => Directory(path.join(rootPath ?? '', 'worlds'));

  Directory get charactersDir =>
      Directory(path.join(rootPath ?? '', 'KoboldManager', 'Characters'));

  /// Directory for all group-private data (decoupled from singular library characters).
  /// Each group gets its own subdirectory (by group id) under here to store its
  /// member avatar PNGs (primary only; no multi-avatar or expressions per spec).
  /// Group data is NEVER written to or resolved from the global charactersDir or library.
  /// The only bridge to library is the user's explicit "Separate to my library" action.
  Directory get groupsDir => Directory(path.join(rootPath ?? '', 'groups'));

  Directory get customBackgroundDir =>
      Directory(path.join(rootPath ?? '', 'custom_backgrounds'));

  /// Cache for downscaled avatar/card thumbnails served to the web/mobile UI.
  /// Purely derived data — safe to delete at any time; regenerated on demand.
  Directory get webThumbnailCacheDir =>
      Directory(path.join(rootPath ?? '', 'cache', 'web_thumbs'));

  /// Resolve a character [imagePath] (stored in the DB) to a [File].
  ///
  /// The DB may contain either:
  ///   • A **basename** only — e.g. `"Maggie_1234567890.png"` (written by the
  ///     manual avatar picker and older AI-generated entries).
  ///   • A **full absolute path** — e.g. `/Users/.../Maggie_1234567890.png`
  ///     (written by newer AI-generated entries before this fix).
  ///   • A **relative path with subdirectory** — e.g. `"Aerin/avatars/avatar_1.png"`
  ///     (multi-avatar format with per-character subdirectories).
  ///
  /// In all cases this returns the correct [File].  Pass the result to
  /// [FileImage] or [Image.file] instead of [File(imagePath)] directly so
  /// that the code remains valid when the app data directory moves or the
  /// character card is used on a different machine.
  File resolveCharacterImage(String imagePath) {
    if (path.isAbsolute(imagePath)) return File(imagePath);
    final resolved = File(path.join(charactersDir.path, imagePath));
    return resolved;
  }

  /// The character's private data folder (`<charactersDir>/<safeName>`).
  /// `avatars/` (expressions) and `looks/` (gallery) both live under it, so this
  /// single-sources the safe-name rule they must agree on.
  /// (Creation is the caller's responsibility when writing files.)
  Directory characterBaseDir(String characterName) {
    final safeName = characterName
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');
    return Directory(path.join(charactersDir.path, safeName));
  }

  /// Return the avatars subdirectory for a character by name.
  /// (Creation is the caller's responsibility when writing files, matching original god contract/impl.)
  Directory characterAvatarDir(String characterName) =>
      Directory(path.join(characterBaseDir(characterName).path, 'avatars'));
}
