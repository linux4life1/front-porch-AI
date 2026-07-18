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

/// Origin allowlist for WebSocket upgrades, shared by every WS endpoint.
///
/// Because the session cookie is sent automatically, a missing check would let
/// a malicious page open a cross-site socket (WS-CSRF/hijack). Allow
/// same-origin (origin host == request host) and the localhost dev origins
/// used by the Vite dev server.
bool wsOriginAllowed(shelf.Request request, String origin) {
  final o = Uri.tryParse(origin);
  if (o == null) return false;
  if (o.host == 'localhost' || o.host == '127.0.0.1') return true;
  return o.host == request.requestedUri.host;
}
