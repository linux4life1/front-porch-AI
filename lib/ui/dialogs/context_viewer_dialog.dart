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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/context_viewer_section_row.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Dialog showing token budget breakdown of the last assembled prompt, or of
/// one reply's prompt when [snapshot] is given.
class ContextViewerDialog extends StatefulWidget {
  final ChatService chatService;

  /// A reply's recorded prompt. When set, the dialog shows that send instead
  /// of the chat's last one and offers no live refresh.
  final ContextViewerSnapshot? snapshot;

  const ContextViewerDialog({
    super.key,
    required this.chatService,
    this.snapshot,
  });

  // Data-viz legend hues: every section needs a distinct identity color for
  // the stacked bar and rows. Chrome around them is AppColors.
  static const sectionColors = LegendColors.contextSections;

  @override
  State<ContextViewerDialog> createState() => _ContextViewerDialogState();
}

class _ContextViewerDialogState extends State<ContextViewerDialog> {
  bool _estimating = false;

  ChatService get chat => widget.chatService;

  Future<void> _refreshEstimate() async {
    if (_estimating) return;
    setState(() => _estimating = true);
    try {
      await chat.estimateContextBudgetNow();
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  String _sourceLabel() {
    switch (chat.promptBudgetSource) {
      case ContextBudgetSource.lastSend:
        return 'Last send';
      case ContextBudgetSource.estimate:
        return 'Estimate (now)';
      case ContextBudgetSource.none:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final snap = widget.snapshot;
        final budget = snap?.budget ?? chat.lastPromptBudget;
        final sections = snap?.sections ?? chat.lastPromptSections;
        final textPruned = snap != null && snap.sections.isEmpty;
        // Read only with a budget on screen: the empty state never needs it.
        final dropped = budget.isEmpty
            ? 0
            : snap?.droppedMessages ?? chat.promptDroppedMessages;
        final totalTokens = budget.values.fold<int>(0, (a, b) => a + b);
        final contextLimit = snap?.contextLimit ?? chat.contextSize;
        final usage = contextLimit > 0 ? totalTokens / contextLimit : 0.0;

        final Color usageColor;
        if (usage >= 0.9) {
          usageColor = AppColors.negativeAccentOf(context);
        } else if (usage >= 0.7) {
          usageColor = AppColors.porchAmberOf(context);
        } else {
          usageColor = AppColors.bondHighOf(context);
        }

        final source = snap != null ? 'This reply' : _sourceLabel();
        final at = snap != null
            ? snap.assembledAt
            : chat.promptBudgetAssembledAt;

        return Dialog(
          backgroundColor: AppColors.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderOf(context)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.analytics_outlined,
                        color: AppColors.formAccentOf(context),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Context Budget',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            if (source.isNotEmpty)
                              Text(
                                at != null
                                    ? '$source · ${_fmtTime(at)}'
                                    : source,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary(context),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (snap == null)
                        IconButton(
                          tooltip: 'Refresh estimate from this chat',
                          onPressed: _estimating ? null : _refreshEstimate,
                          icon: _estimating
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.iconSecondary(context),
                                  ),
                                )
                              : Icon(
                                  Icons.refresh,
                                  color: AppColors.iconSecondary(context),
                                  size: 20,
                                ),
                        ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: AppColors.iconSecondary(context),
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                if (budget.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.iconSecondary(context),
                          size: 32,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No budget for this chat yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Send a message to save the real breakdown, or tap '
                          'refresh for a quick estimate.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total: $totalTokens / $contextLimit tokens',
                              style: TextStyle(
                                color: usageColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${(usage * 100).toStringAsFixed(1)}%',
                              style: TextStyle(color: usageColor, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: usage.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: AppColors.surfaceContainerOf(
                              context,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              usageColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (budget.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 24,
                        child: Row(
                          children: budget.entries.map((e) {
                            final frac = totalTokens > 0
                                ? e.value / totalTokens
                                : 0.0;
                            final color =
                                ContextViewerDialog.sectionColors[e.key] ??
                                LegendColors.unknownSection;
                            return Expanded(
                              flex: (frac * 1000).round().clamp(1, 1000),
                              child: Tooltip(
                                message: '${e.key}: ${e.value} tokens',
                                child: Container(color: color),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                if (dropped > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Text(
                      droppedMessagesNote(dropped),
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (textPruned)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Text(
                      'Only the token counts are kept for older replies.',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shrinkWrap: true,
                    children: budget.entries.map((e) {
                      final color =
                          ContextViewerDialog.sectionColors[e.key] ??
                          LegendColors.unknownSection;
                      final pct = totalTokens > 0
                          ? '${(e.value / totalTokens * 100).toStringAsFixed(1)}%'
                          : '0%';
                      return ContextSectionRow(
                        label: e.key,
                        tokens: e.value,
                        percentage: pct,
                        color: color,
                        rawText: sections[e.key] ?? '',
                        emptyText: textPruned
                            ? '(Not kept for older replies.)'
                            : '(Empty in this snapshot.)',
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _fmtTime(DateTime t) {
    final l = t.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
