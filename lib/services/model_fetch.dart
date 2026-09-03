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
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Shared direct-HTTPS model downloader for the in-process engines that
/// replaced the Python sidecars (emotion classifier, Whisper STT — see
/// docs/design/sidecar-retirement.md). One implementation so every engine
/// gets the same behavior: `.part` temp file + atomic rename (a partial
/// download never masquerades as a complete model), skip-if-present, and
/// throttled ~1% progress callbacks.
class ModelFetch {
  /// Content length of [url] via a HEAD request, or -1 if unknown.
  /// Used to compute aggregate progress across multi-file model sets.
  static Future<int> contentLength(String url) async {
    final client = _client();
    try {
      final req = await client.headUrl(Uri.parse(url));
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode == 200 ? res.contentLength : -1;
    } catch (_) {
      return -1;
    } finally {
      client.close();
    }
  }

  /// Reject a body that cannot be a real model file: a truncated stream
  /// (received != Content-Length) or a body smaller than [minBytes] (a CDN
  /// error page, not weights). Returns the rejection reason, or null when
  /// valid. [expectedBytes] ≤ 0 means the server omitted Content-Length.
  static String? validateDownload({
    required int receivedBytes,
    required int expectedBytes,
    int minBytes = 1,
  }) {
    if (expectedBytes > 0 && receivedBytes != expectedBytes) {
      return 'download truncated ($receivedBytes of $expectedBytes bytes)';
    }
    if (receivedBytes < minBytes) {
      return 'download implausibly small ($receivedBytes bytes, need $minBytes)';
    }
    return null;
  }

  /// Streams [url] to [dest]. Skips files that are already fully
  /// downloaded (size ≥ [minBytes]). [onProgress] receives (bytesDone,
  /// bytesTotal) for THIS file; total is -1 when the server doesn't say.
  ///
  /// A truncated or undersized body is deleted, never renamed onto [dest],
  /// so the next attempt is not skip-poisoned by an HTML error page.
  ///
  /// Retries transient failures: HuggingFace's CDN intermittently serves
  /// 504s (verified in the field — one hiccup used to kill a whole model
  /// download). The last attempt's error propagates to the caller.
  static Future<void> fetch(
    String url,
    File dest, {
    void Function(int done, int total)? onProgress,
    int minBytes = 1,
  }) async {
    const attempts = 3;
    for (var attempt = 1; ; attempt++) {
      try {
        return await _fetchOnce(
          url,
          dest,
          onProgress: onProgress,
          minBytes: minBytes,
        );
      } catch (_) {
        if (attempt >= attempts) rethrow;
        await Future.delayed(Duration(seconds: attempt));
      }
    }
  }

  static Future<void> _fetchOnce(
    String url,
    File dest, {
    void Function(int done, int total)? onProgress,
    int minBytes = 1,
  }) async {
    if (dest.existsSync()) {
      if (dest.lengthSync() >= minBytes) return;
      _deleteQuiet(dest);
    }
    final client = _client();
    final part = File('${dest.path}.part');
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode} for $url');
      }
      final total = res.contentLength;
      await dest.parent.create(recursive: true);
      final sink = part.openWrite();
      var done = 0;
      var lastReport = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          done += chunk.length;
          // Throttle UI updates to ~1% steps on big files.
          if (total > 0 && (done - lastReport) * 100 >= total) {
            lastReport = done;
            onProgress?.call(done, total);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      final invalid = validateDownload(
        receivedBytes: done,
        expectedBytes: total,
        minBytes: minBytes,
      );
      if (invalid != null) {
        _deleteQuiet(part);
        _deleteQuiet(dest);
        throw HttpException('$invalid for $url');
      }
      await part.rename(dest.path);
      onProgress?.call(done, total);
    } finally {
      client.close();
      if (part.existsSync()) {
        _deleteQuiet(part);
      }
    }
  }

  static void _deleteQuiet(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Downloads a `.tar.bz2` model bundle (progress 0–0.85) and extracts it
  /// into [destDir] stripping the archive's single top-level directory
  /// (0.85–1.0, in an isolate — bzip2 on hundreds of MB is CPU-bound).
  /// Used by the sherpa Kokoro/Piper TTS engines
  /// (docs/design/sidecar-retirement.md phase 4).
  static Future<void> fetchAndExtractTarBz2(
    String url,
    String destDir, {
    void Function(double fraction)? onProgress,
  }) async {
    final tmp = File('$destDir.tar.bz2');
    await tmp.parent.create(recursive: true);
    await fetch(
      url,
      tmp,
      onProgress: (done, total) {
        if (total > 0) onProgress?.call(0.85 * done / total);
      },
    );
    onProgress?.call(0.85);
    await _extractTarBz2(tmp.path, destDir);
    try {
      await tmp.delete();
    } catch (_) {}
    onProgress?.call(1.0);
  }

  /// The [Isolate.run] call must live in its own method: closures share
  /// their enclosing scope's context when serialized to an isolate, and
  /// [fetchAndExtractTarBz2]'s scope also holds the caller's [onProgress]
  /// closure — which can capture unsendable objects (TtsService →
  /// StorageService held a live Completer) and abort the whole download.
  /// Here the closure's scope holds only the two path strings.
  static Future<void> _extractTarBz2(String tarBz2Path, String destDir) {
    return Isolate.run(() {
      final bytes = File(tarBz2Path).readAsBytesSync();
      final tar = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
      for (final entry in tar) {
        final parts = p.posix.split(entry.name);
        if (parts.length < 2) continue; // top-level dir itself
        final rel = p.joinAll(parts.sublist(1));
        final out = File(p.join(destDir, rel));
        if (entry.isFile) {
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(entry.content as List<int>);
        }
      }
    });
  }

  static HttpClient _client() =>
      HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
}
