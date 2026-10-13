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

import 'package:front_porch_ai/services/web/facade/persona_conversion_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Character ↔ persona conversion. Its own `/api/persona-convert/` prefix,
/// so `/api/characters/<id>` and `/api/personas/<id>` never catch these.
class WebPersonaConvertRoutes {
  WebPersonaConvertRoutes(this._facade, Router router) {
    router.get('/api/persona-convert/character/<id>', _characterPreview);
    router.post('/api/persona-convert/character/<id>', _characterToPersona);
    router.get('/api/persona-convert/persona/<id>', _characterSeed);
    router.get('/api/persona-convert/persona/<id>/portrait', _portrait);
  }

  final PersonaConversionFacade _facade;

  Future<shelf.Response> _characterPreview(
    shelf.Request request,
    String id,
  ) async {
    final preview = await _facade.characterPreview(id);
    if (preview == null) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok(preview);
  }

  /// Body `{ "swapMacros": bool }` (default true) → the new persona.
  Future<shelf.Response> _characterToPersona(
    shelf.Request request,
    String id,
  ) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      body = const {};
    }
    final persona = await _facade.characterToPersona(
      id,
      swapMacros: body['swapMacros'] != false,
    );
    if (persona == null) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok({'persona': persona});
  }

  /// `?swap=0` keeps `{{char}}` / `{{user}}` as written.
  shelf.Response _characterSeed(shelf.Request request, String id) {
    final seed = _facade.characterSeed(
      id,
      swapMacros: request.url.queryParameters['swap'] != '0',
    );
    if (seed == null) return JsonResponse.error(404, 'Persona not found');
    return JsonResponse.ok(seed);
  }

  /// The persona's picture, shown by the phone's wizards before saving.
  Future<shelf.Response> _portrait(shelf.Request request, String id) async {
    final picture = await _facade.portrait(id);
    if (picture == null) return shelf.Response.notFound('No portrait');
    return shelf.Response.ok(
      picture.bytes,
      headers: {
        'Content-Type': picture.contentType,
        'Cache-Control': 'private, max-age=60',
      },
    );
  }
}
