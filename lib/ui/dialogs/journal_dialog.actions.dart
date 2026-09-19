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

part of 'journal_dialog.dart';

extension _JournalDialogActions on _JournalDialogState {
  Future<void> _plantMemory(String userName) async {
    final draft = await JournalCardEditorDialog.show(
      context,
      title: 'Plant a memory in $_ownerName\'s journal',
      userName: userName,
    );
    if (draft == null || !mounted) return;
    final sessionId = _chat.currentSessionId;
    if (sessionId == null) return;
    final storage = Provider.of<StorageService>(context, listen: false);
    await _chat.journalStore.addCard(
      sessionId: sessionId,
      characterId: _ownerId,
      content: draft.content,
      category: draft.category,
      emotionLabel: draft.feeling,
      storyDay: _chat.timeService.dayCount,
      storyClock: _chat.timeService.storyClockIso,
      maxCards: storage.memorySettings.journalMaxCards,
    );
    await _load();
  }

  Future<void> _editCard(JournalMemoryData card, String userName) async {
    final draft = await JournalCardEditorDialog.show(
      context,
      title: 'Edit memory',
      userName: userName,
      showCategory: false,
      initialContent: card.content,
      initialFeeling: card.emotionLabel,
    );
    if (draft == null || !mounted) return;
    await _chat.journalStore.reviseCard(
      card,
      content: draft.content,
      feeling: draft.feeling,
    );
    await _load();
  }

  Future<void> _deleteCard(JournalMemoryData card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Retire this memory?',
          style: TextStyle(fontSize: 15, color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          '"${card.content}"\n\nThe conversation itself is untouched — only '
          'the journal entry is removed.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Keep',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.negativeAccentOf(ctx),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Retire'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _chat.journalStore.retireCard(card.id);
    await _load();
  }

  /// Receipts: the original chat lines this memory was written from
  /// (sourceMessageIds holds message positions — stable across saves, but a
  /// heavily edited/deleted history can outdate them, hence the guards).
  /// Tapping a line closes the receipts AND the journal, then asks the chat
  /// page to scroll to that message.
  Future<void> _showReceipts(JournalMemoryData card) async {
    final positions = _decodeReceipts(card.sourceMessageIds);
    final messages = _chat.messages;
    final entries = [
      for (final pos in positions)
        if (pos >= 0 && pos < messages.length)
          (
            pos: pos,
            line:
                '#$pos  ${messages[pos].sender}: '
                '${messages[pos].displayText}',
          ),
    ];
    final jump = widget.onJumpToMessage;
    final jumpTo = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Where this memory came from',
          style: TextStyle(fontSize: 15, color: AppColors.textPrimary(ctx)),
        ),
        content: SizedBox(
          width: 420,
          child: entries.isEmpty
              ? Text(
                  'The cited messages are no longer in this chat.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(ctx),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (jump != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Tap a line to go to it in the chat.',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textTertiary(ctx),
                            ),
                          ),
                        ),
                      for (final entry in entries)
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: jump == null
                              ? null
                              : () => Navigator.of(ctx).pop(entry.pos),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Text(
                              entry.line,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.textSecondary(ctx),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
          ),
        ],
      ),
    );
    if (jumpTo == null || jump == null || !mounted) return;
    // Close the journal itself so the chat is visible, THEN scroll.
    Navigator.of(context).pop();
    jump(jumpTo);
  }
}
