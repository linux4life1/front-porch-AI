// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

class KoboldChatTemplateRoutes {
  KoboldChatTemplateRoutes(this.backend, Router router) {
    router.post('/api/backend/local-model/chat-template', save);
    router.post('/api/backend/local-model/chat-template/accept', accept);
  }

  final BackendFacade backend;

  Future<shelf.Response> save(shelf.Request request) async {
    try {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in request.read()) {
        // A 64 KiB template can grow sixfold as JSON (\u0001 escapes).
        if (bytes.length + chunk.length > 512 * 1024) {
          return JsonResponse.badRequest('Template upload is too large.');
        }
        bytes.add(chunk);
      }
      final body = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (body is! Map ||
          body['preset'] is! String ||
          (body['name'] != null && body['name'] is! String) ||
          (body['content'] != null && body['content'] is! String)) {
        return JsonResponse.badRequest(
          'preset, name and content must be text.',
        );
      }
      await backend.saveChatTemplate(
        preset: body['preset'] as String,
        name: body['name'] as String?,
        content: body['content'] as String?,
      );
      return JsonResponse.ok(await backend.localModel());
    } on FormatException catch (error) {
      return JsonResponse.badRequest(error.message);
    } on FileSystemException {
      return JsonResponse.error(
        500,
        'The template or preset could not be saved.',
      );
    }
  }

  Future<shelf.Response> accept(shelf.Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      if (body is! Map || body['preset'] is! String) {
        return JsonResponse.badRequest('preset must be text.');
      }
      await backend.acceptChatTemplate(body['preset'] as String);
      return JsonResponse.ok(await backend.localModel());
    } on FormatException catch (error) {
      return JsonResponse.badRequest(error.message);
    } on FileSystemException {
      return JsonResponse.error(500, 'The choice could not be saved.');
    }
  }
}
