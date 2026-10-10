// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter/painting.dart';

const kPortraitGridDecodeWidth = 512;
const kPortraitGalleryDecodeWidth = 384;
const kPortraitMontageDecodeWidth = 256;

// Image.file(cacheWidth: ...) caches a ResizeImage key, not its FileImage key.
Future<void> evictPortraitImage(File file) async {
  final image = FileImage(file);
  await image.evict();
  for (final width in [
    kPortraitGridDecodeWidth,
    kPortraitGalleryDecodeWidth,
    kPortraitMontageDecodeWidth,
  ]) {
    await ResizeImage(image, width: width).evict();
  }
}
