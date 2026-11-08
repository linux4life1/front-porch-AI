// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The persona endpoints: the global default picker (/api/personas/*) and
// the per-chat voice (/api/chat/persona). Own file for the same reason
// chat_place_move_route.dart has one — chat_routes.dart sits at the 500-
// line ratchet — and the family registers as a set so the big chat router
// carries one line for it. Routes, order and copy are unchanged from when
// these lived inline; only the file moved.

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Registers the persona family as a set. Order matters exactly as before:
/// `/api/personas/select` and `/create` must be matched before the
/// `/api/personas/<id>` catch-alls.
void registerPersonaRoutes(Router router, ChatFacade facade) {
  router.get('/api/personas', (r) => _personas(facade, r));
  router.post('/api/personas/select', (r) => _selectPersona(facade, r));
  router.post('/api/chat/persona', (r) => _selectChatPersona(facade, r));
  router.post('/api/personas/create', (r) => _createPersona(facade, r));
  router.get(
    '/api/personas/<id>/detail',
    (r, id) => _personaDetail(facade, r, id),
  );
  router.post(
    '/api/personas/<id>/delete',
    (r, id) => _deletePersona(facade, r, id),
  );
  router.post('/api/personas/<id>', (r, id) => _updatePersona(facade, r, id));
}

shelf.Response _personas(ChatFacade facade, shelf.Request request) =>
    JsonResponse.ok({'personas': facade.personas()});

Future<shelf.Response> _selectPersona(
  ChatFacade facade,
  shelf.Request request,
) async {
  final body = await _json(request);
  final id = body['id']?.toString();
  if (id == null) return JsonResponse.badRequest('id is required');
  final ok = await facade.setPersona(id);
  if (!ok) return JsonResponse.error(404, 'Persona not found');
  return JsonResponse.ok({'status': 'ok'});
}

/// Speak as a different persona in the CURRENT chat. Separate endpoint from
/// /api/personas/select on purpose: that one moves the default for new chats
/// and must not touch the chat you are in.
Future<shelf.Response> _selectChatPersona(
  ChatFacade facade,
  shelf.Request request,
) async {
  final body = await _json(request);
  final id = body['id']?.toString();
  if (id == null) return JsonResponse.badRequest('id is required');
  final ok = await facade.setChatPersona(id);
  if (!ok) return JsonResponse.error(404, 'Persona not found');
  return JsonResponse.ok({'status': 'ok'});
}

Future<shelf.Response> _createPersona(
  ChatFacade facade,
  shelf.Request request,
) async {
  final body = await _json(request);
  if ((body['name']?.toString().trim() ?? '').isEmpty) {
    return JsonResponse.badRequest('name is required');
  }
  final ok = await facade.createPersona(body);
  if (!ok) return JsonResponse.error(503, 'Personas unavailable');
  return JsonResponse.ok({'personas': facade.personas()});
}

shelf.Response _personaDetail(
  ChatFacade facade,
  shelf.Request request,
  String id,
) {
  final detail = facade.personaDetail(id);
  if (detail == null) return JsonResponse.error(404, 'Persona not found');
  return JsonResponse.ok(detail);
}

Future<shelf.Response> _updatePersona(
  ChatFacade facade,
  shelf.Request request,
  String id,
) async {
  final ok = await facade.updatePersona(id, await _json(request));
  if (!ok) return JsonResponse.error(404, 'Persona not found');
  return JsonResponse.ok({'personas': facade.personas()});
}

Future<shelf.Response> _deletePersona(
  ChatFacade facade,
  shelf.Request request,
  String id,
) async {
  final ok = await facade.deletePersona(id);
  if (!ok) {
    return JsonResponse.error(409, 'Cannot delete (last persona or unknown)');
  }
  return JsonResponse.ok({'personas': facade.personas()});
}

Future<Map<String, dynamic>> _json(shelf.Request request) async {
  try {
    return await RequestBody.readJsonMap(request);
  } catch (_) {
    return const {};
  }
}
