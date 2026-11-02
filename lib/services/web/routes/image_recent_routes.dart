// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Image Studio's Recent shelf for the phone: list it, star, delete, clear
/// and set how many it keeps. The pictures themselves are served by
/// `GET /api/image/saved/<name>`.
class ImageRecentRoutes {
  ImageRecentRoutes(Router router, {required this.image}) {
    router.get('/api/image/recent', _list);
    router.post('/api/image/recent/keep', _keep);
    router.post('/api/image/recent/delete', _delete);
    router.post('/api/image/recent/clear', _clear);
    router.post('/api/image/recent/limit', _limit);
  }

  final ImageFacade image;

  Future<shelf.Response> _list(shelf.Request request) async =>
      JsonResponse.ok(await image.recent.view());

  Future<shelf.Response> _keep(shelf.Request request) async {
    final body = await _json(request);
    final name = body['name'];
    final kept = body['kept'];
    if (name is! String || kept is! bool) {
      return JsonResponse.error(400, 'Name a picture and whether to keep it.');
    }
    final entry = await image.recent.setKept(name, kept);
    if (entry == null) return JsonResponse.error(404, 'That picture is gone.');
    return JsonResponse.ok({'entry': entry});
  }

  Future<shelf.Response> _delete(shelf.Request request) async {
    final name = (await _json(request))['name'];
    if (name is! String || !await image.recent.delete(name)) {
      return JsonResponse.error(404, 'That picture is gone.');
    }
    return JsonResponse.ok({'deleted': name});
  }

  Future<shelf.Response> _clear(shelf.Request request) async =>
      JsonResponse.ok({'cleared': await image.recent.clearUnkept()});

  Future<shelf.Response> _limit(shelf.Request request) async {
    final limit = (await _json(request))['limit'];
    if (limit is! int || !await image.recent.setLimit(limit)) {
      return JsonResponse.error(400, 'Pick one of the keep choices.');
    }
    return JsonResponse.ok(await image.recent.view());
  }

  Future<Map<String, dynamic>> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } on FormatException {
      return const {};
    } on BodyTooLarge {
      return const {};
    }
  }
}
