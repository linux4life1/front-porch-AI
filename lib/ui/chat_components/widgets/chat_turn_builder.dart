// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

/// `Consumer<ChatService>` for chat chrome that never shows streamed reply
/// text (app bar, sidebar, composer, backdrop). It rebuilds on every
/// ChatService change except the ~30/s streaming-text ticks, so a streaming
/// reply rebuilds the transcript, not the whole page.
class ChatTurnBuilder extends StatefulWidget {
  const ChatTurnBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ChatService chat) builder;

  @override
  State<ChatTurnBuilder> createState() => _ChatTurnBuilderState();
}

class _ChatTurnBuilderState extends State<ChatTurnBuilder> {
  ChatService? _chat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chat = Provider.of<ChatService>(context, listen: false);
    if (identical(chat, _chat)) return;
    _chat?.removeListener(_onChange);
    _chat = chat..addListener(_onChange);
  }

  void _onChange() {
    if (!mounted || StreamTickNotify.active) return;
    setState(() {});
  }

  @override
  void dispose() {
    _chat?.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _chat!);
}
