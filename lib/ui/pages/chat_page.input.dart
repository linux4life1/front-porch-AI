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
// ChatPage input column: the trust-repair and guest-activity banners, the
// slash-command and @-mention helpers, the pending photo and the shared send
// path, and the no-mic dialog. The bar itself lives in
// chat_page.input_bar.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/capability/capability.dart';

/// The photo riding on the next user message (bytes already downscaled + PNG
/// re-encoded by pickChatImageAttachment). [visionOk] is null while the
/// capability resolver is still checking the active model; [blindReason]
/// carries the backend-specific "why" for the chip's last-resort explanation
/// when the check fails. [update] is the owning page's setState.
class PendingImageSlot {
  PendingImageSlot({required this.update});

  final void Function(VoidCallback fn) update;

  Uint8List? bytes;
  bool? visionOk;
  String? blindReason;

  /// Drop the attachment (the chip's ✕, or after a send consumed it).
  void clear() => update(() {
    bytes = null;
    visionOk = null;
    blindReason = null;
  });

  /// Pick a photo for the next message and resolve (non-blocking) whether the
  /// active model can actually see it — a blind verdict makes the preview
  /// chip explain why and offer the last-resort Photo Understanding
  /// workaround, but never prevents sending (capability detection can't
  /// interrogate externally-started servers).
  Future<void> pick(BuildContext context) async {
    final picked = await pickChatImageAttachment(context);
    if (picked == null || !context.mounted) return;
    await accept(context, picked);
  }

  /// Picker and desktop-drop both land here so vision-check + chip stay one
  /// path. [context] is the chat page's own.
  Future<void> accept(BuildContext context, Uint8List picked) async {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    update(() {
      bytes = picked;
      visionOk = null;
      blindReason = null;
    });
    final isLocalBackend = llmProvider.activeBackend == BackendType.kobold;
    final support = await VisionSupportResolver.instance.resolveForActiveLlm(
      backend: llmProvider.activeBackend,
      storage: storage,
    );
    if (!context.mounted || bytes == null) return;
    update(() {
      visionOk = support.supported;
      blindReason = support.supported
          ? null
          : (support.source == VisionSource.unknown
                ? 'vision support couldn\'t be verified (the server didn\'t '
                      'answer the check), so the photo is described offline '
                      'instead'
                : (isLocalBackend
                      ? 'your local model has no vision projector (mmproj) '
                            'loaded, so it processes text only'
                      : 'the selected API model is text-only and doesn\'t '
                            'accept images'));
    });
  }
}

/// Shared send path for the Enter key and the send button. Hands text +
/// photo BYTES to ChatService, which saves the photo only after its own
/// guards pass — so we never save a file for a turn ChatService will drop.
/// While [ChatService.sendBusyReason] says the service would drop the send
/// (a reply or the narrator running, a load, a guest joining…) the pending
/// photo and typed text stay for retry rather than being consumed into the
/// void. In observer mode the photo is NOT consumed — director notes are
/// pure instructions and would drop it.
void sendComposerMessage(
  ChatService chatService, {
  required TextEditingController controller,
  required PendingImageSlot pendingImage,
}) {
  final pending = chatService.observerMode ? null : pendingImage.bytes;
  final text = controller.text;
  // The service's own guard set, so this cannot drift narrower than it.
  // Note sendMessage deliberately guards on isGenerating (streaming) and NOT
  // on isSettlingTurn — see the comment there.
  if ((text.trim().isEmpty && pending == null) ||
      chatService.sendBusyReason != null) {
    return;
  }
  // Refused while the speed test runs: said under the chat, text kept.
  final testing = chatService.sendRefusal(text, withImage: pending != null);
  if (testing != null) {
    chatService.announceLookupForce(testing);
    return;
  }
  final lookupBlock = chatService.lookupCommandBlock(text);
  if (lookupBlock != null) {
    chatService.announceLookupForce(lookupBlock);
    return;
  }
  chatService.sendMessage(text, imageBytes: pending);
  if (pending != null) {
    pendingImage.clear();
  }
  controller.clear();
}

/// Everything under the transcript: status banners, the slash and @-mention
/// helpers for [controller], then [inputBar].
class ChatInputArea extends StatelessWidget {
  const ChatInputArea({
    super.key,
    required this.chatService,
    required this.controller,
    required this.focusNode,
    required this.inputBar,
  });

