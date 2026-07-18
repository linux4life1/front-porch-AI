// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'backporch_api.dart';
import 'stoop_card.dart';
import 'stoop_message.dart';

/// Live connection to the messaging WebSocket. Owned for the whole Stoop session
/// (by the notification bell) so new moderator messages arrive instantly; the
/// inbox shares the same socket while open for live append + typing, and the
/// server also pushes live card counters (votes/downloads) down the same pipe.
/// Reconnects itself on drop, reading a fresh access token each attempt.
class StoopMessageSocket {
  final String Function() _token;
  final BackporchApi _api = BackporchApi();

  WebSocket? _ws;
  bool _disposed = false;
  bool _inboxOpen = false;
  Timer? _reconnect;

  final _messages = StreamController<StoopMessage>.broadcast();
  final _modTyping = StreamController<bool>.broadcast();

  // Card counters are global broadcast data (any vote/download, anywhere), and
  // the surfaces showing them (browse grid, detail panel, creator page) don't
  // own the socket — the bell does, and the detail panel even lives in the
  // root overlay outside the Stoop widget subtree. A static stream lets any
  // surface listen with zero plumbing; only one socket is ever live to feed it.
  static final _cardStats = StreamController<StoopCardStats>.broadcast();

  /// Unread moderator-message count, for the bell badge.
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// Every incoming message (mod or the user's own echo).
  Stream<StoopMessage> get onMessage => _messages.stream;

  /// Whether a moderator is currently typing.
  Stream<bool> get onModTyping => _modTyping.stream;

  /// Live card counter updates (net score + unique downloads), app-wide.
  static Stream<StoopCardStats> get onCardStats => _cardStats.stream;

  StoopMessageSocket(this._token) {
    _initUnread();
    _connect();
  }

  Future<void> _initUnread() async {
    final t = _token();
    if (t.isEmpty) return;
    try {
      unread.value = await _api.unreadMessageCount(t);
    } catch (_) {
      // best-effort; the socket will keep it current from here
    }
  }

  Future<void> _connect() async {
    if (_disposed) return;
    final t = _token();
    if (t.isEmpty) {
      _scheduleReconnect();
      return;
    }
    // http://host -> ws://host, https://host -> wss://host
    final wsBase = _api.baseUrl.replaceFirst('http', 'ws');
    final url = '$wsBase/ws?token=${Uri.encodeComponent(t)}';
    try {
      final ws = await WebSocket.connect(url);
      if (_disposed) {
        await ws.close();
        return;
      }
      _ws = ws;
      ws.listen(
        _onData,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _ws = null;
    if (_disposed) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 3), _connect);
  }

  void _onData(dynamic data) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(data as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (j['type']) {
      case 'message':
        final m = StoopMessage.fromJson(j['message'] as Map<String, dynamic>);
        _messages.add(m);
        // Only mod messages count toward the badge, and only when the user
        // isn't already looking at the inbox.
        if (m.fromMod && !_inboxOpen) unread.value = unread.value + 1;
        break;
      case 'typing':
        if (j['fromMod'] == true) _modTyping.add(j['isTyping'] == true);
        break;
      case 'cardStats':
        _cardStats.add(StoopCardStats.fromJson(j));
        break;
    }
  }

  /// Tell the moderator side whether the user is typing.
  void sendTyping(bool isTyping) {
    try {
      _ws?.add(jsonEncode({'type': 'typing', 'isTyping': isTyping}));
    } catch (_) {
      // a dropped socket will reconnect; a missed typing ping is harmless
    }
  }

  /// The inbox calls this on open/close: opening clears the badge and stops new
  /// messages from incrementing it.
  void setInboxOpen(bool open) {
    _inboxOpen = open;
    if (open) unread.value = 0;
  }

  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _ws?.close();
    _messages.close();
    _modTyping.close();
    unread.dispose();
  }
}
