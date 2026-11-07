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

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:front_porch_ai/services/llm_service.dart';

/// Every in-flight client of one OpenAI-compatible service; a set is
/// required because staggered remote evals overlap, and one slot let the
/// first completion disarm Cancel for the rest.
///
/// Each call is closed in the zone that opened it. A close that lands while
/// the socket is still connecting cancels the connect, and dart:io hands
/// that cancellation to a listener in the closer's zone: from any other
/// error zone it escapes as uncaught in the caller's zone, though the caller
/// awaited and caught it. A chat switch's abort from one zone cutting a
/// background ping opened in another failed a finished E2E suite that way.
class OpenRouterClients {
  final Map<http.Client, Zone> _active = {};

  /// Tracks [client] for the call made with [params]. When that caller calls
  /// its request off, only that call closes, and only while it is still
  /// open.
  void add(http.Client client, GenerationParams params) {
    _active[client] = Zone.current;
    params.cancel?.whenCancelled.then((_) => _close(client));
  }

  void remove(http.Client client) => _active.remove(client);

  /// Closes every call still open.
  void abortAll() {
    // Iterate a copy: each close() lets its call's finally run, which mutates
    // the map.
    for (final client in _active.keys.toList()) {
      _close(client);
    }
  }

  void _close(http.Client client) {
    final zone = _active.remove(client);
    if (zone != null) zone.run(client.close);
  }
}
