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
