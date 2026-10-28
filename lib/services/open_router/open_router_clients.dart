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

import 'package:http/http.dart' as http;
import 'package:front_porch_ai/services/llm_service.dart';

/// Every in-flight client of one OpenAI-compatible service; a set is
/// required because staggered remote evals overlap, and one slot let the
/// first completion disarm Cancel for the rest.
class OpenRouterClients {
  final Set<http.Client> _active = {};

  /// Tracks [client] for the call made with [params]. When that caller calls
  /// its request off, only that call closes, and only while it is still
  /// open.
  void add(http.Client client, GenerationParams params) {
    _active.add(client);
    params.cancel?.whenCancelled.then((_) {
      if (_active.remove(client)) client.close();
    });
  }

  void remove(http.Client client) => _active.remove(client);

  /// Closes every call still open.
  void abortAll() {
    // Iterate a copy: each close() lets its call's finally run, which mutates
    // the set.
    for (final client in _active.toList()) {
      client.close();
    }
    _active.clear();
  }
}
