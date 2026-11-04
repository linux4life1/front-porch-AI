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

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/storage/user_audio_store.dart';
import 'package:front_porch_ai/services/web/util/media_ranges.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:path/path.dart' as p;

/// User-owned scene sounds, served from the LIVE data root per request
/// (`deps.storage.rootPath`), not a path captured at server startup. The
/// PWA's world editor uploads bytes to POST `/api/worlds/audio`; the chat
/// page fetches them from `/api/user/audio/<name>` with byte ranges.
class UserAudioRoutes {
  UserAudioRoutes(this._deps, Router router) {
    router.get('/api/user/audio', _list);
    router.get('/api/user/audio/<name>', _serve);
    router.post('/api/worlds/audio', _upload);
  }

  final WebServerDeps _deps;

  /// The picker's library: sounds this server has already stored, newest
  /// first. The client reuses one by PATCHing its name — no re-upload.
  Future<shelf.Response> _list(shelf.Request request) async {
    final sounds = await UserAudioStore.listUserAudio(_deps.storage);
    return JsonResponse.ok({
      'sounds': [
        for (final s in sounds)
          {'name': s.name, 'bytes': s.bytes, 'modifiedMs': s.modifiedMs},
      ],
    });
  }

  Future<shelf.Response> _serve(shelf.Request request, String name) async {
    final decoded = _decoded(name);
    final file = decoded == null ? null : _inside(_audioDir().path, decoded);
    if (file == null) {
      return shelf.Response.notFound('user sound not found');
    }
    return serveMediaRanges(
      file,
      request.headers,
      head: request.method == 'HEAD',
    );
  }

  Future<shelf.Response> _upload(shelf.Request request) async {
    final Uint8List bytes;
    try {
      bytes = await RequestBody.readBytes(
        request,
        maxBytes: RequestBody.uploadMaxBytes,
      );
    } on BodyTooLarge {
      return JsonResponse.badRequest('That sound file is too large.');
    }
    final fileName = request.url.queryParameters['name'] ?? '';
    if (fileName.isEmpty) {
      return JsonResponse.badRequest('name is required');
    }
    final result = await UserAudioStore.storeUserAudioBytes(
      bytes,
      fileName,
      _deps.storage,
    );
    if (result.error != null) {
      return JsonResponse.badRequest(result.error!);
    }
    return JsonResponse.ok({
      'name': result.name,
      if (result.note != null) 'note': result.note,
    });
  }

  Directory _audioDir() => Directory(
    _deps.storage.rootPath == null
        ? ''
        : p.join(_deps.storage.rootPath!, 'audio'),
  );

  static String? _decoded(String encoded) {
    try {
      return Uri.decodeComponent(encoded);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static File? _inside(String? dir, String rel) {
    if (dir == null || dir.isEmpty) return null;
    final normalized = p.normalize(rel);
    if (normalized.contains('..') ||
        p.isAbsolute(normalized) ||
        normalized.startsWith('/')) {
      return null;
    }
    final file = File(p.join(dir, normalized));
    return file.existsSync() ? file : null;
  }
}
