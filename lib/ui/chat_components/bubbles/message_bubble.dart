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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../widgets/inline_chat_image.dart';
import 'live_thinking_timer.dart';
import 'styled_chat_message.dart';
import 'theme_border_resolver.dart';

part 'message_bubble.header.dart';
part 'message_bubble.content.dart';
part 'message_bubble.actions.dart';
part 'message_bubble.dialogs.dart';
part 'message_bubble.realism.dart';
part 'message_bubble.realism_layout.dart';

/// Message bubble widget (extracted from chat_page god file).
/// Preserves all original behavior for 1:1 + group, swipes, TTS, realism indicators, thoughts, actions, Chance Time, etc.
class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final File? characterImage;
  final int index;
  final Color? senderColor;
  final bool? externalImagesAllowed;
  final Future<bool> Function()? onRequestImagePermission;
  final CharacterCard? character;
  final ChatService? chatService;

  /// When set, drives live Thought expand (Waifu `generatingAt`). Chat
  /// leaves this null; [_thoughtOpen] then uses this message's mid-think
  /// stamps — never [ChatService.isGenerating] (that opens every
  /// historical Thought while any turn is running).
  final bool? isGenerating;

  /// Waifu Coder session theme. Chat leaves this null and reads
  /// [ChatService.sessionThemeOverrides] instead.
  final ChatThemeOverrides? themeOverrides;

  const MessageBubble({
    super.key,
    required this.message,
    this.characterImage,
    required this.index,
    this.senderColor,
    this.externalImagesAllowed,
    this.onRequestImagePermission,
    this.character,
    this.chatService,
    this.isGenerating,
    this.themeOverrides,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _thoughtExpanded = false;
  bool _thoughtPinned = false;

  ChatMessage get message => widget.message;
  File? get characterImage => widget.characterImage;
  int get index => widget.index;
  CharacterCard? get character => widget.character;

  /// Re-exposes the protected `setState` for the `part of` extensions
  /// (`message_bubble.*.dart`), which hold the header row, thought/body
  /// children, action rows, dialogs, and realism-chip rendering but can't
  /// call a State's protected members directly (settings_page.dart's
  /// `rebuildState` bridge, same pattern).
  void rebuildState(VoidCallback fn) => setState(fn);

  /// Live think auto-opens so you can watch it. A tap pins the user's
  /// choice so [isGenerating] cannot keep the body open (or shut).
  bool get _thoughtOpen {
    if (_thoughtPinned) return _thoughtExpanded;
    final live =
        widget.isGenerating ??
        (message.thinkingStartTime != null && message.thinkingDurationMs == 0);
    return live && message.hasThinking;
  }

  void _toggleThought() {
    final next = !_thoughtOpen;
    rebuildState(() {
      _thoughtPinned = true;
      _thoughtExpanded = next;
    });
  }

  bool get hasStorage {
    try {
      Provider.of<StorageService>(context, listen: false);
      return true;
    } on ProviderNotFoundException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDirectorNote = message.characterId == '__director__';
    final isChanceTimeNarration =
        message.activeMetadata?['is_chance_time_narration'] == true;
    StorageService? storage;
    try {
      storage = Provider.of<StorageService>(context);
    } on ProviderNotFoundException {
      storage = null;
    }
    final bubbleOpacity = storage?.bubbleOpacity ?? 0.95;
    final theme = storage == null
        ? ThemeBorderResolver.fallback(
            textColor: AppColors.textPrimary(context),
            borderColor: AppColors.borderOf(context),
            isUser: message.isUser,
            isDirectorNote: isDirectorNote,
          )
        : ThemeBorderResolver.resolve(
            chatService: widget.chatService,
            storage: storage,
            character: character,
            isUser: message.isUser,
            isDirectorNote: isDirectorNote,
            themeOverrides: widget.themeOverrides,
          );
    final boundToChat = widget.chatService != null;

    // Centered narration banners: Chance Time and Dreams share ONE builder
    // (the chance-time banner was inlined here before dreams arrived; the
    // extraction deletes that duplication rather than adding a parallel copy).
    if (isChanceTimeNarration) {
      return _narrationBanner(
        context,
        emoji: '🎰',
        text: message.text
            .replaceAll('[🎰 CHANCE TIME! ', '')
            .replaceAll(']', ''),
      );
    }
    if (message.activeMetadata?['is_dream'] == true) {
      return _narrationBanner(
        context,
        emoji: '🌙',
        text: '${message.sender} dreamt: ${message.text}',
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isDirectorNote
            ? MainAxisAlignment.center
            : (message.isUser
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start),
        children: [
          if (!message.isUser && !isDirectorNote)
            CircleAvatar(
              backgroundImage: characterImage != null
                  ? FileImage(characterImage!)
                  : null,
              radius: 16,
              child: characterImage == null ? const Icon(Icons.person) : null,
            ),
          if (!message.isUser && !isDirectorNote) const SizedBox(width: 12),

          Flexible(
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDirectorNote
                        ? AppColors.resolve(
                            context,
                            AppColors.resolve(
                              context,
                              const Color(0xFFFFD166),
                              const Color(0xFFF59E0B),
                            ).withValues(alpha: 0.1 * bubbleOpacity),
                            const Color(
                              0xFFD97706,
                            ).withValues(alpha: 0.12 * bubbleOpacity),
                          )
                        : message.isUser
                        ? (storage
                                  ?.getUserBubbleColor(
                                    character,
                                    theme.preset,
                                    theme.overrides,
                                  )
                                  .withValues(alpha: bubbleOpacity) ??
                              AppColors.porchAmberOf(
                                context,
                              ).withValues(alpha: 0.2))
                        : (storage
                                  ?.getAiBubbleColor(
                                    character,
                                    theme.preset,
                                    theme.overrides,
                                  )
                                  .withValues(alpha: bubbleOpacity) ??
                              AppColors.cardOf(context)),
                    borderRadius: theme.borderRadius,
                    border: isDirectorNote
                        ? Border.all(
                            color: AppColors.resolve(
                              context,
                              AppColors.resolve(
                                context,
                                const Color(0xFFFFD166),
                                const Color(0xFFF59E0B),
                              ).withValues(alpha: 0.3),
                              const Color(0xFFD97706).withValues(alpha: 0.35),
                            ),
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _headerActionsRow(
                        context,
                        theme,
                        storage,
                        isDirectorNote,
                      ),
                      ..._thoughtAndBodyChildren(context, theme),
                      if (boundToChat && index == 0 && !message.isUser)
                        _greetingSwipeRow(),
                      if (boundToChat &&
                          !message.isUser &&
                          message.sender != 'System' &&
                          message.activeMetadata?['is_generated_image'] != true)
                        _messageActionRow(),
                      if (boundToChat &&
                          !message.isUser &&
                          message.sender != 'System' &&
                          message.activeMetadata?['is_generated_image'] != true)
                        _suggestActionsColumn(theme),
                    ],
                  ),
                ),

                // Decorative only — MUST stay IgnorePointer. A CustomPaint
                // with a background painter is hit-test OPAQUE by default, so
                // without this the invisible border layer swallows every tap
                // on the bubble (edit/fork/delete, TTS, thought chips, …) for
                // all 10 theme presets. Same convention as the chat-page
                // background layers.
                if (theme.borderPainter != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: theme.borderRadius,
                        child: CustomPaint(painter: theme.borderPainter),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (message.isUser) const SizedBox(width: 12),
          if (message.isUser)
            boundToChat
                ? Consumer<UserPersonaService>(
                    builder: (context, service, _) {
                      final persona = service.personas
                          .where((p) => p.name == message.sender)
                          .firstOrNull;
                      if (persona?.avatarPath != null) {
                        return CircleAvatar(
                          backgroundImage: FileImage(
                            File(persona!.avatarPath!),
                          ),
                          radius: 16,
                        );
                      }
                      return const CircleAvatar(
                        backgroundColor: Colors.purple,
                        radius: 16,
                        child: Icon(Icons.person, color: Colors.white),
                      );
                    },
                  )
                : CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.porchAmberOf(context),
                    child: Icon(Icons.person, color: AppColors.onChaosAccent),
                  ),
        ],
      ),
    );
  }
}
