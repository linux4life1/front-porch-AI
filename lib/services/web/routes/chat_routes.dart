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

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// Chat state + action endpoints for the rewritten server. Live tokens stream
/// over the WebSocket hub (/api/ws); these endpoints drive and read state.
class WebChatRoutes {
  WebChatRoutes(this._facade, Router router) {
    router.get('/api/chat/state', _state);
    router.get('/api/chat/participant/<id>/realism', _participantRealism);
    router.get('/api/chat/sessions', _sessions);
    router.get('/api/personas', _personas);
    router.post('/api/personas/select', _selectPersona);
    router.post('/api/personas/create', _createPersona);
    router.get('/api/personas/<id>/detail', _personaDetail);
    router.post('/api/personas/<id>/delete', _deletePersona);
    router.post('/api/personas/<id>', _updatePersona);
    router.post('/api/chat/select', _select);
    router.post('/api/chat/select-group', _selectGroup);
    router.post('/api/chat/send', _send);
    router.post('/api/chat/stop', _stop);
    router.post('/api/chat/regenerate', _regenerate);
    router.post('/api/chat/cancel-realism', _cancelRealism);
    router.post('/api/chat/continue', _continue);
    router.post('/api/chat/swipe', _swipe);
    router.post('/api/chat/edit', _edit);
    router.post('/api/chat/delete', _delete);
    router.post('/api/chat/insert-image', _insertImage);
    router.post('/api/chat/reprocess-needs', _reprocessNeeds);
    router.post('/api/chat/revert-needs-reprocess', _revertNeedsReprocess);
    router.post('/api/chat/author-note', _authorNote);
    router.post('/api/chat/session', _session);
  }

  final ChatFacade _facade;

  shelf.Response _state(shelf.Request request) =>
      JsonResponse.ok(_facade.state());

  /// Realism for one cast participant (focus-scoped sidebar in the unified UI).
  shelf.Response _participantRealism(shelf.Request request, String id) {
    final realism = _facade.participantRealism(id);
    if (realism == null) return JsonResponse.error(404, 'Participant not found');
    return JsonResponse.ok(realism);
  }

  /// List the active character's saved conversations (newest first) so the web
  /// UI can show the Conversations drawer and resume any of them.
  Future<shelf.Response> _sessions(shelf.Request request) async =>
      JsonResponse.ok({'sessions': await _facade.sessions()});

  shelf.Response _personas(shelf.Request request) =>
      JsonResponse.ok({'personas': _facade.personas()});

