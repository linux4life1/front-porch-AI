// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

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
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/widgets/styled_text_controller.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

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
    _tabController = TabController(length: 6, vsync: this);
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
                Tab(text: 'Realism'),
                Tab(text: 'Needs'),
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
                  _NeedsTab(
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
  late final StyledTextController _groupSystemController;
  late final StyledTextController _groupAuthorNoteController;

  // Per-character editing state. Keys are live CharacterCard instances
  // (stable references from chatService.groupCharacters).
  final Map<CharacterCard, StyledTextController> _perCharNoteControllers = {};
  final Map<CharacterCard, int> _perCharStrengths = {};

  // Per-character group system prompt overrides (Path B feature).
  final Map<CharacterCard, StyledTextController>
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

    _groupSystemController = StyledTextController(
      preset: StyledTextPreset.prose,
      text: group?.systemPrompt ?? '',
    );
    _groupAuthorNoteController = StyledTextController(
      preset: StyledTextPreset.prose,
      text: cs.authorNote,
    );

    // Pre-create controllers for current characters using live getters
    // (so first render has correct starting values).
    for (final c in cs.groupCharacters) {
      _getOrCreateNoteController(c); // creates + populates from service
      _perCharStrengths[c] ??= cs.getAuthorNoteStrengthForGroupCharacter(c);
    }
  }

  StyledTextController _getOrCreateNoteController(CharacterCard c) {
    return _perCharNoteControllers.putIfAbsent(c, () {
      final initial = widget.chatService.getAuthorNoteForGroupCharacter(c);
      return StyledTextController(
        preset: StyledTextPreset.prose,
        text: initial,
      );
    });
  }

  StyledTextController _getOrCreateSystemPromptController(CharacterCard c) {
    return _perCharSystemPromptControllers.putIfAbsent(c, () {
      final initial = widget.chatService.getSystemPromptForGroupCharacter(c);
      return StyledTextController(
        preset: StyledTextPreset.prose,
        text: initial,
      );
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
                    Icon(Icons.code, size: 16, color: AppColors.formMasterAccent),
                    SizedBox(width: 6),
                    Text(
                      'Group System Prompt',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.formMasterAccent,
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
                      borderSide: const BorderSide(color: AppColors.formMasterAccent),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onChanged: (text) {
                    final g = widget.chatService.activeGroup;
                    if (g != null) {
                      g.systemPrompt = text.trim();
                      // The parent dialog listens to ChatService, so it will rebuild.
                      // Avoid direct notifyListeners() from outside the service.
                    }
                  },
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
            onChanged: (text) {
              widget.chatService.setAuthorNoteForGroupCharacter(c, text);
            },
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
                      final newStrength = val.round();
                      setState(() {
                        _perCharStrengths[c] = newStrength;
                      });
                      // Flush to service so it persists on Save / restart
                      final currentNote =
                          _perCharNoteControllers[c]?.text ?? '';
                      widget.chatService.setAuthorNoteForGroupCharacter(
                        c,
                        currentNote,
                        strength: newStrength,
                      );
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
            onChanged: (text) {
              widget.chatService.setSystemPromptForGroupCharacter(c, text);
            },
          ),
        ],
      ),
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
                    'Reset to defaults',
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

class _RealismNeedsTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _RealismNeedsTab({required this.chatService, this.groupRepo});

  @override
  State<_RealismNeedsTab> createState() => _RealismNeedsTabState();
}

class _RealismNeedsTabState extends State<_RealismNeedsTab> {
  bool _realismEnabled = false;
  bool _passageOfTimeEnabled = true;
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false;
  bool _nsfwEnhancementsEnabled = false;

  // Group-wide Time & Day.
  String _groupTimeOfDay = 'morning';
  int _groupDayCount = 1;
  // Story Calendar seed for fresh sessions (story-calendar.md §3a).
  String? _groupStoryStartDate;
  String? _groupStoryStartTime;
  late final TextEditingController _groupDayCountController;

  List<CharacterCard> _chars = [];

  // Per-member Director/Verifier (Realism Verification) settings for groups.
  // Wired the same as 1:1 via per-member CharacterCard.frontPorchExtensions + impersonation.
  // UI exposed here for existing groups (previously only in creation flow).
  final Map<String, bool> _verificationEnabled = {};
  final Map<String, int> _verificationMaxReprocesses = {};
  final Map<String, int> _verificationStrictness = {};
  final Map<String, bool> _needsDirectorAuthority = {};

  // Baseline seeding state (only bond/trust/emotion/time/day)
  final Map<String, Map<String, dynamic>> _baselineSeeds = {};

  // Per-character editable realism baselines (seeded from baselineSeeds + card ext).
  final Map<String, int> _editShortTermBond = {};
  final Map<String, int> _editLongTermBond = {};
  final Map<String, int> _editTrustLevel = {};
  final Map<String, String> _editEmotion = {};
  final Map<String, String> _editEmotionIntensity = {};

  // Text controllers for inline editing fields.
  final Map<String, TextEditingController> _emotionControllers = {};

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
    _passageOfTimeEnabled = cs.timeService.passageOfTimeEnabled;
    _chaosModeEnabled = cs.chaosModeService.chaosModeEnabled;
    _chaosNsfwEnabled = cs.chaosModeService.chaosNsfwEnabled;
    // Group NSFW Enhancements (arousal/Lust + post-climax cooldowns). Uses the
    // stable per-member group flag (the live nsfwService scalar is per-speaker
    // volatile in groups); the write side propagates to every member.
    _nsfwEnhancementsEnabled = cs.isGroupNsfwEnabled;

