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
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Dialog showing token budget breakdown of the last assembled prompt.
class ContextViewerDialog extends StatelessWidget {
  final ChatService chatService;

  const ContextViewerDialog({super.key, required this.chatService});

  static const _sectionColors = {
    'System Prompt': Color(0xFF3B82F6),
    'Lorebook': Color(0xFF8B5CF6),
    'Persona': Color(0xFF06B6D4),
    'Scenario': Color(0xFF10B981),
    'Examples': Color(0xFFF59E0B),
    'Chat History': Color(0xFF6366F1),
    'Post-History': Color(0xFFEF4444),
  };

  @override
  Widget build(BuildContext context) {
    final budget = chatService.lastPromptBudget;
    final totalTokens = budget.values.fold<int>(0, (a, b) => a + b);
    final contextLimit = chatService.contextSize;
    final usage = contextLimit > 0 ? totalTokens / contextLimit : 0.0;

    Color usageColor;
    if (usage >= 0.9) {
      usageColor = Colors.redAccent;
    } else if (usage >= 0.7) {
      usageColor = Colors.amber;
    } else {
      usageColor = Colors.greenAccent;
    }

    return Dialog(
      backgroundColor: const Color(0xFF0f172a),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.analytics_outlined,
                    color: AppColors.formMasterAccent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Context Budget',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Total usage bar
            if (budget.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white24, size: 32),
                    SizedBox(height: 10),
                    Text(
                      'Send a message to populate the context budget.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Budget is captured each time a prompt is assembled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white24, fontSize: 11),
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
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(usageColor),
                      ),
                    ),
                  ],
                ),
              ),

            // Stacked bar
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
                        final color = _sectionColors[e.key] ?? Colors.grey;
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

            // Section breakdown list
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shrinkWrap: true,
                children: budget.entries.map((e) {
                  final color = _sectionColors[e.key] ?? Colors.grey;
                  final pct = totalTokens > 0
                      ? '${(e.value / totalTokens * 100).toStringAsFixed(1)}%'
                      : '0%';
                  return _SectionRow(
                    label: e.key,
                    tokens: e.value,
                    percentage: pct,
                    color: color,
                    rawText: _getRawTextForSection(e.key),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _getRawTextForSection(String section) {
    // Provide a hint - we don't store individual sections, but we have the full prompt
    final prompt = chatService.lastAssembledPrompt;
    if (prompt.isEmpty) return '(No data — send a message first)';

    switch (section) {
      case 'System Prompt':
        final idx = prompt.indexOf('\n');
        if (idx > 0) return prompt.substring(0, idx);
        return prompt;
      case 'Chat History':
        final startIdx = prompt.indexOf('<START>\n');
        if (startIdx >= 0) {
          final after = prompt.substring(startIdx + 8);
          return after.length > 500 ? '${after.substring(0, 500)}...' : after;
        }
        return '';
      default:
        return '(Tap to view full prompt)';
    }
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
                    style: const TextStyle(color: Colors.white, fontSize: 13),
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
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white24,
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1e293b),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.color.withValues(alpha: 0.3)),
            ),
            child: SelectableText(
              widget.rawText,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        const Divider(height: 1, color: Colors.white10),
      ],
    );
  }
}
