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

part of 'message_bubble.dart';

/// The message header row: Director label / sender name (with the group
/// tap-to-queue affordance) / TTS speaker button / edit / fork / delete.
/// Split out of `message_bubble.dart`'s `build()` to keep the shell under
/// the file-size cap (`settings_page.dart` part-file precedent). Takes the
/// locals `build()` already computed as parameters rather than
/// recomputing them, so behavior is byte-for-byte identical to when this
/// `Row` lived inline.
extension _BubbleHeader on _MessageBubbleState {
  Widget _headerActionsRow(
    BuildContext context,
    ResolvedThemeData theme,
    StorageService? storage,
    bool isDirectorNote,
  ) {
    return Row(
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
              final chatService = widget.chatService;
              final nameWidget = Text(
                message.sender,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color:
                      widget.senderColor ??
                      theme.accent ??
                      storage?.getDialogueColor(character) ??
                      AppColors.textPrimary(context),
                ),
              );
              if (chatService != null && chatService.isGroupMode) {
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
        if (widget.chatService != null &&
            !message.isUser &&
            message.sender != 'System' &&
            !isDirectorNote)
          Consumer2<TtsService, StorageService>(
            builder: (context, tts, storage, _) {
              if (!storage.ttsEnabled) {
                return const SizedBox.shrink();
              }
              final msgId = 'msg_${widget.index}';
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
        if (widget.chatService != null && message.sender != 'System')
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              size: 16,
              color: theme.accent ?? AppColors.textTertiary(context),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Edit message',
            onPressed: () => _showEditDialog(context, index),
          ),
        if (widget.chatService != null && message.sender != 'System')
          const SizedBox(width: 8),
        if (widget.chatService != null && message.sender != 'System')
          IconButton(
            icon: Icon(
              Icons.call_split,
              size: 16,
              color: theme.accent ?? AppColors.textTertiary(context),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Fork from here',
            onPressed: () => _showForkConfirmation(context, index),
          ),
        if (widget.chatService != null && message.sender != 'System')
          const SizedBox(width: 8),
        if (widget.chatService != null)
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 16,
              color: theme.accent ?? AppColors.textTertiary(context),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _showDeleteConfirmation(context, index),
          ),
      ],
    );
  }
}
