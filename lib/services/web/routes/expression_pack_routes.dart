// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// The phone's expression packs: start one for a character, watch it,
/// cancel it, and import what it made. One pack at a time, the same one the
/// desktop dialog shows.
class ExpressionPackRoutes {
  ExpressionPackRoutes(Router router, {required this.image}) {
    router.get('/api/image/expression-pack', _status);
    router.get('/api/image/expression-pack/source', _source);
    router.post('/api/image/expression-pack/write-prompt', _writePrompt);
    router.post('/api/image/expression-pack/discard', _discard);
    router.get(
      '/api/image/expression-pack/settings',
      (_) => JsonResponse.ok(image.packPromptDefaults()),
    );
    router.post(
      '/api/image/expression-pack/settings',
      (shelf.Request r) => _rules(r, save: true),
    );
    router.post(
      '/api/image/expression-pack/preview',
      (shelf.Request r) => _rules(r, preview: true),
    );
    router.post(
      '/api/image/expression-pack/rules',
      (shelf.Request r) => _rules(r),
    );
    router.post('/api/image/expression-pack', _start);
    router.post('/api/image/expression-pack/cancel', _cancel);
    router.post(
      '/api/image/expression-pack/resume',
      (shelf.Request r) => _continue(r),
    );
    router.post(
      '/api/image/expression-pack/reroll',
      (shelf.Request r) => _continue(r, reroll: true),
    );
    router.post('/api/image/expression-pack/import', _import);
    router.get('/api/image/expression-pack/picture', _picture);
  }

  final ImageFacade image;

  Future<shelf.Response> _writePrompt(shelf.Request request) async {
    final (body, failed) = await _body(request);
    if (body == null) return failed!;
    final instruction = '${body['instruction'] ?? ''}'.trim();
    if (instruction.length > 12000) {
      return _refused(
        const DeskRefused('too_large', 'That is too long to work from.', 413),
      );
    }
    try {
      return JsonResponse.ok({
        'prompt': await image.craftPackPrompt(
          '${body['characterId'] ?? ''}',
          instruction: instruction.isEmpty ? null : instruction,
        ),
      });
    } on DeskRefused catch (e) {
      return _refused(e);
    }
  }

  Future<shelf.Response> _source(shelf.Request request) async {
    try {
      return JsonResponse.ok(
        await image.packPortrait(
          request.url.queryParameters['characterId'] ?? '',
        ),
      );
    } on DeskRefused catch (e) {
      return _refused(e);
    }
  }

  shelf.Response _discard(shelf.Request request) {
    try {
      image.discardPack();
      return JsonResponse.ok({'discarded': true});
    } on DeskRefused catch (e) {
      return _refused(e);
    }
  }

  static shelf.Response _refused(DeskRefused e) =>
      JsonResponse.error(e.status, e.message, extra: {'code': e.code});

  Future<(Map<String, dynamic>?, shelf.Response?)> _body(
    shelf.Request request,
  ) async {
    try {
      return (
        await RequestBody.readJsonMap(
          request,
          maxBytes: RequestBody.uploadMaxBytes,
        ),
        null,
      );
    } on BodyTooLarge {
      return (
        null,
        _refused(const DeskRefused('too_large', 'Too large.', 413)),
      );
    } on FormatException {
      return (
        null,
        _refused(
          const DeskRefused('bad_request', 'That request was not JSON.'),
        ),
      );
    }
  }

  Future<shelf.Response> _rules(
    shelf.Request request, {
    bool save = false,
    bool preview = false,
  }) async {
    final (body, failed) = await _body(request);
    if (body == null) return failed!;
    try {
      return JsonResponse.ok(
        save
            ? await image.savePackPromptDefaults(body)
            : preview
            ? image.previewPackPrompts(body)
            : image.updatePackPromptRules(body),
      );
    } on DeskRefused catch (e) {
      return _refused(e);
    }
  }

  shelf.Response _status(shelf.Request request) {
    final view = image.packView();
    return view == null
        ? _refused(const DeskRefused('no_pack', 'No expression pack.', 404))
        : JsonResponse.ok(view);
  }

  Future<shelf.Response> _start(shelf.Request request) async {
    final (body, failed) = await _body(request);
    if (body == null) return failed!;
    try {
      return JsonResponse.ok(await image.startPack(body));
    } on DeskRefused catch (e) {
      return _refused(e);
    }
  }

  shelf.Response _cancel(shelf.Request request) {
    try {
      return JsonResponse.ok(image.cancelPack());
    } on DeskRefused catch (e) {
      return _refused(e);
    }
  }

  Future<shelf.Response> _continue(
    shelf.Request request, {
    bool reroll = false,
  }) async {
    final (body, failed) = await _body(request);
    if (body == null) return failed!;
    try {
      return JsonResponse.ok(await image.continuePack(body, reroll: reroll));
    } on DeskRefused catch (e) {
      return _refused(e);
    }
  }

  Future<shelf.Response> _import(shelf.Request request) async {
    final (body, failed) = await _body(request);
    if (body == null) return failed!;
    try {
      return JsonResponse.ok(await image.importPack(body));
    } on DeskRefused catch (e) {
      return _refused(e);
    }
  }

  shelf.Response _picture(shelf.Request request) {
    final bytes = image.packPicture(request.url.queryParameters['emotion']);
    if (bytes == null) {
      return _refused(const DeskRefused('no_picture', 'No such picture.', 404));
    }
    return shelf.Response.ok(
      bytes,
      headers: {'Content-Type': 'image/png', 'Cache-Control': 'no-store'},
    );
  }
}
