// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/world_from_wiki_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

class WebWorldFromWikiRoutes {
  WebWorldFromWikiRoutes(this._facade, Router router) {
    router.get('/api/worlds/from-wiki/status', _status);
    router.post('/api/worlds/from-wiki/scout', _scout);
    router.post('/api/worlds/from-wiki/write', _write);
    router.post('/api/worlds/from-wiki/abort', _abort);
  }

  final WorldFromWikiFacade _facade;

  Future<shelf.Response> _status(shelf.Request r) async =>
      JsonResponse.ok(await _facade.status());

  Future<shelf.Response> _scout(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final result = await _facade.scout(body);
    if (result['ok'] != true) {
      return JsonResponse.error(
        400,
        result['error']?.toString() ?? 'Bad request',
      );
    }
    return JsonResponse.ok(result);
  }

  Future<shelf.Response> _write(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final result = _facade.startWrite(body);
    if (result['ok'] != true) {
      return JsonResponse.error(
        400,
        result['error']?.toString() ?? 'Bad request',
      );
    }
    return JsonResponse.ok({'status': 'started'});
  }

  shelf.Response _abort(shelf.Request r) {
    _facade.abort();
    return JsonResponse.ok({'status': 'aborted'});
  }
}
