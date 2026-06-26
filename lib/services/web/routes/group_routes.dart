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

import 'package:front_porch_ai/services/web/facade/group_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';

/// Group-chat endpoints: list / member avatar / delete. Groups are *created* and
/// *edited* in-chat now via the unified cast flow (`/join --full`, `/promote`),
/// not an upfront wizard — so there are no create/edit endpoints here. Opening a
/// group is handled by the chat routes (`/api/chat/select-group`).
class WebGroupRoutes {
  WebGroupRoutes(this._facade, Router router) {
    router.get('/api/groups', _list);
    router.get('/api/groups/<id>/members/<memberId>/avatar', _avatar);
    router.post('/api/groups/<id>/delete', _delete);
  }

  final GroupFacade _facade;

  Future<shelf.Response> _list(shelf.Request request) async =>
      JsonResponse.ok({'groups': await _facade.list()});

  Future<shelf.Response> _delete(shelf.Request request, String id) async {
    final ok = await _facade.delete(id);
    if (!ok) return JsonResponse.error(404, 'Group not found');
    return JsonResponse.ok({'status': 'deleted'});
  }

  Future<shelf.Response> _avatar(
    shelf.Request request,
    String id,
    String memberId,
  ) async {
    final file = await _facade.memberAvatarFile(id, memberId);
    if (file == null) return shelf.Response.notFound('No avatar');
    return shelf.Response.ok(
      file.readAsBytesSync(),
      headers: {
        'Content-Type': 'image/png',
        'Cache-Control': 'public, max-age=3600',
      },
    );
  }
}
