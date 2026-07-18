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
  StaticRoutes() : _baseDir = _resolveBaseDir();

  final String? _baseDir;

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

  shelf.Response _serveFile(File file, String relPath) {
    final name = p.basename(relPath).toLowerCase();
    final isImmutable =
        relPath.startsWith('assets/') &&
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
