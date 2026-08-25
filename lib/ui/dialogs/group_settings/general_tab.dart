// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/group_alternate_greetings_editor.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings_support.dart';

part 'general_tab.cards.dart';

class GroupGeneralTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const GroupGeneralTab({super.key, required this.chatService, this.groupRepo});

  @override
  State<GroupGeneralTab> createState() => GroupGeneralTabState();
}

class GroupGeneralTabState extends State<GroupGeneralTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  // Local editing controllers and state (applied on Save)
  late final StyledTextController _nameController;
  late final StyledTextController _scenarioController;
  late final StyledTextController _firstMessageController;
  List<String> _altGreetings = [];
  List<GreetingRealismSeed?> _altGreetingSeeds = [];

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
      _altGreetings = List.from(g.alternateGreetings);
      _altGreetingSeeds = List.from(g.greetingSeeds);
      _turnOrder = g.turnOrder;
      _autoAdvance = g.autoAdvance;
      _directorModeDefault = g.directorMode;
    } else {
      _nameController = StyledTextController(
        preset: StyledTextPreset.prose,
        text: '',
      );
      _scenarioController = StyledTextController(
        preset: StyledTextPreset.prose,
        text: '',
      );
      _firstMessageController = StyledTextController(
        preset: StyledTextPreset.prose,
        text: '',
      );
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

  /// Copies the General editors onto the live group so the dialog footer
  /// Save persists what the user typed, not the untouched [GroupChat].
  void applyToLiveGroup() {
    final g = widget.chatService.activeGroup;
    if (g == null) return;
    g.name = _nameController.text;
    g.scenario = _scenarioController.text;
    g.firstMessage = _firstMessageController.text;
    final paired = compactGreetingPairs(_altGreetings, _altGreetingSeeds);
    g.alternateGreetings = paired.greetings;
    g.greetingSeeds = paired.seeds;
    g.turnOrder = _turnOrder;
    g.autoAdvance = _autoAdvance;
    g.directorMode = _directorModeDefault;
    if (_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final group = widget.chatService.activeGroup;

    if (group == null) {
      return Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: AppColors.textSecondary(context)),
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
                    Icon(
                      Icons.tune,
                      color: AppColors.porchAmberOf(context),
                      size: 20,
                    ),
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
                Text(
                  'Basic group identity, opening message, and conversation flow rules. All changes apply live after Save.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Identity ───────────────────────────────────────────────
                GroupSectionHeader(
                  'Identity',
                  Icons.label_outline,
                  AppColors.porchAmberOf(context),
                ),
                const SizedBox(height: 8),

                // Group Name
                Text(
                  'Group Name',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
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
                      borderSide: BorderSide(
                        color: AppColors.porchAmberOf(context),
                      ),
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
                Text(
                  'Scenario',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Group-level scenario override (blank = use first character\'s scenario).',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _scenarioController,
                  maxLines: 4,
                  minLines: 2,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'The scene, time period, and situation for this group conversation...',
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
                      borderSide: BorderSide(
                        color: AppColors.porchAmberOf(context),
                      ),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 14),

                // First Message
                Text(
                  'First Message / Greeting',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Custom opening message shown when the group starts or is reset (blank = use first character\'s greeting).',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _firstMessageController,
                  maxLines: 3,
                  minLines: 2,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: 'The group\'s initial greeting or narration...',
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
                      borderSide: BorderSide(
                        color: AppColors.porchAmberOf(context),
                      ),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 12),
                GroupAlternateGreetingsEditor(
                  greetings: _altGreetings,
                  seeds: _altGreetingSeeds,
                  showNeeds: true,
                  onChanged: (g, s) {
                    setState(() {
                      _altGreetings = g;
                      _altGreetingSeeds = s;
                      _hasUnsavedChanges = true;
                    });
                  },
                ),
                const SizedBox(height: 20),

                // ── Turn Management ────────────────────────────────────────
                GroupSectionHeader(
                  'Turn Management',
                  Icons.swap_horiz,
                  AppColors.porchAmberOf(context),
                ),
                const SizedBox(height: 8),

                Text(
                  'Turn Order Strategy',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
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
                    color: AppColors.surfaceContainerOf(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            size: 18,
                            color: AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Auto-advance',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: _autoAdvance,
                            activeTrackColor: AppColors.porchAmberOf(context),
                            onChanged: _setAutoAdvance,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 26),
                        child: Text(
                          'After a character finishes responding, automatically prompt the next speaker. Works with both turn orders and Director Mode.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary(context),
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                ..._directorModeSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
