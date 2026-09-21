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

/// Bubble-triggered dialogs: the Chance Time / Dream narration banner
/// (with its long-press delete), and the delete / fork / edit
/// confirmation dialogs invoked from the header row's icon buttons.
extension _BubbleDialogs on _MessageBubbleState {
  /// The one centered narration banner (Chance Time 🎰, Dreams 🌙 — Living
  /// Time §1). Warm-porch amber tints, italic center text. Long-press
  /// deletes: banners return before the normal bubble's action row is ever
  /// built, so without this they were the only messages that could never be
  /// removed (the stuck-dream report, 2026-07-28).
  Widget _narrationBanner(
    BuildContext context, {
    required String emoji,
    required String text,
  }) {
    void deleteBanner() => _showDeleteConfirmation(context, index);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: deleteBanner,
      child: Padding(
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
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Flexible(
                child: SelectableBubbleBody(
                  child: GestureDetector(
                    onLongPress: deleteBanner,
                    child: Text(
                      text,
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
                ),
              ),
            ],
          ),
        ),
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

  Future<void> _showEditDialog(BuildContext context, int index) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final result = await showMessageEditDialog(
      context: context,
      initialText: message.text,
    );
    if (result != null) {
      chatService.editMessage(index, result);
    }
  }
}
