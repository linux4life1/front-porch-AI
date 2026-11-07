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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

/// The phone's side of Image Studio's Recent shelf. It reads and changes the
/// same [StudioRecentStore] the desktop Studio shows.
class ImageStudioRecent {
  ImageStudioRecent(this._storage);

  final StorageService _storage;

  StudioRecentStore get store => StudioRecentStore.of(_storage);

  /// Keep a fresh Studio result. Returns null when there is no storage root.
  Future<StudioRecentEntry?> remember(
    Uint8List png, {
    required String prompt,
    required bool edit,
  }) => rememberStudioResult(_storage, png, prompt: prompt, edit: edit);

  /// The shelf as the phone draws it: newest first, with the limit and how
  /// much room the pictures take.
  Future<Map<String, Object?>> view() async {
    final entries = await store.list();
    final limit = _storage.imageGenSettings.studioRecentLimit;
    return {
      'limit': limit,
      'choices': kStudioRecentChoices,
      'folder': store.folderPath,
      'usage': {
        'bytes': entries.fold<int>(0, (sum, e) => sum + e.bytes),
        'count': entries.length,
        'kept': entries.where((e) => e.kept).length,
      },
      'entries': [
        for (final e in entries)
          {
            ...e.toJson(),
            'url': '/api/image/saved/${Uri.encodeComponent(e.name)}',
          },
      ],
    };
  }

  Future<Map<String, Object?>?> setKept(String name, bool kept) async =>
      (await store.setKept(name, kept))?.toJson();

  Future<bool> delete(String name) => store.delete(name);

  Future<int> clearUnkept() => store.clearUnkept();

  /// False when [limit] is not one the shelf offers.
  Future<bool> setLimit(int limit) async {
    if (!await _storage.imageGenSettings.setStudioRecentLimit(limit)) {
      return false;
    }
    await store.applyLimit();
    return true;
  }

  /// A file a chat message can point at for good. A Recent picture is copied
  /// into the chat pictures folder ([imagesDir]) first, so trimming the shelf
  /// later never breaks the chat. Null when [name] is not a Recent picture.
  File? chatCopy(String name, Directory imagesDir) {
    if (!StudioRecentStore.isRecentName(name)) return null;
    final copy = File(p.join(imagesDir.path, name));
    if (copy.existsSync()) return copy;
    final source = store.fileFor(name);
    if (source == null) return null;
    try {
      imagesDir.createSync(recursive: true);
      return source.copySync(copy.path);
    } on FileSystemException catch (e) {
      debugPrint('ImageStudioRecent: could not copy $name for chat: $e');
      return null;
    }
  }
}
