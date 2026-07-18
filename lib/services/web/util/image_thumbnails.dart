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

import 'package:image/image.dart' as img;
import 'package:shelf/shelf.dart' as shelf;

/// On-disk cache + HTTP responder for downscaled avatar/card thumbnails served
/// to the web/mobile UI.
///
/// The library grid used to fetch the full-resolution character-card PNG for
/// every tile — each one hundreds of KB to over 1 MB, and every one carrying
/// the *entire* character card embedded as base64 `chara` metadata. Painting a
/// home screen of N characters therefore uploaded tens of MB, which is brutal
/// over a slow uplink (Starlink + Tailscale).
///
/// [serve] answers an avatar request from a resolved [File]:
///   • with `?w=<px>` it returns a downscaled JPEG (or PNG when the source has
///     real transparency), generated once and cached to disk. Re-encoding also
///     drops the heavy embedded `chara` chunk, so a ~1 MB card PNG becomes a
///     handful of KB.
///   • without `?w=` it returns the original bytes unchanged.
/// Either way an mtime-based `ETag` is attached and `If-None-Match` is honoured,
/// so a repeat load revalidates with a cheap `304 Not Modified` instead of a
/// full re-download.
///
/// The cache directory holds purely derived data — it is safe to delete at any
/// time and is regenerated on demand.
class ThumbnailCache {
  ThumbnailCache(this._cacheDir);

  final Directory _cacheDir;

  /// Requested widths are clamped to this range: keeps the on-disk cache
  /// bounded and stops a client asking for an absurd (memory-heavy) size.
  static const int _minWidth = 32;
  static const int _maxWidth = 1024;

  /// Build the HTTP response for [file] (already resolved by the caller), or a
  /// 404 when it is null/missing. Honours `?w=` (thumbnail), `If-None-Match`
  /// (304), and always sets an `ETag` + [cacheControl].
  Future<shelf.Response> serve(
    shelf.Request request,
    File? file, {
    String cacheControl = 'public, max-age=3600',
  }) async {
    if (file == null || !file.existsSync()) {
      return shelf.Response.notFound('No avatar');
    }

    final int sourceMtime = file.statSync().modified.millisecondsSinceEpoch;
    final int? width = _parseWidth(request.url.queryParameters['w']);

    final List<int> body;
    final String contentType;
    final String etagBody;
    if (width == null) {
      body = file.readAsBytesSync();
      contentType = 'image/png';
      etagBody = '$sourceMtime-full';
    } else {
      final thumb = await bytesFor(file, width, sourceMtime);
      body = thumb.bytes;
      contentType = thumb.contentType;
      etagBody =
          '$sourceMtime-$width-${contentType == 'image/jpeg' ? 'j' : 'p'}';
      // A thumbnail is immutable for a given source mtime (the ETag encodes it),
      // so it is safe to cache hard and spare the slow link a re-fetch. When the
      // client also passes a content version (`v=`), the URL itself is
      // content-addressed — a swapped picture is a different URL — so we can mark
      // it `immutable` and skip even the conditional revalidation.
      cacheControl = request.url.queryParameters.containsKey('v')
          ? 'public, max-age=604800, immutable'
          : 'public, max-age=604800';
    }

    final etag = '"$etagBody"';
    if (request.headers['if-none-match'] == etag) {
      return shelf.Response(
        304,
        headers: {'ETag': etag, 'Cache-Control': cacheControl},
      );
    }

    return shelf.Response.ok(
      body,
      headers: {
        'Content-Type': contentType,
        'Cache-Control': cacheControl,
        'ETag': etag,
      },
    );
  }

  /// Return the thumbnail bytes + content-type for [source] at [width],
  /// generating and caching on a miss (and regenerating when the source is
  /// newer than the cached copy). Falls back to the original bytes when the
  /// image can't be decoded. Split out from [serve] so it is unit-testable
  /// without an HTTP request.
  Future<ThumbnailBytes> bytesFor(
    File source,
    int width, [
    int? sourceMtime,
  ]) async {
    final int mtime =
        sourceMtime ?? source.statSync().modified.millisecondsSinceEpoch;
    final String key = '${_hash(source.path)}_$width';
    final File jpg = File('${_cacheDir.path}${Platform.pathSeparator}$key.jpg');
    final File png = File('${_cacheDir.path}${Platform.pathSeparator}$key.png');

    // Fresh cache hit → serve it. The extension tells us the content-type, and
    // a cache file at least as new as the source is still valid.
    for (final cached in [jpg, png]) {
      if (cached.existsSync() &&
          cached.statSync().modified.millisecondsSinceEpoch >= mtime) {
        return ThumbnailBytes(
          cached.readAsBytesSync(),
          cached == jpg ? 'image/jpeg' : 'image/png',
        );
      }
    }

    // Miss (or stale): decode → downscale → re-encode.
    final decoded = img.decodeImage(source.readAsBytesSync());
    if (decoded == null) {
      // Not a decodable image — hand back the original untouched (best effort;
      // don't cache so a transient decode issue can recover next time).
      return ThumbnailBytes(source.readAsBytesSync(), 'image/png');
    }
    final resized = decoded.width > width
        ? img.copyResize(
            decoded,
            width: width,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    final bool transparent = _hasRealTransparency(resized);
    final Uint8List bytes;
    final String contentType;
    final File out;
    if (transparent) {
      bytes = img.encodePng(resized);
      contentType = 'image/png';
      out = png;
    } else {
      bytes = img.encodeJpg(resized, quality: 82);
      contentType = 'image/jpeg';
      out = jpg;
    }
    _persist(out, bytes, sibling: transparent ? jpg : png);
    return ThumbnailBytes(bytes, contentType);
  }

  /// Write [bytes] to [out] via a temp file + atomic rename (so a concurrent
  /// reader never sees a half-written thumbnail), then drop the stale [sibling]
  /// (the opposite format for the same key) so a later lookup is unambiguous.
  /// Best-effort: a caching failure never fails the request — the caller still
  /// has the in-memory bytes.
  void _persist(File out, List<int> bytes, {required File sibling}) {
    try {
      if (!_cacheDir.existsSync()) _cacheDir.createSync(recursive: true);
      final tmp = File(
        '${out.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );
      tmp.writeAsBytesSync(bytes, flush: true);
      tmp.renameSync(out.path);
      if (sibling.existsSync()) sibling.deleteSync();
    } catch (_) {
      // Ignore — caching is an optimization, not a correctness requirement.
    }
  }

  int? _parseWidth(String? raw) {
    if (raw == null) return null;
    final v = int.tryParse(raw);
    if (v == null) return null;
    return v.clamp(_minWidth, _maxWidth);
  }

  /// True only when a pixel is actually see-through — not merely that the image
  /// carries an (all-opaque) alpha channel. This keeps opaque portrait art on
  /// the tiny-JPEG path even when it was imported as an RGBA PNG.
  static bool _hasRealTransparency(img.Image image) {
    if (!image.hasAlpha) return false;
    for (final p in image) {
      if (p.a < p.maxChannelValue) return true;
    }
    return false;
  }

  /// FNV-1a 64-bit hex of [s] — a stable, filesystem-safe, dependency-free
  /// cache key derived from the full source path (basenames alone can collide
  /// across the character and group directories).
  static String _hash(String s) {
    var hash = 0xcbf29ce484222325;
    for (final c in s.codeUnits) {
      hash = (hash ^ c) * 0x100000001b3;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }
}

/// The generated (or cached) thumbnail payload: the encoded [bytes] and their
/// [contentType] (`image/jpeg` or `image/png`).
class ThumbnailBytes {
  ThumbnailBytes(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}
