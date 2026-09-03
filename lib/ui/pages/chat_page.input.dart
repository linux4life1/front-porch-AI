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
// slash-command and @-mention helpers, attach/send handlers, and the no-mic
// dialog. Extracted verbatim from chat_page.dart (god-file campaign,
// Tranche A); same library, all privates in scope. The bar itself lives in
// chat_page.input_bar.dart.

part of 'chat_page.dart';

extension _ChatPageInput on _ChatPageState {
  Widget _buildCommandHelper(
    BuildContext context,
    List<SlashCommandInfo> matches,
  ) {
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
              _controller.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
              _chatFocusNode.requestFocus();
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

  /// Pick a photo for the next message and resolve (non-blocking) whether the
  /// active model can actually see it — a blind verdict makes the preview
  /// chip explain why and offer the last-resort Photo Understanding
  /// workaround, but never prevents sending (capability detection can't
  /// interrogate externally-started servers).
  Future<void> _attachImage() async {
    // Capture providers before the async gaps (native picker + isolate decode).
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final bytes = await pickChatImageAttachment();
    if (bytes == null || !mounted) return;
    rebuildState(() {
      _pendingImageBytes = bytes;
      _pendingImageVisionOk = null;
      _pendingImageBlindReason = null;
    });
    final isLocalBackend = llmProvider.activeBackend == BackendType.kobold;
    final support = await VisionSupportResolver.instance.resolveForActiveLlm(
      backend: llmProvider.activeBackend,
      storage: storage,
    );
    // The user may have removed (or sent) the attachment while resolving.
    if (!mounted || _pendingImageBytes == null) return;
    rebuildState(() {
      _pendingImageVisionOk = support.supported;
      _pendingImageBlindReason = support.supported
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

  /// Shared send path for the Enter key and the send button. Hands text +
  /// photo BYTES to ChatService, which saves the photo only after its own
  /// guards pass — so we never save a file for a turn ChatService will drop.
  /// We mirror every one of sendMessage's silent early-returns here
  /// (isGenerating / isLoadingSession / isGuestBusy / entrancesInFlight /
  /// no active chat) so the pending photo and typed text are preserved
  /// for retry rather than consumed into the void. In observer mode the
  /// photo is NOT consumed — director notes are pure instructions and
  /// would drop it.
  void _sendCurrentMessage(ChatService chatService) {
    final pending = chatService.observerMode ? null : _pendingImageBytes;
    final text = _controller.text;
    if ((text.trim().isEmpty && pending == null) ||
        // Mirrors sendMessage's guard set EXACTLY. If this list is ever
        // narrower than the service's, we fall through to _controller.clear()
        // below for a send the service silently refused, and the user's typed
        // text and pending photo are consumed into the void. Note sendMessage
        // deliberately guards on isGenerating (streaming) and NOT on
        // isSettlingTurn — see the comment there.
        chatService.isGenerating ||
        chatService.isLoadingSession ||
        chatService.isGuestBusy ||
        chatService.isPhotoTurnInFlight ||
        chatService.entrancesInFlight ||
        (chatService.activeCharacter == null &&
            chatService.activeGroup == null)) {
      return;
    }
    chatService.sendMessage(text, imageBytes: pending);
    if (pending != null) {
      rebuildState(() {
        _pendingImageBytes = null;
        _pendingImageVisionOk = null;
        _pendingImageBlindReason = null;
      });
    }
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Widget _buildInputArea(BuildContext context, ChatService chatService) {
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
            color: AppColors.resolve(
              context,
              const Color(0xFF7C2D12),
              const Color(0xFFFEF3C7),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Trust is on the line — your next message is your only chance to explain yourself.',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

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
                ? AppColors.resolve(
                    context,
                    const Color(0xFF7C2D12),
                    const Color(0xFFFEF3C7),
                  )
                : AppColors.surfaceContainerOf(context),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: chatService.isGuestBusy
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.relationshipAccent,
                        )
                      : Icon(
                          chatService.guestActivityIsError
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline,
                          size: 14,
                          color: chatService.guestActivityIsError
                              ? Colors.orangeAccent
                              : AppColors.relationshipAccent,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    chatService.guestActivityStatus!,
                    style: TextStyle(
                      color: chatService.guestActivityIsError
                          ? Colors.orangeAccent
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
          valueListenable: _controller,
          builder: (context, value, _) {
            final m = RegExp(r'^/(\w*)$').firstMatch(value.text);
            if (m == null) return const SizedBox.shrink();
            final prefix = m.group(1)!.toLowerCase();
            final matches = ChatCommandHandler.commands
                .where((c) => c.command.startsWith(prefix))
                .toList();
            if (matches.isEmpty) return const SizedBox.shrink();
            return _buildCommandHelper(context, matches);
          },
        ),

        // ── @-mention helper ─────────────────────────────────────────────
        // The cast-name twin of the slash helper: while the cursor token is
        // "@…", lists who can be addressed (host + guests, or group
        // members); tapping fills in "@Name " and that character answers
        // the turn (the sendMessage direct-address router).
        MentionAutocomplete(controller: _controller, focusNode: _chatFocusNode),

        _buildInputBar(context, chatService),
      ],
    );
  }

  void _showNoMicDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        icon: const Icon(Icons.mic_off, color: Colors.redAccent, size: 40),
        title: const Text(
          'No Microphone Detected',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'No microphone was found or microphone permission was denied.\n\n'
          '• Check that a microphone is connected\n'
          '• Grant microphone permission if prompted\n'
          '• Select a specific microphone in Settings → Voice Input',
          style: TextStyle(color: Colors.white70, fontSize: 13),
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
}
