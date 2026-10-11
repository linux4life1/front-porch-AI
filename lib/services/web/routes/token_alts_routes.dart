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

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// "Other words" on a reply (KoboldCpp only): the words the model weighed,
/// and a pick that rewrites the last reply from one of them.
class WebTokenAltsRoutes {
  WebTokenAltsRoutes(this._facade, Router router) {
    router.get('/api/chat/token-alts', _list);
    router.post('/api/chat/token-alts/pick', _pick);
  }

  final ChatFacade _facade;

  shelf.Response _list(shelf.Request request) {
    final index = int.tryParse(request.url.queryParameters['index'] ?? '');
    if (index == null) return JsonResponse.badRequest('index is required');
    return JsonResponse.ok(_facade.tokenAlternatives(index));
  }

  Future<shelf.Response> _pick(shelf.Request request) async {
    final Object? body;
    try {
      body = jsonDecode(await request.readAsString());
    } on FormatException {
      return JsonResponse.badRequest('Expected JSON');
    }
    if (body is! Map) return JsonResponse.badRequest('Expected an object');
    final index = body['index'];
    final place = body['place'];
    final word = body['word'];
    if (index is! int || place is! int || word is! String) {
      return JsonResponse.badRequest('index, place and word are required');
    }
    final refusal = _facade.pickTokenAlternative(index, place, word);
    if (refusal != null) return JsonResponse.error(409, refusal);
    return JsonResponse.ok({'status': 'ok'});
  }
}
