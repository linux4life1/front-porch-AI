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
  // Persona files (PR 7d): the desktop persona page imports from a JSON
  // file and exports one persona to `<name>_FPAIpersona.json` (SillyTavern
  // format). The PWA has no folder picker, so the document travels as raw
  // bytes and the service runs the same format detection the desktop's
  // dialog feeds it. `/import` must match before the /<id> catch-all below.
  router.post('/api/personas/import', (r) => _importPersonas(facade, r));
  router.get(
    '/api/personas/<id>/export.json',
    (r, id) => _exportPersona(facade, r, id),
  );
  // The desktop's header upload icon exports the whole pick in one file
  // (`FPAI_personas.json`); the web twin downloads it whole.
  router.get(
    '/api/personas/export-all.json',
    (r) => _exportAllPersonas(facade, r),
  );
  // Imported persona avatars are files on disk; the desktop paints them in
  // its circles, so the web needs them served to match.
  router.get(
    '/api/personas/<id>/avatar',
    (r, id) => _personaAvatar(facade, r, id),
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

/// Import a persona JSON document sent as raw text (the body IS the
/// document, in any format UserPersonaService accepts — FPAI bundle, ST
/// V2/V1 character export, V2 card). Raw, not a JSON envelope, so the
/// document is never double-encoded. A body that matches no format
/// answers 400 with the desktop's message, like its status line.
Future<shelf.Response> _importPersonas(
  ChatFacade facade,
  shelf.Request request,
) async {
  String text;
  try {
    text = await RequestBody.readString(request);
  } on BodyTooLarge {
    return JsonResponse.error(413, 'Persona file is too large (8 MB cap).');
  }
  if (text.trim().isEmpty) {
    return JsonResponse.error(400, 'Please select a file first');
  }
  try {
    final imported = await facade.personaOps.importJson(text);
    if (imported == null) {
      return JsonResponse.error(400, 'Import failed — unrecognized format');
    }
    return JsonResponse.ok({
      'status': 'ok',
      'imported': imported,
      'personas': facade.personas(),
    });
  } on StateError catch (e) {
    return JsonResponse.error(503, e.message);
  } catch (_) {
    return JsonResponse.error(400, 'Import failed — unrecognized format');
  }
}

/// Export one persona as an ST-format JSON download, named like the
/// desktop's file (`Ada_Lovelace_FPAIpersona.json`).
Future<shelf.Response> _exportPersona(
  ChatFacade facade,
  shelf.Request request,
  String id,
) async {
  final ({String filename, List<int> bytes})? out;
  try {
    out = await facade.personaOps.exportJson(id);
  } catch (_) {
    return JsonResponse.error(500, 'Export failed');
  }
  if (out == null) return JsonResponse.error(404, 'Persona not found');
  return shelf.Response.ok(
    out.bytes,
    headers: {
      'content-type': 'application/json',
      'content-disposition': 'attachment; filename="${out.filename}"',
    },
  );
}

/// Export every persona as one ST-format JSON download, named like the
/// desktop's multi-persona file (`FPAI_personas.json`).
Future<shelf.Response> _exportAllPersonas(
  ChatFacade facade,
  shelf.Request request,
) async {
  final ({String filename, List<int> bytes})? out;
  try {
    out = await facade.personaOps.exportAllJson();
  } catch (_) {
    return JsonResponse.error(500, 'Export failed');
  }
  if (out == null) return JsonResponse.error(503, 'Unavailable');
  return shelf.Response.ok(
    out.bytes,
    headers: {
      'content-type': 'application/json',
      'content-disposition': 'attachment; filename="${out.filename}"',
    },
  );
}

/// The persona avatar image. 404 when the persona has none — the web then
/// shows the color circle, the desktop's own fallback.
Future<shelf.Response> _personaAvatar(
  ChatFacade facade,
  shelf.Request request,
  String id,
) async {
  final ({List<int> bytes, String contentType})? img;
  try {
    img = await facade.personaOps.avatar(id);
  } catch (_) {
    return JsonResponse.error(500, 'Avatar read failed');
  }
  if (img == null) return JsonResponse.error(404, 'No avatar');
  return shelf.Response.ok(
    img.bytes,
    headers: {'content-type': img.contentType},
  );
}

Future<Map<String, dynamic>> _json(shelf.Request request) async {
  try {
    return await RequestBody.readJsonMap(request);
  } catch (_) {
    return const {};
  }
}
