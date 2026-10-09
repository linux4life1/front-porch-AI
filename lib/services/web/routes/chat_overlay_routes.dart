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
/// Realism read, dismiss the notice that follows, skip the goal check.
class WebChatOverlayRoutes {
  WebChatOverlayRoutes(this._facade, Router router) {
    router.post('/api/chat/cancel-realism', _cancelRealism);
    router.post('/api/chat/stopped-reply/dismiss', _dismissStoppedReply);
    router.post('/api/chat/skip-objective-check', _skipObjectiveCheck);
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
}
