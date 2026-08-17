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
//
// ChatPage input-bar actions: the chat-management menu and the button strip
// (image studio, attach photo, impersonate, mic, call, auto-play, send/stop).
// Extracted verbatim from the input bar's Row children (god-file campaign,
// Tranche A). The list is spread back into the same position, so the widget
// tree is unchanged.

part of 'chat_page.dart';

extension _ChatPageInputActions on _ChatPageState {
  /// The folder-icon chat-management popup — verbatim.
  Widget _buildChatManagementMenu(
    BuildContext context,
    ChatService chatService,
  ) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.folder_open, color: AppColors.iconSecondary(context)),
      padding: EdgeInsets.zero,
      tooltip: 'Chat Management',
      onSelected: (value) {
        if (value == 'new_chat') {
          _showClearChatConfirmation(context);
        } else if (value == 'history') {
          _showHistoryDialog(context);
        } else if (value == 'import') {
          // itemBuilder runs once when the menu opens. A turn can start
          // while the menu is still up, leaving a stale-enabled item.
          if (!chatService.isGenerating &&
              !chatService.isSettlingTurn &&
              !chatService.isImporting) {
            _importChat();
          }
        } else if (value == 'export') {
          _exportChat();
        } else if (value == 'context') {
          showDialog(
            context: context,
            builder: (_) => ContextViewerDialog(chatService: chatService),
          );
        } else if (value == 'to_story') {
          ChatToStoryDialog.show(context, chatService: chatService);
        } else if (value == 'fork_group') {
          _showConvertToGroupPicker(chatService);
        } else if (value == 'kobold_log') {
          showDialog(context: context, builder: (_) => const KoboldLogDialog());
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'new_chat',
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 20),
              SizedBox(width: 12),
              Text('New Chat'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'history',
          child: Row(
            children: [
              Icon(Icons.history, size: 20),
              SizedBox(width: 12),
              Text('Chat History'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'import',
          enabled:
              !chatService.isGenerating &&
              !chatService.isSettlingTurn &&
              !chatService.isImporting,
          child: Tooltip(
            message: (!chatService.isGenerating && !chatService.isSettlingTurn)
                ? 'Import a chat file'
                : 'Wait until the current reply finishes, then import',
            child: const Row(
              children: [
                Icon(Icons.file_upload, size: 20),
                SizedBox(width: 12),
                Text('Import Chat'),
              ],
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(Icons.file_download, size: 20),
              SizedBox(width: 12),
              Text('Export Chat'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'context',
          child: Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 20,
                color: Colors.cyanAccent,
              ),
              SizedBox(width: 12),
              Text('Context Budget'),
            ],
          ),
        ),
        // Living Time §4: chat → novella. 1:1 only for now
        // (multi-protagonist novelization is a future effort).
        if (chatService.activeCharacter != null &&
            chatService.activeGroup == null)
          const PopupMenuItem(
            value: 'to_story',
            child: Row(
              children: [
                Icon(Icons.auto_stories_outlined, size: 20),
                SizedBox(width: 12),
                Text('Turn Into a Story…'),
              ],
            ),
          ),
        // (The old Character Evolution dialog was replaced by the
        // Growth panel in the sidebar — Journal & Memory group —
        // which hosts the toggle, timeline, and all actions.)
        if (chatService.activeCharacter != null &&
            chatService.activeGroup == null)
          const PopupMenuItem(
            value: 'fork_group',
            child: Row(
              children: [
                Icon(Icons.group_add, size: 20, color: Colors.purpleAccent),
                SizedBox(width: 12),
                Text('Add Character (Group)…'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'kobold_log',
          child: Row(
            children: [
              Icon(Icons.terminal, size: 20, color: Colors.greenAccent),
              SizedBox(width: 12),
              Text('KoboldCpp Log'),
            ],
          ),
        ),
      ],
    );
  }

  /// Every action button to the right of the menu — verbatim Row children,
  /// spread back in place. A spread of the same widgets in the same order is
  /// an identical child list.
  List<Widget> _buildInputActionButtons(
    BuildContext context,
    ChatService chatService,
  ) {
    return <Widget>[
      // Image Generation: the magic-wand button opens the Image
      // Studio, where the user picks a Subject (Freeform / Character
      // / Persona) and crafts the prompt.
      Consumer<StorageService>(
        builder: (context, storage, _) {
          if (!storage.imageGenEnabled) {
            return const SizedBox.shrink();
          }
          return IconButton(
            icon: Icon(
              Icons.auto_awesome,
              color: AppColors.resolve(
                context,
                AppColors.formMasterAccent,
                AppColors.formMasterAccent,
              ),
            ),
            padding: EdgeInsets.zero,
            tooltip: 'Image Studio',
            onPressed: () => _showImageGenDialog(context, chatService),
          );
        },
      ),

      // Attach a photo to the next message (vision-capable models
      // see the pixels; others get the history marker). Hidden in
      // observer mode — director notes carry no images.
      if (!chatService.observerMode)
        IconButton(
          icon: Icon(
            Icons.add_photo_alternate_outlined,
            color: AppColors.iconSecondary(context),
          ),
          padding: EdgeInsets.zero,
          tooltip: 'Attach photo',
          onPressed: _attachImage,
        ),

      const SizedBox(width: 4),

      Expanded(
        child: AppTextField(
          controller: _controller,
          focusNode: _chatFocusNode,
          enabled: !chatService.isLoadingSession,
          maxLines: 10,
          minLines: _inputMinLines,
          textInputAction: TextInputAction.newline,
          style: TextStyle(color: AppColors.textPrimary(context)),
          spellCheckConfiguration: SpellCheckConfiguration.disabled(),
          decoration: InputDecoration(
            hintText: chatService.observerMode
                ? 'Direct the scene...'
                : 'Type a message...',
            hintStyle: TextStyle(
              color: chatService.observerMode
                  ? Colors.amberAccent.withValues(alpha: 0.6)
                  : AppColors.textTertiary(context),
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      // Impersonate button (magic wand — AI writes your next message)
      Tooltip(
        message: 'Impersonate (AI writes your message)',
        child: IconButton(
          icon: const Icon(Icons.auto_fix_high, color: Colors.amberAccent),
          padding: EdgeInsets.zero,
          onPressed: chatService.isGenerating
              ? null
              : () {
                  final prefix = _controller.text;
                  chatService.impersonateUser(
                    prefix: prefix,
                    onToken: (accumulated) {
                      // ChatService is app-scoped and impersonation keeps
                      // streaming after the page pops — writing a disposed
                      // controller here throws inside the stream loop.
                      if (!mounted) return;
                      _controller.text = accumulated;
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: accumulated.length),
                      );
                    },
                  );
                },
        ),
      ),
      // Mic button (push-to-talk STT)
      Consumer2<SttService, StorageService>(
        builder: (context, sttService, storage, _) {
          if (!storage.sttEnabled) {
            return const SizedBox.shrink();
          }
          if (sttService.isTranscribing) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formMasterAccent,
                ),
              ),
            );
          }
          return Tooltip(
            message: sttService.isRecording ? 'Stop recording' : 'Voice input',
            child: IconButton(
              icon: Icon(
                sttService.isRecording ? Icons.stop_circle : Icons.mic,
                color: sttService.isRecording
                    ? Colors.redAccent
                    : AppColors.iconSecondary(context),
              ),
              onPressed: chatService.isGenerating
                  ? null
                  : () async {
                      if (sttService.isRecording) {
                        final text = await sttService
                            .stopRecordingAndTranscribe();
                        if (!mounted) return;
                        if (text != null && text.isNotEmpty) {
                          if (storage.autoSendTranscription &&
                              _controller.text.isEmpty) {
                            chatService.sendMessage(text);
                          } else {
                            _controller.text = _controller.text.isEmpty
                                ? text
                                : '${_controller.text} $text';
                            _controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: _controller.text.length),
                            );
                          }
                        }
                      } else {
                        final micOk = await sttService.checkMicAvailable();
                        if (!micOk && context.mounted) {
                          _showNoMicDialog(context);
                          return;
                        }
                        await sttService.startRecording();
                      }
                    },
            ),
          );
        },
      ),
      // Call button (voice call mode)
      Consumer2<SttService, StorageService>(
        builder: (context, sttService, storage, _) {
          if (!storage.sttEnabled || chatService.isGroupMode) {
            return const SizedBox.shrink();
          }
          return Tooltip(
            message: 'Start voice call',
            child: IconButton(
              icon: Icon(Icons.call, color: AppColors.porchAmberOf(context)),
              onPressed: chatService.isGenerating || sttService.isBusy
                  ? null
                  : () async {
                      final micOk = await sttService.checkMicAvailable();
                      if (!micOk && context.mounted) {
                        _showNoMicDialog(context);
                        return;
                      }
                      rebuildState(() => _isCallActive = true);
                    },
            ),
          );
        },
      ),
      // Auto-play button (observer mode only)
      if (chatService.isGroupMode &&
          chatService.observerMode &&
          !chatService.isGenerating)
        Tooltip(
          message: chatService.autoPlayActive
              ? 'Pause auto-chat'
              : 'Start auto-chat',
          child: IconButton(
            icon: Icon(
              chatService.autoPlayActive
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: chatService.autoPlayActive
                  ? Colors.orangeAccent
                  : Colors.amberAccent,
            ),
            onPressed: () {
              if (chatService.autoPlayActive) {
                chatService.stopAutoPlay();
              } else {
                chatService.startAutoPlay();
              }
            },
          ),
        ),
      // Next Character button (group mode only, not in auto-play)
      if (chatService.isGroupMode &&
          !chatService.isGenerating &&
          !chatService.autoPlayActive)
        Tooltip(
          message: chatService.nextCharacter != null
              ? 'Next: ${chatService.nextCharacter!.name}'
              : 'Trigger next character',
          child: IconButton(
            icon: const Icon(Icons.group, color: Colors.purpleAccent),
            onPressed: () => chatService.triggerNextCharacter(),
          ),
        ),
      // Generate reply button (1:1 only) — shown when the AI is
      // "up next", i.e. the last message is the user's (e.g. the
      // previous reply was deleted). Gives a visible way to
      // (re)generate without retyping. Group mode already covers
      // this via the Next Character button above.
      if (!chatService.isGroupMode &&
          !chatService.isGenerating &&
          !chatService.autoPlayActive &&
          chatService.messages.isNotEmpty &&
          chatService.messages.last.isUser)
        Tooltip(
          message: 'Generate reply ($_regenShortcutLabel)',
          child: IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orangeAccent),
            onPressed: () => chatService.regenerateLastMessage(),
          ),
        ),
      chatService.isGenerating
          ? IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
              tooltip: chatService.autoPlayActive
                  ? 'Stop Auto-Chat'
                  : 'Stop Generation',
              onPressed: () {
                chatService.stopAutoPlay();
                chatService.stopGeneration();
              },
            )
          : Tooltip(
              message: chatService.observerMode
                  ? 'Send director note'
                  : 'Send message',
              child: IconButton(
                icon: Icon(
                  chatService.observerMode ? Icons.movie_creation : Icons.send,
                  color: chatService.isGuestBusy
                      ? AppColors.iconSecondary(context)
                      : (chatService.observerMode
                            ? Colors.amberAccent
                            : AppColors.porchAmberOf(context)),
                ),
                onPressed: chatService.isLoadingSession
                    ? null
                    : () => _sendCurrentMessage(chatService),
              ),
            ),
    ];
  }
}
