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
import 'package:flutter/services.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Dialog showing token budget breakdown of the last assembled prompt.
class ContextViewerDialog extends StatefulWidget {
  final ChatService chatService;

  const ContextViewerDialog({super.key, required this.chatService});

  // theme-keep: data-viz legend hues — every section needs a DISTINCT
  // identity color for the stacked bar + rows (shared verbatim with the web
  // ContextBudgetModal). Chrome around them is AppColors.
  static const sectionColors = {
    'System Prompt': Color(0xFF3B82F6),
    'Lorebook': Color(0xFF8B5CF6),
    'Persona': Color(0xFF06B6D4),
    'Scenario': Color(0xFF10B981),
    'Examples': Color(0xFFF59E0B),
    'Chat History': Color(0xFF6366F1),
    'Post-History': Color(0xFFEF4444),
    'Journal': Color(0xFFF97316),
    'Realism Mode': Color(0xFFEC4899),
    'Memories': Color(0xFF14B8A6),
    'Speaker Card': Color(0xFF7C3AED),
  };

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
        final budget = chat.lastPromptBudget;
        final totalTokens = budget.values.fold<int>(0, (a, b) => a + b);
        final contextLimit = chat.contextSize;
        final usage = contextLimit > 0 ? totalTokens / contextLimit : 0.0;

        final Color usageColor;
        if (usage >= 0.9) {
          usageColor = AppColors.negativeAccentOf(context);
        } else if (usage >= 0.7) {
          usageColor = AppColors.porchAmberOf(context);
        } else {
          usageColor = AppColors.bondHighOf(context);
        }

        final source = _sourceLabel();
        final at = chat.promptBudgetAssembledAt;

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
                      const Icon(
                        Icons.analytics_outlined,
                        color: AppColors.formMasterAccent,
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
                                Colors.grey;
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
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shrinkWrap: true,
                    children: budget.entries.map((e) {
                      final color =
                          ContextViewerDialog.sectionColors[e.key] ??
                          Colors.grey;
                      final pct = totalTokens > 0
                          ? '${(e.value / totalTokens * 100).toStringAsFixed(1)}%'
                          : '0%';
                      return _SectionRow(
                        label: e.key,
                        tokens: e.value,
                        percentage: pct,
                        color: color,
                        rawText: chat.lastPromptSections[e.key] ?? '',
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

class _SectionRow extends StatefulWidget {
  final String label;
  final int tokens;
  final String percentage;
  final Color color;
  final String rawText;

  const _SectionRow({
    required this.label,
    required this.tokens,
    required this.percentage,
    required this.color,
    required this.rawText,
  });

  @override
  State<_SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<_SectionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '${widget.tokens}',
                  style: TextStyle(
                    color: widget.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    widget.percentage,
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.iconSecondary(context),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.color.withValues(alpha: 0.3)),
            ),
            constraints: const BoxConstraints(maxHeight: 240),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.copy_outlined,
                    size: 14,
                    color: AppColors.iconSecondary(context),
                  ),
                  padding: const EdgeInsets.only(top: 6, right: 6),
                  constraints: const BoxConstraints(),
                  tooltip: 'Copy section text',
                  onPressed: widget.rawText.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(
                            ClipboardData(text: widget.rawText),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Section text copied.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText(
                        widget.rawText.isEmpty
                            ? '(Empty in this snapshot.)'
                            : widget.rawText,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Divider(height: 1, color: AppColors.borderOf(context)),
      ],
    );
  }
}
