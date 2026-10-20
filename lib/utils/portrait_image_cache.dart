// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter/painting.dart';

// Keep new portrait decode sizes in the eviction list below.
const kPortraitGridDecodeWidth = 512;
const kPortraitGalleryDecodeWidth = 384;
const kPortraitMontageDecodeWidth = 256;

/// Small round avatars (up to about 64 logical px): 128 covers a 2x screen.
const kPortraitAvatarDecodeWidth = 128;

/// [file] decoded at [kPortraitAvatarDecodeWidth], for a small avatar's
/// `backgroundImage` / `DecorationImage`.
ImageProvider portraitAvatarImage(
  File file, {
  int width = kPortraitAvatarDecodeWidth,
}) => ResizeImage(FileImage(file), width: width);

// Image.file(cacheWidth: ...) caches a ResizeImage key, not its FileImage key.
Future<void> evictPortraitImage(File file) async {
  final image = FileImage(file);
  await image.evict();
  for (final width in [
    kPortraitGridDecodeWidth,
    kPortraitGalleryDecodeWidth,
    kPortraitMontageDecodeWidth,
    kPortraitAvatarDecodeWidth,
  ]) {
    await ResizeImage(image, width: width).evict();
  }
}
