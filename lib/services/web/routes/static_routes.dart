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
import 'package:shelf/shelf.dart' as shelf;

/// Serves the built React SPA (assets/web) with a history fallback so client-side
/// routes resolve to index.html. Hashed build assets are cached aggressively;
/// index.html and the service worker are never cached.
///
/// The asset base is resolved once across dev / macOS bundle / Linux+Windows
/// layouts (the same locations the legacy WebAssetServer used). This is the
/// clean-namespace replacement that will fully supersede it at Phase 6 cutover.
class StaticRoutes {
  StaticRoutes._(this._baseDir, this._backgroundsDir, this._sceneAudioDir);

  /// Resolves the web-app dir and, from it, the sibling per-chat theme
  /// backgrounds dir (both live under the same `flutter_assets/assets/` tree).
  factory StaticRoutes() => StaticRoutes.at(_resolveBaseDir());

  /// Serves the web app built into [webAppDir] (`…/assets/web_app`) and its
  /// siblings under the same `assets/` folder; null serves nothing.
  @visibleForTesting
  factory StaticRoutes.at(String? webAppDir) {
    final assets = webAppDir == null ? null : p.dirname(webAppDir);
    return StaticRoutes._(
      webAppDir,
      assets == null ? null : p.join(assets, 'backgrounds'),
      assets == null ? null : p.join(assets, 'audio', 'scene'),
    );
  }

  final String? _baseDir;

  /// `assets/audio/scene/` — the Ambient Stage's scene sound, bundled once
  /// for the desktop and served from there so the web chat plays the same
  /// files as `/audio/scene/<file>` (docs/design/ambient-stage.md §5).
  final String? _sceneAudioDir;

  /// `assets/backgrounds/` — theme scene images shared with the desktop app,
  /// served so the web chat can show the same per-chat background.
  final String? _backgroundsDir;

  /// Handle a non-`api/` GET as a static asset or SPA fallback.
  shelf.Response handle(shelf.Request request) {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return shelf.Response(405, body: 'Method Not Allowed');
    }
    final base = _baseDir;
    if (base == null) {
      return shelf.Response.notFound('Web UI assets not found');
    }

    final rel = request.url.path; // already strips leading '/'

    // Per-chat theme background images (parity with the desktop chat scene).
    // Served from the sibling assets/backgrounds dir; the web CSS references
    // them as `/backgrounds/<key>.png`.
    if (rel.startsWith('backgrounds/')) {
      final bgDir = _backgroundsDir;
      if (bgDir != null) {
        final normalized = p.normalize(rel.substring('backgrounds/'.length));
        if (!normalized.contains('..') &&
            !p.isAbsolute(normalized) &&
            !normalized.startsWith('/')) {
          final file = File(p.join(bgDir, normalized));
          if (file.existsSync()) return _serveFile(file, rel);
        }
      }
      return shelf.Response.notFound('background not found');
    }

    // The scene sound, shared with the desktop (not in the Vite bundle):
    // the MP3s only, not the folder's licence record.
    if (rel.startsWith('audio/scene/')) {
      // The name is decoded, so an encoded `..%2F` meets the guard as `../`.
      final name = _decoded(rel.substring('audio/scene/'.length));
      final file = name != null && name.toLowerCase().endsWith('.mp3')
          ? _inside(_sceneAudioDir, name)
          : null;
      if (file != null) return _serveMedia(file, rel, request.headers);
      return shelf.Response.notFound('scene sound not found');
    }

    if (rel.isNotEmpty) {
      final normalized = p.normalize(rel);
      if (!normalized.contains('..') &&
          !p.isAbsolute(normalized) &&
          !normalized.startsWith('/')) {
        final file = File(p.join(base, normalized));
        if (file.existsSync()) return _serveFile(file, rel);
      }
    }

