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
import 'package:front_porch_ai/ui/chat_components/stage/transcript_window.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/generating_image_bubble.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/message_jump.dart';

/// Forward chat transcript (oldest at top, newest at bottom). Growing
/// the live bubble does not move scroll offset by itself. When follow
/// is on and the user is at the bottom, [followTranscriptWhileStreaming]
/// pins to latest after each token. Hold / absorb / reverse stay ripped.
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
    this.followStreamingReplies = true,
    this.replyStreaming = false,
    this.themeOverrides,
    this.padding = const EdgeInsets.all(20),
    this.window,
    this.onNeedOlderHistory,
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

  /// General "Follow streaming replies". Default ON.
  final bool followStreamingReplies;

  /// List-level generating flag. Not [isGenerating] — that opens Thought
  /// on every row.
  final bool replyStreaming;
  final ChatThemeOverrides? themeOverrides;
  final EdgeInsetsGeometry padding;

  /// Shared with journal jump so a receipt can mount its row first.
  /// Owned here when null (Waifu).
  final TranscriptWindow? window;

  /// Scroll hit the first mounted row and older lines still live in
  /// the database. No-op while a backfill is already running.
  final Future<void> Function()? onNeedOlderHistory;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  ScrollController? _owned;
  TranscriptWindow? _ownedWindow;
  String? _prevSession;
  String? _spanSession;
  String _spanTip = '';
  int _prevLen = 0;
  int _trackedFull = 0;
  String _prevTip = '';
  double _maxAtLastFrame = 0;
  TranscriptGrowth? _pending;
  bool _openSettled = false;
  bool _nearTop = false;
  bool _loadingOlder = false;
  bool _revealQueued = false;
  int _openPins = 0;

  ScrollController? get _controller => widget.controller ?? _owned;
  TranscriptWindow get _window => widget.window ?? _ownedWindow!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _owned = ScrollController(keepScrollOffset: false);
    }
    if (widget.window == null) _ownedWindow = TranscriptWindow();
    _applyWindow();
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
    _applyWindow();
    _noteGrowth();
  }

  void _applyWindow() {
    final next = widget.messages.length;
    final tip = transcriptTipKey(widget.messages);
    final opened = widget.sessionId != _spanSession || _trackedFull == 0;
    final prepended = !opened && next > _trackedFull && tip == _spanTip;
    _window.apply(
      previousLength: _trackedFull,
      nextLength: next,
      opened: opened,
      prepended: prepended,
      nearTop: _openSettled && _nearTop,
    );
    if (opened) {
      _openSettled = false;
      _openPins = 0;
      _nearTop = false;
    }
    _trackedFull = next;
    _spanTip = tip;
    _spanSession = widget.sessionId;
  }

  int get _start {
    final n = widget.messages.length;
    if (n == 0) return 0;
    final start = _window.start;
    return start < 0 ? 0 : (start > n ? n : start);
  }

  int get _end {
    final n = widget.messages.length;
    final start = _start;
    final end = _window.end;
    if (end < start) return start;
    return end > n ? n : end;
  }

  void _noteGrowth() {
    final start = _start;
    final end = _end;
    final visible = start == 0 && end == widget.messages.length
        ? widget.messages
        : widget.messages.sublist(start, end);
    final tip = transcriptTipKey(visible);
    final kind = classifyTranscriptGrowth(
      sessionId: widget.sessionId,
      prevSession: _prevSession,
      prevLen: _prevLen,
      prevTip: _prevTip,
      nextLen: visible.length,
      nextTip: tip,
    );
    _prevSession = widget.sessionId;
    _prevLen = visible.length;
    _prevTip = tip;
    if (kind != TranscriptGrowth.other) _pending = kind;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _controller;
      final pending = _pending;
      applyTranscriptGrowth(c, pending: pending, previousMax: _maxAtLastFrame);
      if (pending == TranscriptGrowth.open) {
        _settleOpenPin();
      } else if (pending == null || pending == TranscriptGrowth.other) {
        followTranscriptWhileStreaming(
          c,
          followEnabled: widget.followStreamingReplies,
          generating: widget.replyStreaming,
          previousMax: _maxAtLastFrame,
        );
        _openSettled = true;
      } else {
        _openSettled = true;
      }
      _pending = null;
      if (c != null && c.hasClients) {
        _maxAtLastFrame = c.position.maxScrollExtent;
      }
    });
  }

  /// One jump lands on the laid-out estimate. A short tail is fully
  /// known after a few more jumps; then the reader is at the latest line.
  void _settleOpenPin() {
    final c = _controller;
    if (!mounted) return;
    if (c == null || !c.hasClients) {
      if (_openPins < 8) {
        _openPins++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _settleOpenPin();
        });
        return;
      }
      _openSettled = true;
      return;
    }
    final max = c.position.maxScrollExtent;
    if (max - c.offset > 1 && _openPins < 8) {
      _openPins++;
      c.jumpTo(max);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _settleOpenPin();
      });
      return;
    }
    _openPins = 0;
    _openSettled = true;
    _nearTop = false;
    _maxAtLastFrame = max;
  }

  void _onScroll(ScrollNotification notification) {
    if (!_openSettled) return;
    if (notification.metrics.axis != Axis.vertical) return;
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return;
    }
    _nearTop = notification.metrics.pixels <= 64;
    // One page per time the reader settles at the top. Revealing on
    // every drag update would mount the whole archive in one fling.
    if (notification is! ScrollEndNotification) return;
    if (!_nearTop || _loadingOlder || _revealQueued) return;
    if (_window.start > 0) {
      _revealQueued = true;
      _window.revealOlder(widget.messages.length);
      setState(_noteGrowth);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _revealQueued = false;
      });
      return;
    }
    final load = widget.onNeedOlderHistory;
    if (load == null) return;
    _loadingOlder = true;
    load().whenComplete(() {
      if (mounted) _loadingOlder = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    final visibleCount = _end - start;
    final scrollBehavior = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _onScroll(notification);
        return false;
      },
      child: ScrollConfiguration(
        behavior: scrollBehavior,
        child: Scrollbar(
          controller: _controller,
          interactive: true,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 12,
          radius: const Radius.circular(6),
          notificationPredicate: (notification) => notification.depth == 0,
          child: ListView.builder(
            key: const ValueKey('transcript-listview'),
            controller: _controller,
            reverse: false,
            primary: false,
            scrollCacheExtent: const ScrollCacheExtent.pixels(4000),
            padding: widget.padding,
            itemCount: visibleCount + (widget.generatingImage ? 1 : 0),
            itemBuilder: (context, index) {
              if (widget.generatingImage && index == visibleCount) {
                return const GeneratingImageBubble();
              }
              final messageIndex = start + index;
              final msg = widget.messages[messageIndex];
              return _row(msg, messageIndex);
            },
          ),
        ),
      ),
    );
  }

  Widget _row(ChatMessage msg, int index) {
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
          isGenerating: widget.generatingAt?.call(index) ?? widget.isGenerating,
          followStreamingReplies: widget.followStreamingReplies,
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
  }
}
