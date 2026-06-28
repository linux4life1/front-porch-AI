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
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// Group-chat endpoints: list / member avatar / delete. Groups are *created* and
/// *edited* in-chat now via the unified cast flow (`/join --full`, `/promote`),
/// not an upfront wizard — so there are no create/edit endpoints here. Opening a
/// group is handled by the chat routes (`/api/chat/select-group`).
class WebGroupRoutes {
  WebGroupRoutes(this._facade, Router router) {
    router.get('/api/groups', _list);
    router.post('/api/groups', _create);
    router.get('/api/groups/<id>/members/<memberId>/avatar', _avatar);
    router.get('/api/groups/<id>/export.png', _export);
    router.post('/api/groups/<id>/extract', _extract);
    router.post('/api/groups/<id>/delete', _delete);
    router.post('/api/groups/<id>/settings', _settings);
  }

  final GroupFacade _facade;

  Future<shelf.Response> _list(shelf.Request request) async =>
      JsonResponse.ok({'groups': await _facade.list()});

  /// Create a group. Body: {name, memberIds:[dbId,…] (>=2), turnOrder?}.
  Future<shelf.Response> _create(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON');
    }
    final result = await _facade.createGroup(body);
    if (result == null) {
      return JsonResponse.badRequest('A group needs a name and at least 2 members');
    }
    return JsonResponse.ok(result);
  }

  Future<shelf.Response> _delete(shelf.Request request, String id) async {
    final ok = await _facade.delete(id);
    if (!ok) return JsonResponse.error(404, 'Group not found');
    return JsonResponse.ok({'status': 'deleted'});
  }

  /// Update a group's settings (name / prompts / scenario / turn order /
  /// per-member overrides) — settings-only, not membership.
  Future<shelf.Response> _settings(shelf.Request request, String id) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final ok = await _facade.updateSettings(id, body);
    if (!ok) return JsonResponse.error(404, 'Group not found');
    return JsonResponse.ok({'status': 'ok'});
  }

  /// Export a group as a self-contained Group Card PNG download.
  Future<shelf.Response> _export(shelf.Request request, String id) async {
    final result = await _facade.exportGroupCardBytes(id);
    if (result == null) return shelf.Response.notFound('Group not found');
    final stem = (result['name'] as String).replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final name = stem.isEmpty ? 'group' : stem;
    return shelf.Response.ok(
      result['bytes'] as List<int>,
      headers: {
        'Content-Type': 'image/png',
        'Content-Disposition': 'attachment; filename="$name.group.png"',
        'Cache-Control': 'no-store',
      },
    );
  }

  /// Extract a group's members into the library as independent characters.
  Future<shelf.Response> _extract(shelf.Request request, String id) async {
    final extracted = await _facade.extractMembers(id);
    if (extracted == null) return JsonResponse.error(404, 'Group not found');
    return JsonResponse.ok({'extracted': extracted});
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
