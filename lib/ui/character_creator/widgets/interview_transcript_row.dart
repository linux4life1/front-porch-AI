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

import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The Profile step's "Interview transcript" (docs/design/creator-ui-spec.md,
/// "Collapsed row"): a 44px row, radius 12, 1px `line`, transparent, that
/// opens the interview read only, so the user can see where the rewrite came
/// from. Disabled at 50% while a rewrite runs.
class InterviewTranscriptRow extends StatelessWidget {
  const InterviewTranscriptRow({
    super.key,
    required this.transcript,
    required this.open,
    required this.onToggle,
    this.enabled = true,
  });

  final String transcript;
  final bool open;
  final VoidCallback onToggle;
  final bool enabled;

  /// Questions are the transcript's `Q:` lines.
  int get questions =>
      RegExp(r'^Q: ', multiLine: true).allMatches(transcript).length;

  @override
  Widget build(BuildContext context) {
    final line = StudioColors.lineOf(context);
    final row = InkWell(
      key: const ValueKey('profile-transcript'),
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onToggle : null,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: line),
        ),
        child: Row(
          spacing: 10,
          children: [
            Icon(
              open ? Icons.expand_more : Icons.chevron_right,
              size: 18,
              color: StudioColors.proseOf(context),
            ),
            Text(
              'Interview transcript',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: StudioColors.proseOf(context),
              ),
            ),
            Expanded(
              child: Text(
                '$questions questions, read only, so you can see where the '
                'rewrite came from',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          row,
          if (open)
            Container(
              key: const ValueKey('profile-transcript-body'),
              constraints: const BoxConstraints(maxHeight: 360),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: StudioColors.bgOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: line),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  transcript,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: StudioColors.proseOf(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
