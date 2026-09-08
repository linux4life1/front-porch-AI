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
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/mcp/mcp_models.dart';
import 'package:front_porch_ai/services/mcp/mcp_transport.dart';

/// Opens one stdio MCP session. Test seam — production uses [McpStdioSession.spawn].
typedef McpStdioOpener =
    Future<McpStdioSession> Function(McpServerConfig config);

/// JSON-RPC over newline-delimited stdin/stdout. Process.start lives here
/// so the HTTP client files keep their no-spawn pin.
class McpStdioSession {
  McpStdioSession({
    required Stream<List<int>> stdout,
    required void Function(List<int> bytes) write,
    Future<void> Function()? flush,
    void Function()? kill,
    Stream<List<int>>? stderr,
  }) : _write = write,
       _flush = flush,
       _kill = kill {
    _stdoutSub = stdout.listen(
      _onChunk,
      onError: (_) => _onDead('stdio MCP stdout failed'),
      onDone: () => _onDead('stdio MCP process exited'),
    );
    if (stderr != null) {
      _stderrSub = stderr.listen((chunk) {
        _stderr.write(utf8.decode(chunk, allowMalformed: true));
      });
    }
  }

  final void Function(List<int> bytes) _write;
  final Future<void> Function()? _flush;
  final void Function()? _kill;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _buf = StringBuffer();
  final _stderr = StringBuffer();
  var _nextId = 1;
  var _closed = false;
  String? lastError;

  String get stderrText => _stderr.toString();

  Future<Map<String, dynamic>?> rpc(
    String method,
    Map<String, dynamic> params, {
    required Duration timeout,
  }) async {
    if (_closed) return null;
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
    debugPrint(
      '[MCP] stdio RPC id=$id method=$method '
      'params="${mcpClip(jsonEncode(params))}"',
    );
    try {
      _write(utf8.encode('${jsonEncode(payload)}\n'));
      await _flush?.call();
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      lastError = 'stdio MCP timed out on $method';
      debugPrint('[MCP] stdio RPC id=$id timeout');
      return null;
    } catch (e) {
      _pending.remove(id);
      lastError = e.toString();
      debugPrint('[MCP] stdio RPC id=$id threw: $e');
      return null;
    }
  }

  Future<void> notify(String method, Map<String, dynamic> params) async {
    if (_closed) return;
    final payload = {'jsonrpc': '2.0', 'method': method, 'params': params};
    debugPrint('[MCP] stdio notify $method');
    _write(utf8.encode('${jsonEncode(payload)}\n'));
    await _flush?.call();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _failPending('stdio MCP closed');
    try {
      _kill?.call();
    } catch (e) {
      debugPrint('[MCP] stdio kill: $e');
    }
  }

  void _onChunk(List<int> chunk) {
    _buf.write(utf8.decode(chunk, allowMalformed: true));
    var text = _buf.toString();
    while (true) {
      final nl = text.indexOf('\n');
      if (nl < 0) break;
      final line = text.substring(0, nl).trim();
      text = text.substring(nl + 1);
      if (line.isNotEmpty) _onLine(line);
    }
    _buf
      ..clear()
      ..write(text);
  }

  void _onLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final id = map['id'];
      if (id is int) {
        _pending.remove(id)?.complete(map);
      } else if (id is num) {
        _pending.remove(id.toInt())?.complete(map);
      }
    } catch (e) {
      debugPrint('[MCP] stdio parse failed: $e line="${mcpClip(line)}"');
    }
  }

  void _onDead(String reason) {
    lastError = _stderr.toString().trim().isEmpty
        ? reason
        : mcpClip(_stderr.toString());
    debugPrint('[MCP] stdio dead: $lastError');
    _failPending(lastError!);
  }

  void _failPending(String reason) {
    final waiting = Map<int, Completer<Map<String, dynamic>>>.from(_pending);
    _pending.clear();
    for (final c in waiting.values) {
      if (!c.isCompleted) {
        c.completeError(StateError(reason));
      }
    }
  }
}
