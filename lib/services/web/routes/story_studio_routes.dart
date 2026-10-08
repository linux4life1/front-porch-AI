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
import 'package:front_porch_ai/services/web/util/util.dart';

/// Studio endpoints beside the base story routes: Stop, the Director,
/// continuity-fix undo, lore, the run log, and the read-only helpers. The
/// fixed paths register before `story_routes`' `<id>` params would swallow
/// them, so this class is constructed first.
class WebStoryStudioRoutes {
  WebStoryStudioRoutes(this._facade, Router router) {
    router.get('/api/stories/lenses', _lenses);
    router.get('/api/stories/pacing', _pacing);
    router.get('/api/stories/lanes', _lanes);
    router.post('/api/stories/lane-label', _laneLabel);
    router.get('/api/stories/host-models', _hostModels);
    router.post('/api/stories/host-key', _hostKey);
    router.post('/api/stories/quality', _quality);
    router.post('/api/stories/<id>/stop', _stop);
    router.post('/api/stories/<id>/rename', _rename);
    router.post('/api/stories/<id>/director/action', _directorAction);
    router.post('/api/stories/<id>/director/protect', _directorProtect);
    router.post('/api/stories/<id>/director/discard', _directorDiscard);
    router.post('/api/stories/<id>/director/undo', _directorUndo);
    router.post('/api/stories/<id>/undo-fix', _undoFix);
    router.post('/api/stories/<id>/lore', _addLore);
    router.post('/api/stories/<id>/lore/search', _searchLore);
    router.get('/api/stories/<id>/portrait', _portrait);
    router.post('/api/stories/<id>/portrait', _paintPortrait);
    router.get('/api/stories/<id>/log', _log);
    router.post('/api/stories/<id>/log/clear', _clearLog);
  }

  final StoryFacade _facade;

  shelf.Response _lenses(shelf.Request r) =>
      JsonResponse.ok({'lenses': _facade.lenses()});

  shelf.Response _pacing(shelf.Request r) {
    final words = int.tryParse(r.url.queryParameters['words'] ?? '') ?? 80000;
    return JsonResponse.ok(_facade.pacing(words));
  }

  shelf.Response _lanes(shelf.Request r) => JsonResponse.ok(_facade.lanes());

  Future<shelf.Response> _rename(shelf.Request r, String id) async {
    final body = await _json(r);
    final ok = await _facade.rename(id, body['title']?.toString() ?? '');
    return ok
        ? JsonResponse.ok({'ok': true})
        : JsonResponse.error(404, 'No such story, or an empty title');
  }

  Future<shelf.Response> _laneLabel(shelf.Request r) async {
    final body = await _json(r);
    return JsonResponse.ok({'label': _facade.laneLabel(body)});
  }

  Future<shelf.Response> _hostModels(shelf.Request r) async {
    final q = r.url.queryParameters;
    try {
      final models = await _facade.hostModels(q['type'] ?? '', q['url'] ?? '');
      return JsonResponse.ok({'models': models});
    } catch (e) {
      return JsonResponse.error(502, 'Could not list models: $e');
    }
  }

  Future<shelf.Response> _hostKey(shelf.Request r) async {
    final body = await _json(r);
    await _facade.saveHostKey(
      body['type']?.toString() ?? '',
      body['url']?.toString() ?? '',
      body['key']?.toString() ?? '',
    );
    return JsonResponse.ok({'ok': true});
  }

  Future<shelf.Response> _quality(shelf.Request r) async {
    final body = await _json(r);
    final banned = (body['banned'] as List?)?.map((e) => '$e').toList() ?? [];
    return JsonResponse.ok(
      _facade.quality(body['text']?.toString() ?? '', banned),
    );
  }

  shelf.Response _stop(shelf.Request r, String id) =>
      JsonResponse.ok(_facade.stop());

