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

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// The Memory section's Sources picker and Data Bank (`?participant=<id>`
/// scopes them to the focused cast member). Additive routes: nothing an older
/// PWA calls changes.
class WebMemoryBankRoutes {
  WebMemoryBankRoutes(this._facade, Router router) {
    router.get('/api/chat/tools/memory/sources', _sources);
    router.post('/api/chat/tools/memory/sources', _setSource);
    router.get('/api/chat/tools/memory/databank', _bank);
    router.post('/api/chat/tools/memory/databank', _bankAction);
  }

  final ChatToolsFacade _facade;

  String? _who(shelf.Request r) => r.url.queryParameters['participant'];

  Future<shelf.Response> _sources(shelf.Request r) async =>
      JsonResponse.ok(await _facade.memoryBank.sources(_who(r)));

  Future<shelf.Response> _setSource(shelf.Request r) async {
    final body = await _json(r);
    final id = body['id']?.toString();
    final selected = body['selected'];
    if (id == null || id.isEmpty || selected is! bool) {
      return JsonResponse.badRequest('id and selected are required');
    }
    final out = await _facade.memoryBank.setSource(_who(r), id, selected);
    if (out == null) {
      return JsonResponse.error(409, 'This character has no library entry');
    }
    return JsonResponse.ok(out);
  }

  Future<shelf.Response> _bank(shelf.Request r) async =>
      JsonResponse.ok(await _facade.memoryBank.dataBank(_who(r)));

  Future<shelf.Response> _bankAction(shelf.Request r) async {
    final out = await _facade.memoryBank.dataBankAction(
      _who(r),
      await _json(r),
    );
    if (out == null) {
      return JsonResponse.badRequest('Not a valid Data Bank edit');
    }
    return JsonResponse.ok(out);
  }

  Future<Map<String, dynamic>> _json(shelf.Request r) async {
    final raw = await r.readAsString();
    if (raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  }
}
