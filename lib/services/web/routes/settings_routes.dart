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

import 'package:front_porch_ai/services/web/facade/settings_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// Core generation + backend settings endpoints for the web Settings page.
class WebSettingsRoutes {
  WebSettingsRoutes(this._deps, Router router)
    : _facade = _deps.settingsFacade! {
    router.get('/api/settings', _get);
    router.post('/api/settings', _post);
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
    // Redirecting generation (URL) or overwriting the API key is
    // credential-grade — same password (+ TOTP) step-up as tunnel enable.
    // Samplers and Porch Life toggles stay session-only.
    if (remoteCredentialWriteNeedsStepUp(
      body,
      currentRemoteApiUrl: _facade.currentRemoteApiUrl,
    )) {
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
