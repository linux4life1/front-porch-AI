// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Size of the solid-colour picture [V2CardService] writes into a card that
/// has no portrait (creator "None for now", JSON import...).
const int kPlaceholderPortraitWidth = 400;
const int kPlaceholderPortraitHeight = 600;

/// True when [decoded] is that synthetic picture: exactly 400×600 and one
/// colour across a 5×5 grid of samples. Real photos are kept even if they
/// happen to be flat-coloured at another size or show any variance.
bool isSolidPlaceholderImage(img.Image decoded) {
  if (decoded.width != kPlaceholderPortraitWidth ||
      decoded.height != kPlaceholderPortraitHeight) {
    return false;
  }
  int? r0, g0, b0;
  for (final yf in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
    for (final xf in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final px = decoded.getPixel(
        (xf * (decoded.width - 1)).round(),
        (yf * (decoded.height - 1)).round(),
      );
      final r = px.r.toInt(), g = px.g.toInt(), b = px.b.toInt();
      if (r0 == null) {
        r0 = r;
        g0 = g;
        b0 = b;
      } else if (r != r0 || g != g0 || b != b0) {
        return false;
      }
    }
  }
  return true;
}

/// Answers "is this picture the no-portrait placeholder?" for painting, so a
/// character made without a portrait shows the app's person icon instead of
/// a flat coloured box. Results are cached per file and [version] (the
/// caller's cache epoch or the file's mtime) because a real portrait later
/// overwrites the placeholder in place, under the same path.
///
/// Only a PNG whose header says 400×600 is decoded, off the UI isolate; every
/// other picture is answered from its first 24 bytes.
class PlaceholderPortraitProbe {
  PlaceholderPortraitProbe._();

  static final Map<String, Future<bool>> _pending = {};
  static final Map<String, bool> _known = {};

  static String _key(String path, Object version) => '$path|$version';

  /// The cached answer, or null when [check] has not finished for it yet.
  static bool? known(File file, {required Object version}) =>
      _known[_key(file.path, version)];

  /// The answer for [file] at [version]. The same [Future] is returned for
  /// repeat calls, so a `FutureBuilder` does not restart on rebuild.
  static Future<bool> check(File file, {required Object version}) {
    final key = _key(file.path, version);
    final done = _known[key];
    if (done != null) return SynchronousFuture(done);
    return _pending[key] ??= _probe(file).then((answer) {
      _pending.remove(key);
      _known[key] = answer;
      return answer;
    });
  }

  static Future<bool> _probe(File file) async {
    try {
      // A missing file paints the picture widget's own fallback.
      if (!await file.exists()) return false;
      if (!await _headerSaysPlaceholderSize(file)) return false;
      final bytes = await file.readAsBytes();
      return await Isolate.run(() {
        final decoded = img.decodeImage(bytes);
        return decoded != null && isSolidPlaceholderImage(decoded);
      });
    } catch (e) {
      // Unreadable: paint whatever the picture widget makes of it.
      debugPrint('PlaceholderPortraitProbe: ${file.path}: $e');
      return false;
    }
  }

  /// PNG signature, then the IHDR chunk's big-endian width and height.
  static Future<bool> _headerSaysPlaceholderSize(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(24);
      if (head.length < 24) return false;
      const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      for (var i = 0; i < sig.length; i++) {
        if (head[i] != sig[i]) return false;
      }
      int u32(int at) =>
          (head[at] << 24) |
          (head[at + 1] << 16) |
          (head[at + 2] << 8) |
          head[at + 3];
      return u32(16) == kPlaceholderPortraitWidth &&
          u32(20) == kPlaceholderPortraitHeight;
    } finally {
      await raf.close();
    }
  }

  @visibleForTesting
  static void clearCache() {
    _pending.clear();
    _known.clear();
  }
}
