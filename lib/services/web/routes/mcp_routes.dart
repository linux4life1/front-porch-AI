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

import 'package:front_porch_ai/services/web/facade/mcp_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// MCP server list + connect/refresh for the web Settings page.
class WebMcpRoutes {
  WebMcpRoutes(WebServerDeps deps, Router router)
    : _mcp = McpFacade(deps.storage, deps.settingsFacade?.boundChat) {
    router.get('/api/mcp/servers', _get);
    router.get('/api/mcp/servers/find-local', _findLocal);
    router.post('/api/mcp/servers', _add);
    router.post('/api/mcp/servers/default', _default);
    router.post('/api/mcp/servers/check-draft', _checkDraft);
    router.post('/api/mcp/servers/<id>', _update);
    router.post('/api/mcp/servers/<id>/delete', _delete);
    router.post('/api/mcp/servers/<id>/refresh', _refresh);
    router.post('/api/mcp/servers/<id>/check', _check);
  }

  final McpFacade _mcp;

  shelf.Response _get(shelf.Request request) =>
      JsonResponse.ok(_mcp.settingsState());

  Future<shelf.Response> _findLocal(shelf.Request request) async =>
      JsonResponse.ok(await _mcp.findLocal());

  Future<shelf.Response> _add(shelf.Request request) async {
    final body = await _json(request);
    if (body == null) return JsonResponse.badRequest('Invalid JSON body');
    final url = body['url']?.toString().trim() ?? '';
    if (url.isEmpty) return JsonResponse.badRequest('url is required');
    return JsonResponse.ok(await _mcp.addServer(body));
  }

  Future<shelf.Response> _default(shelf.Request request) async {
    final body = await _json(request);
    if (body == null || body['mcpDefault'] is! bool) {
      return JsonResponse.badRequest('mcpDefault bool required');
    }
    await _mcp.setMcpDefault(body['mcpDefault'] as bool);
    return JsonResponse.ok(_mcp.settingsState());
  }

  Future<shelf.Response> _update(shelf.Request request, String id) async {
    final body = await _json(request);
    if (body == null) return JsonResponse.badRequest('Invalid JSON body');
    return JsonResponse.ok(await _mcp.updateServer(id, body));
  }

  Future<shelf.Response> _delete(shelf.Request request, String id) async =>
      JsonResponse.ok(await _mcp.removeServer(id));

  Future<shelf.Response> _refresh(shelf.Request request, String id) async =>
      JsonResponse.ok(await _mcp.refreshServer(id));

  Future<shelf.Response> _check(shelf.Request request, String id) async =>
      JsonResponse.ok(await _mcp.checkServer(id));

  Future<shelf.Response> _checkDraft(shelf.Request request) async {
    final body = await _json(request);
    if (body == null) return JsonResponse.badRequest('Invalid JSON body');
    return JsonResponse.ok(await _mcp.checkDraft(body));
  }

  Future<Map<String, dynamic>?> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } catch (_) {
      return null;
    }
  }
}
