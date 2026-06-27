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
import 'package:front_porch_ai/services/web/facade/character_library_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// Character endpoints (list / avatar / detail / create / edit / delete /
/// avatar management) for the rewritten server.
class WebCharacterRoutes {
  WebCharacterRoutes(
    this._facade,
    Router router, {
    CharacterAuthoringFacade? authoring,
    CharacterLibraryFacade? library,
  }) : _authoring = authoring,
       _library = library {
    router.get('/api/characters', _list);
    router.get('/api/folders', _folders);
    // Folder write ops (create/rename/delete). 'rename'/'delete' are deeper than
    // the bare '<id>' so order doesn't matter, but create shares the GET path.
    router.post('/api/folders', _createFolder);
    router.post('/api/folders/<id>/rename', _renameFolder);
    router.post('/api/folders/<id>/delete', _deleteFolder);
    // Register before '/api/characters/<id>' so 'import'/'create'/'move' aren't
    // captured as an id.
    router.post('/api/characters/import', _import);
    router.post('/api/characters/create', _create);
    router.post('/api/characters/move', _bulkMove);
    // Active-character expression portrait (mood-driven). Static path, so it
    // registers before the '<id>' captures below.
    router.get('/api/chat/expression-avatar', _expressionAvatar);
    router.get('/api/characters/<id>/avatar', _avatar);
    router.get('/api/characters/<id>/detail', _detail);
    router.get('/api/characters/<id>/export.png', _exportPng);
    router.get('/api/characters/<id>/export.json', _exportJson);
    // Avatar management (specific sub-paths before the bare '<id>' POST).
    router.get('/api/characters/<id>/avatars', _avatars);
    router.post('/api/characters/<id>/avatars', _addAvatar);
    router.get('/api/characters/<id>/avatars/<avatarId>/image', _avatarImage);
    router.post('/api/characters/<id>/avatars/<avatarId>/prime', _setPrime);
    router.post(
      '/api/characters/<id>/avatars/<avatarId>/delete',
      _removeAvatar,
    );
    router.post('/api/characters/<id>/duplicate', _duplicate);
    router.post('/api/characters/<id>/move', _move);
    router.post('/api/characters/<id>/delete', _delete);
    router.post('/api/characters/<id>', _update);
  }

  final CharacterFacade _facade;
  final CharacterAuthoringFacade? _authoring;
  final CharacterLibraryFacade? _library;

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
      scope: q['scope'] ?? 'currentFolder',
    );
    return JsonResponse.ok(result);
  }

  /// The character folder tree, so the library can render folder navigation.
  shelf.Response _folders(shelf.Request request) =>
      JsonResponse.ok({'folders': _facade.folders()});

  /// Create a folder (optionally nested via `parentId`). Returns the new folder.
  Future<shelf.Response> _createFolder(shelf.Request request) async {
    final lib = _library;
    if (lib == null) return JsonResponse.error(503, 'Unavailable');
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final name = body['name']?.toString().trim() ?? '';
    if (name.isEmpty) return JsonResponse.badRequest('name is required');
    final result = await lib.createFolder(
      name,
      parentId: body['parentId']?.toString(),
    );
    if (result == null) {
      return JsonResponse.error(422, 'Could not create folder');
    }
    return JsonResponse.ok(result);
  }

  Future<shelf.Response> _renameFolder(shelf.Request request, String id) async {
    final lib = _library;
    if (lib == null) return JsonResponse.error(503, 'Unavailable');
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final name = body['name']?.toString().trim() ?? '';
    if (name.isEmpty) return JsonResponse.badRequest('name is required');
    final ok = await lib.renameFolder(id, name);
    if (!ok) return JsonResponse.error(404, 'Folder not found');
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _deleteFolder(shelf.Request request, String id) async {
    final lib = _library;
    if (lib == null) return JsonResponse.error(503, 'Unavailable');
    final ok = await lib.deleteFolder(id);
    if (!ok) return JsonResponse.error(404, 'Folder not found');
    return JsonResponse.ok({'status': 'deleted'});
  }

  /// Duplicate a character (deep-copies extensions + fresh stable id).
  Future<shelf.Response> _duplicate(shelf.Request request, String id) async {
    final lib = _library;
    if (lib == null) return JsonResponse.error(503, 'Unavailable');
    final result = await lib.duplicate(id);
    if (result == null) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok(result);
  }

  /// Move one character into a folder, or back to root when `folderId` is
  /// null/empty/absent.
  Future<shelf.Response> _move(shelf.Request request, String id) async {
    final lib = _library;
    if (lib == null) return JsonResponse.error(503, 'Unavailable');
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final ok = await lib.moveToFolder(id, body['folderId']?.toString());
    if (!ok) return JsonResponse.error(404, 'Character or folder not found');
    return JsonResponse.ok({'status': 'ok'});
  }

  /// Move many characters into a folder (or root) in one call.
  Future<shelf.Response> _bulkMove(shelf.Request request) async {
    final lib = _library;
    if (lib == null) return JsonResponse.error(503, 'Unavailable');
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final ids = body['ids'] is List
        ? (body['ids'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    if (ids.isEmpty) return JsonResponse.badRequest('ids is required');
    final moved = await lib.bulkMove(ids, body['folderId']?.toString());
    return JsonResponse.ok({'moved': moved});
  }

  /// Export a character as a downloadable V2 PNG card.
  Future<shelf.Response> _exportPng(shelf.Request request, String id) async {
    final lib = _library;
    if (lib == null) return shelf.Response.notFound('Unavailable');
    final out = await lib.exportPng(id);
    if (out == null) return shelf.Response.notFound('Character not found');
    return shelf.Response.ok(
      out.bytes,
      headers: {
        'Content-Type': 'image/png',
        'Content-Disposition': 'attachment; filename="${out.filename}"',
      },
    );
  }

  /// Export a character as a downloadable V2 `.json` card.
  Future<shelf.Response> _exportJson(shelf.Request request, String id) async {
    final lib = _library;
    if (lib == null) return shelf.Response.notFound('Unavailable');
    final out = await lib.exportJson(id);
    if (out == null) return shelf.Response.notFound('Character not found');
    return shelf.Response.ok(
      out.json,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Disposition': 'attachment; filename="${out.filename}"',
      },
    );
  }

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
