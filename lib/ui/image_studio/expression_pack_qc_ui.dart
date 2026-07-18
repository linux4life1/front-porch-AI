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

import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Slightly-tinted rounded backdrop so overlay controls stay legible on any
/// generated image. Shared by the grid's keep/re-roll chips and the QC badge.
Widget packOverlayChip(BuildContext context, {required Widget child}) {
  return Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceOf(context).withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(6),
    ),
    child: child,
  );
}

/// The amber "advisory warning" pair used across the Image Studio (same pair
/// as the group-shot caveat in studio_view.dart).
Color _qcWarnColor(BuildContext context) => AppColors.resolve(
  context,
  const Color(0xFFDAA83F),
  const Color(0xFFA97514),
);

/// Per-cell Vision QC verdict badge: green check when the image cleanly
/// passed, amber warning (with the reasons in a tooltip) otherwise. Purely
/// advisory — it never changes the keep state by itself.
class PackQcBadge extends StatelessWidget {
  const PackQcBadge({super.key, required this.verdict, required this.emotion});

  final PackQcVerdict verdict;
  final String emotion;

  @override
  Widget build(BuildContext context) {
    final clean = verdict.pass && verdict.note.isEmpty;
    final message = clean
        ? 'Looks good — same person, expression reads as «$emotion»'
        : [
            if (!verdict.samePerson) 'May be a different person',
            if (!verdict.expressionMatches)
              'Expression doesn\'t read as «$emotion»',
            if (verdict.note.isNotEmpty) verdict.note,
          ].join('\n');
    return packOverlayChip(
      context,
      child: Tooltip(
        message: message,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            clean ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 16,
            color: clean ? AppColors.bondHighOf(context) : _qcWarnColor(context),
          ),
        ),
      ),
    );
  }
}

/// The Vision-check cluster for the grid footer: the "Vision check" trigger
/// (spinner while the capability resolve or the QC pass runs, with a stop
/// affordance), plus the post-run "Uncheck flagged (N)" action and the
/// "couldn't be checked" caption. Visibility (done images exist, session not
/// running, not importing) is decided by the grid's footer — this widget
/// always renders its content.
class PackQcFooterControls extends StatelessWidget {
  const PackQcFooterControls({
    super.key,
    required this.session,
    required this.qc,
    required this.resolvingVision,
    required this.onVisionCheck,
  });

  final ExpressionPackSession session;
  final ExpressionPackQc? qc;

  /// True while the dialog resolves whether the active text LLM has vision.
  final bool resolvingVision;
  final VoidCallback onVisionCheck;

  @override
  Widget build(BuildContext context) {
    final qc = this.qc;
    final running = qc != null && qc.isRunning;
    final children = <Widget>[];

    if (qc != null && !running && qc.unparsedCount > 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            '${qc.unparsedCount} couldn\'t be checked',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    children.add(
      OutlinedButton.icon(
        onPressed: (running || resolvingVision) ? null : onVisionCheck,
        icon: (running || resolvingVision)
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.visibility_outlined,
                size: 16,
                color: AppColors.iconSecondary(context),
              ),
        label: Text(
          running
              ? 'Checking ${qc.checkedCount} / ${qc.totalToCheck}…'
              : 'Vision check',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.borderOf(context)),
        ),
      ),
    );

    if (running) {
      children.add(
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          iconSize: 16,
          tooltip: 'Stop checking',
          icon: Icon(Icons.close, color: AppColors.iconSecondary(context)),
          onPressed: qc.cancel,
        ),
      );
    } else {
      // Count flagged (QC failed) slots that are still kept, so the button
      // disappears once it has done its job.
      final flaggedKept = _flaggedKeptIndices();
      if (flaggedKept.isNotEmpty) {
        children.add(
          TextButton(
            onPressed: () {
              for (final i in flaggedKept) {
                session.setKeep(i, false);
              }
            },
            child: Text(
              'Uncheck flagged (${flaggedKept.length})',
              style: TextStyle(color: _qcWarnColor(context), fontSize: 12),
            ),
          ),
        );
      }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  /// Indices of slots the QC pass flagged (did not pass) that the user still
  /// has marked for import. The one explicit "Uncheck flagged" action targets
  /// exactly these — pass-with-note ambers stay untouched.
  List<int> _flaggedKeptIndices() {
    final slots = session.slots;
    return [
      for (var i = 0; i < slots.length; i++)
        if (slots[i].keep && slots[i].qc?.pass == false) i,
    ];
  }
}
