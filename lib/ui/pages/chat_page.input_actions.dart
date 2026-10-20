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
// The strip is a list spread into the bar's Row, so it is a plain builder
// rather than a widget: its Expanded message box must stay a direct Row child.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input.dart';
import 'package:front_porch_ai/ui/pages/chat_page.session_dialogs.dart';
import 'package:front_porch_ai/ui/pages/chat_page.regen_shortcut.dart';

/// The folder-icon chat-management popup. Import, export and add-character
/// are the page's own flows; the rest open from this menu's context.
class ChatManagementMenu extends StatelessWidget {
  const ChatManagementMenu({
    super.key,
    required this.chatService,
    required this.onImport,
    required this.onExport,
    required this.onConvertToGroup,
  });

  final ChatService chatService;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onConvertToGroup;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.folder_open, color: AppColors.iconSecondary(context)),
      padding: EdgeInsets.zero,
      tooltip: 'Chat Management',
      onSelected: (value) {
        if (value == 'new_chat') {
          showNewChatConfirmation(context);
        } else if (value == 'history') {
          showManageChats(context);
        } else if (value == 'import') {
          // itemBuilder runs once when the menu opens. A turn can start
          // while the menu is still up, leaving a stale-enabled item.
          if (!chatService.isGenerating &&
              !chatService.isSettlingTurn &&
              !chatService.isImporting) {
            onImport();
          }
        } else if (value == 'export') {
          onExport();
        } else if (value == 'context') {
          showDialog(
            context: context,
            builder: (_) => ContextViewerDialog(chatService: chatService),
          );
        } else if (value == 'to_story') {
          ChatToStoryDialog.show(context, chatService: chatService);
        } else if (value == 'fork_group') {
          onConvertToGroup();
        } else if (value == 'kobold_log') {
          showDialog(context: context, builder: (_) => const KoboldLogDialog());
        }
      },
      itemBuilder: (context) {
        final amber = AppColors.porchAmberOf(context);
        return [
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
                Text('Manage Chats'),
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
              message:
                  (!chatService.isGenerating && !chatService.isSettlingTurn)
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
          PopupMenuItem(
            value: 'context',
            child: Row(
              children: [
                Icon(Icons.analytics_outlined, size: 20, color: amber),
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
            PopupMenuItem(
              value: 'fork_group',
              child: Row(
                children: [
                  Icon(Icons.group_add, size: 20, color: amber),
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
        ];
      },
    );
  }
}

/// Every action button to the right of the menu, in Row order.
class ChatInputActionStrip {
  const ChatInputActionStrip({
    required this.chatService,
    required this.controller,
    required this.focusNode,
    required this.minLines,
    required this.isPageMounted,
    required this.onOpenImageStudio,
    required this.onAttachImage,
    required this.onStartCall,
    required this.onSend,
  });

  final ChatService chatService;

  /// The chat page's message box. It dies with the page, not with this bar.
  final TextEditingController controller;
  final FocusNode focusNode;
  final int minLines;
  final ValueGetter<bool> isPageMounted;
  final VoidCallback onOpenImageStudio;
  final VoidCallback onAttachImage;
  final VoidCallback onStartCall;
  final VoidCallback onSend;

  /// Whether the page that owns [controller] is still alive. Async results
  /// (Impersonate tokens, Whisper transcripts) land after it may have closed.
  bool get mounted => isPageMounted();

  /// The buttons, spread into the bar's Row (a spread of the same widgets in
  /// the same order is an identical child list).
  List<Widget> build(BuildContext context) {
    return <Widget>[
      // Image Generation: the magic-wand button opens the Image
      // Studio, where the user picks a Subject (Freeform / Character
      // / Persona) and crafts the prompt.
      Consumer<StorageService>(
        builder: (context, storage, _) {
          if (!storage.imageGenSettings.imageGenEnabled) {
            return const SizedBox.shrink();
          }
          return IconButton(
            icon: Icon(
              Icons.auto_awesome,
              color: AppColors.resolve(
                context,
                AppColors.formAccentOf(context),
                AppColors.formAccentOf(context),
              ),
            ),
            padding: EdgeInsets.zero,
            tooltip: 'Image Studio',
            onPressed: onOpenImageStudio,
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
          onPressed: onAttachImage,
        ),

      const SizedBox(width: 4),

      Expanded(
        child: Consumer2<LLMProvider, OpenRouterService>(
          builder: (context, llm, _, _) {
            final apiReady = llm.composerConnectionReady;
            final hint = chatComposerHint(
              apiReady: apiReady,
              observerMode: chatService.observerMode,
              reason: llm.composerConnectionHint,
            );
            final storage = Provider.of<StorageService>(context);
            return ReadingSizeScope(
              textScale: storage.uiSettings.textScale,
              child: AppTextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !chatService.isLoadingSession,
                maxLines: 10,
                minLines: minLines,
                textInputAction: TextInputAction.newline,
                style: readingSurfaceStyle(
                  color: AppColors.textPrimary(context),
                ),
                spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: !apiReady
                        ? AppColors.negativeAccentOf(context)
                        : chatService.observerMode
                        ? AppColors.porchAmberOf(context).withValues(alpha: 0.7)
                        : AppColors.textTertiary(context),
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: AppCorners.of(context).circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            );
          },
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
                  final prefix = controller.text;
                  chatService.impersonateUser(
                    prefix: prefix,
                    onToken: (accumulated) {
                      // ChatService is app-scoped and impersonation keeps
                      // streaming after the page pops — writing a disposed
                      // controller here throws inside the stream loop.
                      if (!mounted) return;
                      controller.text = accumulated;
                      controller.selection = TextSelection.fromPosition(
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
          if (!storage.sttSettings.sttEnabled) {
            return const SizedBox.shrink();
          }
          if (sttService.isTranscribing) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formAccentOf(context),
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
                          if (storage.sttSettings.autoSendTranscription &&
                              controller.text.isEmpty) {
                            chatService.sendMessage(text);
                          } else {
                            controller.text = controller.text.isEmpty
                                ? text
                                : '${controller.text} $text';
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                          }
                        }
                      } else {
                        final micOk = await sttService.checkMicAvailable();
                        if (!micOk && context.mounted) {
                          showNoMicDialog(context);
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
          if (!storage.sttSettings.sttEnabled || chatService.isGroupMode) {
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
                        showNoMicDialog(context);
                        return;
                      }
                      onStartCall();
                    },
            ),
          );
        },
      ),
      // Auto-play (Director Mode) + Next Character; Next stays greyed out
      // while auto-play runs so Pause lands where Play was. Pause stays up
      // through an auto-chat reply: it lets that reply finish.
      if (chatService.isGroupMode &&
          (!chatService.isGenerating || chatService.autoPlayActive))
        DirectorTurnButtons(
          showAutoPlay: chatService.observerMode,
          autoPlayActive: chatService.autoPlayActive,
          autoPlayPaused: chatService.autoPlayPaused,
          turnsLeft: chatService.autoChatTurnsLeft,
          onStopAutoPlay: chatService.stopAutoPlay,
          nextTooltip: chatService.nextCharacter != null
              ? 'Next: ${chatService.nextCharacter!.name}'
              : 'Trigger next character',
          onToggleAutoPlay: chatService.autoPlayActive
              ? chatService.pauseAutoPlay
              : chatService.startAutoPlay,
          onNextCharacter: chatService.triggerNextCharacter,
          playColor: AppColors.porchAmberOf(context),
          pauseColor: Colors.orangeAccent,
          nextColor: Colors.purpleAccent, // theme-keep: director Next, not Play
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
          message: 'Generate reply ($chatRegenShortcutLabel)',
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
                      : AppColors.porchAmberOf(context),
                ),
                onPressed: chatService.isLoadingSession ? null : onSend,
              ),
            ),
    ];
  }
}
