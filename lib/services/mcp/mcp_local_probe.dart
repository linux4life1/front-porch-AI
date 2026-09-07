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

import 'package:front_porch_ai/services/mcp/mcp_models.dart';

class McpLocalProbeResult {
  const McpLocalProbeResult({
    required this.found,
    this.url,
    required this.message,
  });

  final bool found;
  final String? url;
  final String message;
}

/// Look for a Docker MCP HTTP gateway on 8811. /health needs no token.
class McpLocalProbe {
  McpLocalProbe({this.get});

  final Future<http.Response> Function(Uri uri)? get;

  Future<McpLocalProbeResult> findDocker() async {
    final getter =
        get ??
        (uri) => http.get(uri).timeout(const Duration(milliseconds: 800));
    try {
      final health = await getter(Uri.parse('http://127.0.0.1:8811/health'));
      if (health.statusCode < 500) {
        return const McpLocalProbeResult(
          found: true,
          url: kMcpDockerMcpUrl,
          message: 'Found a gateway on port 8811. Tap Check connection.',
        );
      }
    } catch (e) {
      return McpLocalProbeResult(
        found: false,
        message: mcpHumanizeConnectError('$e', url: kMcpDockerMcpUrl),
      );
    }
    return const McpLocalProbeResult(
      found: false,
      message: 'Port 8811 answered, but not as an MCP gateway.',
    );
  }
}
