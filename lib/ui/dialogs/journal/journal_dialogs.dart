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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One receipt line: the 0-based message position and its display text.
typedef JournalReceiptEntry = ({int pos, String line});

/// Asks before retiring the memory whose text is [content]. True = retire.
Future<bool?> showRetireMemoryDialog(BuildContext context, String content) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardOf(ctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        'Retire this memory?',
        style: TextStyle(fontSize: 15, color: AppColors.textPrimary(ctx)),
      ),
      content: Text(
        '"$content"\n\nThe conversation itself is untouched — only '
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
}

/// Lists the chat lines a memory was written from. When [canJump], tapping
/// a line pops with its position; otherwise the lines are inert.
Future<int?> showJournalReceiptsDialog(
  BuildContext context, {
  required List<JournalReceiptEntry> entries,
  required bool canJump,
}) {
  return showDialog<int>(
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
                    if (canJump)
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
                        onTap: !canJump
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
}
