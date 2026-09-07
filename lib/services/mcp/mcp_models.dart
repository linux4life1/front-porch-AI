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

/// Connection state of one MCP server.
enum McpConnectionStatus { disconnected, connecting, connected, error }

/// Where a catalog entry came from. Never shown to the model.
enum McpToolSource { inProcess, mcp }

/// Persisted MCP server the user added in Settings.
class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.displayName,
    required this.url,
    this.headers = const {},
    this.authToken = '',
    this.enabledGlobal = true,
  });

  final String id;
  final String displayName;
  final String url;
  final Map<String, String> headers;
  final String authToken;
  final bool enabledGlobal;

  McpServerConfig copyWith({
    String? displayName,
    String? url,
    Map<String, String>? headers,
    String? authToken,
    bool? enabledGlobal,
  }) {
    return McpServerConfig(
      id: id,
      displayName: displayName ?? this.displayName,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      authToken: authToken ?? this.authToken,
      enabledGlobal: enabledGlobal ?? this.enabledGlobal,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'url': url,
    'headers': headers,
    'enabledGlobal': enabledGlobal,
    if (authToken.isNotEmpty) 'authToken': authToken,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k is String && v != null) headers[k] = v.toString();
      });
    }
    return McpServerConfig(
      id: json['id']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      headers: headers,
      authToken: json['authToken']?.toString() ?? '',
      enabledGlobal: json['enabledGlobal'] != false,
    );
  }
}

