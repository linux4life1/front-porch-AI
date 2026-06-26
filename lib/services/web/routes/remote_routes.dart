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

import 'package:front_porch_ai/services/web/tunnels/tailscale_provider.dart';
import 'package:front_porch_ai/services/web/tunnels/tunnel_manager.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// Remote-access (Tailscale / ngrok / port-forward) status + control endpoints.
class WebRemoteRoutes {
  WebRemoteRoutes(this._deps, this._tunnels, Router router) {
    router.get('/api/remote/status', _status);
    router.post('/api/remote/tailscale', _tailscale);
    router.post('/api/remote/tailscale/login', _tailscaleLogin);
    router.post('/api/remote/ngrok', _ngrok);
  }

  final WebServerDeps _deps;
  final TunnelManager _tunnels;

  Future<shelf.Response> _status(shelf.Request request) async =>
      JsonResponse.ok(await _statusMap());

  /// Tunnel status enriched with whether an ngrok authtoken is already saved
  /// (so the UI can pre-skip the token step).
  Future<Map<String, dynamic>> _statusMap() async {
    final status = await _tunnels.status();
    final ngrok = status['ngrok'];
    if (ngrok is Map) {
      ngrok['hasAuthToken'] =
          _deps.storage.webServerSettings.webServerNgrokAuthToken.isNotEmpty;
    }
    return status;
  }

  Future<shelf.Response> _tailscaleLogin(shelf.Request request) async {
    final url = await _tunnels.tailscaleLogin();
    if (url == null) {
      return JsonResponse.error(
        502,
        'Could not start Tailscale login. If Tailscale is already logged in, '
        'just enable HTTPS below; otherwise open the Tailscale app and sign in.',
      );
    }
    return JsonResponse.ok({'url': url});
  }

  Future<shelf.Response> _tailscale(shelf.Request request) async {
    final body = await _json(request);
    if (body['enable'] == true) {
      final result = await _tunnels.enableTailscale();
      if (result.outcome != TailscaleServeOutcome.ok) {
        final message = result.outcome == TailscaleServeOutcome.httpsDisabled
            ? 'HTTPS certificates aren\'t enabled for your tailnet yet. Turn them '
                'on once at ${TailscaleProvider.enableHttpsUrl}, then try again.'
            : 'Could not start Tailscale serve (is Tailscale running and signed in?).';
        return JsonResponse.error(502, message);
      }
    } else {
      await _tunnels.disableTailscale();
    }
    return JsonResponse.ok(await _statusMap());
  }

  Future<shelf.Response> _ngrok(shelf.Request request) async {
    final body = await _json(request);
    if (body['enable'] == true) {
      // Persist a provided authtoken; otherwise reuse the stored one.
      final settings = _deps.storage.webServerSettings;
      final provided = body['authToken']?.toString();
      if (provided != null && provided.isNotEmpty) {
        await settings.setWebServerNgrokAuthToken(provided);
      }
      final token = settings.webServerNgrokAuthToken;
      final url = await _tunnels.enableNgrok(
        authToken: token.isEmpty ? null : token,
      );
      if (url == null) {
        return JsonResponse.error(
          502,
          'Could not start ngrok (check the authtoken and your plan limits)',
        );
      }
    } else {
      await _tunnels.disableNgrok();
    }
    return JsonResponse.ok(await _statusMap());
  }

  Future<Map<String, dynamic>> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } catch (_) {
      return const {};
    }
  }
}
