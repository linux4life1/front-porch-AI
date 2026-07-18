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
import 'package:front_porch_ai/services/chat/realism_verification.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../widgets/inline_chat_image.dart';
import 'styled_chat_message.dart';

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
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _thoughtExpanded = false;

  ChatMessage get message => widget.message;
  File? get characterImage => widget.characterImage;
  int get index => widget.index;
  CharacterCard? get character => widget.character;

  @override
  Widget build(BuildContext context) {
    final isDirectorNote = message.characterId == '__director__';
    final isChanceTimeNarration =
        message.activeMetadata?['is_chance_time_narration'] == true;
    final bubbleOpacity = Provider.of<StorageService>(context).bubbleOpacity;
    final storage = Provider.of<StorageService>(context);

    // Chance Time narrations get a special centered banner
    if (isChanceTimeNarration) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.resolve(
              context,
              const Color(0xFFFFD166).withValues(alpha: 0.12),
              const Color(0xFFF59E0B).withValues(alpha: 0.18),
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.resolve(
                context,
                const Color(0xFFFFD166).withValues(alpha: 0.35),
                const Color(0xFFF59E0B).withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎰', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.text
                      .replaceAll('[🎰 CHANCE TIME! ', '')
                      .replaceAll(']', ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.resolve(
                      context,
                      const Color(0xFFFFD166),
                      const Color(0xFFB45309),
                    ),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
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
            child: Container(
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
                    ? storage
                          .getUserBubbleColor(character)
                          .withValues(alpha: bubbleOpacity)
                    : storage
                          .getAiBubbleColor(character)
                          .withValues(alpha: bubbleOpacity),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: message.isUser && !isDirectorNote
                      ? const Radius.circular(12)
                      : Radius.zero,
                  bottomRight: message.isUser && !isDirectorNote
                      ? Radius.zero
                      : const Radius.circular(12),
                ),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
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
                      ] else if (!message.isUser) ...[
                        Builder(
                          builder: (context) {
                            final chatService = Provider.of<ChatService>(
                              context,
                              listen: false,
                            );
                            final nameWidget = Text(
                              message.sender,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color:
                                    widget.senderColor ??
                                    storage.getDialogueColor(character),
                              ),
                            );
                            if (chatService.isGroupMode) {
                              return GestureDetector(
                                onTap: () {
                                  final ch = chatService.groupCharacters
                                      .where((c) => c.name == message.sender)
                                      .firstOrNull;
                                  if (ch != null) {
                                    chatService.setNextCharacter(ch);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${message.sender} will respond next',
                                        ),
                                        duration: const Duration(seconds: 1),
                                        backgroundColor:
                                            widget.senderColor ??
                                            AppColors.porchAmberOf(context),
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
                      if (!message.isUser &&
                          message.sender != 'System' &&
                          !isDirectorNote)
                        Consumer2<TtsService, StorageService>(
                          builder: (context, tts, storage, _) {
                            if (!storage.ttsEnabled) {
                              return const SizedBox.shrink();
                            }
                            final msgId = 'msg_${widget.index}';
                            final isThisMsg = tts.currentMessageId == msgId;
                            final isGeneratingThis =
                                isThisMsg && tts.isGenerating;
                            final isSpeakingThis =
                                isThisMsg &&
                                tts.isSpeaking &&
                                !tts.isGenerating;

                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: isGeneratingThis
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () => tts.stop(),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                                  value:
                                                      tts.generationProgress > 0
                                                      ? tts.generationProgress
                                                      : null,
                                                  strokeWidth: 2,
                                                  color: AppColors.porchAmberOf(
                                                    context,
                                                  ),
                                                ),
                                              ),
                                              if (tts.generationProgress > 0)
                                                Text(
                                                  '${(tts.generationProgress * 100).toInt()}',
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.textSecondary(
                                                          context,
                                                        ),
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
                                        isSpeakingThis
                                            ? Icons.stop_circle
                                            : Icons.volume_up,
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
                                          final chatService =
                                              Provider.of<ChatService>(
                                                context,
                                                listen: false,
                                              );
                                          String? voiceKey;
                                          if (chatService.activeGroup != null) {
                                            final charMatch = chatService
                                                .groupCharacters
                                                .where(
                                                  (c) =>
                                                      c.name == message.sender,
                                                )
                                                .firstOrNull;
                                            voiceKey = charMatch?.ttsVoice;
                                          } else {
                                            voiceKey = chatService
                                                .activeCharacter
                                                ?.ttsVoice;
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
                      if (message.sender != 'System')
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: AppColors.textTertiary(context),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Edit message',
                          onPressed: () => _showEditDialog(context, index),
                        ),
                      if (message.sender != 'System') const SizedBox(width: 8),
                      if (message.sender != 'System')
                        IconButton(
                          icon: Icon(
                            Icons.call_split,
                            size: 16,
                            color: AppColors.textTertiary(context),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Fork from here',
                          onPressed: () =>
                              _showForkConfirmation(context, index),
                        ),
                      if (message.sender != 'System') const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: AppColors.textTertiary(context),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () =>
                            _showDeleteConfirmation(context, index),
                      ),
                    ],
                  ),
                  if (!message.isUser) const SizedBox(height: 4),
                  // Collapsible Thought chip
                  if (!message.isUser && message.hasThinking)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _thoughtExpanded = !_thoughtExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _thoughtExpanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 20,
                              color: AppColors.textSecondary(context),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.resolve(
                                  context,
                                  const Color(0xFF2A4A5A),
                                  const Color(0xFFE0F2FE),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Thought',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.tealAccent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                              color: AppColors.resolve(
                                context,
                                AppColors.resolve(
                                  context,
                                  Colors.amber,
                                  const Color(0xFFB45309),
                                ),
                                const Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Expanded thinking details
                  if (!message.isUser &&
                      message.hasThinking &&
                      _thoughtExpanded)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8, left: 20),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.resolve(
                          context,
                          const Color(0xFF1A2A3A),
                          const Color(0xFFE0F2FE),
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (message.thinkingDurationMs > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                'Thought for ${(message.thinkingDurationMs / 1000).toStringAsFixed(1)}s',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.tealAccent,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          if (message.thinkingContent != null)
                            Text(
                              message.thinkingContent!,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                  // Live thinking timer
                  if (!message.isUser &&
                      message.thinkingStartTime != null &&
                      message.thinkingDurationMs == 0)
                    Consumer<ChatService>(
                      builder: (context, chatService, _) {
                        if (!chatService.isGenerating) {
                          return const SizedBox.shrink();
                        }
                        final elapsed =
                            DateTime.now().millisecondsSinceEpoch -
                            message.thinkingStartTime!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.tealAccent,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Thinking ${(elapsed / 1000).toStringAsFixed(0)}s...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary(context),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  StyledChatMessage(
                    text: message.displayText,
                    isUser: message.isUser,
                    externalImagesAllowed: widget.externalImagesAllowed,
                    onRequestImagePermission: widget.onRequestImagePermission,
                    character:
                        widget.character ?? widget.chatService?.activeCharacter,
                  ),
                  // Locally generated image (from /image or the Image Studio's
                  // "Send to chat") — click to zoom, right-click to save.
                  if (message.activeMetadata?['image_path'] is String)
                    InlineChatImage(
                      path: message.activeMetadata!['image_path'] as String,
                      prompt:
                          message.activeMetadata!['image_prompt'] as String?,
                    ),
                  if (message.activeMetadata != null)
                    _buildRealismIndicator(message.activeMetadata!),
                  // Swipe arrows for alternate greetings on first message
                  if (index == 0 && !message.isUser)
                    Consumer<ChatService>(
                      builder: (context, chatService, _) {
                        final character = chatService.activeCharacter;
                        if (character == null) return const SizedBox.shrink();
                        final allGreetings = character.allGreetings;
                        if (allGreetings.length <= 1) {
                          return const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              InkWell(
                                onTap: () => chatService.cycleGreeting(-1),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.chevron_left,
                                    size: 20,
                                    color: AppColors.textSecondary(context),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${chatService.greetingIndex + 1}/${allGreetings.length}',
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => chatService.cycleGreeting(1),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: AppColors.textSecondary(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  // Action buttons: regen, continue, swipe arrows.
                  // Generated-image messages carry no regenerable text, so the
                  // text-generation actions are hidden for them (regen would
                  // stream prose into an image bubble).
                  if (!message.isUser &&
                      message.sender != 'System' &&
                      message.activeMetadata?['is_generated_image'] != true)
                    Consumer<ChatService>(
                      builder: (context, chatService, _) {
                        final isLastBotMessage =
                            index == chatService.messages.length - 1 &&
                            !chatService.isGenerating;
                        final hasSwipes = message.swipes.length > 1;
                        // This host (main character) message is buried under one
                        // or more Scene Guest (Lite NPC) replies, so the normal
                        // last-message regen can't reach it. Offer a regen that
                        // first removes those stale guest replies. (By definition
                        // this is never the last message.)
                        final isRegenHostBelowGuests =
                            index ==
                                chatService.regenerableHostBelowGuestsIndex &&
                            !chatService.isGenerating;

                        // Nothing to show if not last message, no swipes, and not
                        // a host buried under guest replies.
                        if (!isLastBotMessage &&
                            !hasSwipes &&
                            !isRegenHostBelowGuests) {
                          return const SizedBox.shrink();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Regen the main character even though a Lite NPC
                              // spoke after it — pops the NPC's now-stale reply,
                              // regenerates this message, then lets the NPC chime
                              // again only if still relevant.
                              if (isRegenHostBelowGuests) ...[
                                Tooltip(
                                  message:
                                      'Regenerate main character\n(removes the NPC’s reply)',
                                  child: InkWell(
                                    onTap: () =>
                                        chatService.regenerateMainCharacter(),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.refresh,
                                        size: 20,
                                        color: AppColors.resolve(
                                          context,
                                          Colors.orangeAccent,
                                          Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (hasSwipes) const SizedBox(width: 12),
                              ],
                              // Regen button — last bot message only
                              if (isLastBotMessage) ...[
                                Tooltip(
                                  message: 'Regenerate',
                                  child: InkWell(
                                    onTap: () =>
                                        chatService.regenerateLastMessage(),
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.refresh,
                                        size: 20,
                                        color: Colors.orangeAccent,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Continue button
                                Tooltip(
                                  message: 'Continue generation',
                                  child: InkWell(
                                    onTap: () =>
                                        chatService.continueGeneration(),
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.arrow_downward,
                                        size: 20,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                ),
                                if (hasSwipes) const SizedBox(width: 12),
                              ],
                              // Swipe arrows — only when multiple swipes exist
                              if (hasSwipes) ...[
                                InkWell(
                                  onTap: () =>
                                      chatService.swipeMessage(index, -1),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.chevron_left,
                                      size: 20,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${message.swipeIndex + 1}/${message.swipes.length}',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () =>
                                      chatService.swipeMessage(index, 1),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  // Suggest actions button + action pills (last bot message only;
                  // hidden for generated-image messages like the regen row above)
                  if (!message.isUser &&
                      message.sender != 'System' &&
                      message.activeMetadata?['is_generated_image'] != true)
                    Consumer<ChatService>(
                      builder: (context, chatService, _) {
                        final isLast =
                            index == chatService.messages.length - 1 &&
                            !chatService.isGenerating;
                        if (!isLast) return const SizedBox.shrink();

                        final actions = chatService.suggestedActions;
                        final isGenerating = chatService.isGeneratingActions;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // "Suggest actions" button
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: InkWell(
                                onTap: isGenerating
                                    ? null
                                    : () => chatService.generateActions(),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isGenerating)
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: AppColors.textTertiary(
                                              context,
                                            ),
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.lightbulb_outline,
                                          size: 13,
                                          color: Colors.white30,
                                        ),
                                      const SizedBox(width: 5),
                                      Text(
                                        isGenerating
                                            ? 'Thinking...'
                                            : 'Suggest actions',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white30,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Action pills
                            if (actions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: actions.map((action) {
                                    return InkWell(
                                      onTap: () =>
                                          chatService.sendMessage(action),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.06,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white12,
                                          ),
                                        ),
                                        child: Text(
                                          action,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          if (message.isUser) const SizedBox(width: 12),
          if (message.isUser)
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
            ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, int index) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Delete Message'),
        content: const Text(
          'This can\'t be undone. Are you sure you want to delete this message?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              chatService.deleteMessage(index);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showForkConfirmation(BuildContext context, int index) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: Row(
          children: const [
            Icon(Icons.call_split, color: AppColors.formMasterAccent, size: 22),
            SizedBox(width: 8),
            Text('Fork Conversation'),
          ],
        ),
        content: Text(
          'Create a new branch from message #${index + 1}?\n\nThe current chat will remain unchanged. A new conversation will be created with messages up to this point.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              chatService.forkFromMessage(index);
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Conversation forked! You are now on the new branch.',
                    ),
                  ),
                );
              }
            },
            icon: Icon(Icons.call_split, size: 18),
            label: const Text('Fork'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealismIndicator(Map<String, dynamic> metadata) {
    final bondDelta = metadata['bond_delta'] as int? ?? 0;
    final emotionLabel = metadata['emotion_label'] as String? ?? '';
    final arousalDelta = metadata['arousal_delta'] as int? ?? 0;
    final trustDelta = metadata['trust_delta'] as int? ?? 0;
    final bondReason = metadata['bond_reason'] as String? ?? '';
    final trustReason = metadata['trust_reason'] as String? ?? '';
    final timeSkipTo = metadata['time_skip_to'] as String? ?? '';
    final chanceTimeEvent = metadata['chance_time_event'] as String? ?? '';
    final timeReversal = metadata['time_reversal'] as bool? ?? false;
    final needsDeltas = metadata['needs_deltas'] as Map<String, dynamic>?;

    // Verifier result (attached by realism_verification leaf when feature active for the turn).
    // status: 'accepted' | 'corrected'; passes: reprocess count; reason optional for tooltip.
    final verifData =
        metadata[RealismVerification.kMetaKey] as Map<String, dynamic>?;
    final verifStatus = (verifData?['status'] as String? ?? '').trim();
    final verifPasses = (verifData?['passes'] as num?)?.toInt() ?? 0;
    final verifReason = (verifData?['reason'] as String? ?? '').trim();

    if ((needsDeltas == null || needsDeltas.isEmpty) &&
        bondDelta == 0 &&
        emotionLabel.isEmpty &&
        arousalDelta == 0 &&
        trustDelta == 0 &&
        timeSkipTo.isEmpty &&
        chanceTimeEvent.isEmpty &&
        !timeReversal &&
        verifStatus.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget maybeTooltip(Widget child, String tip) {
      if (tip.isEmpty) return child;
      return Tooltip(
        message: tip,
        preferBelow: false,
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: child,
      );
    }

    final chips = <Widget>[];

    // ── Needs Simulation Chips (deltas + reasons) — built into a separate list
    // so we can render them on their own row underneath the classic realism chips.
    final List<Widget> needsChipList = [];

    if (needsDeltas != null && needsDeltas.isNotEmpty) {
      needsDeltas.forEach((need, data) {
        final delta = (data is Map) ? (data['delta'] as int? ?? 0) : 0;
        if (delta == 0) {
          return; // only show needs that actually changed this turn (avoids "Bladder 0" clutter; mirrors bond/trust/lust skipping 0s)
        }
        final reason = (data is Map) ? (data['reason'] as String? ?? '') : '';

        IconData icon;
        Color color;
        String label = need[0].toUpperCase() + need.substring(1);

        switch (need) {
          case 'hunger':
            icon = Icons.restaurant;
            color = AppColors.resolve(
              context,
              Colors.orangeAccent,
              const Color(0xFFEA580C),
            );
            break;
          case 'bladder':
            icon = Icons.water_drop;
            color = Colors.lightBlueAccent;
            break;
          case 'energy':
            icon = Icons.bolt;
            color = AppColors.resolve(
              context,
              const Color(0xFFD97706),
              const Color(0xFFB45309),
            );
            break;
          case 'social':
            icon = Icons.people;
            color = Colors.pinkAccent;
            break;
          case 'fun':
            icon = Icons.celebration;
            color = AppColors.resolve(
              context,
              AppColors.resolve(
                context,
                Colors.deepPurpleAccent,
                const Color(0xFF7C3AED),
              ),
              const Color(0xFF7C3AED),
            );
            break;
          case 'hygiene':
            icon = Icons.shower;
            color = Colors.cyanAccent;
            break;
          case 'comfort':
            icon = Icons.chair;
            color = Colors.greenAccent;
            break;
          default:
            icon = Icons.circle;
            color = Colors.grey;
        }

        final chip = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              '$label ${delta > 0 ? '+$delta' : '$delta'}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.info_outline,
                size: 10,
                color: AppColors.textTertiary(context),
              ),
            ],
          ],
        );

        needsChipList.add(maybeTooltip(chip, reason));
      });
    }

    if (bondDelta != 0) {
      final chip = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            bondDelta > 0 ? Icons.favorite : Icons.heart_broken,
            size: 11,
            color: bondDelta > 0 ? Colors.pinkAccent : Colors.redAccent,
          ),
          const SizedBox(width: 4),
          Text(
            'Bond: ${bondDelta > 0 ? '+$bondDelta' : '$bondDelta'}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: bondDelta > 0 ? Colors.pinkAccent : Colors.redAccent,
            ),
          ),
          if (bondReason.isNotEmpty) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: 10,
              color: AppColors.textTertiary(context),
            ),
          ],
        ],
      );
      chips.add(maybeTooltip(chip, bondReason));
    }

    if (emotionLabel.isNotEmpty) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology, size: 11, color: Colors.purpleAccent),
            const SizedBox(width: 4),
            Text(
              'Mood: $emotionLabel',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.purpleAccent,
              ),
            ),
          ],
        ),
      );
    }

    if (arousalDelta != 0) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              arousalDelta > 0 ? Icons.local_fire_department : Icons.ac_unit,
              size: 11,
              color: arousalDelta > 0
                  ? Colors.deepOrangeAccent
                  : Colors.lightBlueAccent,
            ),
            const SizedBox(width: 4),
            Text(
              'Lust: ${arousalDelta > 0 ? '+$arousalDelta' : '$arousalDelta'}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: arousalDelta > 0
                    ? Colors.deepOrangeAccent
                    : Colors.lightBlueAccent,
              ),
            ),
          ],
        ),
      );
    }

    if (trustDelta != 0) {
      final chip = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            trustDelta > 0 ? Icons.handshake : Icons.gavel,
            size: 11,
            color: trustDelta > 0
                ? Colors.blueAccent
                : AppColors.resolve(
                    context,
                    Colors.deepPurpleAccent,
                    const Color(0xFF7C3AED),
                  ),
          ),
          const SizedBox(width: 4),
          Text(
            'Trust: ${trustDelta > 0 ? '+$trustDelta' : '$trustDelta'}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: trustDelta > 0
                  ? Colors.blueAccent
                  : AppColors.resolve(
                      context,
                      Colors.deepPurpleAccent,
                      const Color(0xFF7C3AED),
                    ),
            ),
          ),
          if (trustReason.isNotEmpty) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: 10,
              color: AppColors.textTertiary(context),
            ),
          ],
        ],
      );
      chips.add(maybeTooltip(chip, trustReason));
    }

    // Time reversal chip
    if (timeReversal) {
      chips.add(
        Tooltip(
          message: 'Time is going backwards?!',
          preferBelow: false,
          textStyle: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '😵‍💫',
                style: TextStyle(fontSize: 11),
              ), // Dizzy face with spirals
              const SizedBox(width: 4),
              const Text(
                'Time Reversal',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.cyanAccent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (timeSkipTo.isNotEmpty) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fast_forward,
              size: 11,
              color: AppColors.resolve(
                context,
                AppColors.resolve(
                  context,
                  Colors.amber,
                  const Color(0xFFB45309),
                ),
                const Color(0xFFB45309),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Time skip: $timeSkipTo',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.resolve(
                  context,
                  AppColors.resolve(
                    context,
                    Colors.amber,
                    const Color(0xFFB45309),
                  ),
                  const Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (chanceTimeEvent.isNotEmpty) {
      chips.add(
        Tooltip(
          message: chanceTimeEvent,
          preferBelow: false,
          textStyle: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎰', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  'Chance Time: ${chanceTimeEvent.length > 30 ? chanceTimeEvent.substring(0, 30) + '…' : chanceTimeEvent}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFD166),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Verifier (Director) status chip — only when present (feature was on for this speaker/turn).
    // Reuses the chip row style + maybeTooltip. Data from ChatMessage metadata set by god/leaf after verify.
    // Status + passes; reason in tooltip if provided. Uses AppColors for new/refactored parts.
    if (verifStatus.isNotEmpty) {
      final isAccepted = verifStatus == 'accepted';
      final label = isAccepted
          ? '✓ Director accepted'
          : '🕵️ Director corrected ($verifPasses reprocess${verifPasses == 1 ? '' : 'es'})';
      final icon = isAccepted ? Icons.verified : Icons.fact_check;
      final chipColor = isAccepted
          ? AppColors.resolve(context, Colors.greenAccent, Colors.green)
          : AppColors.resolve(context, Colors.orangeAccent, Colors.deepOrange);
      final chip = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: chipColor,
            ),
          ),
        ],
      );
      chips.add(
        maybeTooltip(
          chip,
          verifReason.isNotEmpty ? verifReason : 'Realism Verification result',
        ),
      );
    }

    // Safely build a list of children with spacers between them.
    // The old expand(...).toList()..removeLast() pattern would throw
    // "RangeError (length): Invalid value: Valid value range is empty: -1"
    // whenever the source list was empty (chips or needsChipList after 0-delta filtering).
    // This happened for messages whose realism metadata only contained needs_deltas
    // (or a needs_deltas map whose deltas all filtered to 0) with no bond/trust/verif/etc.,
    // or for older messages in history when the indicator was re-built after new realism
    // metadata started being attached. The crash surfaced in the chat ListView item builder.
    List<Widget> _spaced(List<Widget> items, double gap) {
      if (items.isEmpty) return const <Widget>[];
      final out = <Widget>[];
      for (int i = 0; i < items.length; i++) {
        out.add(items[i]);
        if (i < items.length - 1) out.add(SizedBox(width: gap));
      }
      return out;
    }

    final classicSpaced = _spaced(chips, 10);
    final classicRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: classicSpaced,
    );

    if (needsChipList.isEmpty) {
      // Nothing classic and no needs chips → nothing to show (guard should have caught most,
      // but be defensive after 0-delta filtering in needs).
      if (classicSpaced.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.resolve(
              context,
              AppColors.resolve(
                context,
                Colors.black12,
                Colors.black.withValues(alpha: 0.06),
              ),
              Colors.black.withValues(alpha: 0.06),
            ),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white10),
          ),
          child: classicRow,
        ),
      );
    }

    // Two-row layout: Classic Realism chips on top, Needs chips on a dedicated second row below.
    // This prevents the single-row clutter the user was worried about.
    // Only render the classic container if we actually have classic chips (bond/trust/verif/etc.);
    // otherwise just show the needs row without an empty bordered box on top.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Classic Realism (Bond, Trust, Lust, Mood, Time, Chance Time, Director status, etc.)
          if (classicSpaced.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.resolve(
                  context,
                  AppColors.resolve(
                    context,
                    Colors.black12,
                    Colors.black.withValues(alpha: 0.06),
                  ),
                  Colors.black.withValues(alpha: 0.06),
                ),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white10),
              ),
              child: classicRow,
            ),

          if (classicSpaced.isNotEmpty) const SizedBox(height: 4),

          // Row 2: Needs Simulation deltas (Energy, Hunger, Bladder, etc.)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _spaced(needsChipList, 8),
            ),
          ),

          // Row 3: Manual Reprocess / Revert buttons (only for last non-user msg with usable needs state)
          if (widget.chatService != null &&
              index == widget.chatService!.messages.length - 1 &&
              !message.isUser &&
              !widget.chatService!.isGenerating) ...[
            // A guard: only show reprocess affordance if this msg carries realism_state['needs']
            if (() {
              final m = message.activeMetadata;
              final rs = m?['realism_state'];
              return rs is Map && rs['needs'] != null;
            }()) ...[
              const SizedBox(height: 6),
              Tooltip(
                message: 'Reprocess Needs with critique',
                preferBelow: false,
                textStyle: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showReprocessNeedsDialog(context, index),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.resolve(
                          context,
                          AppColors.optionalAccent.withValues(alpha: 0.15),
                          AppColors.optionalAccent.withValues(alpha: 0.15),
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.resolve(
                            context,
                            AppColors.optionalAccent.withValues(alpha: 0.4),
                            AppColors.optionalAccent.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.rate_review,
                            size: 12,
                            color: AppColors.optionalAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Manual Reprocess',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.optionalAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            // D: Revert pill shown only when pre-reprocess stash exists on this (last) msg
            if (message.activeMetadata != null &&
                (message.activeMetadata!['needs_deltas_pre_reprocess']
                    is Map)) ...[
              const SizedBox(height: 4),
              Tooltip(
                message:
                    'Restore previous Needs deltas and live state before the last reprocess',
                preferBelow: false,
                textStyle: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      final chat = widget.chatService;
                      if (chat != null) {
                        try {
                          await chat.revertNeedsReprocess(index);
                        } catch (e) {
                          debugPrint('[Realism:Needs] revert error: $e');
                        }
                        if (mounted) {
                          // mounted guard present for safety after async revert
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.resolve(
                          context,
                          AppColors.optionalAccent.withValues(alpha: 0.12),
                          AppColors.optionalAccent.withValues(alpha: 0.12),
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.resolve(
                            context,
                            AppColors.optionalAccent.withValues(alpha: 0.35),
                            AppColors.optionalAccent.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.undo,
                            size: 11,
                            color: AppColors.optionalAccent,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Revert reprocess',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.optionalAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _showReprocessNeedsDialog(BuildContext context, int index) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final controller = TextEditingController();
    // Capture for snack after dialog pop (A: user feedback on success/fail)
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Reprocess Needs Deltas'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your critique to correct the Needs Simulation deltas. The Realism Director will re-evaluate the scene based on this input.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: controller,
                maxLines: 5,
                minLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText:
                      'e.g., The character ate a granola bar and an energy drink. Hunger and energy should improve.',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF374151),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.resolve(
                context,
                Colors.teal,
                const Color(0xFF0D9488),
              ),
            ),
            onPressed: () async {
              final text = controller.text.trim();
              Navigator.of(context).pop();
              if (text.isNotEmpty) {
                bool success = false;
                try {
                  success = await chatService.manualReprocessNeeds(index, text);
                } catch (e) {
                  debugPrint('[Realism:Needs] reprocess error: $e');
                }
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? 'Needs deltas reprocessed with your critique.'
                            : 'Reprocess received no response from the model. Original deltas preserved.',
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Reprocess',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, int index) {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final controller = TextEditingController(text: message.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Edit Message'),
        content: SizedBox(
          width: 500,
          child: AppTextField(
            controller: controller,
            maxLines: 10,
            minLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF374151),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              chatService.editMessage(index, controller.text);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
            ),
            child: const Text(
              'Save',
              style: TextStyle(color: AppColors.onChaosAccent),
            ),
          ),
        ],
      ),
    );
  }
}
