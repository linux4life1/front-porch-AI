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
import 'package:web_socket_channel/web_socket_channel.dart';

/// Single multiplexed WebSocket fan-out for the web server.
///
/// One authenticated socket with a typed event envelope carries everything the
/// old per-feature SSE channels used to (chat tokens, chargen progress,
/// story-pipeline progress). The browser sends the HttpOnly session cookie on
/// the upgrade, so there is no `?token=` in the URL.
///
/// Depends only on a token [Stream] + an `isGenerating` probe (not the whole
/// ChatService) so it stays unit-testable. Chargen/story progress are pushed
/// via [broadcast] from their facades.
class StreamHub {
  StreamHub(Stream<String> tokenStream, this._isGenerating) {
    _tokenSub = tokenStream.listen(_onToken);
  }

  final bool Function() _isGenerating;
  final Set<WebSocketChannel> _clients = {};
  StreamSubscription<String>? _tokenSub;

  int get clientCount => _clients.length;

  /// Register a freshly-upgraded socket. The auth middleware has already
  /// validated the session cookie before the upgrade reaches here.
  void register(WebSocketChannel channel) {
    _clients.add(channel);
    _send(channel, {'event': 'connected'});
    if (_isGenerating()) _send(channel, {'event': 'generating'});
    channel.stream.listen(
      (msg) => _onClientMessage(channel, msg),
      onDone: () => _clients.remove(channel),
      onError: (_) => _clients.remove(channel),
      cancelOnError: true,
    );
    debugPrint('[StreamHub] client connected (${_clients.length} total)');
  }

  /// Broadcast a chat-state-changed signal (after send/stop/select/etc.).
  void broadcastChatUpdate() => broadcast({'event': 'chat_updated'});

  /// Broadcast an arbitrary typed event to every connected client.
  void broadcast(Map<String, dynamic> event) {
    if (_clients.isEmpty) return;
    final encoded = jsonEncode(event);
    final dead = <WebSocketChannel>[];
    for (final c in _clients) {
      try {
        c.sink.add(encoded);
      } catch (_) {
        dead.add(c);
      }
    }
    for (final d in dead) {
      _clients.remove(d);
    }
  }

  void _onToken(String token) {
    if (token == '__DONE__') {
      broadcast({'event': 'done'});
    } else if (token == '__ERROR__') {
      broadcast({'event': 'error'});
    } else {
      broadcast({'event': 'token', 'data': token});
    }
  }

  void _onClientMessage(WebSocketChannel channel, dynamic raw) {
    if (raw is! String) return;
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['type'] == 'ping') {
        _send(channel, {'event': 'pong'});
      }
      // Other inbound control messages (subscribe/stop) are added in Phase 3
      // alongside the chat facade.
    } catch (_) {
      // Ignore malformed client frames.
    }
  }

  void _send(WebSocketChannel channel, Map<String, dynamic> event) {
    try {
      channel.sink.add(jsonEncode(event));
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    _tokenSub = null;
    // Copy first: closing a sink fires its onDone, which mutates _clients.
    for (final c in _clients.toList()) {
      try {
        await c.sink.close();
      } catch (_) {}
    }
    _clients.clear();
  }
}
