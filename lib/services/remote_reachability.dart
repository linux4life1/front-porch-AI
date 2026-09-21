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

import 'package:http/http.dart' as http;

/// Live ping state for a remote OpenAI-compatible backend.
///
/// [unknown] is "configured, not yet probed" — must not render as the green
/// Ready badge. [reachable] is the only live-ready state.
enum RemoteReachability { unknown, checking, reachable, unreachable }

/// Flutter's test compiler sets this; production binaries do not. Auto-ping
/// on backend activation is skipped in the unit suite so constructing an
/// [OpenRouterService] never hits the network.
const kSkipRemoteAutoPing = bool.fromEnvironment('FLUTTER_TEST');

/// User-facing status for Settings / the engine card. Green "Ready" is
/// reserved for a successful ping.
String remoteBackendStatusLabel({
  required bool configured,
  required RemoteReachability reachability,
}) {
  if (!configured) return 'Not configured';
  return switch (reachability) {
    RemoteReachability.unknown => 'Configured',
    RemoteReachability.checking => 'Checking…',
    RemoteReachability.reachable => 'Ready',
    RemoteReachability.unreachable => 'Configured but unreachable',
  };
}

/// Authorization header used by Check Connection (`GET /models`) and by
/// live chat/completions. Empty key → omit the header so the two paths
/// cannot disagree (a `Bearer ` blank used to look like a missing header
/// on generate while `/models` still went green).
Map<String, String> remoteAuthHeaders(String apiKey) => {
  if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
};

/// Result of `GET {apiUrl}/models` — the cheapest auth+connectivity probe
/// OpenAI-compatible providers share.
class RemotePingResult {
  final bool ok;
  final String message;

  const RemotePingResult({required this.ok, required this.message});
}

/// Lightweight connectivity check. Does not mutate service state; the
/// caller decides whether to stamp [RemoteReachability] from [ok].
///
/// Pass [client] to reuse (or mock) an HTTP client; the caller owns close.
Future<RemotePingResult> pingRemoteModels({
  required String apiUrl,
  required String apiKey,
  required http.Client client,
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (apiUrl.isEmpty) {
    return const RemotePingResult(ok: false, message: 'API URL is empty.');
  }
  final isLocal = apiUrl.contains('localhost') || apiUrl.contains('127.0.0.1');
  if (apiKey.isEmpty && !isLocal) {
    return const RemotePingResult(ok: false, message: 'API key is empty.');
  }

  try {
    final uri = Uri.parse('$apiUrl/models');
    final response = await client
        .get(uri, headers: remoteAuthHeaders(apiKey))
        .timeout(timeout);

    if (response.statusCode == 200) {
      return const RemotePingResult(
        ok: true,
        message: 'Connection successful!',
      );
    }
    var msg = 'HTTP ${response.statusCode}';
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final err = body['error'];
        if (err is Map && err['message'] != null) {
          msg = err['message'].toString();
        } else if (err is String && err.isNotEmpty) {
          msg = err;
        }
      }
    } catch (_) {}
    return RemotePingResult(ok: false, message: 'Connection failed: $msg');
  } catch (e) {
    return RemotePingResult(ok: false, message: 'Connection failed: $e');
  }
}

/// Mutable ping state for one remote client. [OpenRouterService] owns one.
class RemoteApiHealth {
  RemoteReachability reachability = RemoteReachability.unknown;
  int _pingGen = 0;
  http.Client Function()? httpClientFactory;
  void Function()? onChanged;

  bool get isReachable => reachability == RemoteReachability.reachable;
  bool get isChecking => reachability == RemoteReachability.checking;

  http.Client _newClient() => httpClientFactory?.call() ?? http.Client();

  void reset() => _set(RemoteReachability.unknown);

  void _set(RemoteReachability next) {
    if (reachability == next) return;
    reachability = next;
    onChanged?.call();
  }

  /// Live `GET /models`. Stamps [reachability] from the response.
  Future<void> ping({
    required String apiUrl,
    required String apiKey,
    required bool configured,
  }) async {
    if (!configured) {
      _set(RemoteReachability.unknown);
      return;
    }
    final gen = ++_pingGen;
    _set(RemoteReachability.checking);
    final client = _newClient();
    final owned = httpClientFactory == null;
    try {
      final result = await pingRemoteModels(
        apiUrl: apiUrl,
        apiKey: apiKey,
        client: client,
      );
      if (gen != _pingGen) return;
      _set(
        result.ok
            ? RemoteReachability.reachable
            : RemoteReachability.unreachable,
      );
    } finally {
      if (owned) client.close();
    }
  }

  /// Check [apiUrl]/[apiKey] (else the live pair). Stamps live reachability
  /// only when the probe targets the live endpoint.
  Future<String> testConnection({
    required String liveUrl,
    required String liveKey,
    required bool configured,
    String? apiUrl,
    String? apiKey,
  }) async {
    final url = apiUrl ?? liveUrl;
    final key = apiKey ?? liveKey;
    final client = _newClient();
    final owned = httpClientFactory == null;
    try {
      final result = await pingRemoteModels(
        apiUrl: url,
        apiKey: key,
        client: client,
      );
      final testingLive = url == liveUrl && key == liveKey;
      if (testingLive && configured) {
        _set(
          result.ok
              ? RemoteReachability.reachable
              : RemoteReachability.unreachable,
        );
      }
      return result.message;
    } finally {
      if (owned) client.close();
    }
  }
}
