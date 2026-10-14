// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/chargen_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// The AI creator's Profile step and review rewrites on the phone. Each
/// start answers at once; the text streams over the hub. Additive: the
/// one-shot create and the greeting routes are unchanged.
class WebChargenProfileRoutes {
  WebChargenProfileRoutes(this._facade, Router router) {
    router.get('/api/chargen/profile', _profile);
    router.post('/api/chargen/profile/rewrite', _rewrite);
    router.post('/api/chargen/profile/stop', _stop);
    router.post('/api/chargen/profile/facts', _facts);
    router.post('/api/chargen/continue', _continue);
    router.post('/api/chargen/greeting/rewrite-all', _rewriteAll);
    router.post('/api/chargen/greeting/keep-profile', _keepProfile);
    router.get('/api/chargen/review', _review);
    router.post('/api/chargen/rewrite/dialogue', _dialogue);
    router.post('/api/chargen/rewrite/lorebook', _lorebook);
    router.post('/api/chargen/rewrite/stop', _rewriteStop);
  }

  final ChargenFacade _facade;

  Future<Map<String, dynamic>> _json(shelf.Request r) async {
    try {
      return await RequestBody.readJsonMap(r);
    } catch (_) {
      return const {};
    }
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

  String _id(shelf.Request r) =>
      r.url.queryParameters['characterId']?.trim() ?? '';

  /// `?characterId=` optional. `{pending: null}` or `{pending: {…, writing}}`.
  Future<shelf.Response> _profile(shelf.Request r) async {
    final result = await _facade.profile(characterId: _id(r));
    return _answer(
      result,
      () => {
        'pending': result['pending'],
        if (result.containsKey('creating')) 'creating': result['creating'],
      },
    );
  }

  /// Body: `{description, personality, scenario, direction, characterId?}`.
  Future<shelf.Response> _rewrite(shelf.Request r) async =>
      _answer(await _facade.startProfileRewrite(await _json(r)), _started);

  /// Body: `{characterId?}`. `{stopped}` is false when nothing was running.
  Future<shelf.Response> _stop(shelf.Request r) async =>
      JsonResponse.ok({'stopped': _facade.stopProfile(await _json(r))});

  /// Body: `{description, personality, scenario, characterId?}`.
  Future<shelf.Response> _facts(shelf.Request r) async =>
      _answer(await _facade.startFacts(await _json(r)), _started);

  /// Body: `{description, personality, scenario, facts, characterId?}`.
  Future<shelf.Response> _continue(shelf.Request r) async {
    final result = await _facade.startContinue(await _json(r));
    return _answer(
      result,
      () => result['phase'] == 'saved'
          ? {'status': 'saved'}
          : {'status': 'started', 'phase': 'complete'},
    );
  }

  /// Body: `{characterId}`. Writes every greeting again, one at a time.
  Future<shelf.Response> _rewriteAll(shelf.Request r) async {
    final result = _facade.startRewriteAll(await _json(r));
    return _answer(
      result,
      () => {'status': 'started', 'count': result['count']},
    );
  }

  /// Body: `{characterId}`. The greetings count as written from the
  /// profile as it is now.
  Future<shelf.Response> _keepProfile(shelf.Request r) async {
    final id = (await _json(r))['characterId']?.toString().trim() ?? '';
    if (id.isEmpty) return JsonResponse.badRequest('characterId is required');
    return JsonResponse.ok({'ok': await _facade.keepProfile(id)});
  }

  /// `?characterId=`: the example dialogue and lorebook rows.
  shelf.Response _review(shelf.Request r) {
    final review = _facade.review(_id(r));
    return review == null
        ? JsonResponse.error(404, 'character not found')
        : JsonResponse.ok(review);
  }

  /// Body: `{characterId, direction}`.
  Future<shelf.Response> _dialogue(shelf.Request r) async =>
      _answer(_facade.startRewrite('mesExample', await _json(r)), _started);

  /// Body: `{characterId, direction}`.
  Future<shelf.Response> _lorebook(shelf.Request r) async =>
      _answer(_facade.startRewrite('lorebook', await _json(r)), _started);

  /// Body: `{characterId}`.
  Future<shelf.Response> _rewriteStop(shelf.Request r) async {
    final id = (await _json(r))['characterId']?.toString().trim() ?? '';
    return JsonResponse.ok({'stopped': _facade.stopRewrite(id)});
  }

  Map<String, dynamic> _started() => {'status': 'started'};
}
