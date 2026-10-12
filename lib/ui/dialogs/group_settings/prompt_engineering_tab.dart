// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/prompt_engineering_tab/prompt_engineering_tab.dart';

class GroupPromptEngineeringTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const GroupPromptEngineeringTab({
    super.key,
    required this.chatService,
    this.groupRepo,
  });

  @override
  State<GroupPromptEngineeringTab> createState() =>
      _GroupPromptEngineeringTabState();
}

class _GroupPromptEngineeringTabState extends State<GroupPromptEngineeringTab> {
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

  Widget _buildCharacterNoteEditor(CharacterCard c, int index) {
    final strength = _perCharStrengths.putIfAbsent(
      c,
      () => widget.chatService.getAuthorNoteStrengthForGroupCharacter(c),
    );
    return GroupCharacterNoteEditor(
      character: c,
      accent: _charColor(index),
      controller: _getOrCreateNoteController(c),
      strength: strength,
      onNoteChanged: (text) {
        widget.chatService.setAuthorNoteForGroupCharacter(c, text);
      },
      onStrengthChanged: (newStrength) {
        setState(() {
          _perCharStrengths[c] = newStrength;
        });
        // Flush to service so it persists on Save / restart
        final currentNote = _perCharNoteControllers[c]?.text ?? '';
        widget.chatService.setAuthorNoteForGroupCharacter(
          c,
          currentNote,
          strength: newStrength,
        );
      },
    );
  }

  Widget _buildCharacterSystemPromptEditor(CharacterCard c, int index) {
    final promptCtrl = _getOrCreateSystemPromptController(c);
    return GroupCharacterSystemPromptEditor(
      character: c,
      accent: _charColor(index),
      controller: promptCtrl,
      onPromptChanged: (text) {
        widget.chatService.setSystemPromptForGroupCharacter(c, text);
      },
      onClear: () {
        promptCtrl.clear();
        // A programmatic clear() never fires TextField.onChanged, so
        // without this the box looked empty while the old override
        // kept being injected every turn (and came back on reopen).
        widget.chatService.setSystemPromptForGroupCharacter(c, '');
      },
    );
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
            Icon(
              Icons.group_off_outlined,
              size: 48,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(height: 12),
            Text(
              'No active group chat',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Author\'s notes and group prompts are only available in group mode.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
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
                Row(
                  children: [
                    Icon(
                      Icons.code,
                      size: 16,
                      color: AppColors.formMasterAccent,
                    ),
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
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
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
                      borderSide: const BorderSide(
                        color: AppColors.formMasterAccent,
                      ),
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
                Row(
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
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),

                // Per-character system prompt editors
                for (int i = 0; i < chars.length; i++)
                  _buildCharacterSystemPromptEditor(chars[i], i),

                const SizedBox(height: 20),

                // ── Per-Character Author's Notes ────────────────────────────
                Row(
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
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
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
}
