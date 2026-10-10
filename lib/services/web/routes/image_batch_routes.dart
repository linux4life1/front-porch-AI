// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

class ImageBatchRoutes {
  ImageBatchRoutes(Router router, {required this.image}) {
    router.get(
      '/api/image/batches',
      (shelf.Request r) => _handle(() async {
        await queue.ready;
        return JsonResponse.ok(queue.view());
      }),
    );
    router.post(
      '/api/image/batches/preview',
      (shelf.Request r) => _handle(() async {
        return JsonResponse.ok(
          await image.previewBatchPrompts(await RequestBody.readJsonMap(r)),
        );
      }),
    );
    router.post(
      '/api/image/batches/prepare',
      (shelf.Request r) => _handle(() async {
        await image.prepareBatch(await RequestBody.readJsonMap(r));
        return JsonResponse.ok(queue.view());
      }),
    );
    router.post(
      '/api/image/batches/start',
      (shelf.Request r) => _handle(() async {
        await queue.ready;
        if (queue.running || queue.working) throw StateError('Queue is busy.');
        unawaited(
          queue.run().catchError((Object e) {
            queue.reportError(e);
          }),
        );
        await Future<void>.delayed(Duration.zero);
        return JsonResponse.ok(queue.view());
      }),
    );
    router.post('/api/image/batches/pause', (shelf.Request r) {
      queue.pause();
      return JsonResponse.ok(queue.view());
    });
    router.post(
      '/api/image/batches/save',
      (shelf.Request r) => _handle(() async {
        await image.saveBatch();
        return JsonResponse.ok(queue.view());
      }),
    );
    router.post(
      '/api/image/batches/<id>/review',
      (shelf.Request r, String id) => _handle(() async {
        final body = await RequestBody.readJsonMap(r);
        await queue.decide(
          id,
          body['action'] as String,
          prompt: body['prompt'] as String?,
          newSeed: body['newSeed'] != false,
        );
        return JsonResponse.ok(queue.view());
      }),
    );
    router.get(
      '/api/image/batches/<id>/picture',
      (shelf.Request r, String id) => _handle(() async {
        return shelf.Response.ok(
          await queue.picture(id),
          headers: {'content-type': 'image/png', 'cache-control': 'no-store'},
        );
      }),
    );
  }
  final ImageFacade image;
  ImageBatchService get queue => image.batches;
  Future<shelf.Response> _handle(
    Future<shelf.Response> Function() action,
  ) async {
    try {
      return await action();
    } catch (e) {
      return JsonResponse.error(409, '$e');
    }
  }
}
