// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/memory_rag_model_note.dart';

class GroupMemoryRAGTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const GroupMemoryRAGTab({
    super.key,
    required this.chatService,
    this.groupRepo,
  });

  @override
  State<GroupMemoryRAGTab> createState() => _GroupMemoryRAGTabState();
}

class _GroupMemoryRAGTabState extends State<GroupMemoryRAGTab> {
  bool _groupRagEnabled = true;
  int _retrievalCount = 4;
  double _memoryBudgetPercent = 10.0;
  Map<String, double> _charPriorities = {};
  List<CharacterCard> _chars = [];

  @override
  void initState() {
    super.initState();
    _initializeFromActiveGroup();
  }

  void _initializeFromActiveGroup() {
    final group = widget.chatService.activeGroup;
    if (group == null) {
      _chars = [];
      _charPriorities = {};
      return;
    }

    _chars = widget.chatService.groupCharacters;

    // Load live values from ChatService (persisted in sessions.group_realism_state v30).
    _groupRagEnabled = widget.chatService.groupRagEnabled;
    _retrievalCount = widget.chatService.groupRetrievalCount;
    _memoryBudgetPercent = widget.chatService.groupMemoryBudgetPercent;

    // Read priorities per CARD — storage is keyed by stable character id,
    // so the old name-keyed lookup always missed and showed 1.0.
    _charPriorities = {
      for (final c in _chars)
        c.name: widget.chatService.ragPriorityForGroupCharacter(c),
    };
  }

  void _updateCharPriority(CharacterCard char, double value) {
    setState(() {
      _charPriorities[char.name] = value;
    });
    // Live-apply like the sibling controls (budget %, enable toggle). These
    // two setters used to only touch local state — the sliders were dead.
    widget.chatService.setRAGPriorityForGroupCharacter(char, value);
  }

  void _updateRetrievalCount(int value) {
    setState(() {
      _retrievalCount = value;
    });
    widget.chatService.setGroupRetrievalCount(value);
  }

  void _updateMemoryBudget(double value) {
    setState(() {
      _memoryBudgetPercent = value;
    });
    widget.chatService.setGroupMemoryBudgetPercent(value);
  }

  void _toggleGroupRag(bool value) {
    setState(() {
      _groupRagEnabled = value;
    });
    widget.chatService.setGroupRAGEnabled(value);
  }

  void _resetToDefaults() {
    setState(() {
      _groupRagEnabled = true;
      _retrievalCount = 4;
      _memoryBudgetPercent = 10.0;
      _charPriorities = {for (final c in _chars) c.name: 1.0};
    });
    // Push the reset to the service too — it used to be display-only.
    widget.chatService.setGroupRAGEnabled(true);
    widget.chatService.setGroupRetrievalCount(4);
    widget.chatService.setGroupMemoryBudgetPercent(10.0);
    for (final c in _chars) {
      widget.chatService.setRAGPriorityForGroupCharacter(c, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.chatService.activeGroup;

    if (group == null) {
      return Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.psychology, color: Colors.purpleAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Memory & RAG — ${group.name}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Per-group RAG controls. Memories are embedded from this group\'s conversation history and retrieved when context is dropped.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 16),

            // Group-level RAG section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.toggle_on,
                        size: 18,
                        color: Colors.purpleAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Enable RAG for this group',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: _groupRagEnabled,
                        activeTrackColor: Colors.purpleAccent,
                        onChanged: _toggleGroupRag,
                      ),
                    ],
                  ),
                  if (_groupRagEnabled) const GroupRagModelNote(),
                  if (!_groupRagEnabled)
                    Padding(
                      padding: EdgeInsets.only(left: 26, top: 2, bottom: 8),
                      child: Text(
                        'Retrieval skipped for this group even if global RAG is on.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Retrieval count
                  Row(
                    children: [
                      Text(
                        'Memories per turn (retrieval limit)',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _retrievalCount == 0 ? 'All' : '$_retrievalCount',
                        style: const TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 12,
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
                      value: _retrievalCount.toDouble(),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      activeColor: Colors.purpleAccent,
                      inactiveColor: AppColors.borderOf(context),
                      onChanged: (v) => _updateRetrievalCount(v.round()),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Memory budget (context length feel)
                  Row(
                    children: [
                      Text(
                        'RAG memory budget (% of context)',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_memoryBudgetPercent.round()}%',
                        style: const TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 12,
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
                      value: _memoryBudgetPercent,
                      min: 5,
                      max: 25,
                      divisions: 20,
                      activeColor: Colors.purpleAccent,
                      inactiveColor: AppColors.borderOf(context),
                      onChanged: _updateMemoryBudget,
                    ),
                  ),

                  const SizedBox(height: 4),
                  Text(
                    'How much of a moment each memory keeps is set in a '
                    'one-on-one chat\'s sidebar, under Memory (RAG), and '
                    'applies to every chat.',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary(context),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Per-character priorities
            Row(
              children: [
                Icon(Icons.people_alt, size: 18, color: Colors.purpleAccent),
                const SizedBox(width: 8),
                Text(
                  'Per-Character Memory Importance',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _resetToDefaults,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Reset to defaults',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Boost or suppress how heavily each character\'s past messages influence RAG results (0.0–2.0). 1.0 = normal relevance scoring.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),

            if (_chars.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No characters loaded for this group.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              )
            else
              ..._chars.map((char) {
                final priority = _charPriorities[char.name] ?? 1.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.purpleAccent.withValues(
                          alpha: 0.25,
                        ),
                        child: Text(
                          char.name.isNotEmpty
                              ? char.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text(
                          char.name,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                          ),
                          child: Slider(
                            value: priority,
                            min: 0.0,
                            max: 2.0,
                            divisions: 20,
                            activeColor: Colors.purpleAccent,
                            inactiveColor: AppColors.borderOf(context),
                            onChanged: (v) => _updateCharPriority(char, v),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          priority.toStringAsFixed(1),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
