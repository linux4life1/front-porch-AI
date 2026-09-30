// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// The phone Image Studio's actions on the desk: choosing a model, graph or
/// encoder by the desktop's own rules, storing a graph file, and writing a
/// prompt. The phone sends what the person chose; the rules stay here.
class ImageDeskRoutes {
  ImageDeskRoutes(Router router, {required this.deps, required this.image}) {
    router.post('/api/image/studio/pick', _pick);
    router.post('/api/image/studio/graph', _graph);
    router.post('/api/image/studio/write-prompt', _writePrompt);
  }

  final WebServerDeps deps;
  final ImageFacade image;

  /// Longest instruction "Write it for me" is given.
  static const int maxInstruction = 2000;

  static shelf.Response refused(DeskRefused e) =>
      JsonResponse.error(e.status, e.message, extra: {'code': e.code});

  /// The JSON body, or the response that says why there is none.
  Future<(Map<String, dynamic>?, shelf.Response?)> _body(
    shelf.Request request,
  ) async {
    try {
      final body = await RequestBody.readJsonMap(
        request,
        maxBytes: RequestBody.uploadMaxBytes,
      );
      return (body, null);
    } on BodyTooLarge {
      return (null, refused(const DeskRefused('too_large', 'Too large.', 413)));
    } on FormatException {
      return (
        null,
        refused(const DeskRefused('bad_request', 'That request was not JSON.')),
      );
    }
  }

  Future<shelf.Response> _pick(shelf.Request request) async {
    final (body, failed) = await _body(request);
    if (body == null) return failed!;
    final edit = body['mode'] == 'edit';
    try {
      switch (body['kind']) {
        case 'model':
          await image.pickModel(edit: edit, file: '${body['file'] ?? ''}');
        case 'graph':
          await image.pickGraph(edit: edit, id: '${body['id'] ?? ''}');
        case 'support':
          await image.pickSupport(
            edit: edit,
            token: '${body['token'] ?? ''}',
            file: '${body['file'] ?? ''}',
          );
        default:
          return refused(
            const DeskRefused(
              'bad_request',
              'Pick a model, a graph or a slot.',
            ),
          );
      }
    } on DeskRefused catch (e) {
      return refused(e);
    }
    return JsonResponse.ok(image.config());
  }

  /// Storing a graph file changes what ComfyUI runs on this computer, so it
  /// needs the web login password (and the 2FA code, when there is one).
  Future<shelf.Response> _graph(shelf.Request request) async {
    final (body, failed) = await _body(request);
    if (body == null) return failed!;
    final denied = await denyUnlessSteppedUp(
      auth: deps.auth,
      body: body,
      request: request,
    );
    if (denied != null) return denied;
    final List<int> bytes;
    try {
      bytes = base64Decode('${body['data'] ?? ''}');
    } on FormatException {
      return refused(
        const DeskRefused('not_graph', 'That file isn’t a ComfyUI graph.'),
      );
    }
    try {
      final stored = await image.saveGraphFile(
        bytes: bytes,
        name: '${body['name'] ?? ''}',
        edit: body['mode'] == 'edit',
        useFor: body['useFor']?.toString(),
      );
      return JsonResponse.ok({...stored, 'config': image.config()});
    } on DeskRefused catch (e) {
      return refused(e);
    }
  }

  Future<shelf.Response> _writePrompt(shelf.Request request) async {
    final (body, failed) = await _body(request);
    if (body == null) return failed!;
    final chat = deps.chatFacade;
    if (chat == null) {
      return refused(
        const DeskRefused('no_chat', 'Open a chat first, then try again.', 409),
      );
    }
    final instruction = '${body['instruction'] ?? ''}';
    if (instruction.length > maxInstruction) {
      return refused(
        const DeskRefused('too_large', 'That is too long to work from.', 413),
      );
    }
    final subject = '${body['subject'] ?? 'free'}';
    if (!const {'free', 'char', 'persona'}.contains(subject)) {
      return refused(const DeskRefused('bad_request', 'Pick a subject.'));
    }
    final prompt = await chat.craftStudioPrompt(subject, instruction);
    if (prompt == null || prompt.trim().isEmpty) {
      return refused(
        const DeskRefused(
          'no_prompt',
          'Image generation is not set up, so no prompt could be written.',
          409,
        ),
      );
    }
    return JsonResponse.ok({'prompt': prompt.trim()});
  }
}
