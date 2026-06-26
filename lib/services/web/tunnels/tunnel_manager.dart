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

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/web/tunnels/ngrok_provider.dart';
import 'package:front_porch_ai/services/web/tunnels/tailscale_provider.dart';

/// Aggregates the remote-access providers behind one surface the settings UI
/// (Flutter) and the React "Remote Access" page both read — a single source of
/// truth for `{type, url, secure, status}` per tunnel plus a manual
/// port-forward hint.
class TunnelManager {
  TunnelManager(
    this._port, {
    TailscaleProvider? tailscale,
    NgrokProvider? ngrok,
  })  : _tailscale = tailscale ?? TailscaleProvider(),
        _ngrok = ngrok ?? NgrokProvider();

  final int _port;
  final TailscaleProvider _tailscale;
  final NgrokProvider _ngrok;

  String? _tailscaleUrl;
  TailscaleServeOutcome? _tailscaleHttpsState;

  int get port => _port;

  /// Live Tailscale daemon state (running, MagicDNS name, tailnet IP). Exposed
  /// so the desktop setup flow can build the port-fallback URL and guidance.
  Future<TailscaleStatus> tailscaleStatus() => _tailscale.status();

  /// Aggregated remote-access state for the UI (includes install/login guidance
  /// so the Remote Access page can walk the user through every state).
  Future<Map<String, dynamic>> status() async {
    final ts = await _tailscale.status();
    return {
      'port': _port,
      'tailscale': {
        'installed': _tailscale.isInstalled,
        'running': ts.running,
        'needsLogin': ts.needsLogin,
        'backendState': ts.backendState,
        'magicDnsName': ts.magicDnsName,
        'ip': ts.ip,
        'url': _tailscaleUrl,
        'secure': true, // ts.net cert is publicly trusted
        'installUrl': TailscaleProvider.installUrl,
        'enableHttpsUrl': TailscaleProvider.enableHttpsUrl,
        // Last serve outcome so the UI can show the "enable HTTPS certs" path.
        'httpsState': _tailscaleHttpsState?.name,
      },
      'ngrok': {
        'installed': _ngrok.isInstalled,
        'running': _ngrok.isRunning,
        'url': _ngrok.publicUrl,
        'secure': true, // TLS terminated at ngrok edge
        'installUrl': NgrokProvider.installUrl,
        'authTokenUrl': NgrokProvider.authTokenUrl,
      },
      'portForward': {
        // Manual option: forward this TCP port on the router to this host.
        'port': _port,
        'hint':
            'Forward external port to this host:$_port, then use https via a '
                'reverse proxy or a dynamic-DNS + cert for a real secure context.',
      },
    };
  }

  /// Begin interactive Tailscale login; returns the auth URL to open.
  Future<String?> tailscaleLogin() => _tailscale.login();

  /// Turn on Tailscale HTTPS serve. Returns the full outcome so callers can
  /// distinguish "needs the admin HTTPS toggle" from a hard failure.
  Future<TailscaleServeResult> enableTailscale() async {
    final result = await _tailscale.serve(_port);
    _tailscaleUrl = result.url;
    _tailscaleHttpsState = result.outcome;
    return result;
  }

  Future<void> disableTailscale() async {
    await _tailscale.serveOff();
    _tailscaleUrl = null;
    _tailscaleHttpsState = null;
  }

  /// Best-effort end-to-end check that [url] actually routes back to this
  /// server (validates the tunnel + the HTTPS cert). Any HTTP response — even
  /// a 401 — means the address reached us; only a transport failure is "no".
  Future<bool> verifyReachable(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final uri = Uri.parse(url).replace(path: '/api/health');
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      await resp.drain<void>();
      return true;
    } catch (e) {
      debugPrint('[TunnelManager] verifyReachable($url) failed: $e');
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  Future<String?> enableNgrok({String? authToken}) =>
      _ngrok.start(_port, authToken: authToken);

  Future<void> disableNgrok() => _ngrok.stop();

  Future<void> dispose() async {
    await _ngrok.stop();
    await _tailscale.serveOff();
    _tailscaleUrl = null;
  }
}
