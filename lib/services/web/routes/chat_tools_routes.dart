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

import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// Chat sidebar *tools* endpoints (memory/summary/chaos/NSFW/scene-time/
/// objectives) — read state plus the mutations the desktop sidebar offers.
class WebChatToolsRoutes {
  WebChatToolsRoutes(this._facade, Router router) {
    router.get('/api/chat/tools', _state);
    router.post('/api/chat/tools/settings', _settings);
    router.post('/api/chat/tools/toggle', _toggle);
    router.post('/api/chat/tools/time', _time);
    router.post('/api/chat/tools/summary', _summary);
    router.post('/api/chat/tools/objective', _objective);
    router.post('/api/chat/tools/task', _task);
    router.get('/api/chat/tools/evolution', _evolutionGet);
    router.post('/api/chat/tools/evolution', _evolutionPost);
  }

  final ChatToolsFacade _facade;

  shelf.Response _state(shelf.Request request) =>
      JsonResponse.ok(_snapshot(request));

  /// Tools snapshot scoped to the focused cast participant (`?participant=<id>`).
  Map<String, dynamic> _snapshot(shelf.Request request) =>
      _facade.state(participantId: request.url.queryParameters['participant']);

  /// Apply global memory/summary settings (only keys present are changed).
  Future<shelf.Response> _settings(shelf.Request request) async {
    await _facade.applySettings(await _json(request));
    return JsonResponse.ok(_snapshot(request));
  }

  /// Flip one chat-scoped boolean toggle: realism / needs / oneShotEval /
  /// chaos / chaosNsfw / nsfwCooldown / passageOfTime / summaryPaused / director.
  Future<shelf.Response> _toggle(shelf.Request request) async {
    final body = await _json(request);
    final name = body['name']?.toString();
    final value = body['value'];
    if (name == null || value is! bool) {
      return JsonResponse.badRequest('name and bool value are required');
    }
    switch (name) {
      case 'realism':
        await _facade.setRealismEnabled(value);
      case 'needs':
        await _facade.setNeedsEnabled(value);
      case 'oneShotEval':
        await _facade.setOneShotEval(value);
      case 'chaos':
        await _facade.setChaosEnabled(value);
      case 'chaosNsfw':
        await _facade.setChaosNsfw(value);
      case 'nsfwCooldown':
        await _facade.setNsfwCooldown(value);
      case 'passageOfTime':
        await _facade.setPassageOfTime(value);
      case 'summaryPaused':
        _facade.setSummaryPaused(value);
      case 'director':
        _facade.setDirectorMode(value);
      default:
        return JsonResponse.badRequest('Unknown toggle: $name');
    }
    return JsonResponse.ok(_snapshot(request));
  }

  /// Nudge the scene clock by `delta` periods (+1 / -1).
  Future<shelf.Response> _time(shelf.Request request) async {
    final body = await _json(request);
    final delta = body['delta'];
    if (delta is! int) {
      return JsonResponse.badRequest('delta (int) is required');
    }
    await _facade.nudgeTime(delta);
    return JsonResponse.ok(_snapshot(request));
  }

  /// Summary actions: regenerate, or set the summary text directly.
  Future<shelf.Response> _summary(shelf.Request request) async {
    final body = await _json(request);
    final action = body['action']?.toString();
    if (action == 'regenerate') {
      await _facade.regenerateSummary();
    } else if (body.containsKey('text')) {
      _facade.setSummaryText(body['text']?.toString() ?? '');
    } else {
      return JsonResponse.badRequest('action=regenerate or text is required');
    }
    return JsonResponse.ok(_snapshot(request));
  }

