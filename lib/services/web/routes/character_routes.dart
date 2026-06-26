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

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/character_authoring_facade.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// Character endpoints (list / avatar / detail / create / edit / delete /
/// avatar management) for the rewritten server.
class WebCharacterRoutes {
  WebCharacterRoutes(
    this._facade,
    Router router, {
    CharacterAuthoringFacade? authoring,
  }) : _authoring = authoring {
    router.get('/api/characters', _list);
    router.get('/api/folders', _folders);
    // Register before '/api/characters/<id>' so 'import'/'create' aren't
    // captured as an id.
    router.post('/api/characters/import', _import);
    router.post('/api/characters/create', _create);
    // Active-character expression portrait (mood-driven). Static path, so it
    // registers before the '<id>' captures below.
    router.get('/api/chat/expression-avatar', _expressionAvatar);
    router.get('/api/characters/<id>/avatar', _avatar);
    router.get('/api/characters/<id>/detail', _detail);
    // Avatar management (specific sub-paths before the bare '<id>' POST).
    router.get('/api/characters/<id>/avatars', _avatars);
    router.post('/api/characters/<id>/avatars', _addAvatar);
    router.get('/api/characters/<id>/avatars/<avatarId>/image', _avatarImage);
    router.post('/api/characters/<id>/avatars/<avatarId>/prime', _setPrime);
    router.post('/api/characters/<id>/avatars/<avatarId>/delete', _removeAvatar);
    router.post('/api/characters/<id>/delete', _delete);
    router.post('/api/characters/<id>', _update);
  }

  final CharacterFacade _facade;
  final CharacterAuthoringFacade? _authoring;

  /// Import an uploaded character card (raw bytes; `?filename=` gives the type).
  Future<shelf.Response> _import(shelf.Request request) async {
    final filename = request.url.queryParameters['filename'] ?? 'card.png';
    final List<int> bytes;
    try {
      bytes = await RequestBody.readBytes(
        request,
        maxBytes: RequestBody.uploadMaxBytes,
      );
    } catch (_) {
      return JsonResponse.error(413, 'File too large');
    }
    if (bytes.isEmpty) return JsonResponse.badRequest('Empty upload');
    final result = await _facade.importBytes(bytes, filename);
    if (result == null) {
      return JsonResponse.error(422, 'Could not read that character card');
    }
    return JsonResponse.ok(result);
  }

  /// Create a new character from wizard fields (JSON body). Returns {id, name}.
  Future<shelf.Response> _create(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    if ((body['name']?.toString().trim() ?? '').isEmpty) {
      return JsonResponse.badRequest('name is required');
    }
    final result = await _facade.create(body);
    if (result == null) {
      return JsonResponse.error(422, 'Could not create character');
    }
    return JsonResponse.ok(result);
  }

  Future<shelf.Response> _list(shelf.Request request) async {
    final q = request.url.queryParameters;
    final result = await _facade.list(
      search: q['search'],
      folder: q['folder'],
      sort: q['sort'] ?? 'name',
    );
    return JsonResponse.ok(result);
  }

  /// The character folder tree, so the library can render folder navigation.
  shelf.Response _folders(shelf.Request request) =>
      JsonResponse.ok({'folders': _facade.folders()});

  /// Serve the active character's current expression portrait (mood-driven).
  /// Returns 404 when expressions aren't in use so the client falls back to the
  /// static character avatar.
  shelf.Response _expressionAvatar(shelf.Request request) {
    final file = _facade.activeExpressionAvatarFile();
    if (file == null) return shelf.Response.notFound('No expression avatar');
    return shelf.Response.ok(
      file.readAsBytesSync(),
      headers: {
        'Content-Type': 'image/png',
        // Short cache; the client cache-busts via ?v=<expressionLabel> anyway.
        'Cache-Control': 'private, max-age=60',
      },
    );
  }

  Future<shelf.Response> _avatar(shelf.Request request, String id) async {
    final file = await _facade.avatarFile(id);
    if (file == null) return shelf.Response.notFound('No avatar');
    return shelf.Response.ok(
      file.readAsBytesSync(),
      headers: {
        'Content-Type': 'image/png',
        'Cache-Control': 'public, max-age=3600',
      },
    );
  }

  Future<shelf.Response> _detail(shelf.Request request, String id) async {
    final detail = await _facade.detail(id);
    if (detail == null) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok(detail);
  }

  /// Edit an existing character's core fields, then return the fresh detail.
  Future<shelf.Response> _update(shelf.Request request, String id) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final ok = await _facade.update(id, body);
    if (!ok) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok(await _facade.detail(id) ?? {'status': 'ok'});
  }

  /// Delete a character (soft-delete row + remove PNG + chat history).
  Future<shelf.Response> _delete(shelf.Request request, String id) async {
    final auth = _authoring;
    if (auth == null) return JsonResponse.error(503, 'Unavailable');
    final ok = await auth.delete(id);
    if (!ok) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok({'status': 'deleted'});
  }

  Future<shelf.Response> _avatars(shelf.Request request, String id) async {
    final auth = _authoring;
    if (auth == null) return JsonResponse.error(503, 'Unavailable');
    return JsonResponse.ok({'avatars': await auth.avatars(id)});
  }

  /// Upload a new avatar image (raw bytes; `?label=` is optional).
  Future<shelf.Response> _addAvatar(shelf.Request request, String id) async {
    final auth = _authoring;
    if (auth == null) return JsonResponse.error(503, 'Unavailable');
    final List<int> bytes;
    try {
      bytes = await RequestBody.readBytes(
        request,
        maxBytes: RequestBody.uploadMaxBytes,
      );
    } catch (_) {
      return JsonResponse.error(413, 'File too large');
    }
    if (bytes.isEmpty) return JsonResponse.badRequest('Empty upload');
    final ok = await auth.addAvatar(
      id,
      bytes,
      request.url.queryParameters['label'],
    );
    if (!ok) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok({'avatars': await auth.avatars(id)});
  }

  Future<shelf.Response> _avatarImage(
    shelf.Request request,
    String id,
    String avatarId,
  ) async {
    final auth = _authoring;
    if (auth == null) return shelf.Response.notFound('Unavailable');
    final file = await auth.avatarFile(id, avatarId);
    if (file == null) return shelf.Response.notFound('No avatar');
    return shelf.Response.ok(
      file.readAsBytesSync(),
      headers: {
        'Content-Type': 'image/png',
        'Cache-Control': 'public, max-age=3600',
      },
    );
  }

  Future<shelf.Response> _setPrime(
    shelf.Request request,
    String id,
    String avatarId,
  ) async {
    final auth = _authoring;
    if (auth == null) return JsonResponse.error(503, 'Unavailable');
    final ok = await auth.setPrime(id, avatarId);
    if (!ok) return JsonResponse.error(404, 'Avatar not found');
    return JsonResponse.ok({'avatars': await auth.avatars(id)});
  }

  Future<shelf.Response> _removeAvatar(
    shelf.Request request,
    String id,
    String avatarId,
  ) async {
    final auth = _authoring;
    if (auth == null) return JsonResponse.error(503, 'Unavailable');
    final ok = await auth.removeAvatar(id, avatarId);
    if (!ok) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok({'avatars': await auth.avatars(id)});
  }
}