  final ChatService chatService;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget inputBar;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Trust repair warning banner ──────────────────────────────────
        // Shown when a severe trust drop has armed the one-shot repair window.
        // Disappears automatically after the user sends their next message.
        if (chatService.pendingTrustRepair)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: StatusColors.warningPanelOf(context),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: StatusColors.warningOf(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trust is on the line — your next message is your only chance to explain yourself.',
                    style: TextStyle(
                      color: StatusColors.warningOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // A reply the user stopped from the Realism overlay: stays put.
        StoppedReplyNotice(chatService: chatService),

        // ── Scene Guest activity banner ──────────────────────────────────
        // One inline status line for the /create · /join · detection flow that
        // updates in place (Creating → Entering → ✓ joined) and auto-clears.
        // Replaces the old per-step 'System' chat messages so the scene stays
        // clean and nothing is persisted into history.
        if (chatService.guestActivityStatus != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: chatService.guestActivityIsError
                ? StatusColors.warningPanelOf(context)
                : AppColors.surfaceContainerOf(context),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: chatService.isGuestBusy
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.relationshipAccentOf(context),
                        )
                      : Icon(
                          chatService.guestActivityIsError
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline,
                          size: 14,
                          color: chatService.guestActivityIsError
                              ? StatusColors.warningOf(context)
                              : AppColors.relationshipAccentOf(context),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    chatService.guestActivityStatus!,
                    style: TextStyle(
                      color: chatService.guestActivityIsError
                          ? StatusColors.warningOf(context)
                          : AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Send held behind post-gen evals ──────────────────────────────
        // Composer already cleared; the bubble is added after settle. This
        // strip sits on the input (bottom of the chat) so the wait does not
        // look like a lost message.
        if (chatService.isSendWaitingOnSettle)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surfaceContainerOf(context),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.porchAmberOf(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Got it — sending when the last reply is fully wrapped up.',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Slash-command helper ─────────────────────────────────────────
        // When the input is a command-in-progress ("/", "/cr", …) show the
        // matching commands above the bar; tap one to fill it in. Rendered in
        // the input column (no overlay), and scoped to the controller via a
        // ValueListenableBuilder so only this panel rebuilds per keystroke.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final m = RegExp(r'^/(\w*)$').firstMatch(value.text);
            if (m == null) return const SizedBox.shrink();
            final prefix = m.group(1)!.toLowerCase();
            final matches = ChatCommandHandler.commands
                .where((c) => c.command.startsWith(prefix))
                .toList();
            if (matches.isEmpty) return const SizedBox.shrink();
            return _SlashCommandHelper(
              matches: matches,
              controller: controller,
              focusNode: focusNode,
            );
          },
        ),

        // ── @-mention helper ─────────────────────────────────────────────
        // The cast-name twin of the slash helper: while the cursor token is
        // "@…", lists who can be addressed (host + guests, or group
        // members); tapping fills in "@Name " and that character answers
        // the turn (the sendMessage direct-address router).
        MentionAutocomplete(controller: controller, focusNode: focusNode),

        inputBar,
      ],
    );
  }
}

/// Matching slash commands above the bar; tapping one fills it in.
class _SlashCommandHelper extends StatelessWidget {
  const _SlashCommandHelper({
    required this.matches,
    required this.controller,
    required this.focusNode,
  });

  final List<SlashCommandInfo> matches;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: matches.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          thickness: 1,
          color: AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
        itemBuilder: (context, i) {
          final c = matches[i];
          return InkWell(
            onTap: () {
              final text = '/${c.command} ';
              controller.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
              focusNode.requestFocus();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: Text(
                      c.example,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: AppColors.relationshipAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      c.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Explains a missing or refused microphone (mic and call buttons).
void showNoMicDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      icon: Icon(
        Icons.mic_off,
        color: StatusColors.dangerOf(context),
        size: 40,
      ),
      title: Text(
        'No Microphone Detected',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: Text(
        'No microphone was found or microphone permission was denied.\n\n'
        '• Check that a microphone is connected\n'
        '• Grant microphone permission if prompted\n'
        '• Select a specific microphone in Settings → Voice Input',
        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
