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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_inbox_page.dart';

/// The Stoop app-bar notification bell. Owns the live message socket for the
/// whole Stoop session, so a new moderator message instantly bumps the badge and
/// pops a snackbar. Hands the same socket to the inbox when opened so the
/// conversation is live (messages + typing) without a second connection.
class StoopInboxBell extends StatefulWidget {
  const StoopInboxBell({super.key});

  @override
  State<StoopInboxBell> createState() => _StoopInboxBellState();
}

class _StoopInboxBellState extends State<StoopInboxBell> {
  StoopMessageSocket? _socket;
  StreamSubscription<StoopMessage>? _sub;
  bool _inboxOpen = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthState>();
    final socket = StoopMessageSocket(() => auth.accessToken ?? '');
    _socket = socket;
    _sub = socket.onMessage.listen((m) {
      // Announce a new moderator message only when the user isn't already in
      // the inbox reading it.
      if (m.fromMod && mounted && !_inboxOpen) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('New message from a moderator'),
            // Without persist:false, Flutter keeps action snackbars up forever
            // (persist defaults to `action != null`); this notice should fade
            // on its own after the default duration.
            persist: false,
            action: SnackBarAction(label: 'View', onPressed: _open),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final socket = _socket;
    if (socket == null) return;
    _inboxOpen = true;
    socket.setInboxOpen(true);
    await showStoopInbox(context, socket);
    _inboxOpen = false;
    socket.setInboxOpen(false);
  }

  @override
  Widget build(BuildContext context) {
    final socket = _socket;
    return IconButton(
      tooltip: 'Messages',
      onPressed: socket == null ? null : _open,
      icon: socket == null
          ? const Icon(Icons.notifications_none_rounded)
          : ValueListenableBuilder<int>(
              valueListenable: socket.unread,
              builder: (_, count, child) => Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: child,
              ),
              child: const Icon(Icons.notifications_none_rounded),
            ),
    );
  }
}
