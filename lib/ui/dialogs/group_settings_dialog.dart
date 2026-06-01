// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';

/// Main settings dialog for a Group Chat.
/// This is the central place for all per-group and per-character configuration.
class GroupSettingsDialog extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;

  const GroupSettingsDialog({
    super.key,
    required this.chatService,
    this.groupRepo,
  });

  @override
  State<GroupSettingsDialog> createState() => _GroupSettingsDialogState();
}

class _GroupSettingsDialogState extends State<GroupSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 720,
        height: 620,
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Text(
                    'Group Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: AppColors.iconSecondary(context),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Prompt Engineering'),
                Tab(text: 'Memory & RAG'),
                Tab(text: 'Realism & Needs'),
                Tab(text: 'General'),
                Tab(text: 'Lorebook & Worlds'),
              ],
            ),

            Divider(height: 1, color: AppColors.borderOf(context)),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _PromptEngineeringTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                  _MemoryRAGTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                  _RealismNeedsTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                  _GeneralTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                  _LorebookWorldsTab(
                    chatService: widget.chatService,
                    groupRepo: widget.groupRepo,
                  ),
                ],
              ),
            ),

            // Footer
            //
            // Philosophy for this dialog:
            // - Most controls edit the live GroupChat in memory (immediate effect on the running session).
            // - There is only ONE persistence action: "Save" writes the current state to the repository.
            // - Per-tab save buttons were removed as part of the 2026 UX overhaul (they were confusing and redundant).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Close',
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.groupRepo != null)
                    OutlinedButton(
                      onPressed: () {
                        final g = widget.chatService.activeGroup;
                        if (g != null) {
                          widget.groupRepo!.save(g);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Group settings saved.'),
                              backgroundColor: Color(0xFF10B981),
                            ),
                          );
                        }
                      },
                      child: Text(
                        'Save',
                        style: TextStyle(color: AppColors.textPrimary(context)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Placeholder tabs — will be implemented by sub-agents / follow-up work

class _PromptEngineeringTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _PromptEngineeringTab({required this.chatService, this.groupRepo});

  @override
  State<_PromptEngineeringTab> createState() => _PromptEngineeringTabState();
}

class _PromptEngineeringTabState extends State<_PromptEngineeringTab> {
  // Group-level controllers / state (edited locally, applied on Save)
  late final TextEditingController _groupSystemController;
  late final TextEditingController _groupAuthorNoteController;
  int _groupAuthorNoteStrength = 4;

  // Per-character editing state. Keys are live CharacterCard instances
  // (stable references from chatService.groupCharacters).
  final Map<CharacterCard, TextEditingController> _perCharNoteControllers = {};
  final Map<CharacterCard, int> _perCharStrengths = {};

  // Per-character group system prompt overrides (Path B feature).
  final Map<CharacterCard, TextEditingController>
  _perCharSystemPromptControllers = {};

  // Per-character accent colors (matches chat sidebar palette)
  static const List<Color> _charColors = [
    Color(0xFF8B5CF6), // Purple
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFFEF4444), // Red
    Color(0xFF3B82F6), // Blue
    Color(0xFFEC4899), // Pink
    Color(0xFF14B8A6), // Teal
    Color(0xFFF97316), // Orange
  ];

  Color _charColor(int index) => _charColors[index % _charColors.length];

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onServiceChanged);
    _initEditingState();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _initEditingState() {
    final cs = widget.chatService;
    final group = cs.activeGroup;

    _groupSystemController = TextEditingController(
      text: group?.systemPrompt ?? '',
    );
    _groupAuthorNoteController = TextEditingController(text: cs.authorNote);
    _groupAuthorNoteStrength = cs.authorNoteStrength;

    // Pre-create controllers for current characters using live getters
    // (so first render has correct starting values).
    for (final c in cs.groupCharacters) {
      _getOrCreateNoteController(c); // creates + populates from service
      _perCharStrengths[c] ??= cs.getAuthorNoteStrengthForGroupCharacter(c);
    }
  }

  TextEditingController _getOrCreateNoteController(CharacterCard c) {
    return _perCharNoteControllers.putIfAbsent(c, () {
      final initial = widget.chatService.getAuthorNoteForGroupCharacter(c);
      return TextEditingController(text: initial);
    });
  }

  TextEditingController _getOrCreateSystemPromptController(CharacterCard c) {
    return _perCharSystemPromptControllers.putIfAbsent(c, () {
      final initial = widget.chatService.getSystemPromptForGroupCharacter(c);
      return TextEditingController(text: initial);
    });
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceChanged);

    _groupSystemController.dispose();
    _groupAuthorNoteController.dispose();

    for (final ctrl in _perCharNoteControllers.values) {
      ctrl.dispose();
    }
    _perCharNoteControllers.clear();
    _perCharStrengths.clear();

    for (final ctrl in _perCharSystemPromptControllers.values) {
      ctrl.dispose();
    }
    _perCharSystemPromptControllers.clear();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final chars = cs.groupCharacters;
    final hasGroup = cs.activeGroup != null && chars.isNotEmpty;

    if (!hasGroup) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.group_off_outlined,
              size: 48,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            const Text(
              'No active group chat',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Author\'s notes and group prompts are only available in group mode.',
              style: TextStyle(color: Colors.white24, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Group System Prompt ─────────────────────────────────────
                const Row(
                  children: [
                    Icon(Icons.code, size: 16, color: Colors.blueAccent),
                    SizedBox(width: 6),
                    Text(
                      'Group System Prompt',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Overrides the default group system prompt when non-empty.',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: _groupSystemController,
                  maxLines: 5,
                  minLines: 3,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Custom system prompt for the entire group...',
                    hintStyle: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.borderOf(context),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.borderOf(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.blueAccent),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onChanged: (_) {},
                ),

                const SizedBox(height: 20),

                // ── Per-Character System Prompts (Group Only) ───────────────
                const Row(
                  children: [
                    Icon(Icons.code, size: 16, color: Colors.tealAccent),
                    SizedBox(width: 6),
                    Text(
                      'Per-Character System Prompts (Group Only)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.tealAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Full system prompt instructions that only apply to this character while inside this specific group. These take precedence over the character\'s normal card system prompt.',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
                const SizedBox(height: 12),

                // Per-character system prompt editors
                for (int i = 0; i < chars.length; i++)
                  _buildCharacterSystemPromptEditor(chars[i], i),

                const SizedBox(height: 20),

                // ── Per-Character Author's Notes ────────────────────────────
                const Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: Colors.purpleAccent,
                    ),
                    SizedBox(width: 6),
                    Text(
                      "Per-Character Author's Notes",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.purpleAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Specific notes injected only when that character is the current speaker (after any group note). Strength is independent per character.',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
                const SizedBox(height: 12),

                // Character editors (reactive to current groupCharacters)
                for (int i = 0; i < chars.length; i++)
                  _buildCharacterNoteEditor(chars[i], i),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCharacterNoteEditor(CharacterCard c, int index) {
    final noteCtrl = _getOrCreateNoteController(c);
    final strength = _perCharStrengths.putIfAbsent(
      c,
      () => widget.chatService.getAuthorNoteStrengthForGroupCharacter(c),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _charColor(index),
                backgroundImage: c.imagePath != null
                    ? FileImage(File(c.imagePath!))
                    : null,
                child: c.imagePath == null
                    ? Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Note field
          AppTextField(
            controller: noteCtrl,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: "Author's note for ${c.name} (when they speak)...",
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.purpleAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
            onChanged: (_) {},
          ),
          const SizedBox(height: 8),

          // Compact strength slider (1-10)
          Row(
            children: [
              const Text(
                'Strength',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                    activeTrackColor: _charColor(index),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: _charColor(index),
                  ),
                  child: Slider(
                    value: strength.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (val) {
                      setState(() {
                        _perCharStrengths[c] = val.round();
                      });
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 22,
                child: Text(
                  '$strength',
                  style: TextStyle(
                    color: _charColor(index),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterSystemPromptEditor(CharacterCard c, int index) {
    final promptCtrl = _getOrCreateSystemPromptController(c);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _charColor(index),
                backgroundImage: c.imagePath != null
                    ? FileImage(File(c.imagePath!))
                    : null,
                child: c.imagePath == null
                    ? Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () {
                  promptCtrl.clear();
                },
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          AppTextField(
            controller: promptCtrl,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Group-only system prompt for ${c.name}...',
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.tealAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
            onChanged: (_) {},
          ),
        ],
      ),
    );
  }

  /// Builds the group-level strength control with tier labels (matches sidebar styling).
  Widget _buildStrengthSlider({
    required int strength,
    required ValueChanged<int> onChanged,
  }) {
    Color sliderColor;
    String tierLabel;
    if (strength <= 3) {
      sliderColor = Colors.blueAccent;
      tierLabel = 'Subtle';
    } else if (strength <= 7) {
      sliderColor = Colors.amberAccent;
      tierLabel = 'Moderate';
    } else {
      sliderColor = Colors.redAccent;
      tierLabel = 'Strong';
    }

    return Column(
      children: [
        Row(
          children: [
            const Tooltip(
              message:
                  'Controls how forcefully the author\'s note is applied.\n'
                  'Subtle: a gentle suggestion the AI may follow.\n'
                  'Moderate: standard injection into context.\n'
                  'Strong: an urgent directive the AI should apply immediately.',
              child: Text(
                'Strength: ',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: sliderColor,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: sliderColor,
                ),
                child: Slider(
                  value: strength.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$strength — $tierLabel',
                  onChanged: (val) => onChanged(val.round()),
                ),
              ),
            ),
            Text(
              '$strength',
              style: TextStyle(
                color: sliderColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: sliderColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: sliderColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  tierLabel,
                  style: TextStyle(
                    color: sliderColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemoryRAGTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _MemoryRAGTab({required this.chatService, this.groupRepo});

  @override
  State<_MemoryRAGTab> createState() => _MemoryRAGTabState();
}

class _MemoryRAGTabState extends State<_MemoryRAGTab> {
  bool _groupRagEnabled = true;
  int _retrievalCount = 8;
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

    final savedPriorities = widget.chatService.currentGroupRAGPriorities;
    _charPriorities = {
      for (final c in _chars) c.name: savedPriorities[c.name] ?? 1.0,
    };
  }

  void _updateCharPriority(String charName, double value) {
    setState(() {
      _charPriorities[charName] = value;
    });
    // Live application happens via the main Save or when dialog closes for now
  }

  void _updateRetrievalCount(int value) {
    setState(() {
      _retrievalCount = value;
    });
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
      _retrievalCount = 8;
      _memoryBudgetPercent = 10.0;
      _charPriorities = {for (final c in _chars) c.name: 1.0};
    });
  }

  void _saveSettings() {
    final group = widget.chatService.activeGroup;
    if (group == null) return;

    // Apply via ChatService (persists via sessions.group_realism_state)
    widget.chatService.setGroupRAGEnabled(_groupRagEnabled);
    widget.chatService.setGroupRetrievalCount(_retrievalCount);
    widget.chatService.setGroupMemoryBudgetPercent(_memoryBudgetPercent);

    // Per-character priorities
    for (final entry in _charPriorities.entries) {
      // We need stable IDs here — the tab currently uses names.
      // For now we keep the old behavior (names as keys) until we standardize on IDs.
      widget.chatService.setCharacterRAGPriority(entry.key, entry.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.chatService.activeGroup;

    if (group == null) {
      return const Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: Colors.white54),
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
                const Icon(
                  Icons.psychology,
                  color: Colors.purpleAccent,
                  size: 20,
                ),
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
            const Text(
              'Per-group RAG controls. Memories are embedded from this group\'s conversation history and retrieved when context is dropped.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 16),

            // Group-level RAG section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
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
                      const Text(
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
                  if (!_groupRagEnabled)
                    const Padding(
                      padding: EdgeInsets.only(left: 26, top: 2, bottom: 8),
                      child: Text(
                        'Retrieval skipped for this group even if global RAG is on.',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Retrieval count
                  Row(
                    children: [
                      const Text(
                        'Memories per turn (retrieval limit)',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
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
                      inactiveColor: Colors.white12,
                      onChanged: (v) => _updateRetrievalCount(v.round()),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Memory budget (context length feel)
                  Row(
                    children: [
                      const Text(
                        'RAG memory budget (% of context)',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
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
                      inactiveColor: Colors.white12,
                      onChanged: _updateMemoryBudget,
                    ),
                  ),

                  const SizedBox(height: 4),
                  const Text(
                    'Note: Global embedding window size (messages per chunk) lives in main Settings → Memory (RAG). Per-group override would be a future extension.',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white30,
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
                const Icon(
                  Icons.people_alt,
                  size: 18,
                  color: Colors.purpleAccent,
                ),
                const SizedBox(width: 8),
                const Text(
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
                  child: const Text(
                    'Reset all to 1.0',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Boost or suppress how heavily each character\'s past messages influence RAG results (0.0–2.0). 1.0 = normal relevance scoring.',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 8),

            if (_chars.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No characters loaded for this group.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
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
                            inactiveColor: Colors.white12,
                            onChanged: (v) => _updateCharPriority(char.name, v),
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

class _RealismNeedsTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _RealismNeedsTab({required this.chatService, this.groupRepo});

  @override
  State<_RealismNeedsTab> createState() => _RealismNeedsTabState();
}

class _RealismNeedsTabState extends State<_RealismNeedsTab> {
  bool _realismEnabled = false;
  bool _needsSimEnabled = false;
  bool _passageOfTimeEnabled = true;
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false;

  List<CharacterCard> _chars = [];

  // Baseline seeding state (only bond/trust/emotion/time/day)
  final Map<String, Map<String, dynamic>> _baselineSeeds = {};

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onServiceChanged);
    _initializeFromService();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _initializeFromService() {
    final cs = widget.chatService;
    _chars = cs.groupCharacters;

    _realismEnabled = cs.realismEnabled;
    _needsSimEnabled = cs.needsSimEnabled;
    _passageOfTimeEnabled = cs.passageOfTimeEnabled;
    _chaosModeEnabled = cs.chaosModeEnabled;
    _chaosNsfwEnabled = cs.chaosNsfwEnabled;

    // Load immutable creation baseline seeds (only the allowed fields)
    _baselineSeeds.clear();
    for (final c in _chars) {
      _baselineSeeds[_getCharId(c)] = Map<String, dynamic>.from(
        cs.getBaselineSeedForGroupCharacter(c),
      );
    }
  }

  String _getCharId(CharacterCard c) => c.imagePath != null
      ? c.imagePath!.split('/').last.split('.').first
      : c.name;

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _updateRealism(bool value) {
    setState(() {
      _realismEnabled = value;
    });
    widget.chatService.setRealismEnabled(value);
  }

  void _updateNeedsSim(bool value) {
    setState(() {
      _needsSimEnabled = value;
    });
    widget.chatService.setNeedsSimEnabled(value);
  }

  void _updatePassageOfTime(bool value) {
    setState(() {
      _passageOfTimeEnabled = value;
    });
    widget.chatService.setPassageOfTimeEnabled(value);
  }

  void _updateChaosMode(bool value) {
    setState(() {
      _chaosModeEnabled = value;
    });
    widget.chatService.setChaosModeEnabled(value);
  }

  void _updateChaosNsfw(bool value) {
    setState(() {
      _chaosNsfwEnabled = value;
    });
    widget.chatService.setChaosNsfwEnabled(value);
  }

  void _resetAllRealismStates() {
    final cs = widget.chatService;
    if (cs.activeGroup == null) return;

    for (final c in cs.groupCharacters) {
      cs.resetRealismForGroupCharacter(c);
    }
  }

  void _resetCharacterRealism(CharacterCard character) {
    widget.chatService.resetRealismForGroupCharacter(character);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final group = cs.activeGroup;
    final isDirectorMode = cs.observerMode;
    final isRealismActive = cs.isGroupRealismActive;

    if (group == null) {
      return const Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: Colors.white54),
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
                const Icon(
                  Icons.theater_comedy,
                  color: Colors.tealAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Realism & Needs — ${group.name}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Quick baseline note
                if (_baselineSeeds.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text(
                        'Baseline seeded',
                        style: TextStyle(fontSize: 10),
                      ),
                      backgroundColor: Colors.blueGrey,
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Master toggles and per-character baseline management for the Realism Engine, Needs simulation, Chaos Mode, and Passage of Time in this group.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),

            // Director Mode notice (visual indication per requirements)
            if (isDirectorMode)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Director Mode is active. Realism Engine, Needs Simulation, and related tracking are suspended for this group (narrative control only). Exit Director Mode to re-enable.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Master Realism Engine
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: Colors.tealAccent,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Realism Engine for this group',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Switch(
                        value: _realismEnabled,
                        activeThumbColor: Colors.tealAccent,
                        onChanged: _updateRealism,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tracks emotions, short/long-term bond, trust, arousal, and fixation per character. Only takes effect when not in Director Mode.',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  if (!_realismEnabled)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Sub-features (Needs, etc.) have no effect while the master toggle is off.',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white38,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Needs Simulation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.battery_std,
                        size: 18,
                        color: Colors.tealAccent,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Needs Simulation',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Switch(
                        value: _needsSimEnabled,
                        activeThumbColor: Colors.tealAccent,
                        onChanged: _updateNeedsSim,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Simulates hunger, bladder, energy, social, fun, hygiene, and comfort. Low needs influence AI behavior and prompt injections. Only relevant when Realism Engine is enabled.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Passage of Time + Chaos (two-column-ish or stacked)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Passage of Time
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 18,
                        color: Colors.tealAccent,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Passage of Time',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Switch(
                        value: _passageOfTimeEnabled,
                        activeThumbColor: Colors.tealAccent,
                        onChanged: _updatePassageOfTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Automatically advances narrative time between turns. Manual nudge controls remain available in the sidebar.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),

                  const SizedBox(height: 14),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),

                  // Chaos Mode
                  Row(
                    children: [
                      const Text('🎰', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Chaos Mode (Chance Time)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Switch(
                        value: _chaosModeEnabled,
                        activeThumbColor: const Color(0xFFFFD166),
                        onChanged: _updateChaosMode,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Injects random narrative events based on accumulating pressure. Great for surprising group dynamics.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),

                  if (_chaosModeEnabled) ...[
                    const SizedBox(height: 10),

                    // Pressure readout (live from service)
                    Row(
                      children: [
                        Icon(
                          Icons.casino_rounded,
                          size: 14,
                          color: _pressureColorFor(cs.chaosPressure),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pressure: ${cs.chaosPressure}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: _pressureColorFor(cs.chaosPressure),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // NSFW spicy toggle
                    Row(
                      children: [
                        const Text('🌶️', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Include spicy/NSFW events',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: Switch(
                            value: _chaosNsfwEnabled,
                            activeThumbColor: const Color(0xFFFF6B9D),
                            onChanged: _updateChaosNsfw,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Per-character baselines / reset section
            Row(
              children: [
                const Icon(
                  Icons.people_alt,
                  size: 18,
                  color: Colors.tealAccent,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Per-Character Realism Baselines',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _resetAllRealismStates,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Reset ALL',
                    style: TextStyle(fontSize: 11, color: Colors.tealAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Clear tracked emotion, bond, trust, needs, and fixation for characters in the current group. Use to restart relationship arcs or after major story changes. States re-seed automatically on the next Realism evaluation.',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 10),

            if (_chars.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No characters loaded for this group.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              )
            else
              ..._chars.asMap().entries.map((entry) {
                final index = entry.key;
                final char = entry.value;
                final liveState = isRealismActive
                    ? cs.getRealismStateForGroupCharacter(char)
                    : null;
                final emo = liveState?['emotion'] as String?;
                final bond = isRealismActive
                    ? cs.getAffectionForGroupCharacter(char)
                    : 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      // Avatar (matches Prompt tab style)
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: _charAccentColor(index),
                        backgroundImage: char.imagePath != null
                            ? FileImage(File(char.imagePath!))
                            : null,
                        child: char.imagePath == null
                            ? Text(
                                char.name.isNotEmpty
                                    ? char.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              char.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isRealismActive
                                  ? (emo != null
                                        ? 'Emotion: $emo • Bond: $bond'
                                        : 'No realism data yet (will seed on next turn)')
                                  : 'Realism inactive (Director Mode or master off)',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white38,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _resetCharacterRealism(char),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Reset',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.tealAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Helper for chaos pressure color (matches _ChaosModeSection in chat_page)
  Color _pressureColorFor(int pressure) {
    final t = (pressure / 100).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFF2EC4B6), const Color(0xFFE63946), t)!;
  }

  // Simple accent palette for per-char avatars (subset of Prompt tab palette)
  static const List<Color> _charColors = [
    Color(0xFF14B8A6), // Teal (realism accent)
    Color(0xFF8B5CF6), // Purple
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFF3B82F6), // Blue
  ];

  Color _charAccentColor(int index) => _charColors[index % _charColors.length];
}

class _GeneralTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _GeneralTab({required this.chatService, this.groupRepo});

  @override
  State<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<_GeneralTab> {
  // Local editing controllers and state (applied on Save)
  late final TextEditingController _nameController;
  late final TextEditingController _scenarioController;
  late final TextEditingController _firstMessageController;

  TurnOrder _turnOrder = TurnOrder.roundRobin;
  bool _autoAdvance = false;
  bool _directorModeDefault = false;

  bool _hasUnsavedChanges = false;
  String _statusMessage = '';

  // Snapshot of the group at load time (for reset)
  GroupChat? _loadedGroup;

  @override
  void initState() {
    super.initState();
    _loadFromActiveGroup();
  }

  void _loadFromActiveGroup() {
    final g = widget.chatService.activeGroup;
    _loadedGroup = g;

    if (g != null) {
      _nameController = TextEditingController(text: g.name);
      _scenarioController = TextEditingController(text: g.scenario);
      _firstMessageController = TextEditingController(text: g.firstMessage);
      _turnOrder = g.turnOrder;
      _autoAdvance = g.autoAdvance;
      _directorModeDefault = g.directorMode;
    } else {
      _nameController = TextEditingController(text: '');
      _scenarioController = TextEditingController(text: '');
      _firstMessageController = TextEditingController(text: '');
      _turnOrder = TurnOrder.roundRobin;
      _autoAdvance = false;
      _directorModeDefault = false;
    }

    _hasUnsavedChanges = false;
    _statusMessage = '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
        _statusMessage = '';
      });
    }
  }

  void _setTurnOrder(TurnOrder order) {
    if (_turnOrder == order) return;
    setState(() {
      _turnOrder = order;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _setAutoAdvance(bool value) {
    if (_autoAdvance == value) return;
    setState(() {
      _autoAdvance = value;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _setDirectorModeDefault(bool value) {
    if (_directorModeDefault == value) return;
    setState(() {
      _directorModeDefault = value;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _saveSettings() {
    final g = widget.chatService.activeGroup;
    if (g == null) return;

    // Apply all edits to the live GroupChat instance (in-memory, immediate effect)
    g.name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Group Chat';
    g.scenario = _scenarioController.text.trim();
    g.firstMessage = _firstMessageController.text.trim();
    g.turnOrder = _turnOrder;
    g.autoAdvance = _autoAdvance;
    g.directorMode = _directorModeDefault;

    // Note: We mutate the live GroupChat object held by the turn manager.
    // Core reads (turnOrder, scenario, firstMessage, flags) pick it up immediately.
    // UI labels (e.g. sidebar header) will reflect on next rebuild of those widgets.
    // (No notifyListeners here to avoid protected-member analyzer diagnostics.)

    setState(() {
      _hasUnsavedChanges = false;
      _statusMessage = 'Settings applied for this session.';
      _loadedGroup = g; // keep snapshot in sync
    });

    // Persist the GroupChat model
    if (widget.groupRepo != null) {
      widget.groupRepo!.save(g);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('General settings saved.'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.chatService.activeGroup;

    if (group == null) {
      return const Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.tune, color: Colors.tealAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'General — ${group.name}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Basic group identity, opening message, and conversation flow rules. All changes apply live after Save.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 16),

                // ── Identity ───────────────────────────────────────────────
                _buildSectionHeader(
                  'Identity',
                  Icons.label_outline,
                  Colors.tealAccent,
                ),
                const SizedBox(height: 8),

                // Group Name
                const Text(
                  'Group Name',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _nameController,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. The Fellowship',
                    hintStyle: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.borderOf(context),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.borderOf(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 14),

                // Scenario
                const Text(
                  'Scenario',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Group-level scenario override (blank = use first character\'s scenario).',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _scenarioController,
                  maxLines: 4,
                  minLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText:
                        'The scene, time period, and situation for this group conversation...',
                    hintStyle: const TextStyle(
                      color: Colors.white24,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 14),

                // First Message
                const Text(
                  'First Message / Greeting',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Custom opening message shown when the group starts or is reset (blank = use first character\'s greeting).',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _firstMessageController,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'The group\'s initial greeting or narration...',
                    hintStyle: const TextStyle(
                      color: Colors.white24,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 20),

                // ── Turn Management ────────────────────────────────────────
                _buildSectionHeader(
                  'Turn Management',
                  Icons.swap_horiz,
                  Colors.purpleAccent,
                ),
                const SizedBox(height: 8),

                const Text(
                  'Turn Order Strategy',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: _buildTurnStrategyCard(
                        TurnOrder.roundRobin,
                        'Round Robin',
                        'Characters respond in a fixed repeating order. Predictable and fair.',
                        Icons.repeat,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTurnStrategyCard(
                        TurnOrder.random,
                        'Random',
                        'Any eligible character may speak next. More spontaneous and lively.',
                        Icons.shuffle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Auto-advance
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.play_circle_outline,
                            size: 18,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Auto-advance',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: _autoAdvance,
                            activeTrackColor: Colors.greenAccent,
                            onChanged: _setAutoAdvance,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.only(left: 26),
                        child: Text(
                          'After a character finishes responding, automatically prompt the next speaker. Works with both turn orders and Director Mode.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white38,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Director Mode ──────────────────────────────────────────
                _buildSectionHeader(
                  'Director Mode Defaults',
                  Icons.movie_creation_outlined,
                  Colors.amberAccent,
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.visibility,
                            size: 18,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Start this group in Director Mode',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Switch(
                            value: _directorModeDefault,
                            activeTrackColor: Colors.amberAccent,
                            onChanged: _setDirectorModeDefault,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.only(left: 26),
                        child: Text(
                          'When enabled, entering the group begins in observer/director mode. You steer via the input box while characters respond autonomously. The live toggle is also available in the group sidebar.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white38,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Persistence note
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.white38),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'These settings are stored with the group definition. Saving here updates the live session immediately. The values are persisted to the database automatically on membership changes (add/remove character) and on session checkpoints.',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white38,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Save bar ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.borderOf(context))),
            color: AppColors.surfaceContainerOf(context),
          ),
          child: Row(
            children: [
              if (false) // TODO: removed per-tab save logic
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'UNSAVED',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.amber,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildTurnStrategyCard(
    TurnOrder order,
    String label,
    String description,
    IconData icon,
  ) {
    final isSelected = _turnOrder == order;
    final borderColor = isSelected ? Colors.purpleAccent : Colors.white12;
    final bgColor = isSelected
        ? const Color(0xFF1F2937)
        : const Color(0xFF111827);
    final iconColor = isSelected ? Colors.purpleAccent : Colors.white54;
    final textColor = isSelected ? Colors.purpleAccent : Colors.white;

    return GestureDetector(
      onTap: () => _setTurnOrder(order),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white54,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lorebook & Worlds Tab — Full group-level lorebook support + world attachment
// (completes 1:1 parity for classic keyword lorebooks in groups)
// ─────────────────────────────────────────────────────────────────────────────

class _LorebookWorldsTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;

  const _LorebookWorldsTab({required this.chatService, this.groupRepo});

  @override
  State<_LorebookWorldsTab> createState() => _LorebookWorldsTabState();
}

class _LorebookWorldsTabState extends State<_LorebookWorldsTab> {
  bool _inheritCharacterLorebooks = true;
  List<String> _worldIds = [];
  List<LorebookEntry> _groupLoreEntries = [];

  List<World> _allWorlds = [];

  @override
  void initState() {
    super.initState();
    _loadFromActiveGroup();
    _loadWorlds();
  }

  void _loadFromActiveGroup() {
    final g = widget.chatService.activeGroup;

    if (g == null) {
      _inheritCharacterLorebooks = true;
      _worldIds = [];
      _groupLoreEntries = [];
      return;
    }

    _inheritCharacterLorebooks = g.inheritCharacterLorebooks;
    _worldIds = List<String>.from(g.worldIds);

    _groupLoreEntries = [];
    if (g.groupLorebook.isNotEmpty) {
      try {
        final decoded = jsonDecode(g.groupLorebook);
        if (decoded is Map<String, dynamic>) {
          final lb = Lorebook.fromJson(decoded);
          _groupLoreEntries = List<LorebookEntry>.from(lb.entries);
        }
      } catch (_) {
        // Corrupt or legacy plain-text — start fresh
        _groupLoreEntries = [];
      }
    }
  }

  void _loadWorlds() {
    try {
      final repo = Provider.of<WorldRepository>(context, listen: false);
      _allWorlds = List<World>.from(repo.worlds);
    } catch (_) {
      _allWorlds = [];
    }
    setState(() {});
  }

  void _saveSettings() {
    final g = widget.chatService.activeGroup;
    if (g == null) return;

    g.inheritCharacterLorebooks = _inheritCharacterLorebooks;
    g.worldIds = List<String>.from(_worldIds);

    final lb = Lorebook(entries: _groupLoreEntries);
    g.groupLorebook = jsonEncode(lb.toJson());

    if (widget.groupRepo != null) {
      widget.groupRepo!.save(g);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group lorebook settings saved.'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _showEntryEditor({LorebookEntry? existing, int? index}) async {
    final keyCtrl = TextEditingController(text: existing?.key ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');

    bool enabled = existing?.enabled ?? true;
    bool constant = existing?.constant ?? false;
    int stickyDepth = existing?.stickyDepth ?? 1;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(existing == null ? 'Add Lore Entry' : 'Edit Lore Entry'),
        content: StatefulBuilder(
          builder: (innerCtx, setInnerState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!constant) ...[
                    AppTextField(
                      controller: keyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Trigger Keys (comma separated)',
                      ),
                      style: TextStyle(color: AppColors.textPrimary(context)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  AppTextField(
                    controller: contentCtrl,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Content (injected when triggered)',
                    ),
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderOf(context)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Enabled',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'This entry can be injected when its keys match',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: enabled,
                              onChanged: (v) =>
                                  setInnerState(() => enabled = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: AppColors.borderOf(context), height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Constant',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Always considered active (ignores trigger keys)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: constant,
                              onChanged: (v) =>
                                  setInnerState(() => constant = v),
                            ),
                          ],
                        ),
                        if (!constant) ...[
                          const SizedBox(height: 12),
                          Divider(
                            color: AppColors.borderOf(context),
                            height: 1,
                          ),
                          const SizedBox(height: 12),

                          // Sticky Depth — clean slider presentation
                          // (hidden when Constant is on, since constant entries never decay)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Sticky Depth',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerOf(
                                        context,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$stickyDepth',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'How many turns the entry stays active after triggering',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              const SizedBox(height: 6),
                              SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: Colors.tealAccent,
                                  inactiveTrackColor: AppColors.borderOf(
                                    context,
                                  ).withValues(alpha: 0.4),
                                  thumbColor: Colors.tealAccent,
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                ),
                                child: Slider(
                                  value: stickyDepth.toDouble().clamp(0, 12),
                                  min: 0,
                                  max: 12,
                                  divisions: 12,
                                  label: stickyDepth.toString(),
                                  onChanged: (v) => setInnerState(
                                    () => stickyDepth = v.round(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final newEntry = LorebookEntry(
      key: keyCtrl.text.trim(),
      content: contentCtrl.text.trim(),
      enabled: enabled,
      constant: constant,
      stickyDepth: stickyDepth,
    );

    setState(() {
      if (index != null && index >= 0 && index < _groupLoreEntries.length) {
        _groupLoreEntries[index] = newEntry;
      } else {
        _groupLoreEntries.add(newEntry);
      }
    });
  }

  Future<void> _importGroupLorebookJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final file = File(result.files.single.path!);
      final jsonStr = await file.readAsString();
      final Map<String, dynamic> json = jsonDecode(jsonStr);

      final Map<String, dynamic> source = (json['lorebook'] is Map)
          ? json['lorebook'] as Map<String, dynamic>
          : (json['entries'] != null ? json : {});

      final imported = Lorebook.fromJson(source.isNotEmpty ? source : json);

      if (imported.entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No entries found in file.')),
          );
        }
        return;
      }

      setState(() {
        _groupLoreEntries.addAll(imported.entries);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${imported.entries.length} entries.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to import: $e')));
      }
    }
  }

  void _deleteEntry(int index) {
    setState(() {
      _groupLoreEntries.removeAt(index);
    });
  }

  void _toggleWorld(String worldId) {
    setState(() {
      if (_worldIds.contains(worldId)) {
        _worldIds.remove(worldId);
      } else {
        _worldIds.add(worldId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.chatService.activeGroup;
    if (group == null) {
      return const Center(child: Text('No active group.'));
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Inherit toggle
                SwitchListTile(
                  title: const Text('Inherit character lorebooks'),
                  subtitle: const Text(
                    'When enabled, lorebooks from all group members (and their attached worlds) are included in addition to the group lorebook.',
                  ),
                  value: _inheritCharacterLorebooks,
                  onChanged: (v) {
                    setState(() {
                      _inheritCharacterLorebooks = v;
                    });
                  },
                  activeThumbColor: Colors.orangeAccent,
                ),
                const SizedBox(height: 16),

                // Worlds
                _buildSectionHeader(
                  'World Lorebooks',
                  Icons.public,
                  Colors.lightBlueAccent,
                ),
                const SizedBox(height: 8),
                Text(
                  'Attach worlds to pull their lorebooks into every message in this group.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 8),
                if (_allWorlds.isEmpty)
                  const Text(
                    'No worlds available. Create worlds in the Worlds tab to attach them here.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allWorlds.map((w) {
                      final selected = _worldIds.contains(w.name);
                      return FilterChip(
                        label: Text(w.name),
                        selected: selected,
                        onSelected: (_) => _toggleWorld(w.name),
                        selectedColor: Colors.lightBlueAccent.withValues(
                          alpha: 0.3,
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 24),

                // Group lorebook entries
                _buildSectionHeader(
                  'Group Lorebook',
                  Icons.menu_book,
                  Colors.orangeAccent,
                ),
                const SizedBox(height: 6),
                Text(
                  'Highest priority lore. These entries are always available to the whole group.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _importGroupLorebookJson,
                      icon: const Icon(Icons.upload, size: 16),
                      label: const Text('Import JSON'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _showEntryEditor(),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Entry'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_groupLoreEntries.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'No group-level lorebook entries yet.\nAdd entries or import a JSON file.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                else
                  ..._groupLoreEntries.asMap().entries.map((entry) {
                    final i = entry.key;
                    final e = entry.value;
                    final keyPreview = e.key.isEmpty
                        ? '(no trigger keys)'
                        : e.key;
                    final contentPreview = e.content.length > 140
                        ? '${e.content.substring(0, 137)}...'
                        : e.content;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.3),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          keyPreview,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            contentPreview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () =>
                                  _showEntryEditor(existing: e, index: i),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                size: 18,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _deleteEntry(i),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