  /// Objective lifecycle: set a new goal, generate tasks, check completion, or
  /// clear it. `action` selects the operation.
  Future<shelf.Response> _objective(shelf.Request request) async {
    final body = await _json(request);
    final action = body['action']?.toString();
    switch (action) {
      case 'set':
        final goal = body['goal']?.toString();
        if (goal == null || goal.trim().isEmpty) {
          return JsonResponse.badRequest('goal is required');
        }
        await _facade.setObjective(
          goal,
          isPrimary: body['isPrimary'] != false,
          participantId:
              body['participant']?.toString() ??
              request.url.queryParameters['participant'],
        );
      case 'generate':
        final id = body['id']?.toString();
        if (id == null) return JsonResponse.badRequest('id is required');
        final ok = await _facade.generateTasks(
          id,
          taskCount: body['taskCount'] is int ? body['taskCount'] as int : 5,
          nsfw: body['nsfw'] == true,
        );
        if (!ok) return JsonResponse.error(404, 'Objective not found');
      case 'frequency':
        final id = body['id']?.toString();
        final freq = body['frequency'];
        if (id == null || freq is! int) {
          return JsonResponse.badRequest('id and frequency are required');
        }
        if (!await _facade.setCheckFrequency(id, freq)) {
          return JsonResponse.error(404, 'Objective not found');
        }
      case 'check':
        _facade.checkCompletion();
      case 'clear':
        final id = body['id']?.toString();
        if (id == null) return JsonResponse.badRequest('id is required');
        if (!await _facade.clearObjective(id)) {
          return JsonResponse.error(404, 'Objective not found');
        }
      default:
        return JsonResponse.badRequest('Unknown objective action: $action');
    }
    return JsonResponse.ok(_snapshot(request));
  }

  /// Task operations on an objective: add / toggle / update / remove.
  Future<shelf.Response> _task(shelf.Request request) async {
    final body = await _json(request);
    final action = body['action']?.toString();
    final id = body['id']?.toString();
    if (id == null) return JsonResponse.badRequest('id is required');
    bool ok;
    switch (action) {
      case 'add':
        final desc = body['description']?.toString();
        if (desc == null || desc.trim().isEmpty) {
          return JsonResponse.badRequest('description is required');
        }
        ok = await _facade.addTask(id, desc);
      case 'toggle':
        final i = body['taskIndex'];
        if (i is! int) return JsonResponse.badRequest('taskIndex is required');
        ok = await _facade.toggleTask(id, i);
      case 'update':
        final i = body['taskIndex'];
        final desc = body['description']?.toString();
        if (i is! int || desc == null) {
          return JsonResponse.badRequest('taskIndex and description required');
        }
        ok = await _facade.updateTask(id, i, desc);
      case 'remove':
        final i = body['taskIndex'];
        if (i is! int) return JsonResponse.badRequest('taskIndex is required');
        ok = await _facade.removeTask(id, i);
      default:
        return JsonResponse.badRequest('Unknown task action: $action');
    }
    if (!ok) return JsonResponse.error(404, 'Objective not found');
    return JsonResponse.ok(_snapshot(request));
  }

  /// Character-evolution review for the focused participant (`?participant=`).
  /// Returns original + evolved personality/scenario + count (group-aware).
  shelf.Response _evolutionGet(shelf.Request request) => JsonResponse.ok(
    _facade.evolution(request.url.queryParameters['participant']),
  );

  /// Evolution mutation: `action: 'save'` (carries personality/scenario) or
  /// `action: 'reset'`. Scoped to the focused participant. Returns the fresh
  /// evolution block so the modal can reflect the new state.
  Future<shelf.Response> _evolutionPost(shelf.Request request) async {
    final body = await _json(request);
    final action = body['action']?.toString();
    final participant =
        body['participant']?.toString() ??
        request.url.queryParameters['participant'];
    switch (action) {
      case 'save':
        await _facade.saveEvolution(
          participant,
          body['personality']?.toString() ?? '',
          body['scenario']?.toString() ?? '',
        );
      case 'reset':
        await _facade.resetEvolution(participant);
      default:
        return JsonResponse.badRequest('Unknown evolution action: $action');
    }
    return JsonResponse.ok(_facade.evolution(participant));
  }

  Future<Map<String, dynamic>> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } catch (_) {
      return const {};
    }
  }
}
