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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';
import 'package:front_porch_ai/ui/chat_components/stage/transcript_auto_scroll.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/generating_image_bubble.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/message_jump.dart';

/// Forward chat transcript (oldest at top, newest at bottom). Growing
/// the live bubble does not move scroll offset — that is the per-token
/// chase a reverse list at 0 cannot avoid without the ripped hold.
///
/// Item identity is the page-owned [bubbleKeyOf] when present.
/// Chronological ValueKey is the Waifu fallback only.
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.resolveSpeaker,
    this.sessionId,
    this.controller,
    this.characterFor,
    this.chatService,
    this.bubbleKeyOf,
    this.jumpFlash,
    this.generatingImage = false,
    this.externalImagesAllowed,
    this.onRequestImagePermission,
    this.aboveBubble,
    this.belowBubble,
    this.isGenerating,
    this.generatingAt,
    this.themeOverrides,
    this.padding = const EdgeInsets.all(20),
  });

  final String? sessionId;
  final List<ChatMessage> messages;
  final ScrollController? controller;
  final (File?, Color?) Function(ChatMessage message) resolveSpeaker;
  final CharacterCard? Function(ChatMessage message)? characterFor;
  final ChatService? chatService;
  final GlobalKey Function(ChatMessage message)? bubbleKeyOf;
  final ChatMessage? jumpFlash;
  final bool generatingImage;
  final bool? externalImagesAllowed;
  final Future<bool> Function()? onRequestImagePermission;
  final Widget? Function(ChatMessage message, int index)? aboveBubble;
  final Widget? Function(ChatMessage message, int index)? belowBubble;
  final bool? isGenerating;
  final bool Function(int index)? generatingAt;
  final ChatThemeOverrides? themeOverrides;
  final EdgeInsetsGeometry padding;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  ScrollController? _owned;
  String? _prevSession;
  int _prevLen = 0;
  String _prevTip = '';
  double _maxAtLastFrame = 0;
  TranscriptGrowth? _pending;

  ScrollController? get _controller => widget.controller ?? _owned;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _owned = ScrollController(keepScrollOffset: false);
    }
    _noteGrowth();
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChatMessageList old) {
    super.didUpdateWidget(old);
    _noteGrowth();
  }

  void _noteGrowth() {
    final tip = transcriptTipKey(widget.messages);
    final kind = classifyTranscriptGrowth(
      sessionId: widget.sessionId,
      prevSession: _prevSession,
      prevLen: _prevLen,
      prevTip: _prevTip,
      nextLen: widget.messages.length,
      nextTip: tip,
    );
    _prevSession = widget.sessionId;
    _prevLen = widget.messages.length;
    _prevTip = tip;
    if (kind != TranscriptGrowth.other) _pending = kind;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _controller;
      applyTranscriptGrowth(c, pending: _pending, previousMax: _maxAtLastFrame);
      _pending = null;
      if (c != null && c.hasClients) {
        _maxAtLastFrame = c.position.maxScrollExtent;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const ValueKey('transcript-listview'),
      controller: _controller,
      reverse: false,
      primary: false,
      scrollCacheExtent: const ScrollCacheExtent.pixels(4000),
      padding: widget.padding,
      itemCount: widget.messages.length + (widget.generatingImage ? 1 : 0),
      itemBuilder: (context, index) {
        if (widget.generatingImage && index == widget.messages.length) {
          return const GeneratingImageBubble();
        }
        final msg = widget.messages[index];
        final (senderImage, senderColor) = widget.resolveSpeaker(msg);
        final above = widget.aboveBubble?.call(msg, index);
        final extra = widget.belowBubble?.call(msg, index);
        final identityKey = widget.bubbleKeyOf?.call(msg);
        final bubble = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?above,
            MessageBubble(
              key: identityKey == null
                  ? ValueKey('bubble-$index-${msg.isUser}')
                  : null,
              message: msg,
              characterImage: senderImage,
              index: index,
              senderColor: senderColor,
              externalImagesAllowed: widget.externalImagesAllowed,
              onRequestImagePermission: widget.onRequestImagePermission,
              character: widget.characterFor?.call(msg),
              chatService: widget.chatService,
              isGenerating:
                  widget.generatingAt?.call(index) ?? widget.isGenerating,
              themeOverrides: widget.themeOverrides,
            ),
            ?extra,
          ],
        );
        return JumpFlash(
          key: identityKey ?? ValueKey('bubble-$index-${msg.isUser}'),
          flashed: identical(msg, widget.jumpFlash),
          child: bubble,
        );
      },
    );
  }
}
