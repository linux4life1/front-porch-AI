// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

typedef _BodyHandler =
    Future<shelf.Response> Function(
      ChargenTemplateLibrary library,
      Map<String, dynamic> body,
    );

/// The creator's templates on the phone, in the one library the desktop
/// uses (the folder is read on every call, so a moved library follows).
/// Additive: nothing else in the creator relay changed. A body that is not
/// a JSON object is refused (400); 503 while there is no library folder.
class WebChargenTemplateRoutes {
  WebChargenTemplateRoutes(this._library, Router router) {
    router.get('/api/chargen/templates', _list);
    router.put('/api/chargen/templates/<slug>', _put);
    router.post('/api/chargen/templates/<slug>/rename', _rename);
    router.delete('/api/chargen/templates/<slug>', _delete);
  }

  final ChargenTemplateLibrary? Function() _library;

  /// `{templates: [...]}`: yours newest first, then the built-ins, each
  /// with its summary and form; a file that cannot be read says so.
  Future<shelf.Response> _list(shelf.Request r) async {
    final library = _library();
    if (library == null) return _noLibrary();
    return JsonResponse.ok({
      'templates': [for (final t in await library.list()) t.toJson()],
    });
  }

  /// Body: `{name, form, basedOn?}`; the path is the name's slug. Creates
  /// or replaces it: `{template, replaced}`.
  Future<shelf.Response> _put(shelf.Request r, String slug) =>
      _withBody(r, (library, body) async {
        final name = _name(body);
        final refused = templateNameRefusal(name);
        if (refused != null) return _refusal(refused);
        final form = body['form'];
        if (form is! Map<String, dynamic>) {
          return JsonResponse.badRequest('form must be a JSON object');
        }
        if (templateSlug(name) != slug) {
          return JsonResponse.badRequest(
            'The address does not match the name: it should end in '
            '/${templateSlug(name)}.',
          );
        }
        final basedOn = body['basedOn'];
        final saved = await library.save(
          name,
          form,
          basedOn: basedOn is String && basedOn.isNotEmpty ? basedOn : null,
        );
        return JsonResponse.ok({
          'template': saved.template.toJson(),
          'replaced': saved.replaced,
        });
      });

  /// Body: `{name}`. `{template}` under its new name and slug.
  Future<shelf.Response> _rename(shelf.Request r, String slug) =>
      _withBody(r, (library, body) async {
        final renamed = await library.rename(slug, _name(body));
        return JsonResponse.ok({'template': renamed.toJson()});
      });

  /// `{deleted: true}`.
  Future<shelf.Response> _delete(shelf.Request r, String slug) async {
    final library = _library();
    if (library == null) return _noLibrary();
    return _refusals(() async {
      await library.delete(slug);
      return JsonResponse.ok({'deleted': true});
    });
  }

  Future<shelf.Response> _withBody(shelf.Request r, _BodyHandler handle) async {
    final library = _library();
    if (library == null) return _noLibrary();
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (e) {
      debugPrint('[chargen] ${r.url.path}: the body is not a JSON object: $e');
      return JsonResponse.badRequest('invalid JSON');
    }
    return _refusals(() => handle(library, body));
  }

  /// [run]'s answer; a refusal as its status, a disk failure as a 500.
  Future<shelf.Response> _refusals(
    Future<shelf.Response> Function() run,
  ) async {
    try {
      return await run();
    } on TemplateRefused catch (e) {
      return _refusal(e);
    } on FileSystemException catch (e) {
      debugPrint('[chargen] templates: $e');
      return JsonResponse.error(
        500,
        'The templates folder could not be changed (${e.message}).',
      );
    }
  }

  shelf.Response _refusal(TemplateRefused e) => JsonResponse.error(
    e.status,
    e.message,
    extra: {if (e.reason != null) 'reason': e.reason},
  );

  String _name(Map<String, dynamic> body) {
    final name = body['name'];
    return name is String ? name : '';
  }

  shelf.Response _noLibrary() => JsonResponse.error(
    503,
    'Templates are kept in the library folder, and there is none yet. '
    'Open the app on the computer to set one up.',
  );
}
