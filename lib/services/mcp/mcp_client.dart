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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/mcp/mcp_models.dart';
import 'package:front_porch_ai/services/mcp/mcp_stdio.dart';
import 'package:front_porch_ai/services/mcp/mcp_transport.dart';

/// In-process MCP client over Streamable HTTP, with legacy HTTP+SSE fallback
/// and an injected stdio session (spawn lives in [McpStdioSession], not here).
class McpClient {
  McpClient({required this.config, this.sendRequest, this.openStdio});

  McpServerConfig config;
  Future<http.Response> Function(http.BaseRequest request)? sendRequest;
  McpStdioOpener? openStdio;
  McpStdioSession? _stdio;

  McpConnectionStatus status = McpConnectionStatus.disconnected;
  String? lastError;
  List<McpToolDef> tools = const [];
  String? sessionId;
  Uri? _messageUrl;
  int _nextId = 1;
  int connectOrder = 0;

  bool get isConnected => status == McpConnectionStatus.connected;

  Map<String, String> get _headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': '2025-03-26',
      ...config.headers,
    };
    final token = config.authToken.trim();
    if (token.isNotEmpty &&
        !h.keys.any((k) => k.toLowerCase() == 'authorization')) {
      h['Authorization'] = token.toLowerCase().startsWith('bearer ')
          ? token
          : 'Bearer $token';
    }
    if (sessionId != null) h['Mcp-Session-Id'] = sessionId!;
    return h;
  }

  Future<void> connect() async {
    status = McpConnectionStatus.connecting;
    lastError = null;
    tools = const [];
    sessionId = null;
    _messageUrl = null;
    _nextId = 1;
    await _stdio?.close();
    _stdio = null;
    debugPrint(
      '[MCP] connect name="${config.displayName}" '
      'transport=${config.transport.name} url=${config.url} '
      'command=${config.command} id=${config.id}',
    );
    if (config.isStdio) {
      await _connectStdio();
      return;
    }
    try {
      _messageUrl = Uri.parse(config.url);
      await _sendInitialize();
    } catch (e) {
      debugPrint('[MCP] streamable HTTP handshake failed: $e — trying SSE');
      try {
        await _handshakeSse();
      } catch (e2) {
        status = McpConnectionStatus.error;
        lastError = e2.toString();
        debugPrint('[MCP] handshake failure name="${config.displayName}": $e2');
        return;
      }
    }
    status = McpConnectionStatus.connected;
    debugPrint(
      '[MCP] connected name="${config.displayName}" session=${sessionId ?? "none"} '
      'messageUrl=$_messageUrl',
    );
    await listTools();
  }

  Future<void> _connectStdio() async {
    final opener = openStdio;
    if (opener == null) {
      status = McpConnectionStatus.error;
      lastError = 'stdio MCP opener missing';
      return;
    }
    try {
      _stdio = await opener(config);
      await _sendInitialize();
    } catch (e) {
      status = McpConnectionStatus.error;
      final hint = mcpHumanizeStdioError('$e', command: config.command);
      lastError = hint.isEmpty ? e.toString() : hint;
      debugPrint(
        '[MCP] stdio handshake failure name="${config.displayName}": $e',
      );
      await _stdio?.close();
      _stdio = null;
      return;
    }
    status = McpConnectionStatus.connected;
    debugPrint('[MCP] stdio connected name="${config.displayName}"');
    await listTools();
  }

  Future<void> disconnect() async {
    debugPrint('[MCP] disconnect name="${config.displayName}"');
    await _stdio?.close();
    _stdio = null;
    status = McpConnectionStatus.disconnected;
    lastError = null;
    tools = const [];
    sessionId = null;
    _messageUrl = null;
  }

  Future<List<McpToolDef>> listTools() async {
    debugPrint('[MCP] tools/list request name="${config.displayName}"');
    final msg = await _rpc(
      'tools/list',
      const {},
      timeout: kMcpHandshakeTimeout,
    );
    if (msg == null) {
      tools = const [];
      debugPrint(
        '[MCP] tools/list failed (no response) — contributing nothing',
      );
      return tools;
    }
    if (msg['error'] != null) {
      lastError = msg['error'].toString();
      tools = const [];
      status = McpConnectionStatus.error;
      debugPrint('[MCP] tools/list error: ${mcpClip(lastError!)}');
      return tools;
    }
    final result = msg['result'];
    final raw = result is Map ? result['tools'] : null;
    final parsed = <McpToolDef>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          parsed.add(McpToolDef.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    tools = parsed;
    debugPrint(
      '[MCP] tools/list response name="${config.displayName}" '
      'count=${tools.length} names=${[for (final t in tools) t.name]}',
    );
    return tools;
  }

  Future<McpCallResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    debugPrint(
      '[MCP] tools/call request name="${config.displayName}" tool=$name '
      'args="${mcpClip(jsonEncode(arguments))}"',
    );
    if (status != McpConnectionStatus.connected) {
      debugPrint(
        '[MCP] tools/call skipped — not connected '
        '(status=${status.name} error=${lastError ?? "none"})',
      );
      return const McpCallResult(ok: false, text: '', isError: true);
    }
    final msg = await _rpc('tools/call', {
      'name': name,
      'arguments': arguments,
    }, timeout: kMcpCallTimeout);
    if (msg == null) {
      debugPrint('[MCP] tools/call no response tool=$name');
      return const McpCallResult(ok: false, text: '', isError: true);
    }
    if (msg['error'] != null) {
      debugPrint(
        '[MCP] tools/call JSON-RPC error tool=$name: ${mcpClip(msg['error'].toString())}',
      );
      return const McpCallResult(ok: false, text: '', isError: true);
    }
    final result = msg['result'];
    if (result is! Map) {
      debugPrint('[MCP] tools/call empty result tool=$name');
      return const McpCallResult(ok: false, text: '');
    }
    final isError = result['isError'] == true;
    final text = _contentText(result['content']);
    debugPrint(
      '[MCP] tools/call response tool=$name ok=${!isError && text.trim().isNotEmpty} '
      'isError=$isError text="${mcpClip(text)}"',
    );
    return McpCallResult(
      ok: !isError && text.trim().isNotEmpty,
      text: text,
      isError: isError,
    );
  }

  Future<void> _sendInitialize() async {
    final init = await _rpc('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'front-porch-ai', 'version': appVersion},
    }, timeout: kMcpHandshakeTimeout);
    if (init == null || init['error'] != null) {
      throw StateError('initialize failed: ${init?['error'] ?? 'no response'}');
    }
    debugPrint(
      '[MCP] initialize result="${mcpClip(jsonEncode(init['result']))}"',
    );
    await _notify('notifications/initialized', const {});
  }

  Future<void> _handshakeSse() async {
    final uri = Uri.parse(config.url);
    debugPrint('[MCP] SSE GET $uri');
    final request = http.Request('GET', uri)
      ..headers.addAll({
        'Accept': 'text/event-stream',
        'MCP-Protocol-Version': '2025-03-26',
        ...config.headers,
      });
    final token = config.authToken.trim();
    if (token.isNotEmpty) {
      request.headers['Authorization'] =
          token.toLowerCase().startsWith('bearer ') ? token : 'Bearer $token';
    }
    final response = await mcpSend(
      request: request,
      timeout: kMcpHandshakeTimeout,
      sendRequest: sendRequest,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('SSE GET status ${response.statusCode}');
    }
    sessionId = response.sessionId ?? sessionId;
    final endpoint = sseEndpointFrom(response.body);
    if (endpoint == null || endpoint.isEmpty) {
      throw StateError('SSE handshake missing endpoint event');
    }
    final messageUrl = uri.resolve(endpoint);
    final configuredPort = uri.hasPort
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 80);
    final messagePort = messageUrl.hasPort
        ? messageUrl.port
        : (messageUrl.scheme == 'https' ? 443 : 80);
    if (messageUrl.scheme != uri.scheme ||
        messageUrl.host.toLowerCase() != uri.host.toLowerCase() ||
        messagePort != configuredPort) {
      throw StateError(
        'SSE endpoint must stay on the configured scheme, host, and port',
      );
    }
    _messageUrl = messageUrl;
    debugPrint('[MCP] SSE endpoint=$_messageUrl');
    await _sendInitialize();
  }

  Future<void> _notify(String method, Map<String, dynamic> params) async {
    final stdio = _stdio;
    if (stdio != null) {
      await stdio.notify(method, params);
      return;
    }
    final payload = {'jsonrpc': '2.0', 'method': method, 'params': params};
    debugPrint('[MCP] notify $method');
    await _post(payload, timeout: kMcpHandshakeTimeout);
  }

  Future<Map<String, dynamic>?> _rpc(
    String method,
    Map<String, dynamic> params, {
    required Duration timeout,
  }) async {
    final stdio = _stdio;
    if (stdio != null) {
      final msg = await stdio.rpc(method, params, timeout: timeout);
      if (msg == null && stdio.lastError != null) lastError = stdio.lastError;
      return msg;
    }
    final id = _nextId++;
    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
    debugPrint(
      '[MCP] RPC id=$id method=$method params="${mcpClip(jsonEncode(params))}"',
    );
    final response = await _post(payload, timeout: timeout);
    if (response == null) return null;
    if (response.sessionId != null) sessionId = response.sessionId;
    final msg = jsonRpcMessage(response, id);
    if (msg == null) {
      debugPrint('[MCP] RPC id=$id no matching JSON-RPC message');
    }
    return msg;
  }

  Future<McpHttpResponse?> _post(
    Map<String, dynamic> payload, {
    required Duration timeout,
  }) async {
    final url = _messageUrl ?? Uri.parse(config.url);
    try {
      final request = http.Request('POST', url)
        ..headers.addAll(_headers)
        ..body = jsonEncode(payload);
      debugPrint(
        '[MCP] POST $url headers=${_redactedHeaders()} '
        'body="${mcpClip(request.body)}"',
      );
      final response = await mcpSend(
        request: request,
        timeout: timeout,
        sendRequest: sendRequest,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastError = 'HTTP ${response.statusCode}';
        debugPrint('[MCP] POST failed status=${response.statusCode}');
        return null;
      }
      return response;
    } catch (e) {
      lastError = e.toString();
      debugPrint('[MCP] POST threw: $e');
      return null;
    }
  }

  Map<String, String> _redactedHeaders() {
    final out = <String, String>{};
    _headers.forEach((k, v) {
      out[k] = k.toLowerCase() == 'authorization' ? '***' : v;
    });
    return out;
  }

  static String _contentText(dynamic content) {
    if (content is String) return content;
    if (content is! List) return '';
    final buf = StringBuffer();
    for (final item in content) {
      if (item is Map) {
        final type = item['type']?.toString();
        final text = item['text']?.toString() ?? '';
        if ((type == null || type == 'text') && text.isNotEmpty) {
          if (buf.isNotEmpty) buf.write('\n');
          buf.write(text);
        }
      } else if (item is String && item.isNotEmpty) {
        if (buf.isNotEmpty) buf.write('\n');
        buf.write(item);
      }
    }
    return buf.toString();
  }
}
