// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'package:flutter/foundation.dart';
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
        queue.checkCanRun();
        unawaited(
          queue.run().catchError((Object e) {
            queue.reportError(e);
          }),
        );
        await Future<void>.delayed(Duration.zero);
        return JsonResponse.ok(queue.view());
      }),
    );
    router.post(
      '/api/image/batches/retry',
      (shelf.Request r) => _handle(() async {
        await queue.retryLoad();
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
        if (body['action'] is! String ||
            body['prompt'] != null && body['prompt'] is! String ||
            body.containsKey('newSeed') && body['newSeed'] is! bool) {
          throw const FormatException(
            'Provide a review action and valid prompt/seed options.',
          );
        }
        if (!queue.jobs.any((job) => job.id == id)) {
          return JsonResponse.error(404, 'This batch result is unavailable.');
        }
        await image.reviewBatch(id, body);
        return JsonResponse.ok(queue.view());
      }),
    );
    router.get(
      '/api/image/batches/<id>/picture',
      (shelf.Request r, String id) => _handle(() async {
        if (!queue.jobs.any(
          (job) => job.id == id && job.data['candidate'] is String,
        )) {
          return JsonResponse.error(404, 'This batch picture is unavailable.');
        }
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
    } on BodyTooLarge {
      return JsonResponse.error(413, 'The batch request is too large.');
    } on FormatException catch (error) {
      return JsonResponse.error(400, error.message);
    } on ArgumentError catch (error) {
      return JsonResponse.error(400, '${error.message}');
    } on StateError catch (error) {
      return JsonResponse.error(409, error.message);
    } catch (error) {
      debugPrint('[Image batches] request failed: $error');
      return JsonResponse.error(
        500,
        'The batch operation failed. Check the host application.',
      );
    }
  }
}
