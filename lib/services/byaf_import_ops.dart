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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';

/// Delete every temp extract [ByafService.parseByaf] wrote.
void deleteByafTempImages(Iterable<String> paths) {
  for (final imgPath in paths) {
    final img = File(imgPath);
    if (!img.existsSync()) continue;
    try {
      img.deleteSync();
    } catch (_) {}
  }
}

/// Add archive images after the portrait as gallery looks, then delete the
/// temp extracts (portrait included). [addLook] stays on the caller-owned
/// [CharacterRepository] — this file only orchestrates.
/// [replaceExistingLooks] clears prior looks first (Replace → new pack only).
Future<int> applyByafGalleryLooks({
  required CharacterRepository repo,
  required CharacterCard imported,
  required List<String> galleryImagePaths,
  required bool importGalleryImages,
  bool replaceExistingLooks = false,
}) async {
  var added = 0;
  final dbId = imported.dbId;
  if (replaceExistingLooks && dbId != null) {
    await repo.clearGalleryLooks(dbId);
  }
  for (var i = 1; i < galleryImagePaths.length; i++) {
    final imagePath = galleryImagePaths[i];
    final imgFile = File(imagePath);
    if (!imgFile.existsSync()) continue;
    if (importGalleryImages && dbId != null) {
      final lookId = await repo.addLook(
        dbId,
        imported.name,
        await imgFile.readAsBytes(),
      );
      if (lookId.isNotEmpty) added++;
    }
    try {
      await imgFile.delete();
    } catch (_) {}
  }
  if (galleryImagePaths.isNotEmpty) {
    final portrait = File(galleryImagePaths.first);
    if (portrait.existsSync()) {
      try {
        await portrait.delete();
      } catch (_) {}
    }
  }
  return added;
}
