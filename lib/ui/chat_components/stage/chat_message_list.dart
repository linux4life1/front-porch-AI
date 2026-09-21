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
/// Older pages grow above a [CustomScrollView] center sliver so the
/// viewport is not rewritten. Item identity is the page-owned
/// [bubbleKeyOf] when present; object identity is the Waifu fallback.
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
  static const Key _centerKey = ValueKey('transcript-center');

  ScrollController? _owned;
  String? _prevSession;
  int _prevLen = 0;
  String _prevTip = '';
  int _centerIndex = 0;

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
    final prevLen = _prevLen;
    final tip = transcriptTipKey(widget.messages);
    final kind = classifyTranscriptGrowth(
      sessionId: widget.sessionId,
      prevSession: _prevSession,
      prevLen: prevLen,
      prevTip: _prevTip,
      nextLen: widget.messages.length,
      nextTip: tip,
    );
    _centerIndex = nextTranscriptCenterIndex(
      prevCenter: _centerIndex,
      kind: kind,
      prevLen: prevLen,
      nextLen: widget.messages.length,
    );
    _prevSession = widget.sessionId;
    _prevLen = widget.messages.length;
    _prevTip = tip;
    if (kind != TranscriptGrowth.open) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _controller;
      if (c != null) pinTranscriptToLatest(c);
    });
  }

  Key _rowKey(ChatMessage msg) {
    return widget.bubbleKeyOf?.call(msg) ?? ValueKey(identityHashCode(msg));
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.padding.resolve(Directionality.of(context));
    final messages = widget.messages;
    final center = messages.isEmpty
        ? 0
        : _centerIndex.clamp(0, messages.length - 1);
    final belowCount =
        (messages.isEmpty ? 0 : messages.length - center - 1) +
        (widget.generatingImage ? 1 : 0);
    Widget row(int index) {
      final msg = messages[index];
      final (senderImage, senderColor) = widget.resolveSpeaker(msg);
      return JumpFlash(
        key: _rowKey(msg),
        flashed: identical(msg, widget.jumpFlash),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?widget.aboveBubble?.call(msg, index),
            MessageBubble(
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
            ?widget.belowBubble?.call(msg, index),
          ],
        ),
      );
    }

    return CustomScrollView(
      key: const ValueKey('transcript-listview'),
      controller: _controller,
      reverse: false,
      primary: false,
      center: messages.isEmpty ? null : _centerKey,
      scrollCacheExtent: const ScrollCacheExtent.pixels(4000),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            left: pad.left,
            right: pad.right,
            top: pad.top,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => row(center - 1 - index),
              childCount: center,
              findChildIndexCallback: (key) {
                for (var i = 0; i < center; i++) {
                  if (_rowKey(messages[i]) == key) return center - 1 - i;
                }
                return null;
              },
            ),
          ),
        ),
        if (messages.isNotEmpty)
          SliverToBoxAdapter(key: _centerKey, child: row(center)),
        SliverPadding(
          padding: EdgeInsets.only(
            left: pad.left,
            right: pad.right,
            bottom: pad.bottom,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final msgIndex = center + 1 + index;
                if (msgIndex < messages.length) return row(msgIndex);
                return const GeneratingImageBubble(
                  key: ValueKey('generating-image'),
                );
              },
              childCount: belowCount,
              findChildIndexCallback: (key) {
                for (var i = center + 1; i < messages.length; i++) {
                  if (_rowKey(messages[i]) == key) return i - center - 1;
                }
                return null;
              },
            ),
          ),
        ),
      ],
    );
  }
}
