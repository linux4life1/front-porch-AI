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
/// Only a PNG whose header says 400×600 and whose pixel data is tiny is
/// decoded, off the UI isolate; every other picture is answered from its
/// chunk headers ([mightBeFlatPlaceholder]).
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
      if (!await mightBeFlatPlaceholder(file)) return false;
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

  /// The cheap gate before any decode, read from chunk headers only: a PNG
  /// whose IHDR says 400×600 and whose pixel data (the summed IDAT chunk
  /// lengths) is tiny, as one flat colour compresses to a few KB. Card
  /// metadata chunks (`chara`) are skipped, not counted. A real 400×600
  /// portrait (most imported cards are that size) fails here without being
  /// decoded.
  @visibleForTesting
  static Future<bool> mightBeFlatPlaceholder(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(24);
      if (head.length < 24) return false;
      const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      for (var i = 0; i < sig.length; i++) {
        if (head[i] != sig[i]) return false;
      }
      if (_u32(head, 16) != kPlaceholderPortraitWidth ||
          _u32(head, 20) != kPlaceholderPortraitHeight) {
        return false;
      }
      // Walk chunk headers: length(4) type(4) data(length) crc(4).
      var at = 8;
      var imageBytes = 0;
      final fileLength = await raf.length();
      while (at + 8 <= fileLength) {
        await raf.setPosition(at);
        final chunk = await raf.read(8);
        if (chunk.length < 8) break;
        final length = _u32(chunk, 0);
        final type = String.fromCharCodes(chunk.sublist(4, 8));
        if (type == 'IDAT') {
          imageBytes += length;
          if (imageBytes > _kFlatImageDataMaxBytes) return false;
        } else if (type == 'IEND') {
          break;
        }
        at += 12 + length;
      }
      return imageBytes > 0;
    } finally {
      await raf.close();
    }
  }

  /// A flat 400×600 colour is ~1-2 KB of pixel data; a real portrait at that
  /// size is tens to hundreds of KB.
  static const int _kFlatImageDataMaxBytes = 16 * 1024;

  static int _u32(List<int> b, int at) =>
      (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  @visibleForTesting
  static void clearCache() {
    _pending.clear();
    _known.clear();
  }
}
