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
    router.post('/api/worlds', _save);
    // Encode the name in the path; names can contain spaces (URL-encoded).
    router.get('/api/worlds/<name>/detail', _detail);
    router.post('/api/worlds/<name>/delete', _delete);
  }

  final WorldFacade _facade;

  shelf.Response _list(shelf.Request request) =>
      JsonResponse.ok({'worlds': _facade.list()});

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
}
