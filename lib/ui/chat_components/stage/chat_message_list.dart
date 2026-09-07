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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/generating_image_bubble.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/message_jump.dart';

/// Reverse chat transcript of [MessageBubble]s. ChatPage owns keys, speaker
/// resolution, and the image-gen placeholder. Waifu Coder passes
/// [chatService] null so Continue / Regen / realism stay off.
class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.resolveSpeaker,
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
    this.padding = const EdgeInsets.all(20),
  });

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

  /// When set, overrides [isGenerating] per transcript index. Desk uses
  /// this so only the live loop step shows the thinking timer.
  final bool Function(int index)? generatingAt;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: padding,
      itemCount: messages.length + (generatingImage ? 1 : 0),
      itemBuilder: (context, index) {
        if (generatingImage) {
          if (index == 0) return const GeneratingImageBubble();
          index -= 1;
        }
        final reversedIndex = messages.length - 1 - index;
        final msg = messages[reversedIndex];
        final (senderImage, senderColor) = resolveSpeaker(msg);
        Widget bubble = MessageBubble(
          message: msg,
          characterImage: senderImage,
          index: reversedIndex,
          senderColor: senderColor,
          externalImagesAllowed: externalImagesAllowed,
          onRequestImagePermission: onRequestImagePermission,
          character: characterFor?.call(msg),
          chatService: chatService,
          isGenerating: generatingAt?.call(reversedIndex) ?? isGenerating,
        );
        final above = aboveBubble?.call(msg, reversedIndex);
        final extra = belowBubble?.call(msg, reversedIndex);
        if (above != null || extra != null) {
          bubble = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [?above, bubble, ?extra],
          );
        }
        final key = bubbleKeyOf?.call(msg);
        return JumpFlash(
          key: key,
          flashed: identical(msg, jumpFlash),
          child: bubble,
        );
      },
    );
  }
}