/// One tool advertised by `tools/list`.
class McpToolDef {
  const McpToolDef({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  factory McpToolDef.fromJson(Map<String, dynamic> json) {
    final schema = json['inputSchema'];
    return McpToolDef(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      inputSchema: schema is Map
          ? Map<String, dynamic>.from(schema)
          : const {'type': 'object', 'properties': <String, dynamic>{}},
    );
  }
}

/// Result of one `tools/call`.
class McpCallResult {
  const McpCallResult({
    required this.ok,
    required this.text,
    this.isError = false,
  });

  final bool ok;
  final String text;
  final bool isError;
}

/// One entry in the flat catalog the model sees.
class CatalogTool {
  const CatalogTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.source,
    this.serverId,
    this.serverDisplayName,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final McpToolSource source;
  final String? serverId;
  final String? serverDisplayName;

  Map<String, dynamic> toOpenAiTool() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// A tool omitted from the catalog, and why.
class CatalogExclusion {
  const CatalogExclusion({
    required this.toolName,
    required this.serverId,
    required this.serverDisplayName,
    required this.reason,
  });

  final String toolName;
  final String serverId;
  final String serverDisplayName;
  final String reason;
}

/// Snapshot of one connected (or attempted) server for catalog + UI.
class McpServerSnapshot {
  const McpServerSnapshot({
    required this.config,
    required this.status,
    required this.connectOrder,
    this.lastError,
    this.tools = const [],
  });

  final McpServerConfig config;
  final McpConnectionStatus status;
  final int connectOrder;
  final String? lastError;
  final List<McpToolDef> tools;
}

/// Per-chat row the sidebar and web tools panel render.
class McpChatServerView {
  const McpChatServerView({
    required this.id,
    required this.displayName,
    required this.url,
    required this.status,
    required this.enabledForChat,
    required this.enabledGlobal,
    this.lastError,
    this.toolNames = const [],
    this.conflictToolNames = const [],
  });

  final String id;
  final String displayName;
  final String url;
  final McpConnectionStatus status;
  final bool enabledForChat;
  final bool enabledGlobal;
  final String? lastError;
  final List<String> toolNames;
  final List<String> conflictToolNames;
}

/// Docker Desktop's MCP Toolkit talks stdio. HTTP, when you start it:
/// `docker mcp gateway run --transport streaming --port 8811`
const kMcpDockerHttpCommand =
    'docker mcp gateway run --transport streaming --port 8811';

const kMcpDockerMcpUrl = 'http://127.0.0.1:8811/mcp';
const kMcpDockerSseUrl = 'http://127.0.0.1:8811/sse';

/// Local Docker HTTP endpoints we try. /mcp first (streamable), then SSE.
const kMcpDockerUrls = [kMcpDockerMcpUrl, kMcpDockerSseUrl];

bool mcpSameGateway(String a, String b) {
  final ua = Uri.tryParse(a.trim());
  final ub = Uri.tryParse(b.trim());
  if (ua == null || ub == null) return a.trim() == b.trim();
  final portA = ua.hasPort ? ua.port : (ua.scheme == 'https' ? 443 : 80);
  final portB = ub.hasPort ? ub.port : (ub.scheme == 'https' ? 443 : 80);
  return ua.host.toLowerCase() == ub.host.toLowerCase() && portA == portB;
}

/// One line for Settings. Three names is readable; 110 is a wall.
String mcpToolsPhrase(List<String> names) {
  if (names.isEmpty) return 'no tools advertised';
  final n = names.length;
  final noun = n == 1 ? 'tool' : 'tools';
  if (n <= 3) return '$n $noun: ${names.join(', ')}';
  return '$n $noun';
}

String mcpDefaultDisplayName(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed != null && parsed.port == 8811) return 'Docker';
  final host = parsed?.host.trim() ?? '';
  if (host.isNotEmpty) return host;
  return 'MCP server';
}

/// If the user picked one Docker transport, also try the other.
List<String> mcpSiblingUrls(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return const [];
  if (!trimmed.contains(':8811')) return [trimmed];
  if (trimmed.endsWith('/mcp')) {
    return [trimmed, '${trimmed.substring(0, trimmed.length - 4)}/sse'];
  }
  if (trimmed.endsWith('/sse')) {
    return [trimmed, '${trimmed.substring(0, trimmed.length - 4)}/mcp'];
  }
  return [trimmed];
}

bool mcpErrorWantsToken(String? lastError) {
  final lower = (lastError ?? '').toLowerCase();
  return lower.contains('401') || lower.contains('unauthorized');
}

/// Strip SocketException dumps. Keep HTTP 500 as HTTP 500.
String mcpHumanizeConnectError(String? lastError, {String url = ''}) {
  final raw = (lastError ?? '').trim();
  if (raw.isEmpty) return '';
  final lower = raw.toLowerCase();
  final refused =
      lower.contains('connection refused') ||
      lower.contains('errno = 61') ||
      lower.contains('errno = 111') ||
      (lower.contains('socketexception') && lower.contains('refused'));
  if (refused) {
    final onDocker = url.contains('8811') || raw.contains('8811');
    if (onDocker) {
      return 'Nothing is listening there. Docker Desktop MCP does not open a '
          'URL. In a terminal: $kMcpDockerHttpCommand';
    }
    return 'Nothing is listening at that address.';
  }
  if (mcpErrorWantsToken(raw)) {
    return 'This server wants a token. If you started the Docker gateway, it '
        'printed a Bearer token when it started.';
  }
  if (lower.contains('clientexception') || lower.contains('socketexception')) {
    return 'Could not connect. Is the server running?';
  }
  return raw;
}

/// Plain-language line for Settings → Porch Life → Check connection.
String mcpCheckResultLine({
  required String url,
  required McpConnectionStatus status,
  required List<String> toolNames,
  String? lastError,
}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return 'Enter a server address first';
  switch (status) {
    case McpConnectionStatus.connected:
      return 'Connected — ${mcpToolsPhrase(toolNames)}';
    case McpConnectionStatus.connecting:
      return 'Checking $trimmed…';
    case McpConnectionStatus.error:
    case McpConnectionStatus.disconnected:
      final reason = mcpHumanizeConnectError(lastError, url: trimmed);
      if (reason.startsWith('Nothing is listening') ||
          reason.startsWith('This server wants')) {
        return reason;
      }
      return reason.isEmpty
          ? 'Could not reach $trimmed'
          : 'Could not reach $trimmed — $reason';
  }
}
