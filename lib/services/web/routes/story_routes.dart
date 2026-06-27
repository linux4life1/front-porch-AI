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

import 'package:front_porch_ai/services/web/facade/story_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// Porch Stories endpoints: project CRUD, background pipeline stages (progress
/// streams over the WS hub), and export. Specific paths are registered before
/// the `<id>` param route so `/status` isn't swallowed by it.
class WebStoryRoutes {
  WebStoryRoutes(this._facade, Router router) {
    router.get('/api/stories', _list);
    router.post('/api/stories', _create);
    router.get('/api/stories/status', _status);
    router.get('/api/stories/voices', _voices);
    router.get('/api/stories/archetypes', _archetypes);
    router.get('/api/stories/<id>', _get);
    router.post('/api/stories/<id>/run', _run);
    router.post('/api/stories/<id>/delete', _delete);
    router.get('/api/stories/<id>/export', _export);
    router.get('/api/stories/<id>/chat-preview', _chatPreview);
    router.post('/api/stories/<id>', _save);
  }

  final StoryFacade _facade;

  Future<shelf.Response> _list(shelf.Request r) async =>
      JsonResponse.ok({'stories': await _facade.list()});

  Future<shelf.Response> _create(shelf.Request r) async {
    final body = await _json(r);
    return JsonResponse.ok(
      await _facade.create(body['title']?.toString() ?? ''),
    );
  }

  shelf.Response _status(shelf.Request r) => JsonResponse.ok(_facade.status());

  shelf.Response _voices(shelf.Request r) =>
      JsonResponse.ok({'voices': _facade.voices()});

  shelf.Response _archetypes(shelf.Request r) {
    final n = int.tryParse(r.url.queryParameters['count'] ?? '') ?? 6;
    return JsonResponse.ok({
      'archetypes': _facade.archetypes(count: n.clamp(1, 12)),
    });
  }

  Future<shelf.Response> _get(shelf.Request r, String id) async {
    final story = await _facade.get(id);
    if (story == null) return JsonResponse.error(404, 'Story not found');
    return JsonResponse.ok(story);
  }

  Future<shelf.Response> _save(shelf.Request r, String id) async {
    final body = await _json(r);
    if (body.isEmpty) {
      return JsonResponse.badRequest('project body is required');
    }
    final ok = await _facade.save(id, body);
    if (!ok) return JsonResponse.error(404, 'Story not found');
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _delete(shelf.Request r, String id) async {
    final ok = await _facade.delete(id);
    if (!ok) return JsonResponse.error(404, 'Story not found');
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _run(shelf.Request r, String id) async {
    final body = await _json(r);
    final stage = body['stage']?.toString();
    if (stage == null || stage.isEmpty) {
      return JsonResponse.badRequest('stage is required');
    }
    int? asInt(String k) => body[k] is int ? body[k] as int : null;
    final ok = await _facade.runStage(
      id,
      stage,
      actIndex: asInt('actIndex'),
      sceneIndex: asInt('sceneIndex'),
      beatIndex: asInt('beatIndex'),
    );
    if (!ok) {
      return JsonResponse.error(
        404,
        'Unknown story, stage, or missing indices',
      );
    }
    return JsonResponse.ok({'status': 'started'});
  }

  Future<shelf.Response> _export(shelf.Request r, String id) async {
    final format = r.url.queryParameters['format'] ?? 'text';
    final text = await _facade.export(id, format);
    if (text == null) return JsonResponse.error(404, 'Story not found');
    return JsonResponse.ok({'format': format, 'text': text});
  }

  Future<shelf.Response> _chatPreview(shelf.Request r, String id) async =>
      JsonResponse.ok({'messages': await _facade.chatPreview(id)});

  Future<Map<String, dynamic>> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } catch (_) {
      return const {};
    }
  }
}
