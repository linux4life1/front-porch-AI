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

import 'package:front_porch_ai/services/web/facade/chargen_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// AI character creator endpoints. Generation runs in the background and reports
/// progress over the WebSocket hub (chargen_status / chargen_done /
/// chargen_error); these endpoints only start it and report availability.
class WebChargenRoutes {
  WebChargenRoutes(this._facade, Router router) {
    router.get('/api/chargen/status', _status);
    router.post('/api/chargen/create', _create);
  }

  final ChargenFacade _facade;

  shelf.Response _status(shelf.Request r) =>
      JsonResponse.ok({'available': _facade.available});

  Future<shelf.Response> _create(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      body = const {};
    }
    final result = _facade.startCreate(body);
    if (result['ok'] != true) {
      return JsonResponse.error(400, result['error']?.toString() ?? 'Bad request');
    }
    return JsonResponse.ok({'status': 'started'});
  }
}
