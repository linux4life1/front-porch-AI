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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Detects and drives an installed ngrok agent (binary NOT bundled).
///
/// Starts `ngrok http <port>` and reads the public https URL from the local
/// agent API at 127.0.0.1:4040 (robust across versions, unlike stdout scraping).
/// The user supplies the authtoken; we configure it before spawning.
class NgrokProvider {
  NgrokProvider({String? executable}) : _exe = executable ?? _findExe();

  final String _exe;
  Process? _process;
  String? _publicUrl;

  bool get isInstalled => _exe.isNotEmpty;
  bool get isRunning => _process != null;
  String? get publicUrl => _publicUrl;

  /// Where to download ngrok (shown when it isn't installed).
  static const String installUrl = 'https://ngrok.com/download';

  /// Where the user finds their authtoken (shown in the token field help).
  static const String authTokenUrl =
      'https://dashboard.ngrok.com/get-started/your-authtoken';

  /// Start a tunnel to [port]. Returns the public https URL, or null on
  /// failure (bad token, tunnel limit, etc. — surfaced via debug logs).
  Future<String?> start(int port, {String? authToken}) async {
    if (!isInstalled) return null;
    if (isRunning) return _publicUrl;
    try {
      if (authToken != null && authToken.isNotEmpty) {
        await Process.run(_exe, ['config', 'add-authtoken', authToken]);
      }
      _process = await Process.start(
        _exe,
        ['http', '$port', '--log=stdout'],
        includeParentEnvironment: true,
      );
      _process!.exitCode.then((code) {
        debugPrint('[ngrok] agent exited with code $code');
        _process = null;
        _publicUrl = null;
      });
      _publicUrl = await _awaitPublicUrl();
      if (_publicUrl == null) {
        debugPrint('[ngrok] tunnel did not come up (check authtoken/limits)');
        await stop();
      }
      return _publicUrl;
    } catch (e) {
      debugPrint('[ngrok] start error: $e');
      await stop();
      return null;
    }
  }

  Future<void> stop() async {
    _publicUrl = null;
    final proc = _process;
    _process = null;
    proc?.kill();
  }

  /// Poll the local agent API until a public https URL appears (or timeout).
  Future<String?> _awaitPublicUrl() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final res = await http
            .get(Uri.parse('http://127.0.0.1:4040/api/tunnels'))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          final url = parseTunnels(res.body);
          if (url != null) return url;
        }
      } catch (_) {
        // Agent web API not up yet — keep polling.
      }
    }
    return null;
  }

  /// Pure parse of the `/api/tunnels` payload; prefers the https tunnel.
  /// Exposed for testing.
  static String? parseTunnels(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      final tunnels = (data is Map) ? data['tunnels'] : null;
      if (tunnels is! List) return null;
      String? httpsUrl;
      String? anyUrl;
      for (final t in tunnels) {
        if (t is! Map) continue;
        final url = t['public_url']?.toString();
        if (url == null) continue;
        anyUrl ??= url;
        if (url.startsWith('https://')) httpsUrl ??= url;
      }
      return httpsUrl ?? anyUrl;
    } catch (_) {
      return null;
    }
  }

  static String _findExe() {
    const candidates = [
      'ngrok',
      '/usr/local/bin/ngrok',
      '/usr/bin/ngrok',
      '/opt/homebrew/bin/ngrok',
      r'C:\Program Files\ngrok\ngrok.exe',
    ];
    for (final c in candidates) {
      if (c == 'ngrok') {
        try {
          final r = Process.runSync(c, ['version']);
          if (r.exitCode == 0) return c;
        } catch (_) {}
      } else if (File(c).existsSync()) {
        return c;
      }
    }
    return '';
  }
}