  Future<shelf.Response> _directorAction(shelf.Request r, String id) async {
    final body = await _json(r);
    final index = body['index'];
    if (index is! int) return JsonResponse.badRequest('index is required');
    final ok = await _facade.directorAction(id, index, body['enabled'] == true);
    return ok ? JsonResponse.ok({'status': 'ok'}) : _notFound();
  }

  Future<shelf.Response> _directorProtect(shelf.Request r, String id) async {
    final body = await _json(r);
    final ok = await _facade.directorProtect(id, body['protect'] != false);
    return ok ? JsonResponse.ok({'status': 'ok'}) : _notFound();
  }

  Future<shelf.Response> _directorDiscard(shelf.Request r, String id) async {
    final ok = await _facade.directorDiscard(id);
    return ok ? JsonResponse.ok({'status': 'ok'}) : _notFound();
  }

  Future<shelf.Response> _directorUndo(shelf.Request r, String id) async {
    final ok = await _facade.directorUndo(id);
    return JsonResponse.ok({'status': ok ? 'ok' : 'nothing-to-undo'});
  }

  Future<shelf.Response> _undoFix(shelf.Request r, String id) async {
    final body = await _json(r);
    final a = body['actIndex'];
    final s = body['sceneIndex'];
    final b = body['beatIndex'];
    if (a is! int || s is! int || b is! int) {
      return JsonResponse.badRequest(
        'actIndex, sceneIndex, beatIndex required',
      );
    }
    final ok = await _facade.undoFix(id, a, s, b);
    return ok ? JsonResponse.ok({'status': 'ok'}) : _notFound();
  }

  Future<shelf.Response> _addLore(shelf.Request r, String id) async {
    final body = await _json(r);
    final text = body['text']?.toString() ?? '';
    if (text.trim().isEmpty) return JsonResponse.badRequest('text is required');
    final added = await _facade.addLore(
      id,
      body['name']?.toString().trim().isNotEmpty == true
          ? body['name'].toString()
          : 'lore.txt',
      text,
    );
    return added == null ? _notFound() : JsonResponse.ok({'added': added});
  }

  Future<shelf.Response> _searchLore(shelf.Request r, String id) async {
    final body = await _json(r);
    final hits = await _facade.searchLore(
      id,
      body['query']?.toString() ?? '',
      act: body['actIndex'] is int ? body['actIndex'] as int : null,
      scene: body['sceneIndex'] is int ? body['sceneIndex'] as int : null,
    );
    return hits == null ? _notFound() : JsonResponse.ok({'hits': hits});
  }

  Future<shelf.Response> _portrait(shelf.Request r, String id) async {
    final file = await _facade.portraitFile(
      id,
      r.url.queryParameters['name'] ?? '',
    );
    if (file == null) return shelf.Response.notFound('No portrait');
    return shelf.Response.ok(
      await file.readAsBytes(),
      headers: {
        'content-type': 'image/png',
        'cache-control': 'public, max-age=3600',
      },
    );
  }

  Future<shelf.Response> _paintPortrait(shelf.Request r, String id) async {
    final body = await _json(r);
    final name = body['name']?.toString() ?? '';
    if (name.isEmpty) return JsonResponse.badRequest('name is required');
    try {
      final ok = await _facade.generatePortrait(id, name);
      return ok ? JsonResponse.ok({'status': 'ok'}) : _notFound();
    } on StateError catch (e) {
      return JsonResponse.badRequest(e.message);
    }
  }

  Future<shelf.Response> _log(shelf.Request r, String id) async =>
      JsonResponse.ok({'entries': await _facade.runLog(id)});

  Future<shelf.Response> _clearLog(shelf.Request r, String id) async {
    await _facade.clearRunLog(id);
    return JsonResponse.ok({'status': 'ok'});
  }

  shelf.Response _notFound() => JsonResponse.error(404, 'Story not found');

  Future<Map<String, dynamic>> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } catch (_) {
      return const {};
    }
  }
}