  Future<shelf.Response> _selectPersona(shelf.Request request) async {
    final body = await _json(request);
    final id = body['id']?.toString();
    if (id == null) return JsonResponse.badRequest('id is required');
    final ok = await _facade.setPersona(id);
    if (!ok) return JsonResponse.error(404, 'Persona not found');
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _createPersona(shelf.Request request) async {
    final body = await _json(request);
    if ((body['name']?.toString().trim() ?? '').isEmpty) {
      return JsonResponse.badRequest('name is required');
    }
    final ok = await _facade.createPersona(body);
    if (!ok) return JsonResponse.error(503, 'Personas unavailable');
    return JsonResponse.ok({'personas': _facade.personas()});
  }

  shelf.Response _personaDetail(shelf.Request request, String id) {
    final detail = _facade.personaDetail(id);
    if (detail == null) return JsonResponse.error(404, 'Persona not found');
    return JsonResponse.ok(detail);
  }

  Future<shelf.Response> _updatePersona(shelf.Request request, String id) async {
    final ok = await _facade.updatePersona(id, await _json(request));
    if (!ok) return JsonResponse.error(404, 'Persona not found');
    return JsonResponse.ok({'personas': _facade.personas()});
  }

  Future<shelf.Response> _deletePersona(shelf.Request request, String id) async {
    final ok = await _facade.deletePersona(id);
    if (!ok) {
      return JsonResponse.error(409, 'Cannot delete (last persona or unknown)');
    }
    return JsonResponse.ok({'personas': _facade.personas()});
  }

  Future<shelf.Response> _select(shelf.Request request) async {
    final body = await _json(request);
    final id = body['characterId']?.toString();
    if (id == null) return JsonResponse.badRequest('characterId is required');
    final ok = await _facade.select(id);
    if (!ok) return JsonResponse.error(404, 'Character not found');
    return JsonResponse.ok({
      'status': 'ok',
      'sessionId': _facade.currentSessionId,
    });
  }

  Future<shelf.Response> _selectGroup(shelf.Request request) async {
    final body = await _json(request);
    final id = body['groupId']?.toString();
    if (id == null) return JsonResponse.badRequest('groupId is required');
    final ok = await _facade.selectGroup(id);
    if (!ok) return JsonResponse.error(404, 'Group not found');
    return JsonResponse.ok({
      'status': 'ok',
      'sessionId': _facade.currentSessionId,
    });
  }

  Future<shelf.Response> _send(shelf.Request request) async {
    final body = await _json(request);
    final text = body['text']?.toString();
    if (text == null || text.trim().isEmpty) {
      return JsonResponse.badRequest('text is required');
    }
    _facade.send(text);
    return JsonResponse.ok({'status': 'ok'});
  }

  shelf.Response _stop(shelf.Request request) {
    _facade.stop();
    return JsonResponse.ok({'status': 'ok'});
  }

  shelf.Response _regenerate(shelf.Request request) {
    _facade.regenerate();
    return JsonResponse.ok({'status': 'ok'});
  }

  shelf.Response _cancelRealism(shelf.Request request) {
    _facade.cancelRealismEval();
    return JsonResponse.ok({'status': 'ok'});
  }

  shelf.Response _continue(shelf.Request request) {
    _facade.continueGeneration();
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _swipe(shelf.Request request) async {
    final body = await _json(request);
    final index = body['messageIndex'];
    final direction = body['direction'];
    if (index is! int || direction is! int) {
      return JsonResponse.badRequest('messageIndex and direction are required');
    }
    _facade.swipe(index, direction);
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _edit(shelf.Request request) async {
    final body = await _json(request);
    final index = body['index'];
    final text = body['text']?.toString();
    if (index is! int || text == null) {
      return JsonResponse.badRequest('index and text are required');
    }
    _facade.edit(index, text);
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _delete(shelf.Request request) async {
    final body = await _json(request);
    final index = body['index'];
    if (index is! int) return JsonResponse.badRequest('index is required');
    _facade.delete(index);
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _insertImage(shelf.Request request) async {
    final body = await _json(request);
    final filename = body['filename']?.toString();
    if (filename == null || filename.trim().isEmpty) {
      return JsonResponse.badRequest('filename is required');
    }
    final ok = _facade.insertImage(filename);
    if (!ok) return JsonResponse.error(409, 'No message to attach the image to');
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _reprocessNeeds(shelf.Request request) async {
    final body = await _json(request);
    final index = body['index'];
    final critique = body['critique']?.toString().trim() ?? '';
    if (index is! int) return JsonResponse.badRequest('index is required');
    if (critique.isEmpty) return JsonResponse.badRequest('critique is required');
    final ok = await _facade.reprocessNeeds(index, critique);
    if (!ok) return JsonResponse.error(409, 'Message cannot be reprocessed');
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _revertNeedsReprocess(shelf.Request request) async {
    final body = await _json(request);
    final index = body['index'];
    if (index is! int) return JsonResponse.badRequest('index is required');
    final ok = await _facade.revertNeedsReprocess(index);
    if (!ok) return JsonResponse.error(409, 'Nothing to revert');
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _authorNote(shelf.Request request) async {
    final body = await _json(request);
    final note = body['authorNote']?.toString() ?? '';
    final strength = body['strength'] is int ? body['strength'] as int : null;
    _facade.setAuthorNote(note, strength: strength);
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _session(shelf.Request request) async {
    final body = await _json(request);
    final sessionId = await _facade.session(
      action: body['action']?.toString(),
      sessionId: body['sessionId']?.toString(),
    );
    if (sessionId == null && body['action'] != 'new') {
      return JsonResponse.badRequest('sessionId or action is required');
    }
    return JsonResponse.ok({'status': 'ok', 'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } catch (_) {
      return const {};
    }
  }
}
