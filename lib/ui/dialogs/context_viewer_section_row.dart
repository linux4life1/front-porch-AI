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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One expandable section line in the Context Viewer: colour, tokens, share,
/// and the section's raw text with a copy button.
class ContextSectionRow extends StatefulWidget {
  final String label;
  final int tokens;
  final String percentage;
  final Color color;
  final String rawText;

  /// Shown when [rawText] is empty.
  final String emptyText;

  const ContextSectionRow({
    super.key,
    required this.label,
    required this.tokens,
    required this.percentage,
    required this.color,
    required this.rawText,
    this.emptyText = '(Empty in this snapshot.)',
  });

  @override
  State<ContextSectionRow> createState() => _ContextSectionRowState();
}

class _ContextSectionRowState extends State<ContextSectionRow> {
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
                            ? widget.emptyText
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
