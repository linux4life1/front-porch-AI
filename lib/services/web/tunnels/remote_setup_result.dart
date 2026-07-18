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

import 'package:front_porch_ai/services/web/tunnels/tailscale_provider.dart';

/// Outcome of `WebServerHost.setupRemoteAccess` — drives the web-access
/// tutorial's final "you're live / enable HTTPS / not yet" state.
///
/// Kept in its own file (re-exported from `web_server_host.dart`) so the host
/// stays under the file-size cap; existing consumers importing the host are
/// unaffected.
class RemoteSetupResult {
  const RemoteSetupResult({
    required this.outcome,
    this.httpsUrl,
    this.portUrl,
    this.reachable = false,
  });

  /// How the Tailscale HTTPS serve resolved (ok / needs the admin toggle / …).
  final TailscaleServeOutcome outcome;

  /// Clean no-port `https://<magicdns>` address — null unless [outcome] is ok.
  final String? httpsUrl;

  /// `http://<magicdns>:<port>` fallback — works whenever Tailscale is up, even
  /// before HTTPS certs are enabled.
  final String? portUrl;

  /// Whether the best available address was just verified to route back here.
  final bool reachable;

  /// The address to surface first: HTTPS when available, else the port URL.
  String? get primaryUrl => httpsUrl ?? portUrl;
}
