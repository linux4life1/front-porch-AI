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
import 'package:front_porch_ai/services/web/util/util.dart';

/// The buttons on the chat's processing overlays: stop the reply during the
/// Realism read, dismiss the notice that follows, skip the goal check; plus
/// the transient UNDO after an exit, and Director Mode's auto-chat and
/// standing directions (scene goal, whispers).
class WebChatOverlayRoutes {
  WebChatOverlayRoutes(this._facade, Router router) {
    router.post('/api/chat/cancel-realism', _cancelRealism);
    router.post('/api/chat/stopped-reply/dismiss', _dismissStoppedReply);
    router.post('/api/chat/skip-objective-check', _skipObjectiveCheck);
    router.post('/api/chat/exit-undo', _undoExit);
    router.post('/api/chat/director/autoplay', _autoPlay);
    router.post('/api/chat/director/delay', _delay);
    router.post('/api/chat/director/budget', _budget);
    router.post('/api/chat/director/goal', _goal);
    router.post('/api/chat/director/whisper', _whisper);
  }

  final ChatFacade _facade;

  shelf.Response _cancelRealism(shelf.Request request) {
    _facade.cancelRealismEval();
    return JsonResponse.ok({'status': 'ok'});
  }

  shelf.Response _dismissStoppedReply(shelf.Request request) {
    _facade.dismissStoppedReplyNotice();
    return JsonResponse.ok({'status': 'ok'});
  }

  shelf.Response _skipObjectiveCheck(shelf.Request request) {
    _facade.skipObjectiveCheck();
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _undoExit(shelf.Request request) async {
    await _facade.undoLastExit();
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _autoPlay(shelf.Request request) async {
    final body = await RequestBody.readJsonMap(request);
    _facade.setAutoPlay(body['on'] == true);
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _delay(shelf.Request request) async {
    final body = await RequestBody.readJsonMap(request);
    final seconds = body['seconds'];
    if (seconds is! num) return JsonResponse.badRequest('seconds is required');
    await _facade.setDirectorDelay(seconds.toDouble());
    return JsonResponse.ok({'status': 'ok'});
  }

  Future<shelf.Response> _budget(shelf.Request request) async {
    final body = await RequestBody.readJsonMap(request);
    final turns = body['turns'];
    if (turns is! num) return JsonResponse.badRequest('turns is required');
    await _facade.setDirectorTurnBudget(turns.toInt());
    return JsonResponse.ok({'status': 'ok'});
  }

  /// `{text}` pins the scene goal; an empty text clears it.
  Future<shelf.Response> _goal(shelf.Request request) async {
    final body = await RequestBody.readJsonMap(request);
    final text = body['text'];
    if (text is! String) return JsonResponse.badRequest('text is required');
    await _facade.setDirectorGoal(text);
    return JsonResponse.ok({'status': 'ok'});
  }

  /// `{id, text}` sets a member's whisper; an empty text clears it.
  Future<shelf.Response> _whisper(shelf.Request request) async {
    final body = await RequestBody.readJsonMap(request);
    final id = body['id'];
    final text = body['text'];
    if (id is! String || id.isEmpty || text is! String) {
      return JsonResponse.badRequest('id and text are required');
    }
    await _facade.setDirectorWhisper(id, text);
    return JsonResponse.ok({'status': 'ok'});
  }
}
