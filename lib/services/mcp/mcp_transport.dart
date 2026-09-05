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

const Duration kMcpHandshakeTimeout = Duration(seconds: 15);
const Duration kMcpCallTimeout = Duration(seconds: 30);

String mcpClip(String s, [int max = 400]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…';
}

/// One HTTP response after redirects have been refused.
class McpHttpResponse {
  const McpHttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.contentType,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final String contentType;

  String? get sessionId {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'mcp-session-id') return e.value;
    }
    return null;
  }

  bool get isSse => contentType.contains('text/event-stream');
  bool get isJson =>
      contentType.contains('application/json') || contentType.isEmpty;
}

/// POST or GET without following redirects. [sendRequest] is the test seam.
Future<McpHttpResponse> mcpSend({
  required http.Request request,
  required Duration timeout,
  Future<http.Response> Function(http.BaseRequest request)? sendRequest,
}) async {
  request
    ..followRedirects = false
    ..maxRedirects = 0;
  http.Response response;
  if (sendRequest != null) {
    response = await sendRequest(request).timeout(timeout);
  } else {
    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } finally {
      client.close();
    }
  }
  final contentType = response.headers['content-type'] ?? '';
  debugPrint(
    '[MCP] HTTP ${request.method} ${request.url} '
    'status=${response.statusCode} contentType=$contentType '
    'bodyChars=${response.body.length} '
    'body="${mcpClip(response.body)}"',
  );
  return McpHttpResponse(
    statusCode: response.statusCode,
    body: response.body,
    headers: response.headers,
    contentType: contentType.toLowerCase(),
  );
}

/// Parse SSE `data:` frames into JSON-RPC maps. Ignores `endpoint` events
/// except returning their data via [sseEndpointFrom].
List<Map<String, dynamic>> parseSseJsonRpc(String body) {
  final events = <Map<String, dynamic>>[];
  final dataLines = <String>[];

  void flush() {
    if (dataLines.isEmpty) return;
    final data = dataLines.join('\n');
    dataLines.clear();
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        events.add(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Non-JSON data frames (legacy `endpoint` URL) are ignored here.
    }
  }

  for (final raw in body.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.isEmpty) {
      flush();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    }
  }
  flush();
  return events;
}

/// Legacy HTTP+SSE handshake: the `endpoint` event carries the POST URL.
String? sseEndpointFrom(String body) {
  String? eventName;
  final dataLines = <String>[];
  String? endpoint;

  void flush() {
    if (dataLines.isEmpty) return;
    final data = dataLines.join('\n').trim();
    dataLines.clear();
    if (eventName == 'endpoint' && data.isNotEmpty) {
      endpoint = data;
    }
    eventName = null;
  }

  for (final raw in body.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.isEmpty) {
      flush();
    } else if (line.startsWith('event:')) {
      eventName = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    }
  }
  flush();
  return endpoint;
}

/// Pick the JSON-RPC message matching [id] from a JSON body or SSE stream.
Map<String, dynamic>? jsonRpcMessage(McpHttpResponse response, int id) {
  if (response.isSse) {
    for (final msg in parseSseJsonRpc(response.body)) {
      if (msg['id'] == id) return msg;
    }
    return null;
  }
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      if (map['id'] == id || map['id'] == null) return map;
    }
  } catch (e) {
    debugPrint('[MCP] JSON parse failed: $e body="${mcpClip(response.body)}"');
  }
  return null;
}
