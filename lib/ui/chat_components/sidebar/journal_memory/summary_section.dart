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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';
import 'summary_recap_field.dart';

/// "Where we are" sidebar panel — the Journal's per-chat recap.
/// Shows the Journal enable toggle, the editable recap text, pause/regenerate
/// controls, and the maintenance-pass interval. Lives inside the
/// Journal & Memory accordion (the accordion provides collapse — this panel's
/// old chevron header is gone). The full Journal card UI lands in phase 3 —
/// docs/design/journal-memory.md §8.
class SummarySection extends StatefulWidget {
  final ChatService chatService;
  const SummarySection({super.key, required this.chatService});

  @override
  State<SummarySection> createState() => SummarySectionState();
}

class SummarySectionState extends State<SummarySection> {
  late TextEditingController _controller;
  bool _showSettings = false;
  bool _editingRecap = false;
  double? _dragJournalInterval;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.chatService.summary);
    widget.chatService.addListener(_onChatChanged);
  }

  // ChatService notifies constantly during streaming (every token batch);
  // this section only renders the recap + a few journal scalars, so rebuild
  // ONLY when one of them actually changed — the unconditional setState here
  // used to re-render the whole section at the full streaming rate. (Same
  // guarded-listener pattern as journal_panel.dart next door.)
  String _lastSummary = '';
  bool _lastGenerating = false;
  bool _lastPaused = false;
  int _lastIndex = -1;

  void _onChatChanged() {
    if (!mounted) return;
    final c = widget.chatService;
    final changed =
        c.summary != _lastSummary ||
        c.isSummaryGenerating != _lastGenerating ||
        c.summaryPaused != _lastPaused ||
        c.summaryLastIndex != _lastIndex;
    if (!changed) return;
    _lastSummary = c.summary;
    _lastGenerating = c.isSummaryGenerating;
    _lastPaused = c.summaryPaused;
    _lastIndex = c.summaryLastIndex;
    if (_controller.text != c.summary) {
      _controller.text = c.summary;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onChatChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final enabled = storage.memorySettings.journalEnabled;
    final accent = AppColors.journalAccentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with spinner + enable toggle
        SidebarSubHeader(
          icon: Icons.auto_stories,
          label: 'Where we are',
          accent: accent,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (enabled && widget.chatService.isSummaryGenerating)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  ),
                ),
              SizedBox(
                height: 28,
                child: FittedBox(
                  child: Tooltip(
                    message:
                        'Turning the Journal off also stops long-term memory '
                        'AND this "Where we are" recap — the character only '
                        'remembers what still fits in the context window.',
                    child: Switch(
                      value: enabled,
                      onChanged: (val) =>
                          storage.memorySettings.setJournalEnabled(val),
                      activeTrackColor: accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 20),
            child: Text(
              'Journal is off: long-term memory and this recap are paused, '
              'so the character only remembers what still fits in the '
              'context window. Turn it back on to resume the diary of what '
              'happened and how it felt.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),

        if (enabled) ...[
          const SizedBox(height: 8),
          SummaryRecapField(
            controller: _controller,
            text: widget.chatService.summary,
            editing: _editingRecap,
            accent: accent,
            onChanged: widget.chatService.setSummary,
            onStartEditing: () => setState(() => _editingRecap = true),
            onStopEditing: () => setState(() => _editingRecap = false),
          ),
          const SizedBox(height: 6),
          // Controls row
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Row(
              children: [
                // Pause/Resume toggle
                InkWell(
                  onTap: () => widget.chatService.setSummaryPaused(
                    !widget.chatService.summaryPaused,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.chatService.summaryPaused
                              ? Icons.play_arrow
                              : Icons.pause,
                          size: 14,
                          color: widget.chatService.summaryPaused
                              ? AppColors.taskAccentOf(context)
                              : AppColors.iconSecondary(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.chatService.summaryPaused ? 'Paused' : 'Auto',
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.chatService.summaryPaused
                                ? AppColors.taskAccentOf(context)
                                : AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.chatService.summary.trim().isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _editingRecap = !_editingRecap),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        _editingRecap ? 'Done' : 'Edit',
                        style: TextStyle(
                          fontSize: 10,
                          color: _editingRecap
                              ? accent
                              : AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // Settings gear toggle
                InkWell(
                  onTap: () => setState(() => _showSettings = !_showSettings),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Icon(
                      Icons.tune,
                      size: 14,
                      color: _showSettings
                          ? accent
                          : AppColors.iconSecondary(context),
                    ),
                  ),
                ),
                const Spacer(),
                // Regenerate button (runs a full Journal pass: cards + recap)
                InkWell(
                  onTap: widget.chatService.isSummaryGenerating
                      ? null
                      : () => widget.chatService.forceSummaryUpdate(),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh,
                          size: 14,
                          color: widget.chatService.isSummaryGenerating
                              ? AppColors.textTertiary(context)
                              : accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Regen',
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.chatService.isSummaryGenerating
                                ? AppColors.textTertiary(context)
                                : accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.chatService.summaryLastIndex > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 24),
              child: Text(
                'Last updated at message #${widget.chatService.summaryLastIndex}',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),

          // Expandable settings panel
          if (_showSettings) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Update Interval
                    Row(
                      children: [
                        Text(
                          'Update every',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(_dragJournalInterval ?? storage.memorySettings.journalInterval.toDouble()).round()} messages',
                          style: TextStyle(
                            fontSize: 11,
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value:
                            _dragJournalInterval ??
                            storage.memorySettings.journalInterval.toDouble(),
                        min: 3,
                        max: 50,
                        divisions: 47,
                        activeColor: accent,
                        inactiveColor: AppColors.borderOf(context),
                        onChanged: (val) =>
                            setState(() => _dragJournalInterval = val),
                        onChangeEnd: (val) {
                          _dragJournalInterval = null;
                          storage.memorySettings.setJournalInterval(
                            val.toInt(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Review-first mode (phase 4): proposed journal changes
                    // wait in the sidebar for approval instead of applying.
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Review updates first',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: FittedBox(
                            child: Switch(
                              value: storage.memorySettings.journalReviewFirst,
                              activeThumbColor: accent,
                              onChanged: (val) => storage.memorySettings
                                  .setJournalReviewFirst(val),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Proposed journal changes wait below for your approval '
                      'instead of saving automatically.',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // LLMerta Mafia nights → Journal (docs/design/llmerta-porch-memories.md)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Import Mafia game nights',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: FittedBox(
                            child: Switch(
                              value: storage
                                  .memorySettings
                                  .importLlmertaPorchMemories,
                              activeThumbColor: accent,
                              onChanged: (val) => storage.memorySettings
                                  .setImportLlmertaPorchMemories(val),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'When you open a chat, plant diary cards from finished '
                      'LLMerta games (matching persona + character) and have '
                      'the character bring up the night on their next reply.',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 12,
                          color: AppColors.porchAmberOf(context),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Uses your active LLM — consumes tokens on paid APIs.',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.porchAmberOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
