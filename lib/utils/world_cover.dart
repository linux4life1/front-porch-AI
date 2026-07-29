// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Living Worlds place cover images: size-capped data-URL encode/decode.
// Pure helpers — no I/O, safe to call from isolates or UI after pick.

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Soft cap for stored cover payloads (DB + .fpworld).
const int kWorldCoverMaxBytes = 350 * 1024;

/// Longest edge after resize (keeps thumbnails sharp enough for cards).
const int kWorldCoverMaxEdge = 512;

/// Encode raw image bytes as a `data:image/jpeg;base64,…` cover string.
/// Returns null if the bytes are not a decodable image or cannot be capped.
String? encodeWorldCoverDataUrl(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var image = decoded;
  final longEdge =
      image.width > image.height ? image.width : image.height;
  if (longEdge > kWorldCoverMaxEdge) {
    final scale = kWorldCoverMaxEdge / longEdge;
    image = img.copyResize(
      image,
      width: (image.width * scale).round().clamp(1, kWorldCoverMaxEdge),
      height: (image.height * scale).round().clamp(1, kWorldCoverMaxEdge),
      interpolation: img.Interpolation.average,
    );
  }

  var quality = 85;
  var jpg = img.encodeJpg(image, quality: quality);
  while (jpg.length > kWorldCoverMaxBytes && quality > 35) {
    quality -= 10;
    jpg = img.encodeJpg(image, quality: quality);
  }
  if (jpg.length > kWorldCoverMaxBytes) {
    // Last resort: harder shrink.
    image = img.copyResize(
      image,
      width: (image.width * 0.65).round().clamp(1, kWorldCoverMaxEdge),
      height: (image.height * 0.65).round().clamp(1, kWorldCoverMaxEdge),
      interpolation: img.Interpolation.average,
    );
    jpg = img.encodeJpg(image, quality: 55);
    if (jpg.length > kWorldCoverMaxBytes) return null;
  }
  return 'data:image/jpeg;base64,${base64Encode(jpg)}';
}

/// Decode a cover field (data URL, raw base64, or empty) to JPEG/PNG bytes.
/// File paths are not resolved here (no I/O) — pass data URLs from the DB.
Uint8List? decodeWorldCoverBytes(String? cover) {
  if (cover == null || cover.trim().isEmpty) return null;
  final s = cover.trim();
  try {
    if (s.startsWith('data:')) {
      final idx = s.indexOf('base64,');
      if (idx < 0) return null;
      return base64Decode(s.substring(idx + 7));
    }
    // Raw base64 without prefix (import tolerance).
    if (s.length > 64 && !s.contains('/') && !s.contains('\\')) {
      return base64Decode(s);
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// True when [cover] is an inlined data URL (not a filesystem path).
bool isWorldCoverDataUrl(String? cover) {
  if (cover == null) return false;
  return cover.trimLeft().startsWith('data:');
}
