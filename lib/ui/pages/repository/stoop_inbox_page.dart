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
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_notifications_tab.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Open the user's inbox — their single thread with the moderation team. Shares
/// [socket] (owned by the bell) so messages and typing are live.
Future<void> showStoopInbox(BuildContext context, StoopMessageSocket socket) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => StoopInboxPage(socket: socket)));
}

class StoopInboxPage extends StatefulWidget {
  final StoopMessageSocket socket;
  const StoopInboxPage({super.key, required this.socket});

  @override
  State<StoopInboxPage> createState() => _StoopInboxPageState();
}

class _StoopInboxPageState extends State<StoopInboxPage>
    with SingleTickerProviderStateMixin {
  final _api = BackporchApi();
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<StoopMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _modTyping = false;
  String? _error;

  // The one thread, split like the web hub: automated decision notices under
  // Notifications, the human conversation under Moderator chat.
  List<StoopMessage> get _notices =>
      _messages.where((m) => m.isSystem).toList();
  List<StoopMessage> get _chat =>
      _messages.where((m) => !m.isSystem).toList();

  StreamSubscription<StoopMessage>? _msgSub;
  StreamSubscription<bool>? _typingSub;
  Timer? _typingHide; // safety: hide the indicator if a "stopped" event is lost
  Timer? _typingDebounce; // stop sending "typing" after the user pauses
  bool _sentTyping = false;

  @override
  void initState() {
    super.initState();
    _load();
    _msgSub = widget.socket.onMessage.listen(_onIncoming);
    _typingSub = widget.socket.onModTyping.listen(_onModTyping);
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _typingSub?.cancel();
    _typingHide?.cancel();
    _typingDebounce?.cancel();
    if (_sentTyping) widget.socket.sendTyping(false);
    _tabs.dispose();
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _token => context.read<AuthState>().accessToken ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final msgs = await _api.myMessages(_token);
      await _api.markMessagesRead(_token); // opening the inbox clears the badge
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _jumpToBottom();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Couldn’t load your messages.';
          _loading = false;
        });
      }
    }
  }

  // A message pushed over the socket (a mod reply, a decision notice, or the
  // echo of our own send). SYSTEM notices land on the Notifications tab, so
  // only chat messages scroll the thread.
  void _onIncoming(StoopMessage m) {
    if (!mounted) return;
    if (_messages.any((x) => x.id == m.id)) return; // already shown
    setState(() {
      _messages = [..._messages, m];
      if (m.fromMod && !m.isSystem) _modTyping = false; // a reply ends typing
    });
    if (m.fromMod) _api.markMessagesRead(_token); // keep the badge clear
    if (!m.isSystem) _jumpToBottom();
  }

  void _onModTyping(bool isTyping) {
    if (!mounted) return;
    setState(() => _modTyping = isTyping);
    _typingHide?.cancel();
    if (isTyping) {
      _typingHide = Timer(
        const Duration(seconds: 6),
        () => mounted ? setState(() => _modTyping = false) : null,
      );
    }
  }

  // Enter sends; Shift+Enter drops to a new line. Intercepted above the field so
  // the newline is suppressed on a plain Enter.
  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event is KeyDownEvent &&
        isEnter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onComposerChanged(String _) {
    if (!_sentTyping) {
      widget.socket.sendTyping(true);
      _sentTyping = true;
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      widget.socket.sendTyping(false);
      _sentTyping = false;
    });
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _sending) return;
    _typingDebounce?.cancel();
    if (_sentTyping) {
      widget.socket.sendTyping(false);
      _sentTyping = false;
    }
    setState(() => _sending = true);
    try {
      final m = await _api.sendMessage(_token, body);
      if (!mounted) return;
      setState(() {
        if (!_messages.any((x) => x.id == m.id)) {
          _messages = [..._messages, m];
        }
        _reply.clear();
        _sending = false;
      });
      _jumpToBottom();
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn’t send. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = stoopAccent(context);
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimary(context),
        title: const Text('Inbox'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: accent,
          unselectedLabelColor: AppColors.textTertiary(context),
          indicatorColor: accent,
          tabs: const [
            Tab(text: 'Notifications'),
            Tab(text: 'Moderator chat'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: TextStyle(color: AppColors.textTertiary(context)),
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                StoopNotificationsTab(notices: _notices),
                Column(
                  children: [
                    Expanded(child: _chatBody()),
                    if (_modTyping) _typingIndicator(),
                    _composer(),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _chatBody() {
    final chat = _chat;
    if (chat.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 48,
                color: AppColors.iconSecondary(context),
              ),
              const SizedBox(height: 12),
              Text(
                'No messages yet',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Questions about a review or the rules? The moderation team '
                'reads this thread — you can write to them right here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textTertiary(context)),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: chat.length,
      itemBuilder: (_, i) => _bubble(chat[i]),
    );
  }

  Widget _bubble(StoopMessage m) {
    final mine = !m.fromMod; // the user's own messages sit on the right
    final accent = stoopAccent(context);
    final bg = mine
        ? accent.withValues(alpha: 0.9)
        : AppColors.surfaceContainerOf(context);
    final fg = mine ? AppColors.background : AppColors.textPrimary(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'Moderator',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            if (m.character != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  're: ${m.character!.name}',
                  style: TextStyle(
                    fontSize: 11,
                    color: fg.withValues(alpha: 0.75),
                  ),
                ),
              ),
            Text(m.body, style: TextStyle(color: fg, height: 1.3)),
          ],
        ),
      ),
    );
  }

  // The "Moderator is typing…" bubble with pulsing dots, just above the composer.
  Widget _typingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: _TypingDots(color: AppColors.textTertiary(context)),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: _handleComposerKey,
              child: TextField(
                controller: _reply,
                minLines: 1,
                maxLines: 4,
                onChanged: _onComposerChanged,
                style: TextStyle(color: AppColors.textPrimary(context)),
                decoration: InputDecoration(
                  hintText: 'Write a message…',
                  hintStyle: TextStyle(color: AppColors.textTertiary(context)),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            style: IconButton.styleFrom(
              backgroundColor: stoopAccent(context),
              foregroundColor: AppColors.background,
            ),
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

/// Three pulsing dots, for the "is typing…" bubble.
class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_c.value - i * 0.2) % 1.0;
          final op = (0.3 + 0.7 * (1 - (t - 0.5).abs() * 2)).clamp(0.3, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Opacity(
              opacity: op,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