    // SPA history fallback → index.html (no-cache).
    final index = File(p.join(base, 'index.html'));
    if (index.existsSync()) return _serveFile(index, 'index.html');
    return shelf.Response.notFound('index.html not found');
  }

  /// [encoded] with its percent escapes undone, or null when they are bad.
  static String? _decoded(String encoded) {
    try {
      return Uri.decodeComponent(encoded);
    } on ArgumentError {
      return null;
    }
  }

  /// [rel] under [dir] when it names a file there and does not climb out.
  static File? _inside(String? dir, String rel) {
    if (dir == null) return null;
    final normalized = p.normalize(rel);
    if (normalized.contains('..') ||
        p.isAbsolute(normalized) ||
        normalized.startsWith('/')) {
      return null;
    }
    final file = File(p.join(dir, normalized));
    return file.existsSync() ? file : null;
  }

  /// A media file, with byte ranges: an `<audio>` element asks for them
  /// (Safari will not play from a server that ignores them), and the scene
  /// sounds are small enough to cut one range from the whole file. An ETag
  /// (length and mtime) lets a revisit revalidate with a 304 instead of
  /// fetching the file again; a multi-range ask gets the whole file.
  static shelf.Response _serveMedia(
    File file,
    String relPath,
    Map<String, String> request,
  ) {
    final stat = file.statSync();
    final tag =
        '"${stat.size.toRadixString(16)}-'
        '${stat.modified.millisecondsSinceEpoch.toRadixString(16)}"';
    final headers = {
      'Content-Type': _contentType(p.basename(relPath).toLowerCase()),
      'Cache-Control': 'no-cache',
      'Accept-Ranges': 'bytes',
      'ETag': tag,
      'Last-Modified': HttpDate.format(stat.modified),
    };
    final match = request['if-none-match'];
    if (match != null &&
        (match.trim() == '*' ||
            match.split(',').map((t) => t.trim()).contains(tag))) {
      return shelf.Response.notModified(headers: headers);
    }
    final bytes = file.readAsBytesSync();
    final len = bytes.length;
    final range = request['range'];
    final m = range == null
        ? null
        : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
    if (m == null) return shelf.Response.ok(bytes, headers: headers);
    final from = int.tryParse(m.group(1)!);
    final to = int.tryParse(m.group(2)!);
    final int start;
    final int end;
    if (from == null) {
      // `bytes=-N`: the last N bytes.
      if (to == null) return shelf.Response.ok(bytes, headers: headers);
      start = to >= len ? 0 : len - to;
      end = len - 1;
    } else {
      start = from;
      end = to == null || to >= len ? len - 1 : to;
    }
    if (start >= len || start > end) {
      return shelf.Response(
        416,
        headers: {...headers, 'Content-Range': 'bytes */$len'},
      );
    }
    return shelf.Response(
      206,
      body: bytes.sublist(start, end + 1),
      headers: {...headers, 'Content-Range': 'bytes $start-$end/$len'},
    );
  }

  shelf.Response _serveFile(File file, String relPath) {
    final name = p.basename(relPath).toLowerCase();
    final isImmutable =
        (relPath.startsWith('assets/') || relPath.startsWith('backgrounds/')) &&
        name != 'index.html' &&
        !name.endsWith('.webmanifest');
    final isServiceWorker = name == 'sw.js' || name == 'service-worker.js';
    final cache = (isImmutable && !isServiceWorker)
        ? 'public, max-age=31536000, immutable'
        : 'no-cache, no-store, must-revalidate';
    return shelf.Response.ok(
      file.readAsBytesSync(),
      headers: {'Content-Type': _contentType(name), 'Cache-Control': cache},
    );
  }

  static String _contentType(String name) {
    if (name.endsWith('.html')) return 'text/html; charset=utf-8';
    if (name.endsWith('.js') || name.endsWith('.mjs')) {
      return 'application/javascript; charset=utf-8';
    }
    if (name.endsWith('.css')) return 'text/css; charset=utf-8';
    if (name.endsWith('.json')) return 'application/json; charset=utf-8';
    if (name.endsWith('.webmanifest')) return 'application/manifest+json';
    if (name.endsWith('.svg')) return 'image/svg+xml';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.ico')) return 'image/x-icon';
    if (name.endsWith('.woff2')) return 'font/woff2';
    if (name.endsWith('.woff')) return 'font/woff';
    if (name.endsWith('.wav')) return 'audio/wav';
    if (name.endsWith('.mp3')) return 'audio/mpeg';
    if (name.endsWith('.wasm')) return 'application/wasm';
    if (name.endsWith('.map')) return 'application/json';
    return 'application/octet-stream';
  }

  /// Resolve the directory that contains the built web UI (assets/web).
  static String? _resolveBaseDir() {
    final exeDir = File(Platform.resolvedExecutable).parent;

    // 1. Dev: walk up to pubspec.yaml, serve from source tree assets/web.
    Directory dir = exeDir;
    for (int i = 0; i < 12; i++) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
        final candidate = p.join(dir.path, 'assets', 'web_app');
        if (Directory(candidate).existsSync()) return candidate;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    // 2. macOS release bundle (App.framework / Contents/Resources).
    if (Platform.isMacOS) {
      final contents = exeDir.parent;
      for (final fa in [
        p.join(
          contents.path,
          'Frameworks',
          'App.framework',
          'Versions',
          'A',
          'Resources',
          'flutter_assets',
        ),
        p.join(contents.path, 'Resources', 'flutter_assets'),
      ]) {
        final candidate = p.join(fa, 'assets', 'web_app');
        if (Directory(candidate).existsSync()) return candidate;
      }
    }

    // 3. Linux / Windows desktop release: data/flutter_assets next to exe.
    final dataAssets = p.join(
      exeDir.path,
      'data',
      'flutter_assets',
      'assets',
      'web_app',
    );
    if (Directory(dataAssets).existsSync()) return dataAssets;

    debugPrint('[WebServer] Could not resolve web UI asset directory');
    return null;
  }
}
