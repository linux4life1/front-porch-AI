// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/database/database.dart'
    show AppDatabaseGroupQueries;
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings_support.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart'
    show afterglowEnabledOf;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/realism_needs_tab/realism_needs_tab.dart';

class GroupRealismNeedsTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;

  /// Switches the Group Settings dialog holding this tab to another tab: a
  /// member's editor opened from here links back to it, not to a second
  /// Group Settings.
  final void Function(int tab)? onShowTab;
  const GroupRealismNeedsTab({
    super.key,
    required this.chatService,
    this.groupRepo,
    this.onShowTab,
  });

  @override
  State<GroupRealismNeedsTab> createState() => _GroupRealismNeedsTabState();
}

class _GroupRealismNeedsTabState extends State<GroupRealismNeedsTab> {
  late final GroupRealismNeedsController _controller;

  /// The group's saved realism definition, for the members' summaries of
  /// where each starts in its new chats.
  String _persisted = '{}';

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onServiceChanged);
    _controller = GroupRealismNeedsController(widget.chatService)
      ..addListener(_onControllerChanged);
    _readPersisted();
  }

  Future<void> _readPersisted() async {
    final id = widget.chatService.activeGroup?.id;
    if (id == null) return;
    try {
      final row = await liveDatabase(context).getGroupById(id);
      if (!mounted) return;
      setState(() => _persisted = row?.defaultMemberRealismState ?? '{}');
    } catch (e) {
      debugPrint('[GroupSettings] could not read the group: $e');
    }
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceChanged);
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final group = cs.activeGroup;
    final isDirectorMode = cs.observerMode;
    final isRealismActive = cs.isGroupRealismActive;
    final chars = _controller.chars;

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
            const GroupThisChatNote(),
            // Header
            Row(
              children: [
                Icon(
                  Icons.theater_comedy,
                  color: AppColors.porchAmberOf(context),
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
                if (_controller.baselineSeeds.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text(
                        'Baseline seeded',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Master toggles and per-character baseline management for the Realism Engine, Chaos Mode, and Passage of Time in this group.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),

            // Director Mode notice (visual indication per requirements)
            if (isDirectorMode)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AccentColors.goldEdgeOf(context)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AccentColors.goldOf(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Director Mode is active. You are off stage, so bond, trust and emotion toward you hold still. Needs, time, weather and the cast\'s feelings for each other keep running.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AccentColors.goldOf(context),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Master Realism Engine
            GroupRealismEngineCard(controller: _controller),

            // Porch Life (with 18+) allows Afterglow: this chat's own switch.
            if (afterglowEnabledOf(context)) ...[
              const SizedBox(height: 14),
              GroupAfterglowCard(controller: _controller),
            ],

            const SizedBox(height: 14),

            // Passage of Time + Chaos (two-column-ish or stacked)
            GroupTimeAndChaosCard(cs: cs, controller: _controller),

            const SizedBox(height: 16),

            // Per-character baselines / reset section
            Row(
              children: [
                Icon(
                  Icons.people_alt,
                  size: 18,
                  color: AppColors.porchAmberOf(context),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Per-Character Realism Baselines',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _controller.resetAllRealismStates,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Reset ALL',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.porchAmberOf(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Clear tracked emotion, bond, trust, and fixation for characters in the current group. Use to restart relationship arcs or after major story changes. States re-seed automatically on the next Realism evaluation.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 10),

            if (chars.isEmpty)
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
              ...chars.asMap().entries.map(
                (e) => GroupMemberRealismCard(
                  index: e.key,
                  char: e.value,
                  cs: cs,
                  isRealismActive: isRealismActive,
                  controller: _controller,
                  persisted: _persisted,
                  onShowTab: widget.onShowTab,
                  onEdited: _readPersisted,
                ),
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
