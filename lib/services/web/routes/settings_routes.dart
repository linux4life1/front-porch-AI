// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/chat/existing_chats_offer.dart';
import 'package:front_porch_ai/services/web/facade/settings_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// Core generation + backend settings endpoints for the web Settings page.
class WebSettingsRoutes {
  WebSettingsRoutes(this._deps, Router router)
    : _facade = _deps.settingsFacade! {
    router.get('/api/settings', _get);
    router.post('/api/settings', _post);
    // The existing-chats question once Porch Life allows a feature: how many
    // chats have their own switch off, and turning those on.
    router.get('/api/settings/existing-chats', (shelf.Request r) async {
      final f = _featureFor(r.url.queryParameters['feature']);
      if (f == null) return JsonResponse.badRequest('unknown feature');
      return JsonResponse.ok({'count': await _offer().countOff(f)});
    });
    router.post('/api/settings/existing-chats', (shelf.Request r) async {
      final body = await RequestBody.readJsonMap(r);
      final f = _featureFor(body['feature']?.toString());
      if (f == null) return JsonResponse.badRequest('unknown feature');
      // Porch Life may have stopped allowing it since the question opened.
      if (!_allowed(f)) return JsonResponse.ok({'changed': 0});
      return JsonResponse.ok({'changed': await _offer().turnOn(f)});
    });
    // Legacy-engine model cleanup (desktop parity: Reclaim Disk Space).
    router.get(
      '/api/legacy-models',
      (shelf.Request r) async => JsonResponse.ok(await _facade.legacyModels()),
    );
    router.post(
      '/api/legacy-models/reclaim',
      (shelf.Request r) async =>
          JsonResponse.ok({'freedBytes': await _facade.reclaimLegacyModels()}),
    );
  }

  final WebServerDeps _deps;

  /// The feature named on the wire, or null for one it does not know.
  ExistingChatsFeature? _featureFor(String? name) => switch (name) {
    'afterglow' => ExistingChatsFeature.afterglow,
    'needs' => ExistingChatsFeature.needs,
    _ => null,
  };

  bool _allowed(ExistingChatsFeature f) => f == ExistingChatsFeature.needs
      ? _deps.storage.realismSettings.needsSimDefault
      : _deps.storage.realismSettings.afterglowEnabled;

  ExistingChatsOffer _offer() => ExistingChatsOffer(
    _deps.db,
    _facade.boundChat,
    cards: _deps.characterFacade?.cards,
  );
  final SettingsFacade _facade;

  Future<shelf.Response> _get(shelf.Request request) async =>
      JsonResponse.ok(await _readWithLanguages());

  Future<shelf.Response> _post(shelf.Request request) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final refused = _facade.refusal(body);
    if (refused != null) return JsonResponse.badRequest(refused);
    // Redirecting generation (URL) or overwriting the API key is
    // credential-grade — same password (+ TOTP) step-up as tunnel enable.
    // Mouth remote AND worker lane. Samplers and Porch Life stay session-only.
    if (remoteCredentialWriteNeedsStepUp(
          body,
          currentRemoteApiUrl: _facade.currentRemoteApiUrl,
        ) ||
        workerCredentialWriteNeedsStepUp(
          body,
          currentWorkerRemoteApiUrl: _facade.currentWorkerRemoteApiUrl,
        ) ||
        workerPathWriteNeedsStepUp(
          body,
          currentWorkerModelPath: _facade.currentWorkerKoboldModelPath,
          currentWorkerKcppsPath: _facade.currentWorkerKoboldKcppsPath,
        ) ||
        searchApiKeyWriteNeedsStepUp(body) ||
        hfTokenWriteNeedsStepUp(body)) {
      final denied = await denyUnlessSteppedUp(
        auth: _deps.auth,
        body: body,
        request: request,
      );
      if (denied != null) return denied;
    }
    await _facade.update(body);
    return JsonResponse.ok(await _readWithLanguages());
  }

  /// [SettingsFacade.read] is sync, but the installed dictionary list has to be
  /// asked for over a method channel. Merged here so both GET and POST return
  /// the same shape — a web client that saved settings must not lose the
  /// picker's options as a side effect.
  Future<Map<String, dynamic>> _readWithLanguages() async {
    await _facade.ensureReasoningResolved();
    final data = _facade.read();
    data['spellCheckLanguages'] = await _facade.spellCheckLanguages();
    return data;
  }
}