    // Group-wide Time & Day.
    final group = cs.activeGroup;
    if (group != null) {
      final gs = group.defaultMemberRealismState;
      if (gs.isNotEmpty && gs != '{}') {
        final map = (jsonDecode(gs) as Map<String, dynamic>?) ?? {};
        _groupTimeOfDay = (map['timeOfDay'] as String?) ?? 'morning';
        _groupDayCount = (map['dayCount'] as num?)?.toInt() ?? 1;
        _groupStoryStartDate = map['storyStartDate'] as String?;
        _groupStoryStartTime = map['storyStartTime'] as String?;
      }
    }
    _groupDayCountController = TextEditingController(
      text: _groupDayCount.toString(),
    );

    // Load immutable creation baseline seeds (only the allowed fields)
    _baselineSeeds.clear();
    for (final c in _chars) {
      _baselineSeeds[_getCharId(c)] = Map<String, dynamic>.from(
        cs.getBaselineSeedForGroupCharacter(c),
      );
      final id = _getCharId(c);

      // Load per-member Director/Verifier settings (if present on the member's card ext)
      _verificationEnabled[id] =
          c.frontPorchExtensions?.realismVerificationEnabled ?? false;
      _verificationMaxReprocesses[id] =
          c.frontPorchExtensions?.realismVerificationMaxReprocesses ?? 1;
      _verificationStrictness[id] =
          c.frontPorchExtensions?.realismVerificationStrictness ?? 3;
      _needsDirectorAuthority[id] =
          c.frontPorchExtensions?.realismNeedsDirectorAuthority ?? false;

      // Load editable realism baselines from baseline seed + card extensions.
      final seed = _baselineSeeds[id]!;
      _editShortTermBond[id] = (seed['affection'] as num?)?.toInt() ?? 50;
      _editLongTermBond[id] = (seed['trust'] as num?)?.toInt() ?? 50;
      _editTrustLevel[id] = (seed['trust'] as num?)?.toInt() ?? 50;
      _editEmotion[id] = (seed['emotion'] as String?) ?? 'neutral';
      _editEmotionIntensity[id] =
          (seed['emotionIntensity'] as String?) ?? 'moderate';
    }
  }

  // --- Per-member Director/Verifier updates ---
  void _updateMemberVerificationEnabled(CharacterCard char, bool value) {
    final id = _getCharId(char);
    setState(() {
      _verificationEnabled[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            realismVerificationEnabled: value,
          );
      char.frontPorchExtensions?.ensureStableId();
    });

    _persistMemberVerificationPref(id, 'verificationEnabled', value);
  }

  void _updateMemberVerificationMaxReprocesses(CharacterCard char, int value) {
    final id = _getCharId(char);
    setState(() {
      _verificationMaxReprocesses[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            realismVerificationMaxReprocesses: value,
          );
      char.frontPorchExtensions?.ensureStableId();
    });

    _persistMemberVerificationPref(id, 'verificationMaxReprocesses', value);
  }

  void _updateMemberVerificationStrictness(CharacterCard char, int value) {
    final id = _getCharId(char);
    setState(() {
      _verificationStrictness[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            realismVerificationStrictness: value,
          );
      char.frontPorchExtensions?.ensureStableId();
    });

    _persistMemberVerificationPref(id, 'verificationStrictness', value);
  }

  void _updateMemberNeedsDirectorAuthority(CharacterCard char, bool value) {
    final id = _getCharId(char);
    setState(() {
      _needsDirectorAuthority[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            realismNeedsDirectorAuthority: value,
          );
      char.frontPorchExtensions?.ensureStableId();
    });

    _persistMemberVerificationPref(id, 'needsDirectorAuthority', value);
  }

  void _persistMemberVerificationPref(String id, String key, dynamic value) {
    try {
      final group = widget.chatService.activeGroup;
      if (group != null) {
        final map =
            group.defaultMemberRealismState.isNotEmpty &&
                group.defaultMemberRealismState != '{}'
            ? (jsonDecode(group.defaultMemberRealismState)
                      as Map<String, dynamic>? ??
                  {})
            : <String, dynamic>{};
        final perChar = (map['perChar'] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        final current = (perChar[id] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        current[key] = value;
        perChar[id] = current;
        map['perChar'] = perChar;
        group.defaultMemberRealismState = jsonEncode(map);
      }
    } catch (_) {
      // Non-fatal
    }
  }

  // ── Editable realism baseline update methods ──

  void _updateEditShortTermBond(CharacterCard char, int value) {
    final id = _getCharId(char);
    setState(() {
      _editShortTermBond[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _updateEditLongTermBond(CharacterCard char, int value) {
    final id = _getCharId(char);
    setState(() {
      _editLongTermBond[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _updateEditTrustLevel(CharacterCard char, int value) {
    final id = _getCharId(char);
    setState(() {
      _editTrustLevel[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _updateEditEmotion(CharacterCard char, String value) {
    final id = _getCharId(char);
    setState(() {
      _editEmotion[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _updateEditEmotionIntensity(CharacterCard char, String value) {
    final id = _getCharId(char);
    setState(() {
      _editEmotionIntensity[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _applyEditToBaselineSeedAndCard(CharacterCard char, String id) {
    final ext = char.frontPorchExtensions ?? FrontPorchExtensions();
    char.frontPorchExtensions = ext.copyWith(
      shortTermBond: _editShortTermBond[id] ?? 50,
      longTermBond: _editLongTermBond[id] ?? 50,
      trustLevel: _editTrustLevel[id] ?? 50,
      characterEmotion: _editEmotion[id] ?? 'neutral',
      emotionIntensity: _editEmotionIntensity[id] ?? 'moderate',
    );

    // Update the baseline seed via ChatService.
    try {
      widget.chatService.setBaselineSeedForGroupCharacter(char, {
        'affection': _editShortTermBond[id] ?? 50,
        'trust': _editLongTermBond[id] ?? 50,
        'emotion': _editEmotion[id] ?? 'neutral',
        'emotionIntensity': _editEmotionIntensity[id] ?? 'moderate',
      });
    } catch (_) {
      // Non-fatal
    }

    // Persist to group defaultMemberRealismState.
    try {
      final group = widget.chatService.activeGroup;
      if (group != null) {
        final map =
            group.defaultMemberRealismState.isNotEmpty &&
                group.defaultMemberRealismState != '{}'
            ? (jsonDecode(group.defaultMemberRealismState)
                      as Map<String, dynamic>? ??
                  {})
            : <String, dynamic>{};
        final perChar = (map['perChar'] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        final current = (perChar[id] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        current['shortTermBond'] = _editShortTermBond[id] ?? 50;
        current['longTermBond'] = _editLongTermBond[id] ?? 50;
        current['trustLevel'] = _editTrustLevel[id] ?? 50;
        current['characterEmotion'] = _editEmotion[id] ?? 'neutral';
        current['emotionIntensity'] = _editEmotionIntensity[id] ?? 'moderate';
        perChar[id] = current;
        map['perChar'] = perChar;
        group.defaultMemberRealismState = jsonEncode(map);
      }
    } catch (_) {
      // Non-fatal
    }
  }

  String _getCharId(CharacterCard c) => c.imagePath != null
      ? c.imagePath!.split('/').last.split('.').first
      : c.name;

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceChanged);
    _groupDayCountController.dispose();
    super.dispose();
  }

  Widget _sliderRow(
    String label,
    int value,
    int min,
    int max,
    String tierName,
    Color color,
    ValueChanged<int> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              ),
              child: Slider(
                value: value.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min > 0 ? (max - min) ~/ 10 : 0,
                label: value.toString(),
                onChanged: (d) => onChanged(d.round()),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            child: Text(
              value.toString(),
              style: TextStyle(fontSize: 10, color: color),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  void _updateRealism(bool value) {
    setState(() {
      _realismEnabled = value;
    });
    widget.chatService.setRealismEnabled(value);
  }

  void _updatePassageOfTime(bool value) {
    setState(() {
      _passageOfTimeEnabled = value;
    });
    // Through the ChatService wrapper (saves + notifies) — the raw
    // TimeService setter is side-effect-free, so the old direct call never
    // persisted the toggle beyond this dialog's local state.
    widget.chatService.setPassageOfTimeEnabled(value);
  }

  void _updateChaosMode(bool value) {
    setState(() {
      _chaosModeEnabled = value;
    });
    widget.chatService.chaosModeService.setModeEnabled(value);
  }

  void _updateChaosNsfw(bool value) {
    setState(() {
      _chaosNsfwEnabled = value;
    });
    widget.chatService.chaosModeService.setNsfwEnabled(value);
  }

  void _updateNsfwEnhancements(bool value) {
    setState(() {
      _nsfwEnhancementsEnabled = value;
    });
    // Same setter the sidebar gear uses; in a group it propagates the flag to
    // every member's realism state (1:1 just sets the scalar).
    widget.chatService.setNsfwCooldownEnabled(value);
  }

  void _updateGroupTimeOfDay(String value) {
    setState(() {
      _groupTimeOfDay = value;
    });
    _persistGroupTimeDay();
  }

  void _updateGroupDayCount(int value) {
    setState(() {
      _groupDayCount = value;
    });
    _groupDayCountController.text = value.toString();
    _persistGroupTimeDay();
  }

  void _persistGroupTimeDay() {
    final group = widget.chatService.activeGroup;
    if (group == null) return;
    try {
      final map =
          group.defaultMemberRealismState.isNotEmpty &&
              group.defaultMemberRealismState != '{}'
          ? (jsonDecode(group.defaultMemberRealismState)
                    as Map<String, dynamic>?) ??
                {}
          : <String, dynamic>{};
      map['timeOfDay'] = _groupTimeOfDay;
      map['dayCount'] = _groupDayCount;
      if (_groupStoryStartDate != null) {
        map['storyStartDate'] = _groupStoryStartDate;
      } else {
        map.remove('storyStartDate');
      }
      if (_groupStoryStartTime != null) {
        map['storyStartTime'] = _groupStoryStartTime;
      } else {
        map.remove('storyStartTime');
      }
      group.defaultMemberRealismState = jsonEncode(map);
    } catch (_) {
      // Non-fatal
    }
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
                    'Realism — ${group.name}',
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
              'Master toggles and per-character baseline management for the Realism Engine, Chaos Mode, and Passage of Time in this group.',
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
                        'Director Mode is active. Realism Engine and related tracking are suspended for this group (narrative control only). Exit Director Mode to re-enable.',
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

            // NSFW Enhancements (arousal / Lust bar + post-climax cooldowns).
            // Mirrors the sidebar Character State gear toggle so it's findable
            // where users expect group-wide switches; applies to every member.
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
                      const Text('🔥', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'NSFW Enhancements',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Switch(
                        value: _nsfwEnhancementsEnabled,
                        activeThumbColor: const Color(0xFFFF6B9D),
                        onChanged: _updateNsfwEnhancements,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tracks arousal (the Lust bar) with post-climax refractory '
                    'cooldowns for every character in this group. Only takes '
                    'effect while the Realism Engine above is on.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  if (_nsfwEnhancementsEnabled && !_realismEnabled)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Turn on the Realism Engine above for this to have any '
                        'effect.',
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

                  // Time & Day (group-wide)
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 18,
                        color: AppColors.resolve(
                          context,
                          Colors.lightBlueAccent,
                          Colors.lightBlueAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Time & Day',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sets the starting time and day for all characters in this group.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _groupTimeOfDay,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceOf(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(fontSize: 12),
                          items: ['morning', 'afternoon', 'evening', 'night']
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    e,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) _updateGroupTimeOfDay(v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _groupDayCountController,
                          decoration: InputDecoration(
                            hintText: 'Day',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceOf(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(fontSize: 12),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final val = int.tryParse(v) ?? 1;
                            _updateGroupDayCount(val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Story Calendar seed for FRESH sessions (the live chat's
                  // clock is set from the Story Calendar dialog instead).
                  StoryBeginsRow(
                    storyStartDate: _groupStoryStartDate,
                    onStoryStartDateChanged: (v) {
                      setState(() => _groupStoryStartDate = v);
                      _persistGroupTimeDay();
                    },
                    storyStartTime: _groupStoryStartTime,
                    onStoryStartTimeChanged: (v) {
                      setState(() => _groupStoryStartTime = v);
                      _persistGroupTimeDay();
                    },
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
                          color: _pressureColorFor(
                            cs.chaosModeService.chaosPressure,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pressure: ${cs.chaosPressure}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: _pressureColorFor(
                              cs.chaosModeService.chaosPressure,
                            ),
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
              'Clear tracked emotion, bond, trust, and fixation for characters in the current group. Use to restart relationship arcs or after major story changes. States re-seed automatically on the next Realism evaluation.',
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
                            // ── Editable Realism Baselines ─────────────────────
                            const SizedBox(height: 8),
                            // Relationship
                            Row(
                              children: [
                                Icon(
                                  Icons.favorite,
                                  size: 14,
                                  color: AppColors.resolve(
                                    context,
                                    Colors.pinkAccent,
                                    Colors.pinkAccent,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Relationship',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Column(
                                children: [
                                  _sliderRow(
                                    'Short-Term Bond',
                                    _editShortTermBond[_getCharId(char)] ?? 50,
                                    -300,
                                    300,
                                    char.name,
                                    _charAccentColor(index),
                                    (v) => _updateEditShortTermBond(
                                      char,
                                      v.round(),
                                    ),
                                  ),
                                  _sliderRow(
                                    'Long-Term Bond',
                                    _editLongTermBond[_getCharId(char)] ?? 50,
                                    -300,
                                    300,
                                    char.name,
                                    _charAccentColor(index),
                                    (v) => _updateEditLongTermBond(
                                      char,
                                      v.round(),
                                    ),
                                  ),
                                  _sliderRow(
                                    'Trust Level',
                                    _editTrustLevel[_getCharId(char)] ?? 50,
                                    -100,
                                    100,
                                    char.name,
                                    _charAccentColor(index),
                                    (v) =>
                                        _updateEditTrustLevel(char, v.round()),
                                  ),
                                ],
                              ),
                            ),
                            // Starting Emotion
                            Row(
                              children: [
                                Icon(
                                  Icons.mood,
                                  size: 14,
                                  color: AppColors.resolve(
                                    context,
                                    Colors.amber,
                                    Colors.amber,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Starting Emotion',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller:
                                          _emotionControllers[_getCharId(
                                            char,
                                          )] ??= TextEditingController(
                                            text:
                                                _editEmotion[_getCharId(
                                                  char,
                                                )] ??
                                                'neutral',
                                          ),
                                      decoration: InputDecoration(
                                        hintText: 'emotion',
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                        filled: true,
                                        fillColor: AppColors.surfaceOf(context),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      style: const TextStyle(fontSize: 11),
                                      onChanged: (v) =>
                                          _updateEditEmotion(char, v),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue:
                                          _editEmotionIntensity[_getCharId(
                                            char,
                                          )] ??
                                          'moderate',
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                        filled: true,
                                        fillColor: AppColors.surfaceOf(context),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      style: const TextStyle(fontSize: 11),
                                      items: ['calm', 'moderate', 'intense']
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e,
                                              child: Text(
                                                e,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          _updateEditEmotionIntensity(char, v);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // ── End Editable Realism Baselines ──────────────────
                            // Per-member Director/Verifier settings (new in Realism & Needs tab for groups).
                            // These were previously only configurable at group creation time.
                            // Now editable here for existing groups. Uses same perChar persistence + card ext patch.
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Director/Verifier',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: Checkbox(
                                    value:
                                        _verificationEnabled[_getCharId(
                                          char,
                                        )] ??
                                        false,
                                    onChanged: (v) {
                                      if (v != null) {
                                        _updateMemberVerificationEnabled(
                                          char,
                                          v,
                                        );
                                      }
                                    },
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                            // Compact sliders + authority toggle for the Director settings.
                            // Only shown when Director/Verifier is enabled for this member.
                            if (_verificationEnabled[_getCharId(char)] ??
                                false) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    'Max: ${_verificationMaxReprocesses[_getCharId(char)] ?? 1}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 80,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 4,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 8,
                                            ),
                                      ),
                                      child: Slider(
                                        value:
                                            (_verificationMaxReprocesses[_getCharId(
                                                      char,
                                                    )] ??
                                                    1)
                                                .toDouble(),
                                        min: 1,
                                        max: 5,
                                        divisions: 4,
                                        onChanged: (d) {
                                          _updateMemberVerificationMaxReprocesses(
                                            char,
                                            d.round(),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Strict: ${_verificationStrictness[_getCharId(char)] ?? 3}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 80,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 4,
                                        ),
                                      ),
                                      child: Slider(
                                        value:
                                            (_verificationStrictness[_getCharId(
                                                      char,
                                                    )] ??
                                                    3)
                                                .toDouble(),
                                        min: 1,
                                        max: 5,
                                        divisions: 4,
                                        onChanged: (d) {
                                          _updateMemberVerificationStrictness(
                                            char,
                                            d.round(),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Director authority (needs)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: Checkbox(
                                      value:
                                          _needsDirectorAuthority[_getCharId(
                                            char,
                                          )] ??
                                          false,
                                      onChanged: (v) {
                                        if (v != null) {
                                          _updateMemberNeedsDirectorAuthority(
                                            char,
                                            v,
                                          );
                                        }
                                      },
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                            ],
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

// ═══════════════════════════════════════════════════════════════
//  NEEDS TAB
// ═══════════════════════════════════════════════════════════════

class _NeedsTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _NeedsTab({required this.chatService, this.groupRepo});

  @override
  State<_NeedsTab> createState() => _NeedsTabState();
}

class _NeedsTabState extends State<_NeedsTab> {
  bool _needsSimEnabled = false;

  // Per-character needs baselines: char-id → field-name → value
  final Map<String, Map<String, int>> _needsBaselines = {};

  // Per-character needs decay rates ("tick rate"): char-id → field-name → value.
  // Each member decays at its own rate (parity with solo cards); persisted to
  // that member's card ext via ChatService.setGroupNeedsDecayRate(memberId: …).
  final Map<String, Map<String, int>> _decayRates = {};

  // Per-character static preference overrides (e.g. enjoys low hygiene) for this group.
  final Map<String, bool> _enjoysLowHygiene = {};

  List<CharacterCard> _chars = [];

  // Field name constants for needs baselines map keys.
  static const _kHunger = 'hunger';
  static const _kBladder = 'bladder';
  static const _kEnergy = 'energy';
  static const _kSocial = 'social';
  static const _kFun = 'fun';
  static const _kHygiene = 'hygiene';
  static const _kComfort = 'comfort';

  // Engine default decay per need (== NeedsSimulation.needDecay / the
  // FrontPorchExtensions decay defaults) — used to seed a reset.
  static const Map<String, int> _defaultDecayRates = {
    _kHunger: 4,
    _kBladder: 6,
    _kEnergy: 3,
    _kSocial: 2,
    _kFun: 2,
    _kHygiene: 1,
    _kComfort: 2,
  };

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

    _needsSimEnabled = cs.needsSimEnabled;

    for (final c in _chars) {
      final id = _getCharId(c);
      final ext = c.frontPorchExtensions;

      // Seed needs baselines from character card extensions.
      _needsBaselines[id] = {
        _kHunger: ext?.needsBaselineHunger ?? 80,
        _kBladder: ext?.needsBaselineBladder ?? 80,
        _kEnergy: ext?.needsBaselineEnergy ?? 80,
        _kSocial: ext?.needsBaselineSocial ?? 80,
        _kFun: ext?.needsBaselineFun ?? 80,
        _kHygiene: ext?.needsBaselineHygiene ?? 80,
        _kComfort: ext?.needsBaselineComfort ?? 80,
      };

      // Seed per-member decay from ext (fallbacks = the engine's needDecay
      // defaults, which equal the FrontPorchExtensions decay defaults).
      _decayRates[id] = {
        _kHunger: ext?.needsDecayHunger ?? 4,
        _kBladder: ext?.needsDecayBladder ?? 6,
        _kEnergy: ext?.needsDecayEnergy ?? 3,
        _kSocial: ext?.needsDecaySocial ?? 2,
        _kFun: ext?.needsDecayFun ?? 2,
        _kHygiene: ext?.needsDecayHygiene ?? 1,
        _kComfort: ext?.needsDecayComfort ?? 2,
      };

      _enjoysLowHygiene[id] = ext?.enjoysLowHygiene ?? false;
    }
  }

  String _getCharId(CharacterCard c) => c.imagePath != null
      ? c.imagePath!.split('/').last.split('.').first
      : c.name;

  CharacterCard? _findCharById(String id) {
    for (final c in _chars) {
      if (_getCharId(c) == id) return c;
    }
    return null;
  }

  void _updateNeedsBaseline(String id, String field, int value) {
    setState(() {
      _needsBaselines[id] = {...?_needsBaselines[id], field: value};
      final char = _findCharById(id);
      if (char != null) {
        char.frontPorchExtensions =
            (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
              needsBaselineHunger: _needsBaselines[id]?[_kHunger] ?? 80,
              needsBaselineBladder: _needsBaselines[id]?[_kBladder] ?? 80,
              needsBaselineEnergy: _needsBaselines[id]?[_kEnergy] ?? 80,
              needsBaselineSocial: _needsBaselines[id]?[_kSocial] ?? 80,
              needsBaselineFun: _needsBaselines[id]?[_kFun] ?? 80,
              needsBaselineHygiene: _needsBaselines[id]?[_kHygiene] ?? 80,
              needsBaselineComfort: _needsBaselines[id]?[_kComfort] ?? 80,
            );
        char.frontPorchExtensions?.ensureStableId();
      }
    });
    _persistMemberNeedsPref(id, field, value);
  }

  // Local display update while a decay slider is dragged. The persist (member
  // card ext + PNG + DB row) is deferred to the slider's onChangeEnd →
  // ChatService.setGroupNeedsDecayRate(memberId: …) to avoid PNG-encode jank.
  void _updateMemberDecay(String id, String field, int value) {
    setState(() {
      _decayRates[id] = {...?_decayRates[id], field: value};
    });
  }

  void _updateMemberEnjoysLowHygiene(CharacterCard char, bool value) {
    final id = _getCharId(char);
    setState(() {
      _enjoysLowHygiene[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            enjoysLowHygiene: value,
          );
        char.frontPorchExtensions?.ensureStableId();
    });
    _persistMemberVerificationPref(id, 'enjoysLowHygiene', value);
  }

  void _persistMemberVerificationPref(String id, String key, dynamic value) {
    try {
      final group = widget.chatService.activeGroup;
      if (group != null) {
        final map =
            group.defaultMemberRealismState.isNotEmpty &&
                group.defaultMemberRealismState != '{}'
            ? (jsonDecode(group.defaultMemberRealismState)
                      as Map<String, dynamic>? ??
                  {})
            : <String, dynamic>{};
        final perChar = (map['perChar'] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        final current = (perChar[id] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        current[key] = value;
        perChar[id] = current;
        map['perChar'] = perChar;
        group.defaultMemberRealismState = jsonEncode(map);
      }
    } catch (_) {
      // Non-fatal
    }
  }

  void _persistMemberNeedsPref(String id, String field, int value) {
    try {
      final group = widget.chatService.activeGroup;
      if (group != null) {
        final map =
            group.defaultMemberRealismState.isNotEmpty &&
                group.defaultMemberRealismState != '{}'
            ? (jsonDecode(group.defaultMemberRealismState)
                      as Map<String, dynamic>? ??
                  {})
            : <String, dynamic>{};
        final perChar = (map['perChar'] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        final current = (perChar[id] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        // Store needs baselines under a nested 'needsBaselines' key.
        final needsBaselines =
            (current['needsBaselines'] as Map<String, dynamic>? ?? {})
                .cast<String, dynamic>();
        needsBaselines[field] = value;
        current['needsBaselines'] = needsBaselines;
        perChar[id] = current;
        map['perChar'] = perChar;
        group.defaultMemberRealismState = jsonEncode(map);
      }
    } catch (_) {
      // Non-fatal
    }
  }

  void _resetAllNeedsStates() {
    for (final c in _chars) {
      final id = _getCharId(c);
      setState(() {
        _needsBaselines[id] = {
          _kHunger: 80,
          _kBladder: 80,
          _kEnergy: 80,
          _kSocial: 80,
          _kFun: 80,
          _kHygiene: 80,
          _kComfort: 80,
        };
        _decayRates[id] = Map<String, int>.from(_defaultDecayRates);
        _enjoysLowHygiene[id] = false;
      });
      widget.chatService.resetRealismForGroupCharacter(c);
    }
  }

  void _resetCharacterNeeds(CharacterCard character) {
    final id = _getCharId(character);
    setState(() {
      _needsBaselines[id] = {
        _kHunger: 80,
        _kBladder: 80,
        _kEnergy: 80,
        _kSocial: 80,
        _kFun: 80,
        _kHygiene: 80,
        _kComfort: 80,
      };
      _decayRates[id] = Map<String, int>.from(_defaultDecayRates);
      _enjoysLowHygiene[id] = false;
    });
    widget.chatService.resetRealismForGroupCharacter(character);
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _updateNeedsSim(bool value) {
    setState(() {
      _needsSimEnabled = value;
    });
    widget.chatService.setNeedsSimEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final group = cs.activeGroup;
    final isDirectorMode = cs.observerMode;

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
                  Icons.battery_std,
                  color: Colors.tealAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Needs — ${group.name}',
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
              'Configure needs baselines and per-character settings for Needs Simulation in this group.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),

            // Director Mode notice
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
                        'Director Mode is active. Needs Simulation is suspended for this group (narrative control only). Exit Director Mode to re-enable.',
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

            // Needs Simulation master toggle
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
                    'Simulates need satisfaction (hunger, bladder, energy, social, fun, hygiene, comfort). Higher = more sated (100=full, 0=critical). Low values influence AI behavior and prompt injections.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Per-character needs baselines + decay section
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
                    'Per-Character Needs Baselines & Decay',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _resetAllNeedsStates,
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
              'Adjust each character\'s starting needs baselines and their per-turn decay ("tick rate"). Every member decays at its own rate, just like a solo character.',
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
                final id = _getCharId(char);
                final baselines = _needsBaselines[id] ?? {};

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar + name + reset
                      Row(
                        children: [
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
                            child: Text(
                              char.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _resetCharacterNeeds(char),
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
                      const SizedBox(height: 8),

                      // 7 baseline sliders, each with its own per-turn decay.
                      _needsSlider(
                        'Hunger',
                        baselines[_kHunger] ?? 80,
                        (v) => _updateNeedsBaseline(id, _kHunger, v),
                        decayValue: _decayRates[id]?[_kHunger] ?? 4,
                        onDecayChanged: (v) =>
                            _updateMemberDecay(id, _kHunger, v),
                        onDecayChangeEnd: (v) => widget.chatService
                            .setGroupNeedsDecayRate(_kHunger, v, memberId: id),
                      ),
                      _needsSlider(
                        'Bladder',
                        baselines[_kBladder] ?? 80,
                        (v) => _updateNeedsBaseline(id, _kBladder, v),
                        decayValue: _decayRates[id]?[_kBladder] ?? 6,
                        onDecayChanged: (v) =>
                            _updateMemberDecay(id, _kBladder, v),
                        onDecayChangeEnd: (v) => widget.chatService
                            .setGroupNeedsDecayRate(_kBladder, v, memberId: id),
                      ),
                      _needsSlider(
                        'Energy',
                        baselines[_kEnergy] ?? 80,
                        (v) => _updateNeedsBaseline(id, _kEnergy, v),
                        decayValue: _decayRates[id]?[_kEnergy] ?? 3,
                        onDecayChanged: (v) =>
                            _updateMemberDecay(id, _kEnergy, v),
                        onDecayChangeEnd: (v) => widget.chatService
                            .setGroupNeedsDecayRate(_kEnergy, v, memberId: id),
                      ),
                      _needsSlider(
                        'Social',
                        baselines[_kSocial] ?? 80,
                        (v) => _updateNeedsBaseline(id, _kSocial, v),
                        decayValue: _decayRates[id]?[_kSocial] ?? 2,
                        onDecayChanged: (v) =>
                            _updateMemberDecay(id, _kSocial, v),
                        onDecayChangeEnd: (v) => widget.chatService
                            .setGroupNeedsDecayRate(_kSocial, v, memberId: id),
                      ),
                      _needsSlider(
                        'Fun',
                        baselines[_kFun] ?? 80,
                        (v) => _updateNeedsBaseline(id, _kFun, v),
                        decayValue: _decayRates[id]?[_kFun] ?? 2,
                        onDecayChanged: (v) => _updateMemberDecay(id, _kFun, v),
                        onDecayChangeEnd: (v) => widget.chatService
                            .setGroupNeedsDecayRate(_kFun, v, memberId: id),
                      ),
                      _needsSlider(
                        'Hygiene',
                        baselines[_kHygiene] ?? 80,
                        (v) => _updateNeedsBaseline(id, _kHygiene, v),
                        decayValue: _decayRates[id]?[_kHygiene] ?? 1,
                        onDecayChanged: (v) =>
                            _updateMemberDecay(id, _kHygiene, v),
                        onDecayChangeEnd: (v) => widget.chatService
                            .setGroupNeedsDecayRate(_kHygiene, v, memberId: id),
                      ),
                      _needsSlider(
                        'Comfort',
                        baselines[_kComfort] ?? 80,
                        (v) => _updateNeedsBaseline(id, _kComfort, v),
                        decayValue: _decayRates[id]?[_kComfort] ?? 2,
                        onDecayChanged: (v) =>
                            _updateMemberDecay(id, _kComfort, v),
                        onDecayChangeEnd: (v) => widget.chatService
                            .setGroupNeedsDecayRate(_kComfort, v, memberId: id),
                      ),

                      const SizedBox(height: 8),
                      Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 8),

                      // Enjoys low hygiene
                      Row(
                        children: [
                          const Icon(
                            Icons.water_drop_outlined,
                            size: 14,
                            color: Colors.tealAccent,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Enjoys low hygiene',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 20,
                            width: 20,
                            child: Checkbox(
                              value: _enjoysLowHygiene[id] ?? false,
                              onChanged: (v) {
                                if (v != null) {
                                  _updateMemberEnjoysLowHygiene(char, v);
                                }
                              },
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
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

  Widget _needsSlider(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int? decayValue,
    ValueChanged<int>? onDecayChanged,
    ValueChanged<int>? onDecayChangeEnd,
  }) {
    final baseline = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$value',
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.tealAccent,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            thumbColor: Colors.tealAccent,
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: (d) => onChanged(d.round()),
          ),
        ),
      ],
    );

    // No decay wiring → plain baseline slider (keeps the method reusable).
    if (decayValue == null || onDecayChanged == null) return baseline;

    String decayLabel;
    if (decayValue == 0) {
      decayLabel = 'Static (0)';
    } else if (decayValue <= 2) {
      decayLabel = 'Very Slow ($decayValue)';
    } else if (decayValue <= 4) {
      decayLabel = 'Slow ($decayValue)';
    } else if (decayValue <= 7) {
      decayLabel = 'Normal ($decayValue)';
    } else if (decayValue <= 12) {
      decayLabel = 'Fast ($decayValue)';
    } else {
      decayLabel = 'Very Fast ($decayValue)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        baseline,
        Padding(
          padding: const EdgeInsets.only(left: 10, right: 4, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Decay / Turn',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    decayLabel,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.tealAccent.withValues(alpha: 0.45),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                  thumbColor: Colors.tealAccent.withValues(alpha: 0.6),
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                ),
                child: Slider(
                  value: decayValue.toDouble(),
                  min: 0,
                  max: 20,
                  divisions: 20,
                  // Smooth local update while dragging; the (expensive) persist
                  // to the member PNG + DB row happens once, on release.
                  onChanged: (d) => onDecayChanged(d.round()),
                  onChangeEnd: onDecayChangeEnd == null
                      ? null
                      : (d) => onDecayChangeEnd(d.round()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Simple accent palette for per-char avatars (reused from _RealismNeedsTab).
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
  late final StyledTextController _nameController;
  late final StyledTextController _scenarioController;
  late final StyledTextController _firstMessageController;

  TurnOrder _turnOrder = TurnOrder.roundRobin;
  bool _autoAdvance = false;
  bool _directorModeDefault = false;

  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _loadFromActiveGroup();
  }

  void _loadFromActiveGroup() {
    final g = widget.chatService.activeGroup;

    if (g != null) {
      _nameController = StyledTextController(
        preset: StyledTextPreset.prose,
        text: g.name,
      );
      _scenarioController = StyledTextController(
        preset: StyledTextPreset.prose,
        text: g.scenario,
      );
      _firstMessageController = StyledTextController(
        preset: StyledTextPreset.prose,
        text: g.firstMessage,
      );
      _turnOrder = g.turnOrder;
      _autoAdvance = g.autoAdvance;
      _directorModeDefault = g.directorMode;
    } else {
      _nameController = StyledTextController(preset: StyledTextPreset.prose, text: '');
      _scenarioController = StyledTextController(preset: StyledTextPreset.prose, text: '');
      _firstMessageController = StyledTextController(preset: StyledTextPreset.prose, text: '');
      _turnOrder = TurnOrder.roundRobin;
      _autoAdvance = false;
      _directorModeDefault = false;
    }

    _hasUnsavedChanges = false;
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
      });
    }
  }

  void _setTurnOrder(TurnOrder order) {
    if (_turnOrder == order) return;
    setState(() {
      _turnOrder = order;
      _hasUnsavedChanges = true;
    });
  }

  void _setAutoAdvance(bool value) {
    if (_autoAdvance == value) return;
    setState(() {
      _autoAdvance = value;
      _hasUnsavedChanges = true;
    });
  }

  void _setDirectorModeDefault(bool value) {
    if (_directorModeDefault == value) return;
    setState(() {
      _directorModeDefault = value;
      _hasUnsavedChanges = true;
    });
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
          child: Row(children: []),
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

  /// Write the tab's state back onto the LIVE group object after every
  /// mutation. Without this, the dialog-level Save persisted a group this
  /// tab never touched — lorebook/world edits made here were silently lost.
  void _syncToGroup() {
    final g = widget.chatService.activeGroup;
    if (g == null) return;
    g.inheritCharacterLorebooks = _inheritCharacterLorebooks;
    g.worldIds = List<String>.from(_worldIds);
    g.groupLorebook = _groupLoreEntries.isEmpty
        ? ''
        : jsonEncode(Lorebook(entries: _groupLoreEntries).toJson());
  }

  Future<void> _showEntryEditor({LorebookEntry? existing, int? index}) async {
    // The shared Simple/Advanced editor (clone-preserving). The old bespoke
    // 5-field dialog here rebuilt entries from scratch, destroying imported
    // ST metadata (secondary keys, probability, timers, ...) on every edit.
    final result = await showLorebookEntryDialog(
      context: context,
      existing: existing,
      showEnabled: true,
    );
    if (result == null) return;

    setState(() {
      if (index != null && index >= 0 && index < _groupLoreEntries.length) {
        _groupLoreEntries[index] = result;
      } else {
        _groupLoreEntries.add(result);
      }
    });
    _syncToGroup();
  }

  Future<void> _importGroupLorebookJson() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
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
      _syncToGroup();

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
    _syncToGroup();
  }

  void _toggleWorld(String worldId) {
    setState(() {
      if (_worldIds.contains(worldId)) {
        _worldIds.remove(worldId);
      } else {
        _worldIds.add(worldId);
      }
    });
    _syncToGroup();
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
                    _syncToGroup();
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
