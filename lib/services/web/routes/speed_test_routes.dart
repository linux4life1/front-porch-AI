// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// The phone's twin of the Local model card's speed test: the question it
/// asks first, start, and Cancel. Its progress reaches the phone over the
/// stream hub (`speed_test`), and the card's state with the local model
/// (`speedTest` on `/api/backend/local-model`).
class WebSpeedTestRoutes {
  WebSpeedTestRoutes(this._backend, Router router) {
    router.get('/api/backend/local-model/speed-test', _ask);
    router.post('/api/backend/local-model/speed-test', _start);
    router.post('/api/backend/local-model/speed-test/cancel', _cancel);
  }

  final BackendFacade _backend;

  /// `{ask}`: the question, with how long it takes; or `{refused}`: why it
  /// cannot run now.
  Future<shelf.Response> _ask(shelf.Request r) async =>
      JsonResponse.ok(await _backend.speedTestAsk());

  /// Starts it: `{started: true}`, or `{started: false, refused}` in words.
  Future<shelf.Response> _start(shelf.Request r) async {
    final refused = await _backend.startSpeedTest();
    return JsonResponse.ok({'started': refused == null, 'refused': refused});
  }

  shelf.Response _cancel(shelf.Request r) {
    _backend.cancelSpeedTest();
    return JsonResponse.ok({'ok': true});
  }
}
