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

import 'package:front_porch_ai/ui/pages/home/enhance/wizard/enhance_wizard_chrome.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Step 5 of the AI Enhance wizard: the copy is saved; offer to bring the
/// base character's chats along onto it.
class EnhanceChatsCopyStep extends StatelessWidget {
  const EnhanceChatsCopyStep({
    super.key,
    required this.characterName,
    required this.savedCopyName,
    required this.chatCount,
    required this.copying,
    required this.copyDone,
    required this.copyTotal,
    required this.copiedCount,
    required this.copyError,
    required this.onCopy,
  });

  final String characterName;

  /// The saved "(Enhanced)" copy's name; null falls back to the default.
  final String? savedCopyName;
  final int chatCount;
  final bool copying;
  final int copyDone;
  final int copyTotal;

  /// Chats copied so far; null until a copy has finished.
  final int? copiedCount;
  final String? copyError;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final name = characterName;
    final copyName = savedCopyName ?? '$name (Enhanced)';
    final chatWord = chatCount == 1 ? 'chat' : 'chats';

    return EnhanceStepScroll(
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle,
              size: 22,
              color: AppColors.porchAmberOf(context),
            ),
            const SizedBox(width: 8),
            Expanded(child: EnhanceStepHeading(text: '"$copyName" is saved!')),
          ],
        ),
        EnhanceStepBody(
          text:
              'One last thing: $copyName starts with an empty chat list. Want to '
              'bring $name\'s $chatCount $chatWord along? Each one is copied in '
              'full — messages, journal memories, relationship state — so you can '
              'pick up right where you left off with the enhanced version. '
              '$name keeps the originals either way.',
        ),
        if (copiedCount == null) ...[
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: copying ? null : onCopy,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.porchAmberOf(context),
                foregroundColor: AppColors.onChaosAccent,
              ),
              icon: copying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.copy_all, size: 18),
              label: Text(
                copying
                    ? 'Copying... $copyDone of $copyTotal'
                    : 'Copy my $chatWord over',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Or just hit Finish to skip this.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary(context),
            ),
          ),
        ] else
          EnhanceCallout(
            icon: Icons.check_circle_outline,
            text: copiedCount == 0
                ? 'Nothing to copy — $name has no chats yet.'
                : 'Copied $copiedCount $chatWord. You\'ll land in the newest '
                      'one next time you open $copyName.',
          ),
        if (copyError != null) ...[
          const SizedBox(height: 8),
          EnhanceCallout(
            icon: Icons.error_outline,
            text: copyError!,
            accent: AppColors.porchTerracottaOf(context),
          ),
        ],
      ],
    );
  }
}
