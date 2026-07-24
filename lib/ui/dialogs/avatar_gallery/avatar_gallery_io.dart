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
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import 'package:front_porch_ai/utils/emotion_labels.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

/// Pure IO helpers for the Avatar Gallery add flows — file/ZIP picking and
/// sprite-pack decoding. No widgets, no repository, no state: keeps the
/// controller + shell under the size cap and trivially reasoned about.

/// Pick a single image and return its bytes, or null if cancelled. Handles the
/// macOS desktop quirk where `.bytes` is null and only `.path` is populated.
Future<Uint8List?> pickImageBytes() async {
  final result = await PickerPrefs.pickFiles(
    category: PickerPrefs.catImage,
    type: FileType.image,
    allowMultiple: false,
  );
  return _firstBytes(result);
}

/// Pick a `.zip` sprite pack and return its bytes, or null if cancelled.
Future<Uint8List?> pickZipBytes() async {
  final result = await PickerPrefs.pickFiles(
    category: PickerPrefs.catImport,
    type: FileType.custom,
    allowedExtensions: ['zip'],
    allowMultiple: false,
  );
  return _firstBytes(result);
}

Future<Uint8List?> _firstBytes(FilePickerResult? result) async {
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.first;
  if (f.bytes != null) return f.bytes!;
  if (f.path != null) return File(f.path!).readAsBytes();
  return null;
}

/// One recognized emotion sprite from a pack.
class SpritePackEntry {
  const SpritePackEntry(this.bytes, this.emotion);
  final Uint8List bytes;
  final String emotion;
}

/// The result of decoding a sprite pack: the recognized (emotion-named) entries
/// plus a count of files whose name matched no emotion label.
class SpritePackResult {
  const SpritePackResult(this.entries, this.unrecognized);
  final List<SpritePackEntry> entries;
  final int unrecognized;
}

/// Decode a ZIP sprite pack: image files whose base name matches an emotion
/// label (`joy.png`, `anger-1.png`, `sad_2.png`, …) become [SpritePackEntry]s;
/// others are counted as [SpritePackResult.unrecognized]. Same matching as the
/// old expression dialog.
SpritePackResult decodeSpritePack(Uint8List zipBytes) {
  const imageExts = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
  final entries = <SpritePackEntry>[];
  var unrecognized = 0;

  final archive = ZipDecoder().decodeBytes(zipBytes);
  for (final entry in archive) {
    if (!entry.isFile) continue;
    // Match on the file's BASENAME so packs with folders ("sprites/joy.png")
    // still resolve — matching the full path silently failed every foldered pack.
    final name = entry.name.split('/').last.split(r'\').last;
    final ext = name.split('.').last.toLowerCase();
    if (!imageExts.contains(ext)) continue;

    final base = name.replaceAll(RegExp(r'\.\w+$'), '').toLowerCase();
    String? emotion;
    for (final label in EmotionLabels.all) {
      if (base == label ||
          base.startsWith('$label-') ||
          base.startsWith('$label.') ||
          base.startsWith('${label}_')) {
        emotion = label;
        break;
      }
    }
    final data = entry.content as Uint8List?;
    if (emotion == null || data == null) {
      unrecognized++;
      continue;
    }
    entries.add(SpritePackEntry(data, emotion));
  }
  return SpritePackResult(entries, unrecognized);
}
