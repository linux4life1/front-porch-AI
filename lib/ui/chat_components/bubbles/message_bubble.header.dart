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
import 'package:front_porch_ai/services/storage/settings/user_bubble_dialogue.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'theme_border_resolver.dart';

/// The message header row: Director label / sender name (with the group
/// tap-to-queue affordance) / TTS speaker button / edit / fork / delete.
/// User and character rows share one layout.
/// Takes the values the bubble's `build()` already computed rather than
/// recomputing them. The icon buttons report taps through callbacks; the
/// bubble owns the dialogs they open.
class MessageBubbleHeader extends StatelessWidget {
  const MessageBubbleHeader({
    super.key,
    required this.message,
    required this.index,
    required this.chatService,
    required this.senderColor,
    required this.character,
    required this.theme,
    required this.storage,
    required this.isDirectorNote,
    required this.onInspectPrompt,
    required this.onOtherWords,
    required this.onEdit,
    required this.onFork,
    required this.onDelete,
  });

  final ChatMessage message;
  final int index;

  /// Null outside a bound chat: no TTS, edit, fork or delete buttons.
  final ChatService? chatService;
  final Color? senderColor;
  final CharacterCard? character;
  final ResolvedThemeData theme;
  final StorageService? storage;
  final bool isDirectorNote;
  final VoidCallback onInspectPrompt;
  final VoidCallback onOtherWords;
  final VoidCallback onEdit;
  final VoidCallback onFork;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // Mirrored user row: name on the right, buttons on the left.
    final mirrored =
        message.isUser &&
        !isDirectorNote &&
        (storage?.realismSettings.userMessagesOnRight ?? false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: mirrored ? TextDirection.rtl : null,
      children: [
        if (isDirectorNote) ...[
          Icon(
            Icons.movie_creation,
            size: 14,
            color: AppColors.resolve(
              context,
              AppColors.resolve(
                context,
                const Color(0xFFFFD166),
                const Color(0xFFF59E0B),
              ),
              const Color(0xFFD97706),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Director',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: AppColors.resolve(
                context,
                AppColors.resolve(
                  context,
                  const Color(0xFFFFD166),
                  const Color(0xFFF59E0B),
                ),
                const Color(0xFFD97706),
              ),
              fontStyle: FontStyle.italic,
            ),
          ),
          const Spacer(),
        ] else ...[
          Builder(
            builder: (context) {
              final chatService = this.chatService;
              final nameWidget = Text(
                message.sender,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color:
                      senderColor ??
                      theme.accent ??
                      // Your own name sits on your bubble: same readable
                      // tint, from the same inputs, as the quotes in it.
                      (message.isUser
                          ? storage?.uiSettings.userBubbleDialogueColorFor(
                              character,
                              themePreset: theme.preset,
                              themeOverrides: theme.overrides,
                            )
                          : storage?.uiSettings.getDialogueColor(character)) ??
                      AppColors.textPrimary(context),
                ),
              );
              if (chatService != null &&
                  chatService.isGroupMode &&
                  !message.isUser) {
                return GestureDetector(
                  onTap: () {
                    final ch = resolveGroupSpeakerForMessage(
                      chatService.groupCharacters,
                      message,
                    );
                    if (ch != null) {
                      chatService.setNextCharacter(ch);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${message.sender} will respond next'),
                          duration: const Duration(seconds: 1),
                          backgroundColor:
                              senderColor ?? AppColors.porchAmberOf(context),
                        ),
                      );
                    }
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: nameWidget,
                  ),
                );
              }
              return nameWidget;
            },
          ),
          const Spacer(),
        ],
        // TTS speaker button
        if (chatService != null &&
            !message.isUser &&
            message.sender != 'System' &&
            !isDirectorNote)
          Consumer2<TtsService, StorageService>(
            builder: (context, tts, storage, _) {
              if (!storage.ttsSettings.ttsEnabled) {
                return const SizedBox.shrink();
              }
              final msgId = 'msg_$index';
              final isThisMsg = tts.currentMessageId == msgId;
              final isGeneratingThis = isThisMsg && tts.isGenerating;
              final isSpeakingThis =
                  isThisMsg && tts.isSpeaking && !tts.isGenerating;

              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: isGeneratingThis
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => tts.stop(),
                            borderRadius: BorderRadius.circular(10),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.stop_circle,
                                size: 16,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    value: tts.generationProgress > 0
                                        ? tts.generationProgress
                                        : null,
                                    strokeWidth: 2,
                                    color: AppColors.porchAmberOf(context),
                                  ),
                                ),
                                if (tts.generationProgress > 0)
                                  Text(
                                    '${(tts.generationProgress * 100).toInt()}',
                                    style: TextStyle(
                                      color: AppColors.textSecondary(context),
                                      fontSize: 7,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : IconButton(
                        icon: Icon(
                          isSpeakingThis ? Icons.stop_circle : Icons.volume_up,
                          size: 16,
                          color: isSpeakingThis
                              ? Colors.orangeAccent
                              : AppColors.textTertiary(context),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: isSpeakingThis
                            ? 'Stop speaking'
                            : 'Speak message',
                        onPressed: () {
                          if (isSpeakingThis) {
                            tts.stop();
                          } else {
                            final chatService = Provider.of<ChatService>(
                              context,
                              listen: false,
                            );
                            String? voiceKey;
                            if (chatService.activeGroup != null) {
                              final charMatch = resolveGroupSpeakerForMessage(
                                chatService.groupCharacters,
                                message,
                              );
                              voiceKey = charMatch?.ttsVoice;
                            } else {
                              voiceKey = chatService.activeCharacter?.ttsVoice;
                            }
                            tts.speak(
                              message.displayText,
                              voiceKey: voiceKey,
                              messageId: msgId,
                            );
                          }
                        },
                      ),
              );
            },
          ),
        if (chatService != null &&
            !message.isUser &&
            message.activeMetadata?[kReplyContextKey] is Map) ...[
          IconButton(
            icon: Icon(
              Icons.analytics_outlined,
              size: 16,
              color: theme.accent ?? AppColors.textTertiary(context),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Inspect prompt',
            onPressed: onInspectPrompt,
          ),
          const SizedBox(width: 8),
        ],
        if (chatService != null &&
            !message.isUser &&
            message.activeMetadata?[kTokenAltsKey] is List) ...[
          IconButton(
            icon: Icon(
              Icons.alt_route,
              size: 16,
              color: theme.accent ?? AppColors.textTertiary(context),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Other words',
            onPressed: onOtherWords,
          ),
          const SizedBox(width: 8),
        ],
        if (chatService != null && message.sender != 'System')
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              size: 16,
              color: theme.accent ?? AppColors.textTertiary(context),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Edit message',
            onPressed: onEdit,
          ),
        if (chatService != null && message.sender != 'System')
          const SizedBox(width: 8),
        if (chatService != null && message.sender != 'System')
          IconButton(
            icon: Icon(
              Icons.call_split,
              size: 16,
              color: theme.accent ?? AppColors.textTertiary(context),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Fork from here',
            onPressed: onFork,
          ),
        if (chatService != null && message.sender != 'System')
          const SizedBox(width: 8),
        if (chatService != null)
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 16,
              color: theme.accent ?? AppColors.textTertiary(context),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onDelete,
          ),
      ],
    );
  }
}

