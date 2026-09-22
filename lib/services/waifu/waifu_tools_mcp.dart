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
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/chat.dart';

/// Isolated OpenCode `mcp` key. Loopback only — not user-added servers.
const kPorchToolsMcpName = 'porch-tools';

const _kMcpProtocol = '2025-03-26';

/// Process-wide host so sit-down and later list/call share one port.
final porchToolsMcpHost = PorchToolsMcpHost();

/// OpenCode remote MCP block (flat map: name → {type, url, …}).
Map<String, dynamic> porchToolsOpenCodeMcpEntry({
  required Uri url,
  required String token,
}) {
  return {
    kPorchToolsMcpName: {
      'type': 'remote',
      'url': url.toString(),
      'enabled': true,
      'oauth': false,
      'headers': {'Authorization': 'Bearer $token'},
    },
  };
}

/// Empty unless opt-in and `<library>/tools/` has at least one live card.
Future<Map<String, dynamic>> buildPorchToolsMcpMap({
  required bool optIn,
  required Directory toolsDir,
  PorchToolsMcpHost? host,
}) async {
  if (!optIn) return const {};
  final cards = loadUserToolCards(toolsDir);
  if (cards.isEmpty) return const {};
  final bound = await (host ?? porchToolsMcpHost).ensureStarted(toolsDir);
  return porchToolsOpenCodeMcpEntry(url: bound.url, token: bound.token);
}

/// Sync JSON-RPC (list / initialize / ping). Call uses [handlePorchToolsMcpRpcAsync].
Map<String, dynamic> handlePorchToolsMcpRpc(
  Map<String, dynamic> message, {
  required Directory toolsDir,
}) {
  final id = message['id'];
  final method = message['method']?.toString() ?? '';
  if (id == null) return const {};
  return {'jsonrpc': '2.0', 'id': id, 'result': _syncResult(method, toolsDir)};
}

Future<Map<String, dynamic>> handlePorchToolsMcpRpcAsync(
  Map<String, dynamic> message, {
  required Directory toolsDir,
  UserToolHttpSend? send,
}) async {
  final id = message['id'];
  final method = message['method']?.toString() ?? '';
  if (id == null) return const {};
  if (method != 'tools/call') {
    return handlePorchToolsMcpRpc(message, toolsDir: toolsDir);
  }
  final params = message['params'];
  final map = params is Map
      ? Map<String, dynamic>.from(params)
      : <String, dynamic>{};
  final result = await _callTool(map, toolsDir, send);
  return {'jsonrpc': '2.0', 'id': id, 'result': result};
}

Object _syncResult(String method, Directory toolsDir) {
  switch (method) {
    case 'initialize':
      return {
        'protocolVersion': _kMcpProtocol,
        'capabilities': {
          'tools': {'listChanged': false},
        },
        'serverInfo': {'name': kPorchToolsMcpName, 'version': '1.4.0'},
      };
    case 'ping':
      return <String, dynamic>{};
    case 'tools/list':
      return {
        'tools': [
          for (final card in loadUserToolCards(toolsDir))
            {
              'name': card.name,
              'description': card.description,
              'inputSchema': card.parameters,
            },
        ],
      };
    default:
      return {
        'content': [
          {'type': 'text', 'text': 'Unknown method: $method'},
        ],
        'isError': true,
      };
  }
}

Future<Map<String, dynamic>> _callTool(
  Map<String, dynamic> params,
  Directory toolsDir,
  UserToolHttpSend? send,
) async {
  final name = params['name']?.toString() ?? '';
  final rawArgs = params['arguments'];
  final args = rawArgs is Map
      ? Map<String, dynamic>.from(rawArgs)
      : <String, dynamic>{};
  UserToolCard? card;
  for (final c in loadUserToolCards(toolsDir)) {
    if (c.name == name) {
      card = c;
      break;
    }
  }
  if (card == null) {
    return {
      'content': [
        {'type': 'text', 'text': 'Unknown tool: $name'},
      ],
      'isError': true,
    };
  }
  final result = await executeUserToolCard(card, args, send: send);
  return {
    'content': [
      {'type': 'text', 'text': result.text},
    ],
    'isError': !result.ok,
  };
}

/// Loopback Streamable-HTTP MCP server. OpenCode connects with type=remote.
class PorchToolsMcpHost {
  HttpServer? _server;
  String? _token;
  String? _sessionId;
  Directory? _toolsDir;
  UserToolHttpSend? send;

  Uri? get url {
    final server = _server;
    if (server == null) return null;
    return Uri.parse('http://127.0.0.1:${server.port}/mcp');
  }

  String? get token => _token;

  Future<({Uri url, String token})> ensureStarted(Directory toolsDir) async {
    _toolsDir = toolsDir;
    final existing = _server;
    if (existing != null && _token != null) {
      return (
        url: Uri.parse('http://127.0.0.1:${existing.port}/mcp'),
        token: _token!,
      );
    }
    _token = _randomToken();
    _sessionId = _randomToken();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(
      _onRequest,
      onError: (Object e) {
        debugPrint('[PorchToolsMcp] listen error: $e');
      },
    );
    return (
      url: Uri.parse('http://127.0.0.1:${server.port}/mcp'),
      token: _token!,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    _sessionId = null;
    _toolsDir = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _onRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }
    if (request.uri.path != '/mcp') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    if (request.method == 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }
    if (request.method != 'POST') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }
    final expected = 'Bearer $_token';
    if (request.headers.value(HttpHeaders.authorizationHeader) != expected) {
      response.statusCode = HttpStatus.unauthorized;
      await response.close();
      return;
    }
    final raw = await utf8.decoder.bind(request).join();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }
    if (decoded is! Map) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }
    final message = Map<String, dynamic>.from(decoded);
    if (message['id'] == null) {
      response.statusCode = HttpStatus.accepted;
      await response.close();
      return;
    }
    final toolsDir = _toolsDir;
    if (toolsDir == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      await response.close();
      return;
    }
    final body = await handlePorchToolsMcpRpcAsync(
      message,
      toolsDir: toolsDir,
      send: send,
    );
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    if (_sessionId != null) {
      response.headers.set('Mcp-Session-Id', _sessionId!);
    }
    response.write(jsonEncode(body));
    await response.close();
  }
}

String _randomToken() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
