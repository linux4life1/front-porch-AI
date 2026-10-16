// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/chargen_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

typedef _BodyHandler =
    FutureOr<shelf.Response> Function(Map<String, dynamic> body);

/// The AI creator's Profile step and review rewrites on the phone. Each
/// start answers at once; the text streams over the hub. Additive: the
/// one-shot create and the greeting routes are unchanged. A POST whose body
/// is not a JSON object is refused (400), never run with blank fields.
class WebChargenProfileRoutes {
  WebChargenProfileRoutes(this._facade, Router router) {
    router.get('/api/chargen/profile', _profile);
    _post(router, '/api/chargen/profile/rewrite', _rewrite);
    _post(router, '/api/chargen/profile/stop', _stop);
    _post(router, '/api/chargen/profile/facts', _facts);
    _post(router, '/api/chargen/continue', _continue);
    _post(router, '/api/chargen/greeting/rewrite-all', _rewriteAll);
    _post(router, '/api/chargen/greeting/keep-profile', _keepProfile);
    router.get('/api/chargen/review', _review);
    _post(router, '/api/chargen/rewrite/dialogue', _dialogue);
    _post(router, '/api/chargen/rewrite/lorebook', _lorebook);
    _post(router, '/api/chargen/rewrite/stop', _rewriteStop);
  }

  final ChargenFacade _facade;

  void _post(Router router, String path, _BodyHandler handle) {
    router.post(path, (shelf.Request r) async {
      final Map<String, dynamic> body;
      try {
        body = await RequestBody.readJsonMap(r);
      } catch (e) {
        debugPrint('[chargen] $path: the body is not a JSON object: $e');
        return JsonResponse.badRequest('invalid JSON');
      }
      return handle(body);
    });
  }

  shelf.Response _answer(
    Map<String, dynamic> result,
    Map<String, dynamic> Function() ok,
  ) {
    if (result['ok'] == true) return JsonResponse.ok(ok());
    return JsonResponse.error(
      (result['status'] as int?) ?? 400,
      result['error']?.toString() ?? 'Bad request',
    );
  }

  String _id(Map<String, dynamic> body) =>
      body['characterId']?.toString().trim() ?? '';

  String _queryId(shelf.Request r) =>
      r.url.queryParameters['characterId']?.trim() ?? '';

  /// `?characterId=` optional. `{pending: null}` or `{pending: {…, writing}}`.
  Future<shelf.Response> _profile(shelf.Request r) async {
    final result = await _facade.profile(characterId: _queryId(r));
    return _answer(
      result,
      () => {
        'pending': result['pending'],
        if (result.containsKey('creating')) 'creating': result['creating'],
      },
    );
  }

  /// Body: `{description, personality, scenario, direction, characterId?}`.
  Future<shelf.Response> _rewrite(Map<String, dynamic> body) async =>
      _answer(await _facade.startProfileRewrite(body), _started);

  /// Body: `{characterId?}`. Stops a rewrite, a re-read, or the rest of the
  /// card being written. `{stopped}` is false when nothing was running.
  shelf.Response _stop(Map<String, dynamic> body) =>
      JsonResponse.ok({'stopped': _facade.stopProfile(body)});

  /// Body: `{description, personality, scenario, characterId?}`.
  Future<shelf.Response> _facts(Map<String, dynamic> body) async =>
      _answer(await _facade.startFacts(body), _started);

  /// Body: `{description, personality, scenario, facts, characterId?}`.
  Future<shelf.Response> _continue(Map<String, dynamic> body) async {
    final result = await _facade.startContinue(body);
    return _answer(
      result,
      () => result['phase'] == 'saved'
          ? {'status': 'saved'}
          : {'status': 'started', 'phase': 'complete'},
    );
  }

  /// Body: `{characterId}`. Writes every greeting again, one at a time.
  shelf.Response _rewriteAll(Map<String, dynamic> body) {
    final result = _facade.startRewriteAll(body);
    return _answer(
      result,
      () => {'status': 'started', 'count': result['count']},
    );
  }

  /// Body: `{characterId}`. The greetings count as written from the
  /// profile as it is now.
  Future<shelf.Response> _keepProfile(Map<String, dynamic> body) async {
    final id = _id(body);
    if (id.isEmpty) return JsonResponse.badRequest('characterId is required');
    if (!_facade.hasCharacter(id)) {
      return JsonResponse.error(404, 'character not found');
    }
    return JsonResponse.ok({'ok': await _facade.keepProfile(id)});
  }

  /// `?characterId=`: the example dialogue and lorebook rows.
  shelf.Response _review(shelf.Request r) {
    final review = _facade.review(_queryId(r));
    return review == null
        ? JsonResponse.error(404, 'character not found')
        : JsonResponse.ok(review);
  }

  /// Body: `{characterId, direction}`.
  shelf.Response _dialogue(Map<String, dynamic> body) =>
      _answer(_facade.startRewrite('mesExample', body), _started);

  /// Body: `{characterId, direction}`.
  shelf.Response _lorebook(Map<String, dynamic> body) =>
      _answer(_facade.startRewrite('lorebook', body), _started);

  /// Body: `{characterId}`.
  shelf.Response _rewriteStop(Map<String, dynamic> body) =>
      JsonResponse.ok({'stopped': _facade.stopRewrite(_id(body))});

  Map<String, dynamic> _started() => {'status': 'started'};
}