/// Speaker avatar with the message's place in the whole chat under it
/// (1-based; receipts in Journal and Growth use the same number).
class MessageBubbleAvatar extends StatelessWidget {
  const MessageBubbleAvatar({
    super.key,
    required this.message,
    required this.index,
    required this.characterImage,
    required this.chatService,
  });

  final ChatMessage message;
  final int index;
  final File? characterImage;

  /// Null outside a bound chat: no persona lookup and no message number.
  final ChatService? chatService;

  @override
  Widget build(BuildContext context) {
    final chat = chatService;
    final boundToChat = chat != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!message.isUser)
          CircleAvatar(
            radius: 16,
            // The Home card's no-portrait look; a real portrait covers it.
            backgroundColor: AppColors.surfaceContainerOf(context),
            // No portrait, or only the flat placeholder a character made
            // without one carries: the person icon.
            child: RealPortrait(
              file: characterImage,
              portrait: (_, file) => ClipOval(
                child: Image.file(
                  file,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.person,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
              ),
              noPortrait: (_) =>
                  Icon(Icons.person, color: AppColors.iconSecondary(context)),
            ),
          )
        else if (boundToChat)
          Consumer<UserPersonaService>(
            builder: (context, service, _) {
              final persona = service.personas
                  .where((p) => p.name == message.sender)
                  .firstOrNull;
              if (persona?.avatarPath != null) {
                return CircleAvatar(
                  backgroundImage: FileImage(File(persona!.avatarPath!)),
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
        else
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.porchAmberOf(context),
            child: Icon(Icons.person, color: AppColors.onChaosAccent),
          ),
        if (chat != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '#${chat.historyBasePosition + index + 1}',
              key: const Key('message-number'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
      ],
    );
  }
}
