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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'selectable_bubble_body.dart';

// Bubble-triggered dialogs: the Chance Time / Dream narration banner
// (with its long-press delete), and the delete / fork / edit
// confirmation dialogs invoked from the header row's icon buttons.

/// The Context Viewer for the prompt that produced the shown swipe.
void showMessageReplyContext(
  BuildContext context, {
  required ChatService? chat,
  required ChatMessage message,
}) {
  final snap = replyContextOf(message);
  if (chat == null || snap == null) return;
  showWarmDialogOf<void>(
    context,
    builder: (_) => ContextViewerDialog(chatService: chat, snapshot: snap),
  );
}

/// The words the model weighed in this reply; a pick rewrites the last
/// reply from that word (KoboldCpp only).
Future<void> showMessageTokenAlternatives(
  BuildContext context, {
  required ChatService? chat,
  required ChatMessage message,
  required int index,
}) async {
  if (chat == null) return;
  final places = chat.tokenAlternativesAt(index);
  if (places.isEmpty) return;
  final picked = await showWarmDialogOf<TokenAltPick>(
    context,
    builder: (_) => TokenAlternativesDialog(
      body: tokenAltsBody(message.text),
      places: places,
      refusal: chat.tokenAltsPickRefusal(index),
    ),
  );
  if (picked == null) return;
  await chat.rewriteFromAlternative(index, picked.at, picked.word);
}

/// The one centered narration banner (Chance Time 🎰, Dreams 🌙 — Living
/// Time §1). Warm-porch amber tints, italic center text. Long-press
/// deletes: banners return before the normal bubble's action row is ever
/// built, so without this they were the only messages that could never be
/// removed (the stuck-dream report, 2026-07-28).
class MessageNarrationBanner extends StatelessWidget {
  const MessageNarrationBanner({
    super.key,
    required this.emoji,
    required this.text,
    required this.onDelete,
  });

  final String emoji;
  final String text;

  /// Long-press handler; the bubble asks to delete the message.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onDelete,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.resolve(
              context,
              AppColors.chaosAccent.withValues(alpha: 0.12),
              AppColors.porchAmber.withValues(alpha: 0.18),
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.resolve(
                context,
                AppColors.chaosAccent.withValues(alpha: 0.35),
                AppColors.porchAmber.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Flexible(
                child: SelectableBubbleBody(
                  child: GestureDetector(
                    onLongPress: onDelete,
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.resolve(
                          context,
                          AppColors.chaosAccent,
                          AppColors.porchAmberLight,
                        ),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two buttons of a yes/no confirm. Each pops with the dialog's own
/// context (a Builder inside the dialog), so a bubble under a nested
/// Navigator closes the dialog, never the chat page behind it.
List<Widget> _confirmActions(String label, {bool destructive = false}) => [
  Builder(builder: (ctx) => warmDialogCancel(ctx, value: false)),
  Builder(
    builder: (ctx) => warmDialogConfirm(
      ctx,
      label: label,
      destructive: destructive,
      onPressed: () => Navigator.of(ctx).pop(true),
    ),
  ),
];

/// Asks before deleting message [index]; deletes on yes.
Future<void> confirmDeleteMessage(BuildContext context, int index) async {
  final chatService = Provider.of<ChatService>(context, listen: false);
  final yes = await showWarmDialog<bool>(
    context,
    title: 'Delete Message',
    icon: Icons.warning_amber_rounded,
    destructive: true,
    content: const WarmDialogText(
      'This can\'t be undone. Are you sure you want to delete this message?',
    ),
    actions: _confirmActions('Delete', destructive: true),
  );
  if (yes == true) chatService.deleteMessage(index);
}

/// Asks before forking at message [index]; forks on yes and tells the user.
Future<void> confirmForkMessage(BuildContext context, int index) async {
  final chatService = Provider.of<ChatService>(context, listen: false);
  final yes = await showWarmDialog<bool>(
    context,
    title: 'Fork Conversation',
    icon: Icons.call_split,
    accent: AppColors.porchAmberOf(context),
    content: WarmDialogText(
      'Create a new branch from message #${index + 1}?\n\nThe current chat will remain unchanged. A new conversation will be created with messages up to this point.',
    ),
    actions: _confirmActions('Fork'),
  );
  if (yes != true) return;
  chatService.forkFromMessage(index);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Conversation forked! You are now on the new branch.'),
      ),
    );
  }
}

/// Opens the edit dialog on [message] and saves the result at [index].
Future<void> editMessageViaDialog(
  BuildContext context, {
  required ChatMessage message,
  required int index,
}) async {
  final chatService = Provider.of<ChatService>(context, listen: false);
  final result = await showMessageEditDialog(
    context: context,
    initialText: message.text,
    showThinking: !message.isUser,
  );
  if (result != null) {
    chatService.editMessage(index, result);
  }
}
