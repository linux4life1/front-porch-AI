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

import 'settings_base.dart';

/// Persisted web-server settings.
///
/// The server (lib/services/web) uses a real account (Argon2id password +
/// optional TOTP) in the database; its runtime state (sessions, presence,
/// tunnels) lives on WebServerHost. These are just the persisted bind/remote
/// preferences.
class WebServerSettings with SettingsBase {
  bool _webServerEnabled = false;

  /// Launch breadcrumb: true while a start attempt is in flight. If a launch
  /// still sees it set, the previous start never finished (a hard crash/kill
  /// mid-start), so auto-start disables the server instead of re-crashing every
  /// launch. Internal lifecycle state, not UI — its setter does not notify().
  bool _webServerStarting = false;
  int _webServerPort = 8085;

  // Bind policy: localhost-only by default; LAN access is explicit opt-in.
  // Remote access goes through Tailscale/ngrok.
  bool _webServerAllowLan = false;

  // Remote access / TLS.
  // ngrok agent authtoken (treated as a secret; supplied by the user).
  String _webServerNgrokAuthToken = '';

  // Set once the user opts into remote access ("Set it up for me" in the web-
  // access tutorial). When on AND Tailscale is running, the server binds to all
  // interfaces (so the MagicDNS address + port reaches it) and auto-runs
  // `tailscale serve` on launch for the clean no-port HTTPS URL.
  bool _webServerAutoRemote = false;

  bool get webServerEnabled => _webServerEnabled;
  bool get webServerStarting => _webServerStarting;
  int get webServerPort => _webServerPort;
  bool get webServerAllowLan => _webServerAllowLan;
  String get webServerNgrokAuthToken => _webServerNgrokAuthToken;
  bool get webServerAutoRemote => _webServerAutoRemote;

  void load() {
    _webServerEnabled = prefs?.getBool(k('web_server_enabled')) ?? false;
    _webServerStarting = prefs?.getBool(k('web_server_starting')) ?? false;
    _webServerPort = prefs?.getInt(k('web_server_port')) ?? 8085;
    _webServerAllowLan = prefs?.getBool(k('web_server_allow_lan')) ?? false;
    _webServerNgrokAuthToken =
        prefs?.getString(k('web_server_ngrok_authtoken')) ?? '';
    _webServerAutoRemote =
        prefs?.getBool(k('web_server_auto_remote')) ?? false;
  }

  Future<void> setWebServerEnabled(bool value) async {
    _webServerEnabled = value;
    await prefs?.setBool(k('web_server_enabled'), value);
    notify();
  }

  /// Persist the start breadcrumb. No notify(): internal launch state, not UI,
  /// and it is written on the hot launch path where a rebuild is undesirable.
  Future<void> setWebServerStarting(bool value) async {
    _webServerStarting = value;
    await prefs?.setBool(k('web_server_starting'), value);
  }

  Future<void> setWebServerPort(int value) async {
    _webServerPort = value;
    await prefs?.setInt(k('web_server_port'), value);
    notify();
  }

  Future<void> setWebServerAllowLan(bool value) async {
    _webServerAllowLan = value;
    await prefs?.setBool(k('web_server_allow_lan'), value);
    notify();
  }

  Future<void> setWebServerNgrokAuthToken(String value) async {
    _webServerNgrokAuthToken = value;
    await prefs?.setString(k('web_server_ngrok_authtoken'), value);
    notify();
  }

  Future<void> setWebServerAutoRemote(bool value) async {
    _webServerAutoRemote = value;
    await prefs?.setBool(k('web_server_auto_remote'), value);
    notify();
  }
}
