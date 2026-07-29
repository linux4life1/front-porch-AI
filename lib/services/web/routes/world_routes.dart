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

import 'package:front_porch_ai/services/web/facade/world_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// World (shared lorebook) CRUD endpoints for the web authoring UI.
class WebWorldRoutes {
  WebWorldRoutes(this._facade, Router router) {
    router.get('/api/worlds', _list);
    router.get('/api/worlds/climates', _climates);
    router.post('/api/worlds', _save);
    // Static suffix; register before the '<name>' captures so 'import' is never
    // swallowed as a world name.
    router.post('/api/worlds/import', _import);
    router.post('/api/lorebook/import', _importLorebook);
    router.get('/api/chat/places', _chatPlaces);
    router.post('/api/chat/places', _setChatPlaces);
    router.post('/api/chat/climate', _setChatClimate);
    // Encode the name in the path; names can contain spaces (URL-encoded).
    router.get('/api/worlds/<name>/detail', _detail);
    router.get('/api/worlds/<name>/export', _export);
    router.post('/api/worlds/<name>/delete', _delete);
  }

  final WorldFacade _facade;

  shelf.Response _list(shelf.Request request) =>
      JsonResponse.ok({'worlds': _facade.list()});

  shelf.Response _climates(shelf.Request request) =>
      JsonResponse.ok({'climates': _facade.climates()});

  shelf.Response _chatPlaces(shelf.Request request) =>
      JsonResponse.ok(_facade.chatPlaces());

  Future<shelf.Response> _setChatPlaces(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final raw = body['worldIds'];
    final ids = raw is List
        ? [for (final e in raw) e.toString()]
        : <String>[];
    final result = await _facade.setChatPlaces(ids);
    if (result['ok'] != true) {
      return JsonResponse.badRequest(
        result['error']?.toString() ?? 'Could not update places',
      );
    }
    return JsonResponse.ok(result);
  }

  Future<shelf.Response> _setChatClimate(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final id = body['biomeId']?.toString() ?? body['climateId']?.toString();
    if (id == null || id.isEmpty) {
      return JsonResponse.badRequest('biomeId is required');
    }
    final result = await _facade.setChatClimate(id);
    if (result['ok'] != true) {
      return JsonResponse.badRequest(
        result['error']?.toString() ?? 'Could not set climate',
      );
    }
    return JsonResponse.ok(result);
  }

  shelf.Response _detail(shelf.Request request, String name) {
    final detail = _facade.detail(Uri.decodeComponent(name));
    if (detail == null) return JsonResponse.error(404, 'World not found');
    return JsonResponse.ok(detail);
  }

  Future<shelf.Response> _save(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final ok = await _facade.save(body);
    if (!ok) return JsonResponse.badRequest('name is required');
    return JsonResponse.ok({'worlds': _facade.list()});
  }

  Future<shelf.Response> _delete(shelf.Request request, String name) async {
    final ok = await _facade.delete(Uri.decodeComponent(name));
    if (!ok) return JsonResponse.error(404, 'World not found');
    return JsonResponse.ok({'worlds': _facade.list()});
  }

  /// Import a world from a JSON body (SillyTavern / Chub.ai / Front Porch). The
  /// body is parsed + size-capped by [RequestBody.readJsonMap]; structural
  /// validation lives in the facade. Returns the refreshed world list so the
  /// page updates in one round-trip (same shape as save/delete).
  Future<shelf.Response> _import(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final ok = await _facade.importWorld(body);
    if (!ok) {
      return JsonResponse.badRequest(
        'Invalid world file: missing lorebook entries '
        '(supported: SillyTavern, Chub.ai, Front Porch)',
      );
    }
    return JsonResponse.ok({'worlds': _facade.list()});
  }

  /// Export the named world as a downloadable Front Porch world JSON. The
  /// filename is sanitized to a safe charset so the (server-controlled but
  /// name-derived) Content-Disposition header can't be used for injection.
  shelf.Response _export(shelf.Request request, String name) {
    final decoded = Uri.decodeComponent(name);
    final world = _facade.exportWorld(decoded);
    if (world == null) return JsonResponse.error(404, 'World not found');
    final placeName = world['name']?.toString() ?? decoded;
    final safe =
        placeName.replaceAll(RegExp(r'[^A-Za-z0-9 _\-]'), '_').trim();
    final filename = safe.isEmpty ? 'place' : safe;
    return JsonResponse.ok(
      world,
      extraHeaders: {
        'Content-Disposition':
            'attachment; filename="$filename.fpworld.json"',
      },
    );
  }

  /// Import-with-destination (the web Import Lorebook wizard backend).
  Future<shelf.Response> _importLorebook(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    if (body['json'] is! Map) {
      return JsonResponse.badRequest('json object is required');
    }
    final result = await _facade.importLorebook(
      Map<String, dynamic>.from(body['json'] as Map),
      dryRun: body['dryRun'] == true,
      destination: body['destination']?.toString() ?? 'world',
      name: body['name']?.toString(),
      description: body['description']?.toString(),
      characterIds: body['characterIds'] is List
          ? [for (final id in body['characterIds'] as List) id.toString()]
          : const [],
    );
    if (result == null) {
      return JsonResponse.badRequest('Could not import to that destination');
    }
    return JsonResponse.ok(result);
  }
}
